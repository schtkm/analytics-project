-- HotelGroup | US-03-07 | Test integracyjny na SYNTETYCZNYCH kosztach 3 hoteli.
-- WYKONAJ CALY PLIK W pgAdmin 4, w bazie hotelgroup_dw.
-- Wymaga tabel z 20_us_03_07_cost_categories.sql oraz staging.fin_budgets_costs.
-- Nie wymaga danych PMS. Nie dodaje trwalych rekordow: ostatnia instrukcja = ROLLBACK.
-- "APPROVED" ponizej jest WYLACZNIE czescia symulacji, nie rzeczywistym zatwierdzeniem.
-- Test nie weryfikuje przeliczania walut obcych (brak kursow i waluty w zrodle).

BEGIN;

DO $$
BEGIN
  IF current_database() <> 'hotelgroup_dw' THEN
    RAISE EXCEPTION 'PRZERWANO: test wolno wykonac tylko w hotelgroup_dw.';
  END IF;
  IF to_regclass('staging.fin_budgets_costs') IS NULL
     OR to_regclass('core.cost_category') IS NULL
     OR to_regclass('core.hotel_cost_category_mapping') IS NULL
     OR to_regclass('core.finance_currency_policy') IS NULL THEN
    RAISE EXCEPTION 'Brakuje tabel. Utworz je przed testem.';
  END IF;
END $$;

-- 1. Dwie wspolne kategorie (symulowane zaakceptowanie obowiazuje tylko w transakcji).
INSERT INTO core.cost_category
  (category_code, category_name, category_group, business_definition,
   gop_treatment, approval_status)
VALUES
  ('TEST_US0307_PERSONNEL', 'Koszty osobowe', 'PERSONNEL',
   'Demonstracyjna grupa kosztow plac', 'TO_REVIEW', 'APPROVED'),
  ('TEST_US0307_UTILITIES', 'Media i energia', 'OPERATIONS',
   'Demonstracyjna grupa kosztow energii', 'TO_REVIEW', 'APPROVED')
ON CONFLICT (category_code) DO NOTHING;

-- 2. Lokalne nazwy dla 3 przykladowych hoteli.
-- Ten sam koszt plac ma rozne etykiety; "BIURO" ma celowy konflikt.
INSERT INTO core.hotel_cost_category_mapping
  (source_system, hotel_id, local_cost_code, cost_category_id,
   valid_from, valid_to, decision_status, approved_by, approval_note)
SELECT 'FINANCE_CSV', x.hotel_id, x.local_code, c.cost_category_id,
       x.valid_from, NULL::date, 'APPROVED',
       'TEST SYNTETYCZNY - NIE ZATWIERDZENIE', 'Do wycofania przez ROLLBACK'
FROM (VALUES
  ('TST_FIN_KRK', 'PENSJE',        'TEST_US0307_PERSONNEL', DATE '2026-01-01'),
  ('TST_FIN_WAW', 'WYNAGRODZENIA','TEST_US0307_PERSONNEL', DATE '2026-01-01'),
  ('TST_FIN_KRK', 'ENERGIA',       'TEST_US0307_UTILITIES', DATE '2026-01-01'),
  ('TST_FIN_WAW', 'PRAD',          'TEST_US0307_UTILITIES', DATE '2026-01-01'),
  ('TST_FIN_GDA', 'BIURO',         'TEST_US0307_PERSONNEL', DATE '2026-01-01'),
  ('TST_FIN_GDA', 'BIURO',         'TEST_US0307_UTILITIES', DATE '2026-02-01')
) AS x(hotel_id, local_code, target_code, valid_from)
JOIN core.cost_category c ON c.category_code = x.target_code
ON CONFLICT (source_system, hotel_id, local_cost_code, valid_from) DO NOTHING;

