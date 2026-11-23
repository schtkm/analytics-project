"""Run with: python -m etl.run_cleaning --config etl/config.json [--migrate]."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import uuid
from zoneinfo import ZoneInfo

import psycopg
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from dotenv import load_dotenv
from .cleaning import SPECS, transform, reconciliation, CURRENCIES

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'database/schema/02_etl_cleaning.sql'

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
    return psycopg.connect(host=os.environ['PG_HOST'], port=os.environ['PG_PORT'],
                           dbname=os.environ['PG_DATABASE'], user=os.environ['PG_USER'],
                           password=os.environ['PG_PASSWORD'])

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

def run(conn, config):
    validate_config(config)
    run_id = uuid.uuid4()
    # Separate committed run marker survives a later rollback.
    with conn.transaction():
        conn.execute('INSERT INTO core.etl_runs(run_id, status, config) VALUES (%s, %s, %s)',
                     (run_id, 'running', jsonb(config)))
    try:
        with conn.transaction():
            conn.execute("SET LOCAL lock_timeout = '30s'")
            conn.execute("SET LOCAL TIME ZONE 'UTC'")
            conn.execute('SELECT pg_advisory_xact_lock(20260202)')
            names = sql.SQL(', ').join(sql.Identifier('staging', t) for t in SPECS)
            conn.execute(sql.SQL('LOCK TABLE {} IN SHARE MODE').format(names))
            snapshot = {}
            for table, (_, fields) in SPECS.items():
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(sql.SQL('SELECT * FROM {} ORDER BY ctid').format(sql.Identifier('staging', table)))
                    columns = {c.name for c in cur.description}
                    expected = set(fields) - {'currency'}
                    if not expected <= columns:
                        raise ValueError(f'SCHEMA_MISMATCH:{table}')
                    snapshot[table] = cur.fetchall()
            clean, outcomes = transform(snapshot, **config)
            report = reconciliation(outcomes)
            blocked = [t for t in SPECS if t != 'pms_stays' and not clean[t]]
            rejects = []
            for table, rows in outcomes.items():
                for row in rows:
                    if row['outcome'] == 'accepted':
                        continue
                    raw = row['raw']
                    rejects.append((run_id, table, row['position'], row['outcome'],
                                    jsonb({k: raw.get(k) for k in SPECS[table][0]}),
                                    hashlib.sha256(json_text(raw).encode()).hexdigest(),
                                    jsonb(raw), jsonb(row['errors'])))
            with conn.cursor() as cur:
                cur.executemany('''INSERT INTO core.etl_rejected_records
                    (run_id, source_table, source_row, outcome, business_key, row_hash, raw_record, reasons)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s)''', rejects)
            if not blocked:
                for table in reversed(SPECS):
                    conn.execute(sql.SQL('DELETE FROM {}').format(sql.Identifier('core', 'clean_' + table)))
                for table, rows in clean.items():
                    columns = list(SPECS[table][1]) + ['_etl_run_id']
                    query = sql.SQL('INSERT INTO {} ({}) VALUES ({})').format(
                        sql.Identifier('core', 'clean_' + table),
                        sql.SQL(', ').join(map(sql.Identifier, columns)),
                        sql.SQL(', ').join(sql.Placeholder() for _ in columns))
                    with conn.cursor() as cur:
                        cur.executemany(query, [tuple(r[c] for c in columns[:-1]) + (run_id,) for r in rows])
                    # Independently compare database sums/counts with normalized accepted records.
                    count = conn.execute(sql.SQL('SELECT count(*) FROM {}').format(
                        sql.Identifier('core', 'clean_' + table))).fetchone()[0]
                    if count != len(rows):
                        raise RuntimeError('TARGET_COUNT_MISMATCH')
                    for field, (kind, _) in SPECS[table][1].items():
                        if kind != 'money':
                            continue
                        actual = dict(conn.execute(sql.SQL('SELECT currency, sum({}) FROM {} GROUP BY currency').format(
                            sql.Identifier(field), sql.Identifier('core', 'clean_' + table))).fetchall())
                        expected = {k.split(':')[0]: v['accepted'] for k, v in report[table]['amounts'].items()
                                    if k.endswith(':' + field)}
                        for currency in set(actual) | set(expected):
                            if actual.get(currency, 0) != expected.get(currency, 0):
                                raise RuntimeError('TARGET_AMOUNT_MISMATCH')
            status = 'blocked' if blocked else ('completed_with_rejections' if rejects else 'completed')
            report['_blocked_tables'] = blocked
            conn.execute('''UPDATE core.etl_runs SET status=%s, finished_at=clock_timestamp(), report=%s
                            WHERE run_id=%s''', (status, jsonb(report), run_id))
        return {'run_id': str(run_id), 'status': status, 'report': report}
    except Exception as exc:
        # No raw values, SQL messages, credentials or PII in technical error text.
        with conn.transaction():
            conn.execute('''UPDATE core.etl_runs SET status='failed', finished_at=clock_timestamp(), error_code=%s
                            WHERE run_id=%s''', (type(exc).__name__ + ':' + (getattr(exc, 'sqlstate', None) or 'ETL_ERROR'), run_id))
        raise

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--migrate', action='store_true', help='Apply schema migration only; does not run ETL')
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding='utf-8'))
    validate_config(config)
    with connect() as conn:
        if args.migrate:
            migrate(conn)
            print('Migration completed. Run again without --migrate to transform staging.')
            return 0
        result = run(conn, config)
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

        print(json_text(result))
        return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print('ETL failed: ' + type(error).__name__ + '. Check schema/configuration and core.etl_runs.', file=sys.stderr)
        sys.exit(1)
