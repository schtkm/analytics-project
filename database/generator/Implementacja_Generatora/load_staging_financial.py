"""
HOTELGROUP – IMPORT DANYCH FINANSOWYCH DO STAGING

Zadanie: US-02-01
Źródło: System finansowy (CSV)
Cel: PostgreSQL – staging.fin_budgets_costs

Zakres:
- Odczyt syntetycznych danych finansowych z CSV.
- Zachowanie wartości i identyfikatorów źródłowych.
- Kontrola kompletności rekordów.
- Weryfikacja identyfikatorów hoteli względem PMS.
- Pełne odświeżenie danych w jednej transakcji.

Konfiguracja połączenia pochodzi z pliku .env.
Strategia: FULL REFRESH, bez transformacji biznesowych.
"""

import csv
from datetime import datetime
from decimal import Decimal, InvalidOperation
import logging
import os
from pathlib import Path
import sys
import time
import uuid

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

PROJECT_ROOT = Path(__file__).resolve().parents[3]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from etl.incremental import (
    compute_row_hash,
    ensure_watermark_table_exists,
    update_watermark_sa,
    upsert_records_sa,
)

# ============================================================
# 1. KONFIGURACJA
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[3]
CSV_PATH = PROJECT_ROOT / "database" / "generator" / "financial_data.csv"
ENV_PATH = PROJECT_ROOT / ".env"

REQUIRED_FIELDS = {
    "hotel_id",
    "month_id",
    "cost_category",
    "budget_amount",
    "actual_cost",
}

CHUNK_SIZE = 1000

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger(__name__)


# ============================================================
# 2. KONFIGURACJA POSTGRESQL
# ============================================================

def get_postgres_url():

    if not ENV_PATH.is_file():
        raise FileNotFoundError(
            f"Brak pliku konfiguracji: {ENV_PATH}"
        )

    load_dotenv(ENV_PATH)

    required = [
        "PG_HOST",
        "PG_PORT",
        "PG_DATABASE",
        "PG_USER",
        "PG_PASSWORD",
    ]

    missing = [
        variable
        for variable in required
        if not os.getenv(variable)
    ]

    if missing:
        raise ValueError(
            f"Brak zmiennych: {', '.join(missing)}"
        )

    return URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT")),
        database=os.getenv("PG_DATABASE"),
    )


# ============================================================
# 3. ODCZYT I WALIDACJA TECHNICZNA CSV
# ============================================================

def read_financial_data():

    if not CSV_PATH.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono CSV: {CSV_PATH}"
        )

    records = []
    unique_keys = set()

    with CSV_PATH.open(
        "r",
        encoding="utf-8-sig",
        newline="",
    ) as file:

        reader = csv.DictReader(file)

        if reader.fieldnames is None:
            raise ValueError("CSV nie zawiera nagłówka.")

        if set(reader.fieldnames) != REQUIRED_FIELDS:
            raise ValueError(
                "Niezgodne kolumny CSV: "
                f"{reader.fieldnames}"
            )

        for row_number, row in enumerate(reader, start=2):

            if None in row or any(
                value is None for value in row.values()
            ):
                raise ValueError(
                    f"Niepoprawna struktura CSV, wiersz {row_number}"
                )

            hotel_id = row["hotel_id"].strip()
            month_id = row["month_id"].strip()
            category = row["cost_category"].strip()

            if not hotel_id or not month_id or not category:
                raise ValueError(
                    f"Brak wymaganego identyfikatora, wiersz {row_number}"
                )

            unique_key = (hotel_id, month_id, category)

            if unique_key in unique_keys:
                raise ValueError(
                    f"Duplikat: {unique_key}"
                )

            unique_keys.add(unique_key)

            try:
                budget = Decimal(row["budget_amount"])
                actual = Decimal(row["actual_cost"])
            except InvalidOperation as error:
                raise ValueError(
                    f"Niepoprawna kwota, wiersz {row_number}"
                ) from error

            if not budget.is_finite() or not actual.is_finite():
                raise ValueError(
                    f"Nieprawidłowa wartość kwoty, wiersz {row_number}"
                )

            if budget < 0 or actual < 0:
                raise ValueError(
                    f"Ujemna kwota, wiersz {row_number}"
                )

            records.append({
                "hotel_id": hotel_id,
                "month_id": month_id,
                "cost_category": category,
                "budget_amount": budget,
                "actual_cost": actual,
            })

    if not records:
        raise ValueError("Plik finansowy jest pusty.")

    logger.info(
        "Poprawnie odczytano %s rekordów CSV.",
        len(records),
    )

    return records


# ============================================================
# 4. IMPORT DO POSTGRESQL
# ============================================================

def load_financial_data():
    started = time.perf_counter()
    run_id = str(uuid.uuid4())
    records = read_financial_data()
    for rec in records:
        rec["row_hash"] = compute_row_hash(rec)

    engine = create_engine(get_postgres_url(), pool_pre_ping=True)

    try:
        with engine.begin() as connection:
            for table_name in ("staging.fin_budgets_costs", "staging.pms_hotels"):
                exists = connection.execute(
                    text("SELECT to_regclass(:name)"),
                    {"name": table_name},
                ).scalar_one()
                if exists is None:
                    raise ValueError(f"Brak tabeli: {table_name}")

            ensure_watermark_table_exists(connection)

            upserted_count = upsert_records_sa(
                pg_conn=connection,
                schema="staging",
                table="fin_budgets_costs",
                records=records,
                business_cols=[
                    "hotel_id",
                    "month_id",
                    "cost_category",
                    "budget_amount",
                    "actual_cost",
                ],
                conflict_cols=["hotel_id", "month_id", "cost_category"],
                chunk_size=CHUNK_SIZE,
            )

            total_count = connection.execute(
                text("SELECT COUNT(*) FROM staging.fin_budgets_costs")
            ).scalar_one()

            missing_hotels = connection.execute(text("""
                SELECT COUNT(*)
                FROM staging.fin_budgets_costs fin
                LEFT JOIN staging.pms_hotels pms
                    ON fin.hotel_id = pms.hotel_id
                WHERE pms.hotel_id IS NULL
            """)).scalar_one()

            if missing_hotels != 0:
                raise ValueError(f"Nieznane identyfikatory hoteli: {missing_hotels}")

            update_watermark_sa(
                pg_conn=connection,
                source_system="financial",
                table_name="fin_budgets_costs",
                new_watermark_ts=datetime.now(),
                rows_extracted=len(records),
                rows_upserted=upserted_count,
                run_id=run_id,
            )

        elapsed = time.perf_counter() - started
        print("\nPRZYROSTOWY IMPORT DANYCH FINANSOWYCH ZAKOŃCZONY")
        print(f"Odczytano CSV: {len(records)} | Zaktualizowano/dodano (UPSERT): {upserted_count}")
        print(f"Razem w staging.fin_budgets_costs: {total_count} | Czas: {elapsed:.3f} s")

    finally:
        engine.dispose()


# ============================================================
# 5. URUCHOMIENIE
# ============================================================

if __name__ == "__main__":

    try:
        load_financial_data()

    except Exception:
        logger.exception(
            "Import danych finansowych zakończył się błędem."
        )
        raise SystemExit(1)