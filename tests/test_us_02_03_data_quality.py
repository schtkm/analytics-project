import sys
from pathlib import Path
from datetime import datetime

# Umożliwia uruchomienie zarówno przez `python tests/test_us_02_03_data_quality.py`, jak i `pytest`
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from etl.run_cleaning import connect


def table_exists(cur, schema_name: str, table_name: str) -> bool:
    cur.execute(
        """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = %s AND table_name = %s
        );
        """,
        (schema_name, table_name),
    )
    return bool(cur.fetchone()[0])


def table_has_rows(cur, schema_name: str, table_name: str) -> bool:
    if not table_exists(cur, schema_name, table_name):
        return False
    cur.execute(f"SELECT EXISTS (SELECT 1 FROM {schema_name}.{table_name} LIMIT 1);")
    return bool(cur.fetchone()[0])


def run_data_quality_checks(conn=None) -> bool:
    run_ts = datetime.now()
    own_conn = conn is None
    if own_conn:
        conn = connect()

    has_critical_failure = False

    try:
        with conn.cursor() as cur:
            has_clean_res = table_exists(cur, "core", "clean_pms_reservations")
            has_clean_stays = table_exists(cur, "core", "clean_pms_stays")
            has_clean_rooms = table_exists(cur, "core", "clean_pms_rooms")
            has_clean_hotels = table_exists(cur, "core", "clean_pms_hotels")
            has_clean_cm = table_exists(cur, "core", "clean_cm_channels")
            has_clean_fin = table_exists(cur, "core", "clean_fin_budgets_costs")

            has_mart_res = table_has_rows(cur, "mart", "fct_reservations")
            has_mart_rn = table_has_rows(cur, "mart", "fct_room_night")
            has_mart_inv = table_has_rows(cur, "mart", "fct_room_inventory")
            has_mart_date = table_has_rows(cur, "mart", "dim_date")
            has_log_table = table_exists(cur, "core", "dq_test_log")

            rules = [
                {
                    "rule_id": "DQ-01",
                    "rule_name": "Brak pustych kluczy głównych i biznesowych",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE reservation_id IS NULL OR TRIM(reservation_id) = ''
                               OR hotel_id IS NULL OR TRIM(hotel_id) = ''
                               OR guest_id IS NULL OR TRIM(guest_id) = ''
                               OR room_id IS NULL OR TRIM(room_id) = '';
                            """,
                        ),
                        (
                            has_clean_hotels,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_hotels
                            WHERE hotel_id IS NULL OR TRIM(hotel_id) = '';
                            """,
                        ),
                        (
                            has_clean_rooms,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_rooms
                            WHERE room_id IS NULL OR TRIM(room_id) = ''
                               OR hotel_id IS NULL OR TRIM(hotel_id) = '';
                            """,
                        ),
                        (
                            has_mart_res,
                            """
                            SELECT COUNT(*) FROM mart.fct_reservations
                            WHERE reservation_bk IS NULL OR TRIM(reservation_bk) = '';
                            """,
                        ),
                        (
                            has_mart_rn,
                            """
                            SELECT COUNT(*) FROM mart.fct_room_night
                            WHERE stay_date_sk IS NULL OR hotel_sk IS NULL OR room_sk IS NULL;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-02",
                    "rule_name": "Unikalność ziarna tabel faktów i oczyszczonych tabel core",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res,
                            """
                            SELECT COUNT(*) FROM (
                                SELECT reservation_id FROM core.clean_pms_reservations
                                GROUP BY reservation_id HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                        (
                            has_clean_fin,
                            """
                            SELECT COUNT(*) FROM (
                                SELECT hotel_id, month_id, cost_category FROM core.clean_fin_budgets_costs
                                GROUP BY hotel_id, month_id, cost_category HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                        (
                            has_mart_res,
                            """
                            SELECT COUNT(*) FROM (
                                SELECT reservation_bk FROM mart.fct_reservations
                                GROUP BY reservation_bk HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                        (
                            has_mart_rn,
                            """
                            SELECT COUNT(*) FROM (
                                SELECT room_sk, stay_date_sk FROM mart.fct_room_night
                                GROUP BY room_sk, stay_date_sk HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-03",
                    "rule_name": "Integralność referencyjna FK i zgodność hotelu pokoju",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res and has_clean_rooms and has_clean_hotels,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations r
                            LEFT JOIN core.clean_pms_hotels h ON r.hotel_id = h.hotel_id
                            LEFT JOIN core.clean_pms_rooms rm ON r.room_id = rm.room_id
                            WHERE h.hotel_id IS NULL OR rm.room_id IS NULL OR rm.hotel_id <> r.hotel_id;
                            """,
                        ),
                        (
                            has_mart_rn,
                            """
                            SELECT COUNT(*) FROM mart.fct_room_night rn
                            JOIN mart.dim_room r ON rn.room_sk = r.room_sk
                            WHERE r.room_sk > 0 AND rn.hotel_sk <> r.hotel_sk;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-04",
                    "rule_name": "Wskaźnik obłożenia hotelu OCC <= 100%",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_stays and has_clean_rooms,
                            """
                            WITH stayed_nights AS (
                                SELECT rm.hotel_id,
                                       generate_series(
                                           s.actual_check_in,
                                           COALESCE(s.actual_check_out, s.actual_check_in) - INTERVAL '1 day',
                                           INTERVAL '1 day'
                                       )::date AS stay_date
                                FROM core.clean_pms_stays s
                                JOIN core.clean_pms_rooms rm ON s.room_id = rm.room_id
                                WHERE s.actual_check_out IS NULL OR s.actual_check_out > s.actual_check_in
                            ),
                            daily_sold AS (
                                SELECT hotel_id, stay_date, COUNT(*) AS sold_nights
                                FROM stayed_nights
                                GROUP BY hotel_id, stay_date
                            ),
                            capacity AS (
                                SELECT hotel_id, COUNT(*) AS total_rooms
                                FROM core.clean_pms_rooms
                                GROUP BY hotel_id
                            )
                            SELECT COUNT(*)
                            FROM daily_sold ds
                            JOIN capacity c ON ds.hotel_id = c.hotel_id
                            WHERE ds.sold_nights > c.total_rooms;
                            """,
                        ),
                        (
                            has_mart_rn and has_mart_inv,
                            """
                            WITH sold AS (
                                SELECT hotel_sk, stay_date_sk AS date_sk, COUNT(*) AS sold_nights
                                FROM mart.fct_room_night
                                GROUP BY hotel_sk, stay_date_sk
                            ),
                            inv AS (
                                SELECT hotel_sk, inventory_date_sk AS date_sk, SUM(available_room_nights) AS avail_nights
                                FROM mart.fct_room_inventory
                                GROUP BY hotel_sk, inventory_date_sk
                            )
                            SELECT COUNT(*)
                            FROM sold s
                            LEFT JOIN inv i ON s.hotel_sk = i.hotel_sk AND s.date_sk = i.date_sk
                            WHERE s.sold_nights > COALESCE(i.avail_nights, 0);
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-05",
                    "rule_name": "Poprawność chronologii i logiki dat pobytu",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE check_in_date IS NULL OR check_out_date IS NULL
                               OR check_in_date >= check_out_date
                               OR booking_date > check_in_date;
                            """,
                        ),
                        (
                            has_clean_stays,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_stays
                            WHERE actual_check_in IS NULL
                               OR (actual_check_out IS NOT NULL AND actual_check_out < actual_check_in);
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-06",
                    "rule_name": "Spójność statusów rezerwacji z realizacją pobytów",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_stays and has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_stays s
                            JOIN core.clean_pms_reservations r ON s.reservation_id = r.reservation_id
                            WHERE r.status IN ('Anulowana', 'No-Show');
                            """,
                        ),
                        (
                            has_mart_res,
                            """
                            SELECT COUNT(*) FROM mart.fct_reservations
                            WHERE reservation_status = 'Anulowana'
                              AND (cancellation_date_sk IS NULL OR cancellation_date_sk = -1);
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-07",
                    "rule_name": "Standaryzacja słowników i waluty PLN",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE status NOT IN ('Zakończona', 'W trakcie', 'Oczekująca', 'Anulowana', 'No-Show')
                               OR status IS NULL
                               OR guest_segment NOT IN ('Biznes', 'Turystyczny', 'Rodzinny')
                               OR guest_segment IS NULL
                               OR currency <> 'PLN';
                            """,
                        ),
                        (
                            has_clean_rooms,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_rooms
                            WHERE room_type NOT IN ('Standard', 'Premium', 'Apartament')
                               OR room_type IS NULL;
                            """,
                        ),
                        (
                            has_clean_cm,
                            """
                            SELECT COUNT(*) FROM core.clean_cm_channels
                            WHERE currency <> 'PLN';
                            """,
                        ),
                        (
                            has_clean_fin,
                            """
                            SELECT COUNT(*) FROM core.clean_fin_budgets_costs
                            WHERE currency <> 'PLN';
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-08",
                    "rule_name": "Nieujemne kwoty finansowe i poprawny zakres prowizji",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE room_revenue < 0 OR cancellation_fee < 0
                               OR room_revenue IS NULL OR cancellation_fee IS NULL;
                            """,
                        ),
                        (
                            has_clean_cm and has_clean_res,
                            """
                            SELECT COUNT(*) FROM core.clean_cm_channels cm
                            JOIN core.clean_pms_reservations r ON cm.reservation_id = r.reservation_id
                            WHERE cm.commission_amount < 0 OR cm.commission_amount > r.room_revenue;
                            """,
                        ),
                        (
                            has_clean_fin,
                            """
                            SELECT COUNT(*) FROM core.clean_fin_budgets_costs
                            WHERE budget_amount < 0 OR actual_cost < 0;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-09",
                    "rule_name": "Uzgodnienie przychodów core <-> mart (tolerancja 0,1% - NFR-02)",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res and has_mart_rn,
                            """
                            WITH rev_core AS (
                                SELECT COALESCE(SUM(room_revenue), 0) AS total_rev
                                FROM core.clean_pms_reservations
                                WHERE status IN ('Zakończona', 'W trakcie')
                            ),
                            rev_mart AS (
                                SELECT COALESCE(SUM(room_revenue), 0) AS total_rev
                                FROM mart.fct_room_night
                            )
                            SELECT CASE
                                WHEN c.total_rev = 0 AND m.total_rev = 0 THEN 0
                                WHEN c.total_rev = 0 AND m.total_rev > 0 THEN 1
                                WHEN ABS(c.total_rev - m.total_rev) / c.total_rev > 0.001 THEN 1
                                ELSE 0
                            END
                            FROM rev_core c CROSS JOIN rev_mart m;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-10",
                    "rule_name": "Kompletność wymiaru czasu mart.dim_date dla zakresu rezerwacji",
                    "severity": "CRITICAL",
                    "checks": [
                        (
                            has_clean_res and has_mart_date,
                            """
                            WITH bounds AS (
                                SELECT MIN(booking_date) AS min_d, MAX(check_out_date) AS max_d
                                FROM core.clean_pms_reservations
                            ),
                            expected_days AS (
                                SELECT generate_series(min_d, max_d, interval '1 day')::date AS d
                                FROM bounds
                                WHERE min_d IS NOT NULL AND max_d IS NOT NULL
                            )
                            SELECT COUNT(*)
                            FROM expected_days e
                            LEFT JOIN mart.dim_date dd ON dd.full_date = e.d
                            WHERE dd.date_sk IS NULL;
                            """,
                        ),
                    ],
                },
            ]

            print(f"\n=== URUCHAMIANIE TESTÓW JAKOŚCI DANYCH ({run_ts:%Y-%m-%d %H:%M:%S}) ===")
            for rule in rules:
                violations = 0
                for is_applicable, query in rule["checks"]:
                    if not is_applicable:
                        continue
                    cur.execute(query)
                    violations += int(cur.fetchone()[0])

                if violations == 0:
                    status = "PASS"
                elif rule["severity"] == "CRITICAL":
                    status = "FAIL"
                    has_critical_failure = True
                else:
                    status = "WARN"

                details = f"Wykryto {violations} naruszeń reguły {rule['rule_id']}."
                print(f"[{status}] {rule['rule_id']} | {rule['rule_name']} -> naruszenia: {violations}")

                if has_log_table:
                    cur.execute(
                        """
                        INSERT INTO core.dq_test_log
                            (run_timestamp, rule_id, rule_name, severity, violations_count, status, details)
                        VALUES (%s, %s, %s, %s, %s, %s, %s);
                        """,
                        (
                            run_ts,
                            rule["rule_id"],
                            rule["rule_name"],
                            rule["severity"],
                            violations,
                            status,
                            details,
                        ),
                    )
        conn.commit()
    finally:
        if own_conn:
            conn.close()

    return not has_critical_failure


def test_all_data_quality_rules():
    assert run_data_quality_checks(), "Co najmniej jedna krytyczna reguła jakości danych (DQ) nie przeszła walidacji!"


if __name__ == "__main__":
    success = run_data_quality_checks()
    if not success:
        print("\n[BŁĄD KRYTYCZNY] Wykryto naruszenia jakości danych. Propagacja do warstwy raportowej wstrzymana.")
        sys.exit(1)
    print("\n[SUKCES] Wszystkie 10 reguł jakości danych zakończyły się statusem PASS.")