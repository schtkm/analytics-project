"""Run with: python -m etl.run_cleaning --config etl/config.json [--migrate] [--full-refresh]."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import uuid
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from dotenv import load_dotenv

from .cleaning import SPECS, transform, reconciliation, CURRENCIES
from .incremental import (
    EPOCH_WATERMARK,
    get_watermark_psycopg,
    update_watermark_psycopg,
    upsert_clean_table_psycopg,
)

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'database/schema/02_etl_cleaning.sql'
INCREMENTAL_MIGRATION = ROOT / 'database/migrations/US-02-04_incremental_load.sql'


def json_text(value):
    return json.dumps(value, default=str, ensure_ascii=False, sort_keys=True)


def jsonb(value):
    return Jsonb(value, dumps=json_text)


def connect():
    load_dotenv(ROOT / '.env')
    if os.environ.get('ETL_DATABASE_URL'):
        return psycopg.connect(os.environ['ETL_DATABASE_URL'])
    required = ['PG_HOST', 'PG_PORT', 'PG_DATABASE', 'PG_USER', 'PG_PASSWORD']
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        raise ValueError('Missing settings: ' + ', '.join(missing))
    return psycopg.connect(
        host=os.environ['PG_HOST'],
        port=os.environ['PG_PORT'],
        dbname=os.environ['PG_DATABASE'],
        user=os.environ['PG_USER'],
        password=os.environ['PG_PASSWORD'],
    )


def validate_config(config):
    if set(config) != {'source_timezone', 'source_currencies'}:
        raise ValueError('Config must define source_timezone and source_currencies')
    ZoneInfo(config['source_timezone'])
    allowed = {t for t, (_, fields) in SPECS.items() if 'currency' in fields}
    if not set(config['source_currencies']) <= allowed:
        raise ValueError('Unknown monetary source table')
    for currency in config['source_currencies'].values():
        if currency not in set(CURRENCIES.values()):
            raise ValueError('Use an explicit supported ISO currency code')


def migrate(conn):
    with conn.transaction():
        conn.execute(MIGRATION.read_text(encoding='utf-8'))
        if INCREMENTAL_MIGRATION.is_file():
            conn.execute(INCREMENTAL_MIGRATION.read_text(encoding='utf-8'))


def _fetch_parent_context(conn, delta_snapshot, config):
    """Pobiera z core.clean_* rekordy nadrzędne wymagane do walidacji RELATIONS w delcie."""
    context = {t: [] for t in SPECS}

    needed_hotels = (
        {r.get('hotel_id') for r in delta_snapshot['pms_rooms']}
        | {r.get('hotel_id') for r in delta_snapshot['pms_reservations']}
        | {r.get('hotel_id') for r in delta_snapshot['fin_budgets_costs']}
    ) - {r.get('hotel_id') for r in delta_snapshot['pms_hotels']} - {None}

    needed_guests = (
        {r.get('guest_id') for r in delta_snapshot['pms_reservations']}
        | {r.get('guest_id') for r in delta_snapshot['pms_stays']}
    ) - {r.get('guest_id') for r in delta_snapshot['pms_guests']} - {None}

    needed_rooms = (
        {r.get('room_id') for r in delta_snapshot['pms_reservations']}
        | {r.get('room_id') for r in delta_snapshot['pms_stays']}
    ) - {r.get('room_id') for r in delta_snapshot['pms_rooms']} - {None}

    needed_reservations = (
        {r.get('reservation_id') for r in delta_snapshot['pms_stays']}
        | {r.get('reservation_id') for r in delta_snapshot['cm_channels']}
    ) - {r.get('reservation_id') for r in delta_snapshot['pms_reservations']} - {None}

    parent_queries = [
        ('pms_hotels', 'hotel_id', needed_hotels),
        ('pms_guests', 'guest_id', needed_guests),
        ('pms_rooms', 'room_id', needed_rooms),
        ('pms_reservations', 'reservation_id', needed_reservations),
    ]

    for table, key_col, keys in parent_queries:
        if not keys:
            continue
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                sql.SQL('SELECT * FROM {} WHERE {} = ANY(%s)').format(
                    sql.Identifier('core', f'clean_{table}'),
                    sql.Identifier(key_col),
                ),
                (list(keys),),
            )
            rows = cur.fetchall()
            for row in rows:
                row.pop('_etl_run_id', None)
                if 'currency' not in row and table in config.get('source_currencies', {}):
                    row['currency'] = config['source_currencies'][table]
            context[table] = rows

    return context


def run(conn, config, incremental: bool = True):
    started = time.perf_counter()
    validate_config(config)
    run_id = uuid.uuid4()

    with conn.transaction():
        conn.execute(
            'INSERT INTO core.etl_runs(run_id, status, config) VALUES (%s, %s, %s)',
            (run_id, 'running', jsonb(config)),
        )

    pending_watermarks: dict[str, tuple[datetime, int, int]] = {}

    try:
        with conn.transaction():
            conn.execute("SET LOCAL lock_timeout = '30s'")
            conn.execute("SET LOCAL TIME ZONE 'UTC'")
            conn.execute('SELECT pg_advisory_xact_lock(20260202)')
            names = sql.SQL(', ').join(sql.Identifier('staging', t) for t in SPECS)
            conn.execute(sql.SQL('LOCK TABLE {} IN SHARE MODE').format(names))

            delta_snapshot = {}
            delta_keys = {}
            max_timestamps: dict[str, datetime] = {}

            for table, (key_fields, fields) in SPECS.items():
                last_wm = (
                    get_watermark_psycopg(conn, 'staging_to_core', table)
                    if incremental
                    else EPOCH_WATERMARK
                )
                with conn.cursor(row_factory=dict_row) as cur:
                    if incremental:
                        cur.execute(
                            sql.SQL(
                                'SELECT *, COALESCE(_updated_at, _inserted_at) AS _wm_ts '
                                'FROM {} WHERE COALESCE(_updated_at, _inserted_at) > %s ORDER BY ctid'
                            ).format(sql.Identifier('staging', table)),
                            (last_wm,),
                        )
                    else:
                        cur.execute(
                            sql.SQL(
                                'SELECT *, COALESCE(_updated_at, _inserted_at) AS _wm_ts '
                                'FROM {} ORDER BY ctid'
                            ).format(sql.Identifier('staging', table))
                        )
                    columns = {c.name for c in cur.description}
                    expected = set(fields) - {'currency'}
                    if not expected <= columns:
                        raise ValueError(f'SCHEMA_MISMATCH:{table}')

                    raw_rows = cur.fetchall()
                    table_max_ts = last_wm
                    for r in raw_rows:
                        wm_ts = r.pop('_wm_ts', None)
                        if wm_ts is not None:
                            wm_naive = wm_ts.replace(tzinfo=None)
                            if wm_naive > table_max_ts:
                                table_max_ts = wm_naive

                    delta_snapshot[table] = raw_rows
                    max_timestamps[table] = table_max_ts
                    delta_keys[table] = {
                        tuple(str(r.get(k)).strip() for k in key_fields)
                        for r in raw_rows
                    }

            total_delta_rows = sum(len(rows) for rows in delta_snapshot.values())
            if incremental and total_delta_rows == 0:
                report = {
                    t: {'input': 0, 'accepted': 0, 'duplicate': 0, 'rejected': 0, 'amounts': {}, 'unparseable_amounts': {}}
                    for t in SPECS
                }
                report['_mode'] = 'incremental_noop'
                report['_elapsed_seconds'] = round(time.perf_counter() - started, 4)
                conn.execute(
                    '''UPDATE core.etl_runs SET status=%s, finished_at=clock_timestamp(), report=%s
                       WHERE run_id=%s''',
                    ('completed', jsonb(report), run_id),
                )
                return {
                    'run_id': str(run_id),
                    'status': 'completed',
                    'report': report,
                    '_pending_watermarks': {},
                }

            parent_context = (
                _fetch_parent_context(conn, delta_snapshot, config)
                if incremental
                else {t: [] for t in SPECS}
            )
            combined_snapshot = {
                t: parent_context[t] + delta_snapshot[t] for t in SPECS
            }

            clean_all, outcomes_all = transform(combined_snapshot, **config)

            # Odfiltrowujemy wyłącznie wyniki dotyczące bieżącej delty
            clean = {}
            outcomes = {}
            for table in SPECS:
                ctx_len = len(parent_context[table])
                outcomes[table] = outcomes_all[table][ctx_len:]
                clean[table] = [
                    r['data'] for r in outcomes[table] if r['outcome'] == 'accepted'
                ]

            report = reconciliation(outcomes)
            report['_mode'] = 'incremental' if incremental else 'full_refresh'

            blocked = []
            for t in SPECS:
                if t == 'pms_stays':
                    continue
                if incremental:
                    if delta_snapshot[t] and not clean[t]:
                        blocked.append(t)
                elif not clean[t]:
                    blocked.append(t)

            rejects = []
            for table, rows in outcomes.items():
                for row in rows:
                    if row['outcome'] == 'accepted':
                        continue
                    raw = row['raw']
                    rejects.append((
                        run_id,
                        table,
                        row['position'],
                        row['outcome'],
                        jsonb({k: raw.get(k) for k in SPECS[table][0]}),
                        hashlib.sha256(json_text(raw).encode()).hexdigest(),
                        jsonb(raw),
                        jsonb(row['errors']),
                    ))

            with conn.cursor() as cur:
                cur.executemany(
                    '''INSERT INTO core.etl_rejected_records
                       (run_id, source_table, source_row, outcome, business_key, row_hash, raw_record, reasons)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s)''',
                    rejects,
                )

            if not blocked:
                if not incremental:
                    for table in reversed(SPECS):
                        conn.execute(
                            sql.SQL('DELETE FROM {}').format(sql.Identifier('core', 'clean_' + table))
                        )

                for table, rows in clean.items():
                    key_fields = SPECS[table][0]
                    columns = list(SPECS[table][1]) + ['_etl_run_id']
                    rows_tuples = [
                        tuple(r[c] for c in columns[:-1]) + (run_id,)
                        for r in rows
                    ]
                    upsert_clean_table_psycopg(
                        conn=conn,
                        table_name=table,
                        columns=columns,
                        conflict_cols=key_fields,
                        rows_tuples=rows_tuples,
                    )

                    if not incremental:
                        count = conn.execute(
                            sql.SQL('SELECT count(*) FROM {}').format(
                                sql.Identifier('core', 'clean_' + table)
                            )
                        ).fetchone()[0]
                        if count != len(rows):
                            raise RuntimeError('TARGET_COUNT_MISMATCH')
                    else:
                        # Weryfikacja sum kwot dla bieżącej paczki delta w core.clean_<table>
                        for field, (kind, _) in SPECS[table][1].items():
                            if kind != 'money':
                                continue
                            expected = {
                                k.split(':')[0]: v['accepted']
                                for k, v in report[table]['amounts'].items()
                                if k.endswith(':' + field)
                            }
                            if not expected:
                                continue
                            actual = dict(
                                conn.execute(
                                    sql.SQL(
                                        'SELECT currency, COALESCE(sum({}), 0) FROM {} '
                                        'WHERE _etl_run_id = %s GROUP BY currency'
                                    ).format(
                                        sql.Identifier(field),
                                        sql.Identifier('core', 'clean_' + table),
                                    ),
                                    (run_id,),
                                ).fetchall()
                            )
                            for currency in set(actual) | set(expected):
                                if actual.get(currency, 0) != expected.get(currency, 0):
                                    raise RuntimeError('TARGET_AMOUNT_MISMATCH')

                    if delta_snapshot[table]:
                        pending_watermarks[table] = (
                            max_timestamps[table],
                            len(delta_snapshot[table]),
                            len(rows),
                        )

            status = 'blocked' if blocked else ('completed_with_rejections' if rejects else 'completed')
            report['_blocked_tables'] = blocked
            report['_elapsed_seconds'] = round(time.perf_counter() - started, 4)

            conn.execute(
                '''UPDATE core.etl_runs SET status=%s, finished_at=clock_timestamp(), report=%s
                   WHERE run_id=%s''',
                (status, jsonb(report), run_id),
            )

        return {
            'run_id': str(run_id),
            'status': status,
            'report': report,
            '_pending_watermarks': pending_watermarks,
        }
    except Exception as exc:
        with conn.transaction():
            conn.execute(
                '''UPDATE core.etl_runs SET status='failed', finished_at=clock_timestamp(), error_code=%s
                   WHERE run_id=%s''',
                (type(exc).__name__ + ':' + (getattr(exc, 'sqlstate', None) or 'ETL_ERROR'), run_id),
            )
        raise


def commit_watermarks(conn, run_id: str, pending_watermarks: dict[str, tuple[datetime, int, int]]):
    """Przesuwa watermarki staging_to_core dopiero po zaliczeniu kontroli jakości DQ."""
    if not pending_watermarks:
        return
    with conn.transaction():
        for table, (new_wm, extracted, upserted) in pending_watermarks.items():
            update_watermark_psycopg(
                conn=conn,
                source_system='staging_to_core',
                table_name=table,
                new_watermark_ts=new_wm,
                rows_extracted=extracted,
                rows_upserted=upserted,
                run_id=run_id,
                status='SUCCESS',
            )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--migrate', action='store_true', help='Apply schema migration only; does not run ETL')
    parser.add_argument('--full-refresh', action='store_true', help='Force full reload instead of incremental delta')
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding='utf-8'))
    validate_config(config)
    with connect() as conn:
        if args.migrate:
            migrate(conn)
            print('Migration completed. Run again without --migrate to transform staging.')
            return 0
        result = run(conn, config, incremental=not args.full_refresh)
        pending_wms = result.pop('_pending_watermarks', {})
        if result['status'] == 'blocked':
            print(json_text(result))
            return 2

        from tests.test_us_02_03_data_quality import evaluate_data_quality_checks
        dq_outcome = evaluate_data_quality_checks(conn=conn, stage='core')
        result['data_quality'] = {
            'stage': dq_outcome['stage'],
            'passed': dq_outcome['passed'],
            'failed_rules': dq_outcome['failed_rules'],
        }
        if not dq_outcome['passed']:
            result['status'] = 'blocked'
            result['report']['_dq_failed_rules'] = dq_outcome['failed_rules']
            with conn.transaction():
                conn.execute(
                    """UPDATE core.etl_runs
                       SET status = 'blocked', finished_at = clock_timestamp(), report = %s
                       WHERE run_id = %s""",
                    (jsonb(result['report']), uuid.UUID(result['run_id'])),
                )
            print(json_text(result))
            print('Data quality checks (US-02-03) failed. Propagation halted.', file=sys.stderr)
            return 2

        commit_watermarks(conn, result['run_id'], pending_wms)
        print(json_text(result))
        return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('ETL failed: ' + type(error).__name__ + '. Check schema/configuration and core.etl_runs.', file=sys.stderr)
        sys.exit(1)