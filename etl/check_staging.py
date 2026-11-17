"""Read-only local staging contract check. No rows or credentials are printed."""
import json
from .cleaning import SPECS
from .run_cleaning import connect

def main():
    result = {}
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        for table, (_, fields) in SPECS.items():
            columns = dict(conn.execute('''SELECT column_name, data_type
                FROM information_schema.columns WHERE table_schema='staging' AND table_name=%s''', (table,)).fetchall())
            result[table] = {'columns': columns,
                             'missing_required_columns': sorted(set(fields) - {'currency'} - set(columns)),
                             'currency_column_present': 'currency' in columns}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return int(any(r['missing_required_columns'] for r in result.values()))

if __name__ == '__main__':
    raise SystemExit(main())
