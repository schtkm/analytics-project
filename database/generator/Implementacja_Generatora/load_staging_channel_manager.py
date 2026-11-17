"""
HOTELGROUP – IMPORT CHANNEL MANAGERA DO STAGING

Zadanie: US-02-01
Źródło: Channel Manager (JSON)
Cel: PostgreSQL – staging.cm_channels

Skrypt:
- Odczytuje wygenerowany plik channel_manager.json.
- Zachowuje wartości i identyfikatory źródłowe.
- Kontroluje kompletność danych.
- Weryfikuje powiązania reservation_id z PMS.
- Wykonuje pełne odświeżenie w jednej transakcji.

Konfiguracja PostgreSQL pochodzi z pliku .env
w głównym katalogu repozytorium.

Strategia: FULL REFRESH (nie jest to ładowanie przyrostowe).
"""

import json
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


# ============================================================
# 1. KONFIGURACJA
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[3]
ENV_PATH = PROJECT_ROOT / ".env"

JSON_PATH = (
    PROJECT_ROOT / "database" / "generator"
    / "channel_manager.json"
)

TABLE_NAME = "staging.cm_channels"
CHUNK_SIZE = 2000

REQUIRED_FIELDS = {
    "reservation_id",
    "channel_code",
    "commission_rate",
    "commission_amount",
}

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
            f"Nie znaleziono pliku .env: {ENV_PATH}"
        )

    load_dotenv(ENV_PATH)

    required = [
        "PG_HOST", "PG_PORT", "PG_DATABASE",
        "PG_USER", "PG_PASSWORD",
    ]

    missing = [key for key in required if not os.getenv(key)]

    if missing:
        raise ValueError(
            f"Brak konfiguracji: {', '.join(missing)}"
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
# 3. ODCZYT I WALIDACJA TECHNICZNA JSON
# ============================================================

def read_channel_data():

    if not JSON_PATH.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono JSON: {JSON_PATH}"
        )

    with JSON_PATH.open("r", encoding="utf-8") as file:
        records = json.load(file)

    if not isinstance(records, list) or not records:
        raise ValueError("JSON musi zawierać niepustą listę.")

    seen_ids = set()

    for number, record in enumerate(records, start=1):

        if not isinstance(record, dict):
            raise ValueError(f"Rekord {number} nie jest obiektem.")

        if set(record) != REQUIRED_FIELDS:
            raise ValueError(
                f"Niepoprawne pola rekordu {number}."
            )

        reservation_id = record["reservation_id"]

        if not isinstance(reservation_id, str) or not reservation_id:
            raise ValueError(
                f"Niepoprawny reservation_id: rekord {number}"
            )

        if reservation_id in seen_ids:
            raise ValueError(
                f"Duplikat reservation_id: {reservation_id}"
            )

        seen_ids.add(reservation_id)

        if not isinstance(record["channel_code"], str):
            raise ValueError("Niepoprawny channel_code.")

        for field in ("commission_rate", "commission_amount"):
            value = record[field]
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not (0 <= value < float("inf"))
            ):
                raise ValueError(
                    f"Niepoprawna wartość {field}: {reservation_id}"
                )

    logger.info("Poprawnie odczytano %s rekordów JSON.", len(records))

    return records


# ============================================================
# 4. ŁADOWANIE DO STAGING
# ============================================================

def load_channel_manager():

    records = read_channel_data()
    engine = create_engine(get_postgres_url(), pool_pre_ping=True)

    try:
        with engine.begin() as connection:

            # Sprawdzenie wymaganych tabel.
            for table_name in (
                "staging.cm_channels",
                "staging.pms_reservations",
            ):
                exists = connection.execute(
                    text("SELECT to_regclass(:name)"),
                    {"name": table_name},
                ).scalar_one()

                if exists is None:
                    raise ValueError(
                        f"Brak tabeli PostgreSQL: {table_name}"
                    )

            # Ponowne uruchomienie nie tworzy duplikatów.
            connection.execute(
                text("DELETE FROM staging.cm_channels")
            )

            insert_query = text("""
                INSERT INTO staging.cm_channels (
                    reservation_id,
                    channel_code,
                    commission_rate,
                    commission_amount
                )
                VALUES (
                    :reservation_id,
                    :channel_code,
                    :commission_rate,
                    :commission_amount
                )
            """)

            # Ładowanie partiami.
            for start in range(0, len(records), CHUNK_SIZE):

                chunk = records[start:start + CHUNK_SIZE]
                connection.execute(insert_query, chunk)

            loaded_count = connection.execute(
                text("SELECT COUNT(*) FROM staging.cm_channels")
            ).scalar_one()

            if loaded_count != len(records):
                raise ValueError(
                    "Niezgodność liczby rekordów: "
                    f"JSON={len(records)}, PostgreSQL={loaded_count}"
                )

            # Kontrola powiązania Channel Manager -> PMS.
            missing_count = connection.execute(text("""
                SELECT COUNT(*)
                FROM staging.cm_channels cm
                LEFT JOIN staging.pms_reservations pms
                    ON cm.reservation_id = pms.reservation_id
                WHERE pms.reservation_id IS NULL
            """)).scalar_one()

            if missing_count != 0:
                raise ValueError(
                    f"Brak powiązania z PMS dla "
                    f"{missing_count} rekordów."
                )

            logger.info(
                "Poprawnie załadowano %s rekordów.",
                loaded_count,
            )

            logger.info(
                "Wszystkie reservation_id powiązano z PMS."
            )

        # Zatwierdzenie transakcji następuje tutaj.
        print("\nIMPORT CHANNEL MANAGERA ZAKOŃCZONY")
        print(f"JSON: {len(records)}")
        print(f"PostgreSQL: {loaded_count}")
        print(f"Brakujące powiązania PMS: {missing_count}")

    finally:
        engine.dispose()


# ============================================================
# 5. URUCHOMIENIE
# ============================================================

if __name__ == "__main__":

    try:
        load_channel_manager()

    except Exception:
        logger.exception(
            "Import Channel Managera zakończył się błędem."
        )
        raise SystemExit(1)