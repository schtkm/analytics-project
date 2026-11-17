import unittest
from copy import deepcopy
from datetime import date, timezone
from decimal import Decimal
from etl.cleaning import normalize, transform, reconciliation, parse_date, parse_number, parse_timestamp, Invalid
from tests.fixtures import snapshot, CONFIG

class CleaningTests(unittest.TestCase):
    def process(self, data=None):
        return transform(data or snapshot(), **CONFIG)

    def test_all_seven_tables_formats(self):
        clean, _ = self.process()
        self.assertTrue(all(len(v) == 1 for v in clean.values()))
        r = clean['pms_reservations'][0]
        self.assertEqual(r['room_revenue'], Decimal('1234.50'))
        self.assertEqual(r['check_in_date'], date(2026,11,17))
        self.assertEqual(r['currency'], 'PLN')
        self.assertEqual(r['updated_at'].hour, 11)
        self.assertEqual(clean['fin_budgets_costs'][0]['month_id'], date(2026,11,1))
        self.assertEqual(clean['pms_rooms'][0]['room_number'], '001')

    def test_duplicate_all_tables(self):
        data=snapshot()
        for rows in data.values(): rows.append(deepcopy(rows[0]))
        clean, outcomes=self.process(data)
        self.assertTrue(all(len(v)==1 for v in clean.values()))
        self.assertTrue(all(v[1]['outcome']=='duplicate' for v in outcomes.values()))

    def test_duplicates_after_normalization_ignore_metadata(self):
        data=snapshot(); r=deepcopy(data['pms_reservations'][0]);r['room_revenue']='1234.50';r['_inserted_at']='2026-11-01'
        data['pms_reservations'].append(r)
        self.assertEqual(self.process(data)[1]['pms_reservations'][1]['outcome'],'duplicate')

    def test_conflicting_key_rejects_both_and_children(self):
        data=snapshot();r=deepcopy(data['pms_reservations'][0]);r['room_revenue']='100'
        data['pms_reservations'].append(r)
        clean,outcomes=self.process(data)
        self.assertFalse(clean['pms_reservations']);self.assertFalse(clean['cm_channels'])
        self.assertTrue(all(r['errors'][0]['code']=='CONFLICTING_BUSINESS_KEY' for r in outcomes['pms_reservations']))

    def test_invalid_does_not_hide_valid_same_key(self):
        data=snapshot();r=deepcopy(data['pms_reservations'][0]);r['room_revenue']='NaN';data['pms_reservations'].insert(0,r)
        self.assertEqual(len(self.process(data)[0]['pms_reservations']),1)

    def test_required_nulls_rejected_every_table(self):
        from etl.cleaning import SPECS
        for table,(_,fields) in SPECS.items():
            for field,(_,required) in fields.items():
                if not required: continue
                with self.subTest(table=table,field=field):
                    raw=deepcopy(snapshot()[table][0]);raw[field]=' '
                    _,errors=normalize(table,raw,'PLN')
                    self.assertIn({'field':field,'code':'MISSING_REQUIRED'},errors)

    def test_optional_blanks_remain_null(self):
        self.assertIsNone(self.process()[0]['pms_guests'][0]['email'])

    def test_unknown_parent(self):
        data=snapshot();data['pms_rooms'][0]['hotel_id']='bad'
        self.assertFalse(self.process(data)[0]['pms_rooms'])

    def test_room_hotel_mismatch(self):
        data=snapshot();data['pms_hotels'].append(dict(hotel_id='H2',hotel_name='Other'))
        data['pms_reservations'][0]['hotel_id']='H2'
        self.assertEqual(self.process(data)[1]['pms_reservations'][0]['errors'][0]['code'],'ROOM_HOTEL_MISMATCH')

    def test_stay_mismatch(self):
        data=snapshot();data['pms_guests'].append(dict(guest_id='G2'))
        data['pms_stays'][0]['guest_id']='G2'
        self.assertEqual(self.process(data)[1]['pms_stays'][0]['errors'][0]['code'],'STAY_RESERVATION_MISMATCH')

    def test_date_order(self):
        data=snapshot();data['pms_reservations'][0]['check_out_date']='2026-11-16'
        self.assertFalse(self.process(data)[0]['pms_reservations'])

    def test_impossible_dates(self):
        for value in ['2026-02-29','31.04.2026','11/17/2026','yesterday','2026-11-17junk']:
            with self.subTest(value=value),self.assertRaises(Invalid): parse_date(value)

    def test_leap_year(self): self.assertEqual(parse_date('29.02.2024'),date(2024,2,29))

    def test_timestamp_dst_gap_and_fold(self):
        for value in ['2026-03-29 02:30:00','2026-10-25 02:30:00']:
            with self.assertRaises(Invalid): parse_timestamp(value,'Europe/Warsaw')
        self.assertEqual(parse_timestamp('2026-10-25T02:30:00+02:00','Europe/Warsaw').hour,0)

    def test_number_formats(self):
        for value in ['1234.50','1234,50','1 234,50','1\u00a0234,50','1.234,50','1,234.50']:
            self.assertEqual(parse_number(value,2),Decimal('1234.50'))

    def test_invalid_numbers(self):
        for value in ['NaN','Infinity','-1','1e3','1.234','1,234','12 34','1,23,4','10000000000','12.3456']:
            with self.subTest(value=value),self.assertRaises(Invalid): parse_number(value,2)

    def test_currency_normalization(self):
        for value,expected in [('zł','PLN'),(' pln ','PLN'),('€','EUR'),('usd','USD')]:
            raw=snapshot()['pms_reservations'][0];raw['currency']=value
            out,errors=normalize('pms_reservations',raw)
            self.assertFalse(errors);self.assertEqual(out['currency'],expected)

    def test_unknown_currency(self):
        raw=snapshot()['pms_reservations'][0];raw['currency']='$'
        self.assertTrue(normalize('pms_reservations',raw,'PLN')[1])

    def test_missing_currency_needs_explicit_configuration(self):
        raw=snapshot()['pms_reservations'][0]
        self.assertTrue(normalize('pms_reservations',raw)[1])
        raw['currency']=None
        self.assertTrue(normalize('pms_reservations',raw,'PLN')[1])

    def test_rates_are_fractions(self):
        raw=snapshot()['cm_channels'][0];raw['commission_rate']='15'
        self.assertTrue(normalize('cm_channels',raw,'PLN')[1])

    def test_month_not_arbitrarily_truncated(self):
        raw=snapshot()['fin_budgets_costs'][0];raw['month_id']='2026-11-17'
        self.assertTrue(normalize('fin_budgets_costs',raw,'PLN')[1])

    def test_reconciliation_accounts_for_removed_rows(self):
        data=snapshot();data['pms_reservations']*=2
        bad=deepcopy(data['pms_reservations'][0]);bad['reservation_id']='BAD';bad['check_in_date']='no date'
        data['pms_reservations'].append(bad)
        report=reconciliation(self.process(data)[1])['pms_reservations']
        self.assertEqual((report['accepted'],report['duplicate'],report['rejected']),(1,1,1))
        amounts=report['amounts']['PLN:room_revenue']
        self.assertEqual(amounts['input'],Decimal('3703.50'))
        self.assertEqual(amounts['rejected'],Decimal('1234.50'))

    def test_unparseable_amount_explicit(self):
        data=snapshot();data['pms_reservations'][0]['room_revenue']='unknown'
        report=reconciliation(self.process(data)[1])
        self.assertEqual(report['pms_reservations']['unparseable_amounts']['room_revenue'],1)

    def test_source_not_modified(self):
        data=snapshot();before=deepcopy(data);self.process(data);self.assertEqual(data,before)

    def test_repeatable(self): self.assertEqual(self.process(),self.process())

    def test_missing_table_blocks(self):
        data=snapshot();del data['cm_channels']
        with self.assertRaises(ValueError): self.process(data)

    def test_currency_affixes(self):
        for amount in ['1 234,50 zł','PLN 1234.50','1234,50 PLN']:
            raw=snapshot()['pms_reservations'][0];raw['room_revenue']=amount
            out,errors=normalize('pms_reservations',raw,'PLN')
            self.assertFalse(errors);self.assertEqual(out['room_revenue'],Decimal('1234.50'))
        raw['room_revenue']='1234 EUR'
        self.assertIn({'field':'room_revenue','code':'AMOUNT_CURRENCY_MISMATCH'},normalize('pms_reservations',raw,'PLN')[1])
