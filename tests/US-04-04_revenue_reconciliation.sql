-- US-04-04: Uzgodnienie przychodow GOP z PMS
-- Skrypt kontrolny, nie modyfikuje danych.

-- 1. Przychody PMS vs przychody z noclegow
WITH revenue_by_reservation AS (
    SELECT
        reservation_sk,
        SUM(room_revenue) AS room_night_revenue
    FROM mart.fct_room_night
    GROUP BY reservation_sk
)
SELECT
    COUNT(*) AS liczba_rezerwacji,
    ROUND(SUM(p.room_revenue), 2) AS przychod_pms,
    ROUND(SUM(r.room_night_revenue), 2) AS przychod_noclegow,
    ROUND(SUM(r.room_night_revenue) - SUM(p.room_revenue), 2)
        AS roznica_pln
FROM revenue_by_reservation r
JOIN mart.fct_reservations f
    ON r.reservation_sk = f.reservation_sk
JOIN core.clean_pms_reservations p
    ON f.reservation_bk = p.reservation_id;

-- 2. Przychody GOP vs przychody z noclegow
WITH revenue_source AS (
    SELECT
        h.hotel_bk AS hotel_id,
        DATE_TRUNC('month', d.full_date)::date AS month_id,
        SUM(rn.room_revenue) AS revenue_pln
    FROM mart.fct_room_night rn
    JOIN mart.dim_hotel h ON rn.hotel_sk = h.hotel_sk
    JOIN mart.dim_date d ON rn.stay_date_sk = d.date_sk
    WHERE d.full_date >= DATE '2024-01-01'
      AND d.full_date < DATE '2026-01-01'
    GROUP BY h.hotel_bk, DATE_TRUNC('month', d.full_date)::date
)
SELECT
    COUNT(*) AS porownane_okresy,
    COUNT(*) FILTER (
        WHERE g.hotel_id IS NULL OR s.hotel_id IS NULL
    ) AS brakujace_okresy,
    COUNT(*) FILTER (
        WHERE ABS(
            COALESCE(g.revenue_pln, 0)
            - COALESCE(s.revenue_pln, 0)
        ) > 0.01
    ) AS niezgodne_okresy,
    ROUND(SUM(COALESCE(g.revenue_pln, 0)), 2)
        AS przychod_gop,
    ROUND(SUM(COALESCE(s.revenue_pln, 0)), 2)
        AS przychod_zrodlo,
    ROUND(
        SUM(COALESCE(g.revenue_pln, 0))
        - SUM(COALESCE(s.revenue_pln, 0)), 2
    ) AS roznica_pln
FROM mart.v_gop_monthly g
FULL OUTER JOIN revenue_source s
    ON g.hotel_id = s.hotel_id
   AND g.month_id = s.month_id;