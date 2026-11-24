"""
============================================================
HOTELGROUP – IMPORT DANYCH PMS DO STAGING
============================================================

Zadanie: US-02-07 i US-02-04
Technologie: Python, SQLite, PostgreSQL, SQLAlchemy, pandas

OPIS:
    Skrypt pobiera syntetyczne dane z systemu PMS (SQLite)
    i ładuje je do schematu staging hurtowni HotelGroup
    działającej na PostgreSQL.

    Zachowywane są wartości oraz identyfikatory źródłowe.
    Transformacje biznesowe realizowane są poza tym skryptem.

KONFIGURACJA:
    W katalogu głównym repozytorium należy utworzyć plik .env:

    PG_HOST=localhost
    PG_PORT=5432
    PG_DATABASE=hotelgroup_dw
    PG_USER=postgres
    PG_PASSWORD=TU_WPISZ_SWOJE_HASLO

    Każdy członek zespołu używa własnych danych dostępowych.
    Plik .env musi być wykluczony z repozytorium przez .gitignore.

STRATEGIA ŁADOWANIA:
    FULL REFRESH – pełne odświeżenie tabel PMS w staging.

    Przy każdym uruchomieniu dotychczasowe rekordy PMS
    w staging są usuwane i zastępowane aktualnymi danymi
    z pliku źródłowego.

    Operacje odbywają się w jednej transakcji.
    W przypadku błędu wszystkie zmiany są wycofywane.

    Skrypt NIE realizuje ładowania przyrostowego (R-08).

WYMAGANIA:
    pip install pandas sqlalchemy psycopg2-binary python-dotenv

============================================================
"""

"""
HOTELGROUP – PRZYROSTOWY IMPORT DANYCH PMS DO STAGING (US-02-04)
"""

from datetime import datetime
import logging
import os
from pathlib import Path
import sqlite3
import sys
import time
import uuid

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import URL

PROJECT_ROOT = Path(__file__).resolve().parents[3]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from etl.incremental import (
    compute_row_hash,
    ensure_watermark_table_exists,
    get_watermark_sa,
    update_watermark_sa,
    upsert_records_sa,
)

SQLITE_DB_PATH = PROJECT_ROOT / "database" / "generator" / "pms_source.db"
ENV_PATH = PROJECT_ROOT / ".env"
STAGING_SCHEMA = "staging"
CHUNK_SIZE = 2000

TABLE_CONFIG = {
    "pms_hotels": {"pk": ["hotel_id"], "watermark_col": None},
    "pms_guests": {"pk": ["guest_id"], "watermark_col": None},
    "pms_rooms": {"pk": ["room_id"], "watermark_col": None},
    "pms_reservations": {"pk": ["reservation_id"], "watermark_col": "updated_at"},
    "pms_stays": {"pk": ["stay_id"], "watermark_col": None},
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


def get_postgres_url():
    if not ENV_PATH.is_file():
        raise FileNotFoundError(f"Nie znaleziono pliku konfiguracji: {ENV_PATH}")
    load_dotenv(ENV_PATH)
    required = ["PG_HOST", "PG_PORT", "PG_DATABASE", "PG_USER", "PG_PASSWORD"]
    missing = [v for v in required if not os.getenv(v)]
    if missing:
        raise ValueError("Brak wymaganych zmiennych środowiskowych: " + ", ".join(missing))
    return URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT")),
        database=os.getenv("PG_DATABASE"),
    )


def validate_sqlite_source(sqlite_conn):
    for table_name in TABLE_CONFIG:
        cursor = sqlite_conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            (table_name,),
        )
        if cursor.fetchone() is None:
            raise ValueError(f"Brak tabeli źródłowej: {table_name}")
        count = sqlite_conn.execute(f'SELECT COUNT(*) FROM "{table_name}"').fetchone()[0]
        if count == 0:
            raise ValueError(f"Tabela źródłowa {table_name} jest pusta.")


def validate_staging_tables(engine, sqlite_conn):
    inspector = inspect(engine)
    if not inspector.has_schema(STAGING_SCHEMA):
        raise ValueError(f"Nie istnieje schemat PostgreSQL: {STAGING_SCHEMA}")
    for table_name in TABLE_CONFIG:
        if not inspector.has_table(table_name, schema=STAGING_SCHEMA):
            raise ValueError(f"Brak tabeli docelowej: {STAGING_SCHEMA}.{table_name}")
        source_columns = {
            row[1]
            for row in sqlite_conn.execute(f'PRAGMA table_info("{table_name}")').fetchall()
        }
        target_columns = {
            col["name"]
            for col in inspector.get_columns(table_name, schema=STAGING_SCHEMA)
        }
        missing = source_columns - target_columns
        if missing:
            raise ValueError(f"Niezgodna struktura {table_name}. Brakujące: {sorted(missing)}")


