-- HotelGroup / US-04-01: 13 niezaleznych asercji na danych syntetycznych.
-- TYLKO SELECT. Mozna uruchomic w lokalnej hotelgroup_dw bez tabel z US-03-05.
-- W kolumnie wynik oczekujemy 13 wierszy PASS. Nie potwierdza jeszcze integracji.
WITH
stay_dates AS (
    SELECT g.night_date::DATE AS night_date
    FROM generate_series(DATE '2026-01-30', DATE '2026-02-02' - 1, INTERVAL '1 day') g(night_date)
),
ooo_rooms (room_id, day_id, is_ooo, is_sold, room_revenue) AS (
    VALUES
    (101, DATE '2026-02-01', FALSE, TRUE,  200::NUMERIC),
    (101, DATE '2026-02-02', FALSE, TRUE,  200),
    (101, DATE '2026-02-03', FALSE, FALSE, 0),
    (102, DATE '2026-02-01', FALSE, FALSE, 0),
    (102, DATE '2026-02-02', TRUE,  FALSE, 0),
    (102, DATE '2026-02-03', FALSE, TRUE,  200)
),
filter_data (hotel, room_type, stay_date, is_ooo, is_sold, room_revenue) AS (
    VALUES
    ('H001', 'STANDARD', DATE '2026-01-30', FALSE, TRUE,  200::NUMERIC),
    ('H001', 'STANDARD', DATE '2026-01-31', FALSE, TRUE,  200),
    ('H001', 'STANDARD', DATE '2026-02-01', FALSE, FALSE, 0),
    ('H001', 'DELUXE',   DATE '2026-01-30', FALSE, FALSE, 0),
    ('H001', 'DELUXE',   DATE '2026-01-31', TRUE,  FALSE, 0),
    ('H002', 'STANDARD', DATE '2026-01-30', FALSE, TRUE,  300),
    ('H002', 'STANDARD', DATE '2026-01-31', FALSE, FALSE, 0),
    ('H002', 'DELUXE',   DATE '2026-02-01', TRUE,  FALSE, 0)
),
revenue (hotel, kind, amount) AS (
    VALUES
    ('A', 'ROOM', 20000::NUMERIC), ('A', 'FNB', 10000), ('A', 'SPA', 4000),
    ('B', 'ROOM', 90000), ('B', 'FNB',  5000), ('B', 'SPA', 2000)
),
tests (test_id, description, expected, actual) AS (
    SELECT 'AC01', 'OCC 750/1000 = 75%', 75::NUMERIC, 100::NUMERIC*750/1000
    UNION ALL SELECT 'AC02', 'Dwie noce styczen, jedna luty, bez daty wymeldowania',
        1::NUMERIC,
        CASE WHEN (SELECT COUNT(*) FROM stay_dates WHERE night_date < DATE '2026-02-01') = 2
               AND (SELECT COUNT(*) FROM stay_dates WHERE night_date >= DATE '2026-02-01') = 1
               AND NOT EXISTS(SELECT 1 FROM stay_dates WHERE night_date = DATE '2026-02-02')
             THEN 1::NUMERIC ELSE 0::NUMERIC END
    UNION ALL SELECT 'AC03', 'OOO: 6-1=5 dostepnych pokojonocy', 5::NUMERIC,
        (SELECT COUNT(*) FILTER (WHERE NOT is_ooo)::NUMERIC FROM ooo_rooms)
    UNION ALL SELECT 'AC04', 'Filtr H001/styczen/STANDARD: OCC 100%', 100::NUMERIC,
        (SELECT 100::NUMERIC * COUNT(*) FILTER (WHERE is_sold AND NOT is_ooo)
                / NULLIF(COUNT(*) FILTER (WHERE NOT is_ooo), 0)
         FROM filter_data WHERE hotel='H001' AND room_type='STANDARD' AND stay_date >= DATE '2026-01-01' AND stay_date < DATE '2026-02-01')
    UNION ALL SELECT 'AC05', 'Laczny OCC wazony dostepnoscia = 50%', 50::NUMERIC,
        100::NUMERIC*(80+120)/(100+300)
    UNION ALL SELECT 'AC06', 'ADR 150000 / 500 = 300 PLN', 300::NUMERIC,
        150000::NUMERIC / NULLIF(500,0)
    UNION ALL SELECT 'AC07', 'Wykluczenie FNB i SPA: room-only 110000 PLN', 110000::NUMERIC,
        (SELECT SUM(amount) FILTER (WHERE kind='ROOM') FROM revenue)
    UNION ALL SELECT 'AC08', 'Zero sprzedanych => ADR NULL', NULL::NUMERIC,
        120::NUMERIC / NULLIF(0,0)
    UNION ALL SELECT 'AC09', 'Laczny ADR (20000+90000)/(100+300) = 275', 275::NUMERIC,
        (20000::NUMERIC+90000) / (100+300)
    UNION ALL SELECT 'AC10', 'RevPAR 150000 / 1000 = 150', 150::NUMERIC,
        150000::NUMERIC / 1000
    UNION ALL SELECT 'AC11', 'RevPAR == OCC * ADR bez zaokraglenia', 1::NUMERIC,
        CASE WHEN ABS(150000::NUMERIC/1000 - (500::NUMERIC/1000)*(150000::NUMERIC/500)) < 0.000001
             THEN 1::NUMERIC ELSE 0::NUMERIC END
    UNION ALL SELECT 'AC12', 'Laczny RevPAR liczony z sum = 183.333333...', 1::NUMERIC,
        CASE WHEN ABS(110000::NUMERIC / 600 - 183.333333333333::NUMERIC) < 0.000001
             THEN 1::NUMERIC ELSE 0::NUMERIC END
    UNION ALL SELECT 'AC13', 'Zero dostepnych => RevPAR NULL', NULL::NUMERIC,
        150::NUMERIC / NULLIF(0,0)
)
SELECT
    test_id,
    description,
    expected AS oczekiwane,
    ROUND(actual, 6) AS otrzymane,
    CASE WHEN actual IS NOT DISTINCT FROM expected
               OR (actual IS NOT NULL AND expected IS NOT NULL AND ABS(actual - expected) < 0.000001)
         THEN 'PASS' ELSE 'FAIL' END AS wynik
FROM tests
ORDER BY test_id;
