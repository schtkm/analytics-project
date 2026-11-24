"""Wspólne narzędzia ładowania przyrostowego (US-02-04)."""

from datetime import datetime
from decimal import Decimal
import hashlib
import json
from typing import Any, Iterable, Sequence

from psycopg import sql
from sqlalchemy import text


EPOCH_WATERMARK = datetime(1970, 1, 1, 0, 0, 0)


def _normalize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, Decimal):
        return f"{value:.4f}"
    if isinstance(value, float):
        return f"{value:.4f}"
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def compute_row_hash(row: dict[str, Any], exclude_cols: Iterable[str] = ()) -> str:
    """Wylicza deterministyczny hash SHA-256 wiersza na potrzeby CDC."""
    excluded = {"_inserted_at", "_updated_at", "row_hash", *exclude_cols}
    normalized = {
        key: _normalize_value(val)
        for key, val in sorted(row.items())
        if key not in excluded
    }
    raw = json.dumps(normalized, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def ensure_watermark_table_exists(pg_conn) -> None:
    exists = pg_conn.execute(
        text("SELECT to_regclass('core.etl_watermark')")
    ).scalar_one()
    if exists is None:
        raise RuntimeError(
            "Brak tabeli core.etl_watermark. "
            "Uruchom najpierw migrację database/migrations/US-02-04_incremental_load.sql."
        )


def get_watermark_sa(pg_conn, source_system: str, table_name: str) -> datetime:
    """Pobiera ostatni znacznik czasu ładowania (SQLAlchemy connection)."""
    row = pg_conn.execute(
        text("""
            SELECT last_watermark_ts
            FROM core.etl_watermark
            WHERE source_system = :src AND table_name = :tbl
        """),
        {"src": source_system, "tbl": table_name},
    ).fetchone()
    if row and row[0] is not None:
        return row[0].replace(tzinfo=None)
    return EPOCH_WATERMARK


def update_watermark_sa(
    pg_conn,
    source_system: str,
    table_name: str,
    new_watermark_ts: datetime,
    rows_extracted: int,
    rows_upserted: int,
    run_id: str | None = None,
    status: str = "SUCCESS",
) -> None:
    """Aktualizuje stan ładowania po poprawnym zatwierdzeniu paczki."""
    pg_conn.execute(
        text("""
            INSERT INTO core.etl_watermark (
                source_system, table_name, last_watermark_ts,
                last_run_id, rows_extracted, rows_upserted, status, updated_at
            )
            VALUES (
                :src, :tbl, :wm, :run_id, :extracted, :upserted, :status, CURRENT_TIMESTAMP
            )
            ON CONFLICT (source_system, table_name) DO UPDATE SET
                last_watermark_ts = EXCLUDED.last_watermark_ts,
                last_run_id       = EXCLUDED.last_run_id,
                rows_extracted    = EXCLUDED.rows_extracted,
                rows_upserted     = EXCLUDED.rows_upserted,
                status            = EXCLUDED.status,
                updated_at        = CURRENT_TIMESTAMP
        """),
        {
            "src": source_system,
            "tbl": table_name,
            "wm": new_watermark_ts.replace(tzinfo=None),
            "run_id": run_id,
            "extracted": rows_extracted,
            "upserted": rows_upserted,
            "status": status,
        },
    )


def upsert_records_sa(
    pg_conn,
    schema: str,
    table: str,
    records: list[dict[str, Any]],
    business_cols: Sequence[str],
    conflict_cols: Sequence[str],
    chunk_size: int = 2000,
) -> int:
    """
    Wykonuje idempotentny UPSERT do PostgreSQL.
    Aktualizuje istniejący rekord wyłącznie gdy zmienił się jego row_hash.
    Zwraca faktyczną liczbę wstawionych lub zaktualizowanych wierszy.
    """
    if not records:
        return 0

    all_cols = [*business_cols, "row_hash"]
    cols_sql = ", ".join(f'"{c}"' for c in all_cols)
    vals_sql = ", ".join(f":{c}" for c in all_cols)
    conflict_sql = ", ".join(f'"{c}"' for c in conflict_cols)

    update_cols = [c for c in all_cols if c not in conflict_cols]
    set_clauses = [f'"{c}" = EXCLUDED."{c}"' for c in update_cols]
    set_clauses.append('"_updated_at" = CURRENT_TIMESTAMP')
    set_sql = ", ".join(set_clauses)

    stmt = text(f"""
        INSERT INTO "{schema}"."{table}" ({cols_sql})
        VALUES ({vals_sql})
        ON CONFLICT ({conflict_sql}) DO UPDATE SET
            {set_sql}
        WHERE "{schema}"."{table}"."row_hash" IS DISTINCT FROM EXCLUDED."row_hash"
    """)

    affected = 0
    for start in range(0, len(records), chunk_size):
        chunk = records[start : start + chunk_size]
        res = pg_conn.execute(stmt, chunk)
        if res.rowcount and res.rowcount > 0:
            affected += res.rowcount
    return affected


def get_watermark_psycopg(conn, source_system: str, table_name: str) -> datetime:
    """Pobiera ostatni znacznik czasu udanego ładowania (połączenie psycopg)."""
    row = conn.execute(
        """
        SELECT last_watermark_ts
        FROM core.etl_watermark
        WHERE source_system = %s AND table_name = %s
        """,
        (source_system, table_name),
    ).fetchone()
    if row and row[0] is not None:
        return row[0].replace(tzinfo=None)
    return EPOCH_WATERMARK


def update_watermark_psycopg(
    conn,
    source_system: str,
    table_name: str,
    new_watermark_ts: datetime,
    rows_extracted: int,
    rows_upserted: int,
    run_id: str | None = None,
    status: str = "SUCCESS",
) -> None:
    """Aktualizuje watermark po przejściu walidacji i zapisie (psycopg)."""
    conn.execute(
        """
        INSERT INTO core.etl_watermark (
            source_system, table_name, last_watermark_ts,
            last_run_id, rows_extracted, rows_upserted, status, updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (source_system, table_name) DO UPDATE SET
            last_watermark_ts = EXCLUDED.last_watermark_ts,
            last_run_id       = EXCLUDED.last_run_id,
            rows_extracted    = EXCLUDED.rows_extracted,
            rows_upserted     = EXCLUDED.rows_upserted,
            status            = EXCLUDED.status,
            updated_at        = CURRENT_TIMESTAMP
        """,
        (
            source_system,
            table_name,
            new_watermark_ts.replace(tzinfo=None),
            run_id,
            rows_extracted,
            rows_upserted,
            status,
        ),
    )


def upsert_clean_table_psycopg(
    conn,
    table_name: str,
    columns: Sequence[str],
    conflict_cols: Sequence[str],
    rows_tuples: list[tuple[Any, ...]],
) -> None:
    """Wykonuje idempotentny UPSERT do core.clean_<table>."""
    if not rows_tuples:
        return

    target = sql.Identifier("core", f"clean_{table_name}")
    cols_ident = sql.SQL(", ").join(map(sql.Identifier, columns))
    placeholders = sql.SQL(", ").join(sql.Placeholder() for _ in columns)
    conflict_ident = sql.SQL(", ").join(map(sql.Identifier, conflict_cols))

    update_cols = [c for c in columns if c not in conflict_cols]
    set_sql = sql.SQL(", ").join(
        sql.SQL("{} = EXCLUDED.{}").format(sql.Identifier(c), sql.Identifier(c))
        for c in update_cols
    )

    query = sql.SQL(
        "INSERT INTO {} ({}) VALUES ({}) ON CONFLICT ({}) DO UPDATE SET {}"
    ).format(target, cols_ident, placeholders, conflict_ident, set_sql)

    with conn.cursor() as cur:
        cur.executemany(query, rows_tuples)