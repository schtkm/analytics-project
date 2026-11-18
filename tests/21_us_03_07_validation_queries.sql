-- HotelGroup | US-03-07 | Kontrole danych i mapowan, PostgreSQL.
-- SELECT-y bez modyfikacji danych; uruchamiac po przygotowaniu struktur.
-- Zakladana tabela wejsciowa: staging.fin_budgets_costs.
-- Nie wykorzystujemy przychodow PMS jako kosztow finansowych.

-- A. Stan zatwierdzenia centralnego katalogu
SELECT category_code, category_name, category_group, gop_treatment, approval_status
FROM core.cost_category
ORDER BY category_group, category_code;

-- B. Nakladajace sie zatwierdzone mapowania dla tego samego hotelu i lokalnego kodu.
-- Powinno zwrocic 0 wierszy przed uruchomieniem procesu produkcyjnego.
SELECT a.hotel_id, a.source_system, a.local_cost_code,
       a.mapping_id AS mapping_1, b.mapping_id AS mapping_2,
       a.valid_from AS from_1, a.valid_to AS to_1,
       b.valid_from AS from_2, b.valid_to AS to_2
FROM core.hotel_cost_category_mapping a
JOIN core.hotel_cost_category_mapping b
  ON a.mapping_id < b.mapping_id
 AND a.hotel_id = b.hotel_id
 AND a.source_system = b.source_system
 AND upper(btrim(a.local_cost_code)) = upper(btrim(b.local_cost_code))
 AND a.decision_status = 'APPROVED'
 AND b.decision_status = 'APPROVED'
 AND daterange(a.valid_from, a.valid_to, '[)') && daterange(b.valid_from, b.valid_to, '[)')
ORDER BY a.hotel_id, a.local_cost_code;

-- C. Kontrola pojedynczego, zatwierdzonego mapowania kazdego wiersza finansowego.
-- status: OK / MISSING_MAPPING / AMBIGUOUS_MAPPING / BAD_PERIOD / EMPTY_CATEGORY
-- ctid jest wskaznikiem diagnostycznym dla biezacego uruchomienia, NIE trwalym ID.
WITH src AS (
  SELECT f.ctid::text AS diagnostic_row_ref,
         f.hotel_id, f.month_id, f.cost_category, f.budget_amount, f.actual_cost,
         CASE WHEN btrim(f.month_id) ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
              THEN (btrim(f.month_id) || '-01')::date ELSE NULL END AS period_start
  FROM staging.fin_budgets_costs f
), matched AS (
  SELECT s.*, COUNT(m.mapping_id) AS matches,
         MIN(c.category_code) AS proposed_standard_code,
         COUNT(m.mapping_id) FILTER (WHERE c.approval_status <> 'APPROVED') AS unapproved_targets
  FROM src s
  LEFT JOIN core.hotel_cost_category_mapping m
    ON m.hotel_id = s.hotel_id
   AND m.source_system = 'FINANCE_CSV'
   AND upper(btrim(m.local_cost_code)) = upper(btrim(s.cost_category))
   AND m.decision_status = 'APPROVED'
   AND s.period_start >= m.valid_from
   AND (m.valid_to IS NULL OR s.period_start < m.valid_to)
  LEFT JOIN core.cost_category c ON c.cost_category_id = m.cost_category_id
  GROUP BY s.diagnostic_row_ref, s.hotel_id, s.month_id, s.cost_category,
           s.budget_amount, s.actual_cost, s.period_start
)
SELECT hotel_id, month_id, cost_category, budget_amount, actual_cost,
       CASE WHEN period_start IS NULL THEN 'BAD_PERIOD'
            WHEN cost_category IS NULL OR btrim(cost_category) = '' THEN 'EMPTY_CATEGORY'
            WHEN matches = 0 THEN 'MISSING_MAPPING'
            WHEN matches > 1 THEN 'AMBIGUOUS_MAPPING'
            WHEN unapproved_targets > 0 THEN 'UNAPPROVED_CATEGORY'
            ELSE 'OK' END AS validation_status,
       CASE WHEN matches = 1 AND unapproved_targets = 0 THEN proposed_standard_code ELSE NULL END AS standard_category,
       diagnostic_row_ref
FROM matched
ORDER BY hotel_id, month_id, cost_category, diagnostic_row_ref;

-- D. Zatwierdzone mapowania, ktore kieruja do niezatwierdzonych kategorii
SELECT m.hotel_id, m.local_cost_code, c.category_code, c.approval_status
FROM core.hotel_cost_category_mapping m
JOIN core.cost_category c ON c.cost_category_id = m.cost_category_id
WHERE m.decision_status = 'APPROVED' AND c.approval_status <> 'APPROVED';

-- E. Niejednoznaczne zasady walutowe -- nie moze byc dwoch polityk w tym samym okresie
SELECT a.hotel_id, a.policy_id AS policy_1, b.policy_id AS policy_2
FROM core.finance_currency_policy a
JOIN core.finance_currency_policy b
  ON a.policy_id < b.policy_id
 AND a.hotel_id = b.hotel_id
 AND a.source_system = b.source_system
 AND a.approval_status = 'APPROVED'
 AND b.approval_status = 'APPROVED'
 AND daterange(a.valid_from, a.valid_to, '[)') && daterange(b.valid_from, b.valid_to, '[)');

-- F. Przykladowa kontrola pokrycia danych finansowych zatwierdzonymi politykami walut
-- Jesli brak polityki lub kilka polityk, przeliczenia nalezy wstrzymac.
WITH src AS (
  SELECT f.ctid::text AS diagnostic_row_ref, f.hotel_id, f.month_id,
         CASE WHEN btrim(f.month_id) ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
              THEN (btrim(f.month_id) || '-01')::date ELSE NULL END AS period_start
  FROM staging.fin_budgets_costs f
)
SELECT s.hotel_id, s.month_id, s.diagnostic_row_ref,
       COUNT(p.policy_id) AS approved_currency_policies,
       MIN(p.source_currency) AS source_currency,
       MIN(p.reporting_currency) AS reporting_currency
FROM src s
LEFT JOIN core.finance_currency_policy p
  ON p.hotel_id = s.hotel_id
 AND p.source_system = 'FINANCE_CSV'
 AND p.approval_status = 'APPROVED'
 AND s.period_start >= p.valid_from
 AND (p.valid_to IS NULL OR s.period_start < p.valid_to)
GROUP BY s.hotel_id, s.month_id, s.diagnostic_row_ref
ORDER BY s.hotel_id, s.month_id;
