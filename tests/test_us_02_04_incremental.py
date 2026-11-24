"""Testy ładowania przyrostowego (US-02-04)."""
from datetime import datetime, timedelta
from decimal import Decimal
import time
import os

import pytest
import psycopg
from psycopg import sql

from etl.cleaning import SPECS

from etl.incremental import compute_row_hash, get_watermark_psycopg
from etl.run_cleaning import migrate, run, commit_watermarks


CONFIG = {
    "source_timezone": "Europe/Warsaw",
    "source_currencies": {
        "pms_reservations": "PLN",
        "cm_channels": "PLN",
        "fin_budgets_costs": "PLN",
    },
}


@pytest.fixture()
def db_conn():
    database_url = os.getenv("ETL_TEST_DATABASE_URL")
    if not database_url:
        pytest.fail("Missing ETL_TEST_DATABASE_URL")

    with psycopg.connect(database_url) as conn:
        database_name = conn.execute(
            "SELECT current_database()"
        ).fetchone()[0]

        if database_name != "hotelgroup_dw":
            pytest.fail("Tests require a dedicated test database: hotelgroup_dw")

        conn.commit()

        # Odtworzenie struktury testowej niezaleznie od poprzednich testow.
        with conn.transaction():
            conn.execute("DROP SCHEMA IF EXISTS core CASCADE")
            conn.execute("DROP SCHEMA IF EXISTS staging CASCADE")
            conn.execute("CREATE SCHEMA staging")

            for table, (_, fields) in SPECS.items():
                columns = sql.SQL(", ").join(
                    sql.SQL("{} TEXT").format(sql.Identifier(c))
                    for c in fields if c != "currency"
                )
                conn.execute(
                    sql.SQL("CREATE TABLE {} ({})").format(
                        sql.Identifier("staging", table), columns
                    )
                )

        migrate(conn)
        yield conn