-- 3. Symulowane polityki walutowe: dwoch hoteli w PLN; hotel GDA bez polityki.
-- Nie stanowi to potwierdzenia rzeczywistej waluty danych wejsciowych.
INSERT INTO core.finance_currency_policy
  (source_system, hotel_id, source_currency, reporting_currency,
   valid_from, valid_to, approval_status, approved_by, conversion_rule)
VALUES
  ('FINANCE_CSV', 'TST_FIN_KRK', 'PLN', 'PLN', DATE '2026-01-01', NULL,
   'APPROVED', 'TEST SYNTETYCZNY - NIE ZATWIERDZENIE', 'PLN do PLN: mnoznik 1'),
  ('FINANCE_CSV', 'TST_FIN_WAW', 'PLN', 'PLN', DATE '2026-01-01', NULL,
   'APPROVED', 'TEST SYNTETYCZNY - NIE ZATWIERDZENIE', 'PLN do PLN: mnoznik 1')
ON CONFLICT (source_system, hotel_id, valid_from) DO NOTHING;

-- 4. Szesc SYNTETYCZNYCH pozycji w istniejacej tabeli staging.
INSERT INTO staging.fin_budgets_costs
  (hotel_id, month_id, cost_category, budget_amount, actual_cost)
VALUES
  ('TST_FIN_KRK', '2026-03', 'PENSJE',         12000.00, 12300.00),
  ('TST_FIN_WAW', '2026-03', 'WYNAGRODZENIA',  10000.00,  9900.00),
  ('TST_FIN_KRK', '2026-03', 'ENERGIA',         3000.00,  3100.00),
  ('TST_FIN_WAW', '2026-03', 'PRAD',            2500.00,  2450.00),
  ('TST_FIN_KRK', '2026-03', 'NIEZNANY_KOD',     400.00,   420.00),
  ('TST_FIN_GDA', '2026-03', 'BIURO',           1000.00,  1100.00);

-- 5. Kontrola liczby dopasowan kategorii i zasad walut.
CREATE TEMP VIEW us0307_test_results AS
WITH matches AS (
  SELECT f.ctid::text AS row_ref,
         f.hotel_id, f.month_id, f.cost_category, f.budget_amount, f.actual_cost,
         COUNT(DISTINCT m.mapping_id) AS category_matches,
         MIN(c.category_code) AS standard_category,
         COUNT(DISTINCT m.mapping_id) FILTER (WHERE c.approval_status <> 'APPROVED')
           AS unapproved_targets,
         COUNT(DISTINCT p.policy_id) AS currency_policies,
         MIN(p.source_currency) AS source_currency,
         MIN(p.reporting_currency) AS reporting_currency
  FROM staging.fin_budgets_costs f
  LEFT JOIN core.hotel_cost_category_mapping m
    ON m.hotel_id = f.hotel_id
   AND m.source_system = 'FINANCE_CSV'
   AND upper(btrim(m.local_cost_code)) = upper(btrim(f.cost_category))
   AND m.decision_status = 'APPROVED'
   AND (f.month_id || '-01')::date >= m.valid_from
   AND (m.valid_to IS NULL OR (f.month_id || '-01')::date < m.valid_to)
  LEFT JOIN core.cost_category c ON c.cost_category_id = m.cost_category_id
  LEFT JOIN core.finance_currency_policy p
    ON p.hotel_id = f.hotel_id
   AND p.source_system = 'FINANCE_CSV'
   AND p.approval_status = 'APPROVED'
   AND (f.month_id || '-01')::date >= p.valid_from
   AND (p.valid_to IS NULL OR (f.month_id || '-01')::date < p.valid_to)
  WHERE f.hotel_id IN ('TST_FIN_KRK', 'TST_FIN_WAW', 'TST_FIN_GDA')
  GROUP BY f.ctid, f.hotel_id, f.month_id, f.cost_category,
           f.budget_amount, f.actual_cost
)
SELECT hotel_id, month_id, cost_category, budget_amount, actual_cost,
       CASE WHEN category_matches = 0 THEN 'MISSING_MAPPING'
            WHEN category_matches > 1 THEN 'AMBIGUOUS_MAPPING'
            WHEN unapproved_targets > 0 THEN 'UNAPPROVED_CATEGORY'
            ELSE 'OK' END AS category_status,
       CASE WHEN category_matches = 1 AND unapproved_targets = 0
            THEN standard_category ELSE NULL END AS standard_category,
       CASE WHEN currency_policies = 0 THEN 'MISSING_CURRENCY_POLICY'
            WHEN currency_policies > 1 THEN 'AMBIGUOUS_CURRENCY_POLICY'
            WHEN source_currency <> reporting_currency THEN 'NEEDS_FX_RATE'
            ELSE 'PLN_POLICY_OK' END AS currency_status,
       source_currency, reporting_currency, row_ref
