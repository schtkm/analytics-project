-- HotelGroup | US-04-04 | Testy GOP i marzy GOP
-- Testy scenariuszowe i kontrola widoku.
-- Skrypt nie modyfikuje danych.

-- 1. Scenariusze akceptacyjne
WITH test_cases (
    test_name, revenue, costs, expected_gop, expected_margin
) AS (
    VALUES
        ('GOP 150000 i marza 30%',
         500000::numeric, 350000::numeric,
         150000::numeric, 30::numeric),

        ('Ujemny GOP i marza',
         100000::numeric, 120000::numeric,
         -20000::numeric, -20::numeric),

        ('Zerowe przychody',
         0::numeric, 50000::numeric,
         -50000::numeric, NULL::numeric)
),
results AS (
    SELECT
        *,
        revenue - costs AS actual_gop,
        ROUND(
            100.0 * (revenue - costs)
            / NULLIF(revenue, 0), 2
        ) AS actual_margin
    FROM test_cases
)
SELECT
    test_name,
    actual_gop,
    actual_margin,
    CASE
        WHEN actual_gop = expected_gop
         AND actual_margin IS NOT DISTINCT FROM expected_margin
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM results;

-- 2. Kontrola wdrozonego widoku
SELECT
    COUNT(*) AS records,
    COUNT(DISTINCT hotel_id) AS hotels,
    COUNT(DISTINCT month_id) AS months,
    COUNT(*) - COUNT(DISTINCT (hotel_id, month_id))
        AS duplicates,
    COUNT(*) FILTER (
        WHERE gop_pln IS DISTINCT FROM
              revenue_pln - costs_pln
    ) AS invalid_gop,
    COUNT(*) FILTER (
        WHERE gop_margin_pct IS DISTINCT FROM
              ROUND(
                  100.0 * gop_pln
                  / NULLIF(revenue_pln, 0), 2
              )
    ) AS invalid_margin
FROM mart.v_gop_monthly;