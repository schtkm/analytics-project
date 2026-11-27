-- HotelGroup | US-03-08 | Robocze mapowania kategorii
-- Wpisy DRAFT: nie sa zatwierdzone do publikacji w mart.

BEGIN;

INSERT INTO core.hotel_cost_category_mapping (
    source_system,
    hotel_id,
    local_cost_code,
    cost_category_id,
    valid_from,
    decision_status,
    approval_note
)
SELECT
    'FINANCE_CSV',
    h.hotel_id,
    m.local_code,
    c.cost_category_id,
    DATE '2024-01-01',
    'DRAFT',
    'Propozycja na podstawie syntetycznych danych FINANCE_CSV. Wymaga akceptacji.'
FROM (
    SELECT DISTINCT hotel_id
    FROM core.clean_fin_budgets_costs
) h
CROSS JOIN (
    VALUES
        ('MAINTENANCE', 'MAINTENANCE'),
        ('MARKETING', 'SALES_MARKETING'),
        ('PERSONNEL', 'PERSONNEL'),
        ('UTILITIES', 'UTILITIES')
) AS m(local_code, target_code)
JOIN core.cost_category c
    ON c.category_code = m.target_code
ON CONFLICT (
    source_system,
    hotel_id,
    local_cost_code,
    valid_from
) DO NOTHING;

COMMIT