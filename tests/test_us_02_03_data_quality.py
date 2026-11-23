import sys
import unittest
from pathlib import Path
from datetime import datetime

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
    row = cur.fetchone()
    return bool(row and row[0])


def table_has_rows(cur, schema_name: str, table_name: str) -> bool:
    if not table_exists(cur, schema_name, table_name):
        return False
    cur.execute(f"SELECT EXISTS (SELECT 1 FROM {schema_name}.{table_name} LIMIT 1);")
    row = cur.fetchone()
    return bool(row and row[0])


def evaluate_data_quality_checks(conn=None, stage: str = "all") -> dict:
    """
    Uruchamia reguły DQ-01..DQ-10 w trybie fail-closed:
    - stage='core': sprawdza reguły warstwy core.clean_* (DQ-01..DQ-08) po run_cleaning.
    - stage='all': sprawdza wszystkie 10 reguł (core + mart, w tym DQ-09 i DQ-10).
    Brak wymaganej tabeli lub niewykonanie żadnego sprawdzenia w regule -> FAIL.
    """
    if stage not in ("core", "all"):
        raise ValueError("Parametr stage musi mieć wartość 'core' lub 'all'.")

    run_ts = datetime.now()
    own_conn = conn is None
    if own_conn:
        conn = connect()

    has_critical_failure = False
    results = []

    try:
        with conn.cursor() as cur:
            # Wymagane tabele warstwy core (fail-closed: brak tabeli lub pusta tabela = naruszenie)
            has_clean_res = table_has_rows(cur, "core", "clean_pms_reservations")
            has_clean_stays = table_exists(cur, "core", "clean_pms_stays")
            has_clean_rooms = table_has_rows(cur, "core", "clean_pms_rooms")
            has_clean_hotels = table_has_rows(cur, "core", "clean_pms_hotels")
            has_clean_cm = table_has_rows(cur, "core", "clean_cm_channels")
            has_clean_fin = table_has_rows(cur, "core", "clean_fin_budgets_costs")

            # Wymagane tabele warstwy mart (sprawdzane w stage='all')
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
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res,
                            "Brak lub pusta tabela core.clean_pms_reservations",
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
                            "Brak lub pusta tabela core.clean_pms_hotels",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_hotels
                            WHERE hotel_id IS NULL OR TRIM(hotel_id) = '';
                            """,
                        ),
                        (
                            has_clean_rooms,
                            "Brak lub pusta tabela core.clean_pms_rooms",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_rooms
                            WHERE room_id IS NULL OR TRIM(room_id) = ''
                               OR hotel_id IS NULL OR TRIM(hotel_id) = '';
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-02",
                    "rule_name": "Unikalność ziarna tabel faktów i oczyszczonych tabel core",
                    "severity": "CRITICAL",
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res,
                            "Brak lub pusta tabela core.clean_pms_reservations",
                            """
                            SELECT COUNT(*) FROM (
                                SELECT reservation_id FROM core.clean_pms_reservations
                                GROUP BY reservation_id HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                        (
                            has_clean_fin,
                            "Brak lub pusta tabela core.clean_fin_budgets_costs",
                            """
                            SELECT COUNT(*) FROM (
                                SELECT hotel_id, month_id, cost_category FROM core.clean_fin_budgets_costs
                                GROUP BY hotel_id, month_id, cost_category HAVING COUNT(*) > 1
                            ) d;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-03",
                    "rule_name": "Integralność referencyjna FK i zgodność hotelu pokoju",
                    "severity": "CRITICAL",
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res and has_clean_rooms and has_clean_hotels,
                            "Brak wymaganych tabel core (reservations/rooms/hotels)",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations r
                            LEFT JOIN core.clean_pms_hotels h ON r.hotel_id = h.hotel_id
                            LEFT JOIN core.clean_pms_rooms rm ON r.room_id = rm.room_id
                            WHERE h.hotel_id IS NULL OR rm.room_id IS NULL OR rm.hotel_id <> r.hotel_id;
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-04",
                    "rule_name": "Wskaźnik obłożenia hotelu OCC <= 100%",
                    "severity": "CRITICAL",
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_stays and has_clean_rooms,
                            "Brak wymaganych tabel core (clean_pms_stays / clean_pms_rooms)",
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
                    ],
                },
                {
                    "rule_id": "DQ-05",
                    "rule_name": "Poprawność chronologii i logiki dat pobytu",
                    "severity": "CRITICAL",
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res,
                            "Brak lub pusta tabela core.clean_pms_reservations",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE check_in_date IS NULL OR check_out_date IS NULL
                               OR check_in_date >= check_out_date
                               OR booking_date > check_in_date;
                            """,
                        ),
                        (
                            has_clean_stays,
                            "Brak tabeli core.clean_pms_stays",
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
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_stays and has_clean_res,
                            "Brak wymaganych tabel core (clean_pms_stays / clean_pms_reservations)",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_stays s
                            JOIN core.clean_pms_reservations r ON s.reservation_id = r.reservation_id
                            WHERE r.status IN ('Anulowana', 'No-Show');
                            """,
                        ),
                    ],
                },
                {
                    "rule_id": "DQ-07",
                    "rule_name": "Standaryzacja słowników i waluty PLN",
                    "severity": "CRITICAL",
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res,
                            "Brak lub pusta tabela core.clean_pms_reservations",
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
                            "Brak lub pusta tabela core.clean_pms_rooms",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_rooms
                            WHERE room_type NOT IN ('Standard', 'Premium', 'Apartament')
                               OR room_type IS NULL;
                            """,
                        ),
                        (
                            has_clean_cm,
                            "Brak lub pusta tabela core.clean_cm_channels",
                            """
                            SELECT COUNT(*) FROM core.clean_cm_channels
                            WHERE currency <> 'PLN';
                            """,
                        ),
                        (
                            has_clean_fin,
                            "Brak lub pusta tabela core.clean_fin_budgets_costs",
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
                    "scope": "core",
                    "checks": [
                        (
                            has_clean_res,
                            "Brak lub pusta tabela core.clean_pms_reservations",
                            """
                            SELECT COUNT(*) FROM core.clean_pms_reservations
                            WHERE room_revenue < 0 OR cancellation_fee < 0
                               OR room_revenue IS NULL OR cancellation_fee IS NULL;
                            """,
                        ),
                        (
                            has_clean_cm and has_clean_res,
                            "Brak wymaganych tabel core (clean_cm_channels / clean_pms_reservations)",
                            """
                            SELECT COUNT(*) FROM core.clean_cm_channels cm
                            JOIN core.clean_pms_reservations r ON cm.reservation_id = r.reservation_id
                            WHERE cm.commission_amount < 0 OR cm.commission_amount > r.room_revenue;
                            """,
                        ),
                        (
                            has_clean_fin,
                            "Brak lub pusta tabela core.clean_fin_budgets_costs",
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
                    "scope": "mart",
                    "checks": [
                        (
                            has_clean_res and has_mart_rn,
                            "Brak lub pusta tabela mart.fct_room_night lub core.clean_pms_reservations",
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
                    "scope": "mart",
                    "checks": [
                        (
                            has_clean_res and has_mart_date,
                            "Brak lub pusta tabela mart.dim_date lub core.clean_pms_reservations",
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

            print(f"\n=== URUCHAMIANIE TESTÓW JAKOŚCI DANYCH [stage={stage}] ({run_ts:%Y-%m-%d %H:%M:%S}) ===")
            for rule in rules:
                if stage == "core" and rule["scope"] == "mart":
                    status = "SKIPPED"
                    violations = 0
                    details = "Pominięto w etapie core (uruchamiane po odświeżeniu warstwy mart)."
                    print(f"[{status}] {rule['rule_id']} | {rule['rule_name']} -> {details}")
                    results.append({"rule_id": rule["rule_id"], "status": status, "violations": violations, "details": details})
                    continue

                violations = 0
                executed_checks = 0
                missing_reasons = []

                for is_ready, missing_msg, query in rule["checks"]:
                    if not is_ready:
                        missing_reasons.append(missing_msg)
                        continue
                    cur.execute(query)
                    row = cur.fetchone()
                    violations += int(row[0]) if row else 1
                    executed_checks += 1

                # Zasada fail-closed: brak wymaganej tabeli lub 0 wykonanych sprawdzeń -> FAIL
                if missing_reasons or executed_checks == 0:
                    violations += len(missing_reasons) if missing_reasons else 1
                    status = "FAIL"
                    has_critical_failure = True
                    reasons_txt = "; ".join(missing_reasons) if missing_reasons else "Brak wykonanych zapytań."
                    details = f"FAIL-CLOSED: {reasons_txt}"
                elif violations == 0:
                    status = "PASS"
                    details = f"Wykryto 0 naruszeń reguły {rule['rule_id']}."
                elif rule["severity"] == "CRITICAL":
                    status = "FAIL"
                    has_critical_failure = True
                    details = f"Wykryto {violations} naruszeń reguły {rule['rule_id']}."
                else:
                    status = "WARN"
                    details = f"Wykryto {violations} ostrzeżeń reguły {rule['rule_id']}."

                print(f"[{status}] {rule['rule_id']} | {rule['rule_name']} -> naruszenia: {violations} ({details})")
                results.append({"rule_id": rule["rule_id"], "status": status, "violations": violations, "details": details})

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

    failed_rules = [r["rule_id"] for r in results if r["status"] == "FAIL"]
    return {
        "passed": not has_critical_failure,
        "stage": stage,
        "failed_rules": failed_rules,
        "results": results,
    }


def run_data_quality_checks(conn=None, stage: str = "all") -> bool:
    return evaluate_data_quality_checks(conn=conn, stage=stage)["passed"]


# --- Testy jednostkowe dla `unittest discover` (workflow CI z US-02-02) ---
class _FakeCursor:
    def __init__(self, table_map, query_results):
        self.table_map = table_map
        self.query_results = query_results
        self._last = (0,)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, sql_text, params=None):
        sql_clean = " ".join(sql_text.split())
        if "information_schema.tables" in sql_clean:
            schema, table = params
            exists = f"{schema}.{table}" in self.table_map
            self._last = (exists,)
        elif sql_clean.startswith("SELECT EXISTS (SELECT 1 FROM "):
            target = sql_clean.split("FROM ")[1].split(" LIMIT 1")[0]
            has_rows = bool(self.table_map.get(target, False))
            self._last = (has_rows,)
        elif "INSERT INTO core.dq_test_log" in sql_clean:
            self._last = (1,)
        else:
            for key, val in self.query_results.items():
                if key in sql_clean:
                    self._last = (val,)
                    return
            self._last = (0,)

    def fetchone(self):
        return self._last


class _FakeConn:
    def __init__(self, table_map, query_results=None):
        self.table_map = table_map
        self.query_results = query_results or {}
        self.committed = False

    def cursor(self):
        return _FakeCursor(self.table_map, self.query_results)

    def commit(self):
        self.committed = True

    def close(self):
        pass


class TestDataQualityGate(unittest.TestCase):
    FULL_TABLES = {
        "core.clean_pms_reservations": True,
        "core.clean_pms_stays": True,
        "core.clean_pms_rooms": True,
        "core.clean_pms_hotels": True,
        "core.clean_cm_channels": True,
        "core.clean_fin_budgets_costs": True,
        "mart.fct_reservations": True,
        "mart.fct_room_night": True,
        "mart.fct_room_inventory": True,
        "mart.dim_date": True,
        "core.dq_test_log": True,
    }

    def test_01_valid_package_passes(self):
        conn = _FakeConn(self.FULL_TABLES)
        res = evaluate_data_quality_checks(conn=conn, stage="all")
        self.assertTrue(res["passed"])
        self.assertEqual(res["failed_rules"], [])

    def test_02_occupancy_above_100_percent_fails_dq04(self):
        conn = _FakeConn(self.FULL_TABLES, query_results={"WHERE ds.sold_nights > c.total_rooms": 3})
        res = evaluate_data_quality_checks(conn=conn, stage="all")
        self.assertFalse(res["passed"])
        self.assertIn("DQ-04", res["failed_rules"])

    def test_03_missing_or_empty_mart_table_fails_dq09(self):
        tables = dict(self.FULL_TABLES)
        tables["mart.fct_room_night"] = False  # pusta tabela wymagana przez DQ-09
        conn = _FakeConn(tables)
        res = evaluate_data_quality_checks(conn=conn, stage="all")
        self.assertFalse(res["passed"])
        self.assertIn("DQ-09", res["failed_rules"])

    def test_04_missing_all_tables_fails_closed(self):
        conn = _FakeConn({})
        res = evaluate_data_quality_checks(conn=conn, stage="all")
        self.assertFalse(res["passed"])
        self.assertEqual(len(res["failed_rules"]), 10)


if __name__ == "__main__":
    stage_arg = "core" if "--stage-core" in sys.argv else "all"
    outcome = evaluate_data_quality_checks(stage=stage_arg)
    if not outcome["passed"]:
        print(f"\n[BŁĄD KRYTYCZNY] Wykryto naruszenia jakości danych ({', '.join(outcome['failed_rules'])}). Propagacja wstrzymana.")
        sys.exit(1)
    print("\n[SUKCES] Kontrola jakości danych zakończona statusem PASS.")