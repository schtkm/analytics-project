"""Scheduled HotelGroup ETL. Run with the project's virtualenv Python."""
import json
import os
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]


def emit(event, run, stage, **fields):
    print(json.dumps(dict(time=datetime.now(timezone.utc).isoformat(), event=event,
                          run_id=run, stage=stage, **fields)), flush=True)


def webhook(url, message):
    request = Request(url, data=json.dumps({"text": message}).encode(),
                      headers={"Content-Type": "application/json"}, method="POST")
    with urlopen(request, timeout=10) as response:
        if not 200 <= response.status < 300:
            raise OSError("Webhook rejected the alert")


def plan(settings):
    def command(key):
        args = settings.get(key)
        if not isinstance(args, list) or not args or not all(isinstance(a, str) and a for a in args):
            raise ValueError("Configure " + key)
        return args

    steps = [
        ("sources_incremental", command("sources_incremental")),
        ("clean_core", [sys.executable, "-m", "etl.run_cleaning", "--config", "etl/config.json"]),
        ("refresh_mart", command("refresh_mart")),
        ("quality_all", [sys.executable, "tests/test_us_02_03_data_quality.py"]),
    ]
    for stage, argv in steps:
        if not shutil.which(argv[0]):
            raise FileNotFoundError(stage)
    return steps


def main():
    os.chdir(ROOT)
    run = str(uuid.uuid4())
    stage = "configuration"
    url = os.environ.get("HOTELGROUP_ALERT_WEBHOOK")
    try:
        path = Path(os.environ.get("HOTELGROUP_PLAN", "ops/us-02-05/commands.json"))
        steps = plan(json.loads(path.read_text(encoding="utf-8")))
        for stage, argv in steps:
            emit("stage_started", run, stage)
            subprocess.run(argv, check=True)
            emit("stage_completed", run, stage)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        code = exc.returncode if isinstance(exc, subprocess.CalledProcessError) else 1
        emit("pipeline_failed", run, stage, exit_code=code, reason=type(exc).__name__)
        if url:
            try:
                webhook(url, f"HotelGroup ETL FAILED | stage={stage} | exit={code} | run={run}")
                emit("alert_delivered", run, stage)
            except (OSError, ValueError) as error:
                emit("alert_delivery_failed", run, stage, reason=type(error).__name__)
        return code if 0 < code < 256 else 1
    emit("pipeline_completed", run, "quality_all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