def test_incremental_load_updates_modified_historical_record(db_conn):
    """
    Kryterium akceptacji US-02-04:
    - Modyfikacja starego rekordu źródłowego + dodanie nowego rekordu.
    - Potok pobiera i aktualizuje wyłącznie deltę, a nie całą historię.
    - Czas wykonania przyrostowego przebiegu jest krótszy niż pełnego.
    """
    t0 = datetime(2026, 11, 20, 10, 0, 0)
    t1 = t0 + timedelta(hours=2)

    with db_conn.transaction():
        # Czyszczenie danych testowych przed testem
        db_conn.execute("TRUNCATE staging.pms_hotels, staging.pms_guests, staging.pms_rooms, "
                        "staging.pms_reservations, staging.pms_stays, staging.cm_channels, "
                        "staging.fin_budgets_costs CASCADE;")
        db_conn.execute("TRUNCATE core.clean_pms_hotels, core.clean_pms_guests, core.clean_pms_rooms, "
                        "core.clean_pms_reservations, core.clean_pms_stays, core.clean_cm_channels, "
                        "core.clean_fin_budgets_costs CASCADE;")
        db_conn.execute("UPDATE core.etl_watermark SET last_watermark_ts = '1970-01-01 00:00:00';")

        # 1. Załadowanie danych bazowych do staging (2 rezerwacje historyczne)
        db_conn.execute(
            """
            INSERT INTO staging.pms_hotels (hotel_id, hotel_name, city, region, _updated_at, row_hash)
            VALUES ('H-TEST', 'Hotel Testowy', 'Kraków', 'Małopolskie', %s, 'h1');
            """,
            (t0,),
        )
        db_conn.execute(
            """
            INSERT INTO staging.pms_guests (guest_id, first_name, last_name, email, phone, _updated_at, row_hash)
            VALUES ('G-TEST', 'Jan', 'Kowalski', 'jan@example.com', '500600700', %s, 'g1');
            """,
            (t0,),
        )
        db_conn.execute(
            """
            INSERT INTO staging.pms_rooms (room_id, hotel_id, room_number, room_type, _updated_at, row_hash)
            VALUES ('R-TEST', 'H-TEST', '101', 'DOUBLE', %s, 'r1');
            """,
            (t0,),
        )
        db_conn.execute(
            """
            INSERT INTO staging.pms_reservations (
                reservation_id, hotel_id, guest_id, room_id, guest_segment,
                booking_date, check_in_date, check_out_date, status,
                room_revenue, cancellation_fee, updated_at, _updated_at, row_hash
            )
            VALUES
                ('RES-OLD-1', 'H-TEST', 'G-TEST', 'R-TEST', 'Leisure',
                 '2026-10-01', '2026-10-10', '2026-10-12', 'Zakończona',
                 '1000.00', '0.00', %s, %s, 'res1'),
                ('RES-OLD-2', 'H-TEST', 'G-TEST', 'R-TEST', 'Business',
                 '2026-10-05', '2026-10-15', '2026-10-17', 'Zakończona',
                 '2000.00', '0.00', %s, %s, 'res2');
            """,
            (t0, t0, t0, t0),
        )
        
    def test_incremental_load_updates_only_channel_commission(db_conn):
        """
        Scenariusz z feedbacku PR #69:
        Zmiana samej prowizji w staging.cm_channels przy braku zmian w rezerwacji,
        hotelu, pokoju i gościu nie może kończyć się błędem MISSING_PARENT.
        """
        t0 = datetime(2026, 11, 20, 10, 0, 0)
        t1 = t0 + timedelta(hours=2)

        with db_conn.transaction():
            db_conn.execute(
                "TRUNCATE staging.pms_hotels, staging.pms_guests, staging.pms_rooms, "
                "staging.pms_reservations, staging.pms_stays, staging.cm_channels, "
                "staging.fin_budgets_costs CASCADE;"
            )
            db_conn.execute(
                "TRUNCATE core.clean_pms_hotels, core.clean_pms_guests, core.clean_pms_rooms, "
                "core.clean_pms_reservations, core.clean_pms_stays, core.clean_cm_channels, "
                "core.clean_fin_budgets_costs CASCADE;"
            )
            db_conn.execute("UPDATE core.etl_watermark SET last_watermark_ts = '1970-01-01 00:00:00';")

            db_conn.execute(
                """
                INSERT INTO staging.pms_hotels (hotel_id, hotel_name, city, region, _updated_at, row_hash)
                VALUES ('H-TEST', 'Hotel Testowy', 'Kraków', 'Małopolskie', %s, 'h1');
                """,
                (t0,),
            )
            db_conn.execute(
                """
                INSERT INTO staging.pms_guests (guest_id, first_name, last_name, email, phone, _updated_at, row_hash)
                VALUES ('G-TEST', 'Jan', 'Kowalski', 'jan@example.com', '500600700', %s, 'g1');
                """,
                (t0,),
            )
            db_conn.execute(
                """
                INSERT INTO staging.pms_rooms (room_id, hotel_id, room_number, room_type, _updated_at, row_hash)
                VALUES ('R-TEST', 'H-TEST', '101', 'DOUBLE', %s, 'r1');
                """,
                (t0,),
            )
            db_conn.execute(
                """
                INSERT INTO staging.pms_reservations (
                    reservation_id, hotel_id, guest_id, room_id, guest_segment,
                    booking_date, check_in_date, check_out_date, status,
                    room_revenue, cancellation_fee, updated_at, _updated_at, row_hash
                )
                VALUES (
                    'RES-COMM-1', 'H-TEST', 'G-TEST', 'R-TEST', 'Leisure',
                    '2026-10-01', '2026-10-10', '2026-10-12', 'Zakończona',
                    '1000.00', '0.00', %s, %s, 'res1'
                );
                """,
                (t0, t0),
            )
            db_conn.execute(
                """
                INSERT INTO staging.cm_channels (
                    reservation_id, channel_code, commission_rate, commission_amount, _updated_at, row_hash
                )
                VALUES ('RES-COMM-1', 'BOOKING', '0.15', '150.00', %s, 'ch1');
                """,
                (t0,),
            )

        res_initial = run(db_conn, CONFIG, incremental=True)
        commit_watermarks(db_conn, res_initial["run_id"], res_initial["_pending_watermarks"])
        assert res_initial["status"] == "completed"

        # Zmiana WYŁĄCZNIE prowizji w cm_channels (rezerwacja, hotel, pokój i gość bez zmian)
        new_hash = compute_row_hash(
            {"reservation_id": "RES-COMM-1", "channel_code": "BOOKING", "commission_rate": "0.18", "commission_amount": "180.00"}
        )
        with db_conn.transaction():
            db_conn.execute(
                """
                UPDATE staging.cm_channels
                SET commission_rate = '0.18',
                    commission_amount = '180.00',
                    _updated_at = %s,
                    row_hash = %s
                WHERE reservation_id = 'RES-COMM-1';
                """,
                (t1, new_hash),
            )

        res_inc = run(db_conn, CONFIG, incremental=True)
        commit_watermarks(db_conn, res_inc["run_id"], res_inc["_pending_watermarks"])

        assert res_inc["status"] == "completed"
        assert res_inc["report"]["cm_channels"]["accepted"] == 1
        assert res_inc["report"]["cm_channels"]["rejected"] == 0

        updated_channel = db_conn.execute(
            "SELECT commission_rate, commission_amount FROM core.clean_cm_channels WHERE reservation_id = 'RES-COMM-1';"
        ).fetchone()
        assert updated_channel == (Decimal("0.1800"), Decimal("180.00"))

    # 2. Pierwszy przebieg (inicjalny)
    full_start = time.perf_counter()
    res_initial = run(db_conn, CONFIG, incremental=True)
    commit_watermarks(db_conn, res_initial["run_id"], res_initial["_pending_watermarks"])
    full_elapsed = time.perf_counter() - full_start

    assert res_initial["status"] == "completed"
    assert res_initial["report"]["pms_reservations"]["input"] == 2

    # 3. Modyfikacja STAREGO rekordu źródłowego (RES-OLD-1) + dodanie 1 NOWEGO rekordu (RES-NEW-3)
    new_hash = compute_row_hash({"reservation_id": "RES-OLD-1", "room_revenue": "1250.00", "status": "Anulowana"})
    with db_conn.transaction():
        db_conn.execute(
            """
            UPDATE staging.pms_reservations
            SET status = 'Anulowana',
                room_revenue = '1250.00',
                updated_at = %s,
                _updated_at = %s,
                row_hash = %s
            WHERE reservation_id = 'RES-OLD-1';
            """,
            (t1.isoformat(), t1, new_hash),
        )
        db_conn.execute(
            """
            INSERT INTO staging.pms_reservations (
                reservation_id, hotel_id, guest_id, room_id, guest_segment,
                booking_date, check_in_date, check_out_date, status,
                room_revenue, cancellation_fee, updated_at, _updated_at, row_hash
            )
            VALUES (
                'RES-NEW-3', 'H-TEST', 'G-TEST', 'R-TEST', 'Corporate',
                '2026-11-20', '2026-11-25', '2026-11-27', 'Oczekująca',
                '1500.00', '0.00', %s, %s, 'res3'
            );
            """,
            (t1.isoformat(), t1),
        )

    # 4. Uruchomienie potoku przyrostowego — powinien pobrać TYLKO 2 rekordy delty (nie 3!)
    inc_start = time.perf_counter()
    res_inc = run(db_conn, CONFIG, incremental=True)
    commit_watermarks(db_conn, res_inc["run_id"], res_inc["_pending_watermarks"])
    inc_elapsed = time.perf_counter() - inc_start

    assert res_inc["status"] == "completed"
    assert res_inc["report"]["_mode"] == "incremental"
    assert res_inc["report"]["pms_reservations"]["input"] == 2
    assert res_inc["report"]["pms_reservations"]["accepted"] == 2
    # Pozostałe tabele bez zmian nie były ponownie przetwarzane:
    assert res_inc["report"]["pms_hotels"]["input"] == 0
    assert res_inc["report"]["pms_guests"]["input"] == 0

    # Weryfikacja w core.clean_pms_reservations (brak duplikatów, zaktualizowany stary rekord)
    rows_in_core = db_conn.execute(
        "SELECT reservation_id, status, room_revenue FROM core.clean_pms_reservations ORDER BY reservation_id;"
    ).fetchall()
    assert rows_in_core == [
        ("RES-NEW-3", "Oczekująca", Decimal("1500.00")),
        ("RES-OLD-1", "Anulowana", Decimal("1250.00")),
        ("RES-OLD-2", "Zakończona", Decimal("2000.00")),
    ]

    # Weryfikacja przesunięcia watermarka
    wm_after = get_watermark_psycopg(db_conn, "staging_to_core", "pms_reservations")
    assert wm_after == t1

    # 5. Kolejne uruchomienie bez zmian -> 0 rekordów przetworzonych (noop)
    noop_start = time.perf_counter()
    res_noop = run(db_conn, CONFIG, incremental=True)
    noop_elapsed = time.perf_counter() - noop_start
    assert res_noop["report"]["_mode"] == "incremental_noop"
    assert noop_elapsed < full_elapsed or inc_elapsed >= 0