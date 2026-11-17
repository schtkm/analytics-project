"""
============================================================
HOTELGROUP – IMPORT DANYCH PMS DO STAGING
============================================================

Zadanie: US-02-07
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

import logging
import os
import sqlite3
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import URL


# ============================================================
# 1. KONFIGURACJA
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[3]

SQLITE_DB_PATH = (
    PROJECT_ROOT / "database" / "generator" / "pms_source.db"
)

ENV_PATH = PROJECT_ROOT / ".env"

STAGING_SCHEMA = "staging"

TABLES_TO_LOAD = [
    "pms_hotels",
    "pms_guests",
    "pms_rooms",
    "pms_reservations",
    "pms_stays",
]

CHUNK_SIZE = 2000

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

logger = logging.getLogger(__name__)


# ============================================================
# 2. KONFIGURACJA POŁĄCZENIA POSTGRESQL
# ============================================================

def get_postgres_url():
    """Odczytuje konfigurację PostgreSQL z pliku .env."""

    if not ENV_PATH.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono pliku konfiguracji: {ENV_PATH}"
        )

    load_dotenv(ENV_PATH)

    required_variables = [
        "PG_HOST",
        "PG_PORT",
        "PG_DATABASE",
        "PG_USER",
        "PG_PASSWORD",
    ]

    missing = [
        variable
        for variable in required_variables
        if not os.getenv(variable)
    ]

    if missing:
        raise ValueError(
            "Brak wymaganych zmiennych środowiskowych: "
            + ", ".join(missing)
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
# 3. WERYFIKACJA ŹRÓDŁA SQLITE
# ============================================================

def validate_sqlite_source(sqlite_conn):
    """Sprawdza istnienie tabel i wymaganych danych PMS."""

    logger.info("Weryfikacja źródłowej bazy PMS...")

    for table_name in TABLES_TO_LOAD:

        cursor = sqlite_conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = ?",
            (table_name,),
        )

        if cursor.fetchone() is None:
            raise ValueError(
                f"Brak tabeli źródłowej: {table_name}"
            )

        count = sqlite_conn.execute(
            f'SELECT COUNT(*) FROM "{table_name}"'
        ).fetchone()[0]

        if count == 0:
            raise ValueError(
                f"Tabela źródłowa {table_name} jest pusta. "
                "Przerwano import, aby chronić istniejące dane."
            )

        logger.info(
            "SQLite | %s | %s rekordów",
            table_name,
            count,
        )


# ============================================================
# 4. WERYFIKACJA STRUKTUR POSTGRESQL
# ============================================================

def validate_staging_tables(engine, sqlite_conn):
    """Sprawdza obecność tabel i wymaganych kolumn staging."""

    inspector = inspect(engine)

    if not inspector.has_schema(STAGING_SCHEMA):
        raise ValueError(
            f"Nie istnieje schemat PostgreSQL: {STAGING_SCHEMA}"
        )

    for table_name in TABLES_TO_LOAD:

        if not inspector.has_table(
            table_name,
            schema=STAGING_SCHEMA,
        ):
            raise ValueError(
                "Brak tabeli docelowej: "
                f"{STAGING_SCHEMA}.{table_name}"
            )

        source_columns = {
            row[1]
            for row in sqlite_conn.execute(
                f'PRAGMA table_info("{table_name}")'
            ).fetchall()
        }

        target_columns = {
            column["name"]
            for column in inspector.get_columns(
                table_name,
                schema=STAGING_SCHEMA,
            )
        }

        missing_columns = source_columns - target_columns

        if missing_columns:
            raise ValueError(
                f"Niezgodna struktura {table_name}. "
                f"Brakujące kolumny: {sorted(missing_columns)}"
            )

    logger.info("Struktury tabel staging zweryfikowane.")


# ============================================================
# 5. ŁADOWANIE DANYCH PMS
# ============================================================

def load_data_to_staging():
    """
    Wykonuje pełne, transakcyjne odświeżenie danych PMS.

    W przypadku błędu transakcja zostaje wycofana.
    """

    logger.info("Rozpoczynam import PMS do PostgreSQL.")

    if not SQLITE_DB_PATH.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono bazy PMS: {SQLITE_DB_PATH}"
        )

    postgres_url = get_postgres_url()

    engine = create_engine(
        postgres_url,
        pool_pre_ping=True,
    )

    results = {}

    try:
        # Otwieramy istniejącą bazę SQLite w trybie read-only.
        sqlite_uri = SQLITE_DB_PATH.resolve().as_uri() + "?mode=ro"

        with sqlite3.connect(
            sqlite_uri,
            uri=True,
        ) as sqlite_conn:

            # Zapewniamy spójny odczyt źródła.
            sqlite_conn.execute("BEGIN")

            validate_sqlite_source(sqlite_conn)

            validate_staging_tables(
                engine,
                sqlite_conn,
            )

            # Jedna transakcja dla wszystkich tabel PostgreSQL.
            with engine.begin() as pg_conn:

                logger.info(
                    "Rozpoczynam transakcyjne odświeżenie staging."
                )

                # Usuwamy stare dane w odwrotnej kolejności,
                # aby uwzględnić ewentualne zależności FK.
                for table_name in reversed(TABLES_TO_LOAD):

                    pg_conn.execute(
                        text(
                            f'DELETE FROM '
                            f'"{STAGING_SCHEMA}"."{table_name}"'
                        )
                    )

                    logger.info(
                        "Wyczyszczono staging.%s",
                        table_name,
                    )

                # Ładowanie od tabel nadrzędnych do zależnych.
                for table_name in TABLES_TO_LOAD:

                    logger.info(
                        "Ładowanie tabeli: %s",
                        table_name,
                    )

                    source_count = sqlite_conn.execute(
                        f'SELECT COUNT(*) FROM "{table_name}"'
                    ).fetchone()[0]

                    loaded_count = 0

                    query = f'SELECT * FROM "{table_name}"'

                    for chunk in pd.read_sql_query(
                        query,
                        sqlite_conn,
                        chunksize=CHUNK_SIZE,
                    ):

                        chunk.to_sql(
                            name=table_name,
                            con=pg_conn,
                            schema=STAGING_SCHEMA,
                            if_exists="append",
                            index=False,
                        )

                        loaded_count += len(chunk)

                    target_count = pg_conn.execute(
                        text(
                            f'SELECT COUNT(*) FROM '
                            f'"{STAGING_SCHEMA}"."{table_name}"'
                        )
                    ).scalar_one()

                    # Weryfikacja zgodności liczby rekordów.
                    if (
                        source_count != loaded_count
                        or source_count != target_count
                    ):
                        raise ValueError(
                            f"Niezgodność liczby rekordów: {table_name}. "
                            f"SQLite={source_count}, "
                            f"Python={loaded_count}, "
                            f"PostgreSQL={target_count}"
                        )

                    results[table_name] = {
                        "source": source_count,
                        "loaded": target_count,
                    }

                    logger.info(
                        "OK | %s | %s rekordów",
                        table_name,
                        target_count,
                    )

            # Wyjście z engine.begin() bez wyjątku
            # oznacza zatwierdzenie całej transakcji.
            sqlite_conn.rollback()

        logger.info("Import PMS zakończony pomyślnie.")

        print("\n========== PODSUMOWANIE IMPORTU PMS ==========")

        for table_name, counts in results.items():
            print(
                f"{table_name}: "
                f"SQLite={counts['source']} | "
                f"PostgreSQL={counts['loaded']} | OK"
            )

        print("=============================================")
        print("Wszystkie tabele PMS zostały załadowane.")

    finally:
        engine.dispose()


# ============================================================
# 6. PUNKT STARTOWY
# ============================================================

if __name__ == "__main__":

    try:
        load_data_to_staging()

    except Exception:
        logger.exception(
            "Import PMS nie powiódł się. "
            "Zmiany niezakończonej transakcji zostały wycofane."
        )
        raise SystemExit(1)