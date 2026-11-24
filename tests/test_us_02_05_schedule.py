import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

RUNNER = Path(__file__).resolve().parents[1] / "ops/us-02-05/pipeline.py"


class ScheduledPipelineTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.script = self.root / "ops/us-02-05/pipeline.py"
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(RUNNER, self.script)
        for filename in ("etl/run_cleaning.py", "tests/test_us_02_03_data_quality.py"):
            path = self.root / filename
            path.parent.mkdir()
            path.write_text("pass\n")
            (path.parent / "__init__.py").touch()
        self.plan = {key: [sys.executable, "-c", "pass"]
                     for key in ("sources_incremental", "refresh_mart")}
        self.messages = []
        messages = self.messages

        class Receiver(BaseHTTPRequestHandler):
            def do_POST(self):
                messages.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Receiver)
        self.url = f"http://127.0.0.1:{server.server_port}/etl"
        worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
        worker.start()
        self.addCleanup(server.server_close)
        self.addCleanup(worker.join)
        self.addCleanup(server.shutdown)

    def invoke(self):
        (self.script.parent / "commands.json").write_text(json.dumps(self.plan))
        env = dict(os.environ, HOTELGROUP_ALERT_WEBHOOK=self.url,
                   HOTELGROUP_PLAN=str(self.script.parent / "commands.json"))
        result = subprocess.run([sys.executable, self.script], env=env, capture_output=True,
                                text=True, timeout=20)
        return result.returncode, [json.loads(line) for line in result.stdout.splitlines()]

    def test_success(self):
        code, events = self.invoke()
        self.assertEqual(code, 0)
        self.assertEqual([e["stage"] for e in events if e["event"] == "stage_completed"],
                         ["sources_incremental", "clean_core", "refresh_mart", "quality_all"])
        self.assertEqual(events[-1]["event"], "pipeline_completed")
        self.assertFalse(self.messages)

    def test_failed_source_and_blocked_core_stop_and_deliver_alert(self):
        for stage, code in [("sources_incremental", 7), ("clean_core", 2)]:
            with self.subTest(stage=stage):
                self.plan["sources_incremental"][-1] = "raise SystemExit(7)" if code == 7 else "pass"
                if code == 2:
                    (self.root / "etl/run_cleaning.py").write_text("raise SystemExit(2)")
                status, events = self.invoke()
                self.assertEqual(status, code)
                self.assertNotIn("refresh_mart", [e["stage"] for e in events])
                self.assertEqual(events[-2]["event"], "pipeline_failed")
                self.assertEqual(events[-1]["event"], "alert_delivered")
                self.assertIn(events[-1]["run_id"], self.messages[-1]["text"])
                self.assertIn(f"stage={stage} | exit={code}", self.messages[-1]["text"])

    def test_missing_integration_fails_before_first_stage(self):
        self.plan["refresh_mart"] = []
        code, events = self.invoke()
        self.assertEqual(code, 1)
        self.assertEqual([e["event"] for e in events], ["pipeline_failed", "alert_delivered"])
