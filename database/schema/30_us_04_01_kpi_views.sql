-- HotelGroup / US-04-01: dzienne i miesięczne widoki OCC, ADR, RevPAR.
-- WYMAGA: zasilonych modeli US-03-05A i US-03-05B w hotelgroup_dw.
-- NIE uruchamiaj na lokalnej bazie, jeśli fct_room_night / fct_room_inventory nie istnieją.
-- Fakty agregujemy OSOBNO przed polaczeniem: brak mnozenia kwot.
-- Filtr typu: fizyczny (occupied_room_type_sk w sprzedazy, room_type_sk w dostepnosci).
-- Zrodlo PMS nie zawiera OOO: OOO=0 jest zalozeniem poczatkowego zasilenia US-03-05B.
-- Brak kursow FX: bez automatycznych przewalutowan. Obsluga wylacznie przychodu PLN.

BEGIN;

DO $preflight$
DECLARE
    missing_objects TEXT;
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'US-04-01: niepoprawna baza %. Oczekiwano hotelgroup_dw.', current_database();
    END IF;
    SELECT string_agg(x.obj, ', ' ORDER BY x.obj)
      INTO missing_objects
    FROM (VALUES
        ('mart.fct_room_night'), ('mart.fct_room_inventory'),
        ('mart.dim_date'), ('mart.dim_hotel'), ('mart.dim_room_type')
    ) AS x(obj)
    WHERE to_regclass(x.obj) IS NULL;
    IF missing_objects IS NOT NULL THEN
        RAISE EXCEPTION 'US-04-01: brak obiektow: %. Najpierw zintegruj US-03-05A/B.', missing_objects;
    END IF;
END $preflight$;

-- Dokladne wartosci (niezaokraglone) i miary bazowe pozwalaja sumowac dane po filtrach.
CREATE OR REPLACE VIEW mart.vw_us_04_01_kpi_daily AS
WITH sales AS (
    SELECT
        fn.hotel_sk,
        fn.stay_date_sk AS date_sk,
        fn.occupied_room_type_sk AS room_type_sk,
        SUM(fn.room_night_count)::BIGINT AS sold_room_nights,
        SUM(fn.room_revenue)::NUMERIC(20,2) AS room_revenue_raw,
        COUNT(*) FILTER (
            WHERE btrim(fn.currency_code) <> 'PLN' OR fn.currency_code IS NULL
        )::BIGINT AS non_pln_rows
    FROM mart.fct_room_night fn
    GROUP BY fn.hotel_sk, fn.stay_date_sk, fn.occupied_room_type_sk
),
inventory AS (
    SELECT
        fi.hotel_sk,
        fi.inventory_date_sk AS date_sk,
        fi.room_type_sk,
        SUM(fi.available_room_nights)::BIGINT AS available_room_nights,
        SUM(fi.out_of_order_room_nights)::BIGINT AS ooo_room_nights,
        SUM(fi.total_room_nights)::BIGINT AS total_room_nights
    FROM mart.fct_room_inventory fi
    GROUP BY fi.hotel_sk, fi.inventory_date_sk, fi.room_type_sk
),
combined AS (
    SELECT
        COALESCE(s.hotel_sk, i.hotel_sk) AS hotel_sk,
        COALESCE(s.date_sk, i.date_sk) AS date_sk,
        COALESCE(s.room_type_sk, i.room_type_sk) AS room_type_sk,
        COALESCE(s.sold_room_nights, 0)::BIGINT AS sold_room_nights,
        COALESCE(i.available_room_nights, 0)::BIGINT AS available_room_nights,
        COALESCE(i.ooo_room_nights, 0)::BIGINT AS ooo_room_nights,
        COALESCE(i.total_room_nights, 0)::BIGINT AS total_room_nights,
        COALESCE(s.room_revenue_raw, 0)::NUMERIC(20,2) AS room_revenue_raw,
        COALESCE(s.non_pln_rows, 0)::BIGINT AS non_pln_rows,
        (i.date_sk IS NULL) AS missing_inventory
    FROM sales s
    FULL OUTER JOIN inventory i
      ON s.hotel_sk = i.hotel_sk
     AND s.date_sk = i.date_sk
     AND s.room_type_sk = i.room_type_sk
),
quality AS (
    SELECT c.*,
        CASE
            WHEN c.non_pln_rows > 0 THEN 'INVALID_CURRENCY'
            WHEN c.missing_inventory THEN 'MISSING_INVENTORY'
            WHEN c.sold_room_nights > c.available_room_nights THEN 'SOLD_EXCEEDS_AVAILABILITY'
            WHEN c.room_revenue_raw <> 0 AND c.sold_room_nights = 0 THEN 'REVENUE_WITHOUT_NIGHT'
            ELSE 'OK'
        END AS kpi_quality_status
    FROM combined c
)
SELECT
    q.hotel_sk,
    q.date_sk,
    dd.full_date,
    q.room_type_sk,
    q.sold_room_nights,
    q.available_room_nights,
    q.ooo_room_nights,
    q.total_room_nights,
    CASE WHEN q.non_pln_rows = 0 THEN q.room_revenue_raw ELSE NULL END AS room_revenue_pln,
    q.non_pln_rows,
    q.kpi_quality_status,
    CASE WHEN q.kpi_quality_status = 'OK'
        THEN 100::NUMERIC * q.sold_room_nights / NULLIF(q.available_room_nights, 0)
        ELSE NULL END AS occ_pct,
    CASE WHEN q.kpi_quality_status = 'OK'
        THEN q.room_revenue_raw / NULLIF(q.sold_room_nights, 0)
        ELSE NULL END AS adr_pln,
    CASE WHEN q.kpi_quality_status = 'OK'
        THEN q.room_revenue_raw / NULLIF(q.available_room_nights, 0)
        ELSE NULL END AS revpar_pln
