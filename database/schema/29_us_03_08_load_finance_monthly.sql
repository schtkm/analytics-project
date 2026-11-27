-- HotelGroup | US-03-08 | Zasilenie faktu finansowego
-- Ziarno: hotel x miesiac x kategoria x scenariusz
-- Tylko zatwierdzone mapowania i kategorie.
-- Ponowne uruchomienie nie duplikuje danych.

BEGIN;

DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    -- Waluta zrodla musi byc zgodna z waluta raportowa.
    IF NOT EXISTS (
        SELECT 1
        FROM core.finance_reporting_settings
        WHERE config_key = 'HOTELGROUP'
          AND reporting_currency = 'PLN'
    ) THEN
        RAISE EXCEPTION 'Brak ustawien raportowania PLN.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.clean_fin_budgets_costs
        WHERE currency <> 'PLN'
    ) THEN
        RAISE EXCEPTION 'Wykryto dane finansowe poza PLN.';
    END IF;

    -- Kazdy rekord musi miec dokladnie jedno
    -- zatwierdzone mapowanie i aktywna kategorie.
    SELECT COUNT(*)
    INTO invalid_count
    FROM core.clean_fin_budgets_costs f
    WHERE (
        SELECT COUNT(*)
        FROM core.hotel_cost_category_mapping m
        JOIN core.cost_category c
          ON c.cost_category_id = m.cost_category_id
        JOIN mart.dim_cost_category dc
          ON dc.cost_category_bk = c.category_code
         AND dc.is_active = TRUE
        WHERE m.source_system = 'FINANCE_CSV'
          AND m.hotel_id = f.hotel_id
          AND m.local_cost_code = f.cost_category
          AND f.month_id >= m.valid_from
          AND (m.valid_to IS NULL OR f.month_id < m.valid_to)
          AND m.decision_status = 'APPROVED'
          AND c.approval_status = 'APPROVED'
          AND c.is_active = TRUE
    ) <> 1;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Niepoprawne lub niezatwierdzone mapowania: % rekordow.',
            invalid_count;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.clean_fin_budgets_costs f
        LEFT JOIN mart.dim_hotel h
          ON h.hotel_bk = f.hotel_id
        LEFT JOIN mart.dim_date d
          ON d.full_date = f.month_id
        WHERE h.hotel_sk IS NULL
           OR d.date_sk IS NULL
           OR EXTRACT(DAY FROM f.month_id) <> 1
    ) THEN
        RAISE EXCEPTION 'Brak wymiaru hotelu lub miesiaca.';
    END IF;
END $$;

INSERT INTO mart.fct_finance_monthly (
    hotel_sk,
    month_date_sk,
    cost_category_sk,
    scenario,
    amount,
    currency_code
)
SELECT
    h.hotel_sk,
    d.date_sk,
    dc.cost_category_sk,
    s.scenario,
    s.amount,
    f.currency
FROM core.clean_fin_budgets_costs f
JOIN mart.dim_hotel h
  ON h.hotel_bk = f.hotel_id
JOIN mart.dim_date d
  ON d.full_date = f.month_id
JOIN core.hotel_cost_category_mapping m
  ON m.hotel_id = f.hotel_id
 AND m.source_system = 'FINANCE_CSV'
 AND m.local_cost_code = f.cost_category
 AND f.month_id >= m.valid_from
 AND (m.valid_to IS NULL OR f.month_id < m.valid_to)
 AND m.decision_status = 'APPROVED'
JOIN core.cost_category c
  ON c.cost_category_id = m.cost_category_id
 AND c.approval_status = 'APPROVED'
 AND c.is_active = TRUE
JOIN mart.dim_cost_category dc
  ON dc.cost_category_bk = c.category_code
 AND dc.is_active = TRUE
CROSS JOIN LATERAL (
    VALUES
        ('ACTUAL', f.actual_cost),
        ('BUDGET', f.budget_amount)
) AS s(scenario, amount)
ON CONFLICT ON CONSTRAINT uq_finance_monthly_grain
DO UPDATE SET
    amount = EXCLUDED.amount,
    currency_code = EXCLUDED.currency_code;

COMMIT;