FROM matches;

-- Tabela wynikow; widoczna tylko podczas tej transakcji.
SELECT hotel_id, cost_category, actual_cost, category_status,
       standard_category, currency_status
FROM us0307_test_results
ORDER BY hotel_id, cost_category;

-- Suma poprawnie przypisanych kosztow rzeczywistych:
-- PERSONNEL = 12 300 + 9 900 = 22 200 PLN
-- UTILITIES = 3 100 + 2 450 = 5 550 PLN
SELECT standard_category, SUM(actual_cost) AS total_actual_cost_pln
FROM us0307_test_results
WHERE category_status = 'OK' AND currency_status = 'PLN_POLICY_OK'
GROUP BY standard_category
ORDER BY standard_category;

-- 6. Asercje: przerwij test jesli wynik jest inny od oczekiwanego.
DO $$
DECLARE
  ok_count INT;
  missing_count INT;
  ambiguous_count INT;
  policy_ok_count INT;
  no_policy_count INT;
  payroll_total NUMERIC(12,2);
  utilities_total NUMERIC(12,2);
BEGIN
  SELECT COUNT(*) FILTER (WHERE category_status = 'OK'),
         COUNT(*) FILTER (WHERE category_status = 'MISSING_MAPPING'),
         COUNT(*) FILTER (WHERE category_status = 'AMBIGUOUS_MAPPING'),
         COUNT(*) FILTER (WHERE currency_status = 'PLN_POLICY_OK'),
         COUNT(*) FILTER (WHERE currency_status = 'MISSING_CURRENCY_POLICY')
    INTO ok_count, missing_count, ambiguous_count, policy_ok_count, no_policy_count
  FROM us0307_test_results;

  SELECT COALESCE(SUM(actual_cost) FILTER (WHERE standard_category = 'TEST_US0307_PERSONNEL'), 0),
         COALESCE(SUM(actual_cost) FILTER (WHERE standard_category = 'TEST_US0307_UTILITIES'), 0)
    INTO payroll_total, utilities_total
  FROM us0307_test_results
  WHERE category_status = 'OK';

  IF (ok_count, missing_count, ambiguous_count, policy_ok_count, no_policy_count,
      payroll_total, utilities_total)
     IS DISTINCT FROM (4, 1, 1, 5, 1, 22200.00::numeric, 5550.00::numeric) THEN
    RAISE EXCEPTION
      'NIEZALICZONY: OK=%, missing=%, ambiguous=%, waluty_ok=%, brak_waluty=%, personel=%, media=%',
      ok_count, missing_count, ambiguous_count, policy_ok_count, no_policy_count,
      payroll_total, utilities_total;
  END IF;

  RAISE NOTICE 'US-03-07 TEST ZALICZONY: 4 OK, 1 brak mapowania, 1 konflikt mapowania;';
  RAISE NOTICE 'POLITYKA WALUT: 5 wierszy PLN OK, 1 brak polityki;';
  RAISE NOTICE 'SUMY: PERSONNEL=22200.00 PLN, UTILITIES=5550.00 PLN.';
END $$;

-- Wszystkie dane i symulowane decyzje zostaja wycofane.
ROLLBACK;
