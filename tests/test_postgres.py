"""Live PostgreSQL tests. ONLY a disposable database ending in _etl_test is accepted."""
import os
import unittest
from copy import deepcopy
from decimal import Decimal
import psycopg
from psycopg import sql
from etl.cleaning import SPECS
from etl.run_cleaning import migrate, run
from tests.fixtures import snapshot, CONFIG

@unittest.skipUnless(os.getenv('ETL_TEST_DATABASE_URL'), 'Set ETL_TEST_DATABASE_URL for live PostgreSQL tests')
class PostgresTests(unittest.TestCase):
    def setUp(self):
        self.conn=psycopg.connect(os.environ['ETL_TEST_DATABASE_URL'])
        name=self.conn.execute('SELECT current_database()').fetchone()[0]
        self.conn.commit()
        if not name.endswith('_etl_test'):
            self.conn.close();raise RuntimeError('Refusing destructive tests outside *_etl_test database')
        self.addCleanup(self.conn.close)
        with self.conn.transaction():
            self.conn.execute('DROP SCHEMA IF EXISTS core CASCADE; DROP SCHEMA IF EXISTS staging CASCADE; CREATE SCHEMA staging')
            for table,(_,fields) in SPECS.items():
                columns=sql.SQL(', ').join(sql.SQL('{} TEXT').format(sql.Identifier(c)) for c in fields if c!='currency')
                self.conn.execute(sql.SQL('CREATE TABLE {} ({})').format(sql.Identifier('staging',table),columns))
        migrate(self.conn)
        self.load(snapshot())

    def load(self,data):
        with self.conn.transaction():
            for table,rows in data.items():
                self.conn.execute(sql.SQL('DELETE FROM {}').format(sql.Identifier('staging',table)))
                for row in rows:
                    query=sql.SQL('INSERT INTO {} ({}) VALUES ({})').format(sql.Identifier('staging',table),
                        sql.SQL(', ').join(map(sql.Identifier,row)),sql.SQL(', ').join(sql.Placeholder() for _ in row))
                    self.conn.execute(query,list(row.values()))

    def test_end_to_end_and_idempotency(self):
        data=snapshot();data['pms_reservations'].append(deepcopy(data['pms_reservations'][0]))
        bad=deepcopy(data['pms_reservations'][0]);bad['reservation_id']='BAD';bad['check_in_date']='31.02.2026'
        data['pms_reservations'].append(bad);self.load(data)
        result=run(self.conn,CONFIG)
        self.assertEqual(result['status'],'completed_with_rejections')
        with self.conn.transaction():
            self.assertEqual(self.conn.execute('SELECT count(*) FROM core.clean_pms_reservations').fetchone()[0],1)
            self.assertEqual(self.conn.execute('SELECT count(*) FROM core.etl_rejected_records WHERE run_id=%s',(result['run_id'],)).fetchone()[0],2)
            self.assertEqual(self.conn.execute('SELECT room_revenue FROM core.clean_pms_reservations').fetchone()[0],Decimal('1234.50'))
            self.assertEqual(self.conn.execute('SELECT count(*) FROM staging.pms_reservations').fetchone()[0],3)
        second=run(self.conn,CONFIG)
        self.assertEqual(result['report'],second['report'])

    def test_failed_write_rolls_back_and_records_failure(self):
        first=run(self.conn,CONFIG)
        with self.conn.transaction():
            self.conn.execute('ALTER TABLE core.clean_fin_budgets_costs ADD CONSTRAINT force_failure CHECK(actual_cost<1600)')
            self.conn.execute("UPDATE staging.fin_budgets_costs SET actual_cost='2000'")
        with self.assertRaises(psycopg.errors.CheckViolation):run(self.conn,CONFIG)
        with self.conn.transaction():
            self.assertEqual(self.conn.execute('SELECT actual_cost FROM core.clean_fin_budgets_costs').fetchone()[0],Decimal('1500'))
            self.assertEqual(str(self.conn.execute('SELECT _etl_run_id FROM core.clean_pms_hotels').fetchone()[0]),first['run_id'])
            self.assertEqual(self.conn.execute("SELECT count(*) FROM core.etl_runs WHERE status='failed'").fetchone()[0],1)

    def test_empty_source_blocks_without_clearing_target(self):
        run(self.conn,CONFIG)
        data=snapshot();data['cm_channels']=[];self.load(data)
        result=run(self.conn,CONFIG);self.assertEqual(result['status'],'blocked')
        with self.conn.transaction():
            self.assertEqual(self.conn.execute('SELECT count(*) FROM core.clean_cm_channels').fetchone()[0],1)

    def test_all_rejected_is_logged_without_publishing(self):
        data=snapshot();data['pms_hotels'][0]['hotel_id']='';self.load(data)
        result=run(self.conn,CONFIG);self.assertEqual(result['status'],'blocked')
        with self.conn.transaction():
            self.assertGreater(self.conn.execute('SELECT count(*) FROM core.etl_rejected_records').fetchone()[0],0)

    def test_migration_preserves_old_typed_staging(self):
        with self.conn.transaction():
            self.conn.execute("UPDATE staging.pms_reservations SET check_in_date='2026-11-17',check_out_date='2026-11-20',room_revenue='1234.50'")
            self.conn.execute('ALTER TABLE staging.pms_reservations ALTER COLUMN check_in_date TYPE DATE USING check_in_date::date')
            self.conn.execute('ALTER TABLE staging.pms_reservations ALTER COLUMN room_revenue TYPE NUMERIC(10,2) USING room_revenue::numeric')
        migrate(self.conn);migrate(self.conn)
        self.assertEqual(run(self.conn,CONFIG)['status'],'completed')

    def test_explicit_currency_column(self):
        with self.conn.transaction():
            for table in CONFIG['source_currencies']:
                self.conn.execute(sql.SQL('ALTER TABLE {} ADD COLUMN currency TEXT').format(sql.Identifier('staging',table)))
                self.conn.execute(sql.SQL("UPDATE {} SET currency=' eur '").format(sql.Identifier('staging',table)))
        self.assertEqual(run(self.conn,CONFIG)['status'],'completed')
        with self.conn.transaction():
            self.assertEqual(self.conn.execute('SELECT currency FROM core.clean_pms_reservations').fetchone()[0],'EUR')

    def test_missing_staging_schema_fails_before_target_changes(self):
        run(self.conn,CONFIG)
        with self.conn.transaction():self.conn.execute('ALTER TABLE staging.pms_reservations DROP COLUMN room_id')
        with self.assertRaises(ValueError):run(self.conn,CONFIG)
        with self.conn.transaction():
            self.assertEqual(self.conn.execute('SELECT count(*) FROM core.clean_pms_reservations').fetchone()[0],1)