FROM quality q
JOIN mart.dim_date dd ON dd.date_sk = q.date_sk;

COMMENT ON VIEW mart.vw_us_04_01_kpi_daily IS
'US-04-01. Agregacje dwoch faktow oddzielnie: hotel x data x fizyczny typ pokoju. PLN; przypadki naruszen jakosci flagowane, KPI NULL.';

CREATE OR REPLACE VIEW mart.vw_us_04_01_kpi_monthly AS
WITH monthly AS (
    SELECT
        hotel_sk,
        DATE_TRUNC('month', full_date)::DATE AS month_start,
        room_type_sk,
        SUM(sold_room_nights)::BIGINT AS sold_room_nights,
        SUM(available_room_nights)::BIGINT AS available_room_nights,
        SUM(ooo_room_nights)::BIGINT AS ooo_room_nights,
        SUM(room_revenue_pln)::NUMERIC(20,2) AS room_revenue_pln,
        BOOL_OR(kpi_quality_status <> 'OK') AS invalid_data,
        COUNT(*) FILTER (WHERE kpi_quality_status <> 'OK') AS invalid_days
    FROM mart.vw_us_04_01_kpi_daily
    GROUP BY hotel_sk, DATE_TRUNC('month', full_date)::DATE, room_type_sk
)
SELECT
    hotel_sk,
    month_start,
    room_type_sk,
    sold_room_nights,
    available_room_nights,
    ooo_room_nights,
    CASE WHEN NOT invalid_data THEN room_revenue_pln ELSE NULL END AS room_revenue_pln,
    invalid_days,
    CASE WHEN invalid_data THEN 'INVALID_DATA' ELSE 'OK' END AS kpi_quality_status,
    CASE WHEN NOT invalid_data
         THEN 100::NUMERIC * sold_room_nights / NULLIF(available_room_nights, 0)
         ELSE NULL END AS occ_pct,
    CASE WHEN NOT invalid_data
         THEN room_revenue_pln / NULLIF(sold_room_nights, 0)
         ELSE NULL END AS adr_pln,
    CASE WHEN NOT invalid_data
         THEN room_revenue_pln / NULLIF(available_room_nights, 0)
         ELSE NULL END AS revpar_pln
FROM monthly;

COMMENT ON VIEW mart.vw_us_04_01_kpi_monthly IS
'US-04-01. Suma miar bazowych na poziomie hotel x miesiac x typ pokoju; raporty multi-hotel licza KPI ponownie z SUM, nie AVG.';

COMMIT;
