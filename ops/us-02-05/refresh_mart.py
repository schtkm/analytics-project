import argparse
import re
import sys
from pathlib import Path

from psycopg import sql

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from etl.run_cleaning import connect


def transaction_body(path):
    script = path.read_text(encoding="utf-8-sig")
    match = re.search(r"^BEGIN;\s*\n(.*?)^COMMIT;", script, re.M | re.S)
    if match is None:
        raise ValueError(f"Nie znaleziono bloku BEGIN/COMMIT w {path}")
    return match[1]


def refresh_fact(conn, path, table, keys):
    body = transaction_body(path)
    target = f"mart.{table}"
    match = re.search(
        rf"INSERT INTO {re.escape(target)}\s*\(([^)]+)\)", body, re.I
    )
    if match is None:
        raise ValueError(f"Nie znaleziono kolumn INSERT w {path}")

    columns = [column.strip() for column in match[1].split(",")]
    fields = [column for column in columns if column not in keys]
    identifiers = sql.SQL(", ").join(map(sql.Identifier, columns))
    fact = sql.Identifier("mart", table)
    temp_name = f"refresh_{table}"
    temp = sql.Identifier("pg_temp", temp_name)

    conn.execute(sql.SQL(
        "CREATE TEMP TABLE {} ON COMMIT DROP AS SELECT {} FROM {} WITH NO DATA"
    ).format(sql.Identifier(temp_name), identifiers, fact))
    conn.execute(body.replace(target, f"pg_temp.{temp_name}"))
    conn.execute(sql.SQL("ANALYZE {}").format(temp))

    key_match = sql.SQL(" AND ").join(
        sql.SQL("t.{0} = s.{0}").format(sql.Identifier(key)) for key in keys
    )
    old_values = sql.SQL(", ").join(sql.Identifier("t", field) for field in fields)
    new_values = sql.SQL(", ").join(sql.Identifier("s", field) for field in fields)
    assignments = sql.SQL(", ").join(
        sql.SQL("{0} = s.{0}").format(sql.Identifier(field)) for field in fields
    )
    insert_values = sql.SQL(", ").join(
        sql.Identifier("s", column) for column in columns
    )

    changed = conn.execute(sql.SQL("""
        MERGE INTO {fact} AS t
        USING {temp} AS s ON {key_match}
        WHEN MATCHED AND ROW({old_values}) IS DISTINCT FROM ROW({new_values})
            THEN UPDATE SET {assignments}
        WHEN NOT MATCHED THEN INSERT ({columns}) VALUES ({insert_values})
    """).format(
        fact=fact, temp=temp, key_match=key_match,
        old_values=old_values, new_values=new_values,
        assignments=assignments, columns=identifiers, insert_values=insert_values,
    )).rowcount

    removed = conn.execute(sql.SQL("""
        DELETE FROM {} AS t
        WHERE NOT EXISTS (SELECT 1 FROM {} AS s WHERE {})
    """).format(fact, temp, key_match)).rowcount
    print(f"{target} | dodane lub zmienione={changed} | usunięte={removed}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    seeds = ROOT / "database/seeds"

    with connect() as conn:
        conn.autocommit = True
        with conn.transaction(force_rollback=not args.apply):
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            conn.execute("SET LOCAL lock_timeout = '30s'")
            conn.execute("SELECT pg_advisory_xact_lock(20260205)")
            for path in (
                seeds / "US-03-04_load_dimensions.sql",
                seeds / "US-03-05_load_room_dimensions.sql",
                ROOT / "ops/us-02-05/refresh_reservations.sql",
            ):
                conn.execute(transaction_body(path))
                print(f"OK {path.name}", flush=True)

            refresh_fact(conn, seeds / "US-03-05A_load_fct_room_night.sql",
                         "fct_room_night", ("stay_bk", "room_sk", "stay_date_sk"))
            refresh_fact(conn, seeds / "US-03-05B_load_fct_room_inventory.sql",
                         "fct_room_inventory", ("room_sk", "inventory_date_sk"))

    print("Zapisano odświeżenie mart." if args.apply else "Próba OK. Wycofano zmiany w tabelach.")


if __name__ == "__main__":
    main()
