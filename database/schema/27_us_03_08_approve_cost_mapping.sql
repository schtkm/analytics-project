-- HotelGroup | US-03-08 | Akceptacja mapowan
-- Decyzja projektowa z 2026-11-27.
-- Nie zatwierdza klasyfikacji kosztow do GOP (US-04-04).

BEGIN;

-- Kontrola warunkow przed zatwierdzeniem.
DO $$
DECLARE
    category_count INTEGER;
    mapping_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO category_count
    FROM core.cost_category
    WHERE category_code IN (
        'MAINTENANCE',
        'SALES_MARKETING',
        'PERSONNEL',
        'UTILITIES'
    );

    SELECT COUNT(*)
    INTO mapping_count
    FROM core.hotel_cost_category_mapping m
    JOIN core.cost_category c
      ON c.cost_category_id = m.cost_category_id
    JOIN (
        VALUES
            ('MAINTENANCE', 'MAINTENANCE'),
            ('MARKETING', 'SALES_MARKETING'),
            ('PERSONNEL', 'PERSONNEL'),
            ('UTILITIES', 'UTILITIES')
    ) AS expected(local_code, target_code)
      ON expected.local_code = m.local_cost_code
     AND expected.target_code = c.category_code
    WHERE m.source_system = 'FINANCE_CSV'
      AND m.valid_from = DATE '2024-01-01'
      AND m.valid_to IS NULL
      AND m.hotel_id IN (
          SELECT DISTINCT hotel_id
          FROM core.clean_fin_budgets_costs
      );

    IF category_count <> 4 OR mapping_count <> 32 THEN
        RAISE EXCEPTION
            'Nieprawidlowa liczba kategorii (%) lub mapowan (%).',
            category_count, mapping_count;
    END IF;
END $$;

-- Akceptacja czterech kategorii.
UPDATE core.cost_category
SET approval_status = 'APPROVED'
WHERE category_code IN (
    'MAINTENANCE',
    'SALES_MARKETING',
    'PERSONNEL',
    'UTILITIES'
);

-- Akceptacja 32 mapowan na podstawie decyzji projektowej.
UPDATE core.hotel_cost_category_mapping m
SET decision_status = 'APPROVED',
    approved_by = 'Przedstawiciel zespolu HotelGroup',
    approval_note =
        'Akceptacja projektowa 2026-11-27. '
        || 'Potwierdzono 4 mapowania dla 8 hoteli. '
        || 'Nie stanowi akceptacji kontrolera hotelowego.'
FROM core.cost_category c
JOIN (
    VALUES
        ('MAINTENANCE', 'MAINTENANCE'),
        ('MARKETING', 'SALES_MARKETING'),
        ('PERSONNEL', 'PERSONNEL'),
        ('UTILITIES', 'UTILITIES')
) AS expected(local_code, target_code)
    ON c.category_code = expected.target_code
WHERE m.cost_category_id = c.cost_category_id
  AND m.local_cost_code = expected.local_code
  AND m.source_system = 'FINANCE_CSV'
  AND m.valid_from = DATE '2024-01-01'
  AND m.valid_to IS NULL
  AND m.hotel_id IN (
      SELECT DISTINCT hotel_id
      FROM core.clean_fin_budgets_costs
  );

COMMIT;