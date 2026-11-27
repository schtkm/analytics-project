-- HotelGroup | US-04-04 | GOP i marza GOP
-- Zakres: miesieczne dane za lata 2024-2025.
-- Przychody: zrealizowane pokojonoce.
-- Koszty: ACTUAL, kategorie INCLUDED.
-- Uproszczony GOP na danych syntetycznych.

CREATE OR REPLACE VIEW mart.v_gop_monthly AS
WITH revenue AS (
    SELECT
        r.hotel_sk,
        DATE_TRUNC('month', d.full_date)::date AS month_id,
        SUM(r.room_revenue) AS revenue_pln
    FROM mart.fct_room_night r
    JOIN mart.dim_date d
        ON d.date_sk = r.stay_date_sk
    WHERE d.full_date >= DATE '2024-01-01'
      AND d.full_date < DATE '2026-01-01'
    GROUP BY
        r.hotel_sk,
        DATE_TRUNC('month', d.full_date)::date
),
costs AS (
    SELECT
        f.hotel_sk,
        d.full_date AS month_id,
        SUM(f.amount) AS costs_pln
    FROM mart.fct_finance_monthly f
    JOIN mart.dim_date d
        ON d.date_sk = f.month_date_sk
    JOIN mart.dim_cost_category c
        ON c.cost_category_sk = f.cost_category_sk
    WHERE f.scenario = 'ACTUAL'
      AND c.gop_treatment = 'INCLUDED'
      AND c.is_active = TRUE
      AND d.full_date >= DATE '2024-01-01'
      AND d.full_date < DATE '2026-01-01'
    GROUP BY
        f.hotel_sk,
        d.full_date
)
SELECT
    h.hotel_bk AS hotel_id,
    r.month_id,
    r.revenue_pln,
    c.costs_pln,
    r.revenue_pln - c.costs_pln AS gop_pln,
    ROUND(
        100.0 * (r.revenue_pln - c.costs_pln)
        / NULLIF(r.revenue_pln, 0),
        2
    ) AS gop_margin_pct
FROM revenue r
JOIN costs c
    ON c.hotel_sk = r.hotel_sk
   AND c.month_id = r.month_id
JOIN mart.dim_hotel h
    ON h.hotel_sk = r.hotel_sk;