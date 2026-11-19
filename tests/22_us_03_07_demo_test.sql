-- HotelGroup | US-03-07 | Test na WYMYSLONYCH danych dwoch hoteli.
-- WYMAGANE: uruchom 20_us_03_07_cost_categories.sql przed tym plikiem.
-- UWAGA: ROLLBACK wycofuje wprowadzone rekordy po tescie.
-- Scenariusze: rozne lokalne nazwy -> wspolny kod; brak mapowania; konflikt mapowania.

BEGIN;

INSERT INTO core.cost_category
(category_code, category_name, category_group, business_definition, gop_treatment, approval_status)
VALUES
('TEST_US0307_PAYROLL', 'Wynagrodzenia', 'PERSONNEL', 'Kategoria testowa pensji', 'INCLUDED', 'APPROVED'),
('TEST_US0307_UTILITIES', 'Media', 'OPERATIONS', 'Kategoria testowa energii i wody', 'INCLUDED', 'APPROVED')
ON CONFLICT (category_code) DO NOTHING;

INSERT INTO core.hotel_cost_category_mapping
(source_system, hotel_id, local_cost_code, cost_category_id, valid_from, valid_to, decision_status, approved_by)
SELECT 'FINANCE_CSV', x.hotel_id, x.local_code, c.cost_category_id,
       x.valid_from, x.valid_to, 'APPROVED', 'TEST - symulacja'
FROM (VALUES
  ('TEST-US0307-H01', 'PENSJE', 'TEST_US0307_PAYROLL', DATE '2026-01-01', NULL::date),
  ('TEST-US0307-H02', 'WYNAGRODZENIA', 'TEST_US0307_PAYROLL', DATE '2026-01-01', NULL::date),
  ('TEST-US0307-H01', 'ENERGIA', 'TEST_US0307_UTILITIES', DATE '2026-01-01', NULL::date),
  -- Celowa niejednoznacznosc dla hotelu 3:
  ('TEST-US0307-H03', 'PŁACE', 'TEST_US0307_PAYROLL', DATE '2026-01-01', NULL::date),
  ('TEST-US0307-H03', 'PŁACE', 'TEST_US0307_UTILITIES', DATE '2026-02-01', NULL::date)
) AS x(hotel_id, local_code, target_code, valid_from, valid_to)
JOIN core.cost_category c ON c.category_code = x.target_code;

CREATE TEMP TABLE test_us0307_finance (
  hotel_id VARCHAR(50), month_id VARCHAR(7), cost_category VARCHAR(100), amount NUMERIC(12,2)
) ON COMMIT DROP;

INSERT INTO test_us0307_finance VALUES
('TEST-US0307-H01', '2026-03', 'PENSJE', 1000.00),
('TEST-US0307-H02', '2026-03', 'WYNAGRODZENIA', 2000.00),
('TEST-US0307-H01', '2026-03', 'ENERGIA', 300.00),
('TEST-US0307-H01', '2026-03', 'BRAK_KODU', 50.00),
('TEST-US0307-H03', '2026-03', 'PŁACE', 400.00);

CREATE TEMP VIEW test_us0307_results AS
SELECT f.hotel_id, f.cost_category, f.amount,
       COUNT(m.mapping_id) AS match_count,
       CASE WHEN COUNT(m.mapping_id) = 0 THEN 'MISSING_MAPPING'
            WHEN COUNT(m.mapping_id) > 1 THEN 'AMBIGUOUS_MAPPING'
            ELSE 'OK' END AS status,
       CASE WHEN COUNT(m.mapping_id) = 1 THEN MIN(c.category_code) ELSE NULL END AS standard_category
FROM test_us0307_finance f
LEFT JOIN core.hotel_cost_category_mapping m
  ON m.hotel_id=f.hotel_id
 AND m.source_system='FINANCE_CSV'
 AND upper(btrim(m.local_cost_code))=upper(btrim(f.cost_category))
 AND m.decision_status='APPROVED'
 AND DATE '2026-03-01' >= m.valid_from
 AND (m.valid_to IS NULL OR DATE '2026-03-01' < m.valid_to)
LEFT JOIN core.cost_category c ON c.cost_category_id=m.cost_category_id
GROUP BY f.hotel_id, f.cost_category, f.amount;

SELECT * FROM test_us0307_results ORDER BY hotel_id, cost_category;

DO $$
DECLARE n_ok integer; n_missing integer; n_ambiguous integer;
BEGIN
 SELECT COUNT(*) FILTER (WHERE status='OK'),
        COUNT(*) FILTER (WHERE status='MISSING_MAPPING'),
        COUNT(*) FILTER (WHERE status='AMBIGUOUS_MAPPING')
 INTO n_ok, n_missing, n_ambiguous
 FROM test_us0307_results;
 IF n_ok <> 3 OR n_missing <> 1 OR n_ambiguous <> 1 THEN
   RAISE EXCEPTION 'Test US-03-07 niezaliczony: OK=%, brak=%, konflikt=%', n_ok, n_missing, n_ambiguous;
 END IF;
 RAISE NOTICE 'Test US-03-07 zaliczony: 3 OK, 1 brak mapowania, 1 konflikt';
END $$;

ROLLBACK;