def _parse_ts(value) -> datetime:
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    return datetime.fromisoformat(str(value).replace("Z", "+00:00")).replace(tzinfo=None)


def load_data_to_staging():
    started = time.perf_counter()
    run_id = str(uuid.uuid4())
    logger.info("Rozpoczynam przyrostowy import PMS (run_id=%s).", run_id)

    if not SQLITE_DB_PATH.is_file():
        raise FileNotFoundError(f"Nie znaleziono bazy PMS: {SQLITE_DB_PATH}")

    engine = create_engine(get_postgres_url(), pool_pre_ping=True)
    results = {}

    try:
        sqlite_uri = SQLITE_DB_PATH.resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(sqlite_uri, uri=True) as sqlite_conn:
            sqlite_conn.execute("BEGIN")
            validate_sqlite_source(sqlite_conn)
            validate_staging_tables(engine, sqlite_conn)

            with engine.begin() as pg_conn:
                ensure_watermark_table_exists(pg_conn)

                for table_name, cfg in TABLE_CONFIG.items():
                    source_cols = [
                        row[1]
                        for row in sqlite_conn.execute(
                            f'PRAGMA table_info("{table_name}")'
                        ).fetchall()
                    ]
                    wm_col = cfg["watermark_col"]
                    has_wm_col = wm_col is not None and wm_col in source_cols
                    last_wm = get_watermark_sa(pg_conn, "pms", table_name)

                    if has_wm_col:
                        wm_str = last_wm.strftime("%Y-%m-%d %H:%M:%S")
                        query = f'SELECT * FROM "{table_name}" WHERE "{wm_col}" > ? ORDER BY "{wm_col}" ASC'
                        params = (wm_str,)
                    else:
                        query = f'SELECT * FROM "{table_name}"'
                        params = ()

                    extracted_count = 0
                    upserted_count = 0
                    max_wm = last_wm

                    for chunk_df in pd.read_sql_query(
                        query, sqlite_conn, params=params, chunksize=CHUNK_SIZE
                    ):
                        # Zamiana NaN/NaT na None dla psycopg2
                        chunk_df = chunk_df.astype(object).where(pd.notnull(chunk_df), None)
                        records = chunk_df.to_dict(orient="records")
                        for rec in records:
                            rec["row_hash"] = compute_row_hash(rec)
                            if has_wm_col and rec.get(wm_col) is not None:
                                rec_ts = _parse_ts(rec[wm_col])
                                if rec_ts > max_wm:
                                    max_wm = rec_ts

                        extracted_count += len(records)
                        upserted_count += upsert_records_sa(
                            pg_conn=pg_conn,
                            schema=STAGING_SCHEMA,
                            table=table_name,
                            records=records,
                            business_cols=source_cols,
                            conflict_cols=cfg["pk"],
                            chunk_size=CHUNK_SIZE,
                        )

                    new_wm = max_wm if has_wm_col else datetime.now()
                    update_watermark_sa(
                        pg_conn=pg_conn,
                        source_system="pms",
                        table_name=table_name,
                        new_watermark_ts=new_wm,
                        rows_extracted=extracted_count,
                        rows_upserted=upserted_count,
                        run_id=run_id,
                    )

                    total_in_pg = pg_conn.execute(
                        text(f'SELECT COUNT(*) FROM "{STAGING_SCHEMA}"."{table_name}"')
                    ).scalar_one()

                    results[table_name] = {
                        "extracted": extracted_count,
                        "upserted": upserted_count,
                        "total_pg": total_in_pg,
                    }
                    logger.info(
                        "OK | %s | delta_extracted=%s | upserted=%s | total_staging=%s",
                        table_name,
                        extracted_count,
                        upserted_count,
                        total_in_pg,
                    )

            sqlite_conn.rollback()

        elapsed = time.perf_counter() - started
        print("\n====== PODSUMOWANIE PRZYROSTOWEGO IMPORTU PMS ======")
        for table_name, stats in results.items():
            print(
                f"{table_name}: pobrano_delty={stats['extracted']} | "
                f"zapisano(UPSERT)={stats['upserted']} | razem_staging={stats['total_pg']}"
            )
        print(f"Czas wykonania: {elapsed:.3f} s")
        print("====================================================")
    finally:
        engine.dispose()


if __name__ == "__main__":
    try:
        load_data_to_staging()
    except Exception:
        logger.exception("Przyrostowy import PMS nie powiódł się.")
        raise SystemExit(1)