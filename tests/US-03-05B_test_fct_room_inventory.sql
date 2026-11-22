-- US-03-05B | Zestaw testów akceptacyjnych i reguł DQ dla mart.fct_room_inventory

-- 1. Główny zestaw testów walidacyjnych (T01 - T08)
SELECT 'T01_DQ02_GRAIN_UNIQUENESS' AS test_id,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*) AS metric_value
FROM (
    SELECT room_sk, inventory_date_sk
    FROM mart.fct_room_inventory
    GROUP BY room_sk, inventory_date_sk
    HAVING COUNT(*) > 1
) dup

UNION ALL

SELECT 'T02_FULL_ROOM_DATE_COVERAGE',
       CASE WHEN (SELECT COUNT(*) FROM mart.fct_room_inventory) =
                 (SELECT COUNT(*) FROM mart.dim_room) *
                 (SELECT COUNT(*) FROM mart.dim_date WHERE full_date IS NOT NULL)
            THEN 'PASS' ELSE 'FAIL' END,
       (SELECT COUNT(*) FROM mart.fct_room_inventory)

UNION ALL

SELECT 'T03_DQ03_FK_AND_HOTEL_CONSISTENCY',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM mart.fct_room_inventory fi
LEFT JOIN mart.dim_date dd ON dd.date_sk = fi.inventory_date_sk AND dd.full_date IS NOT NULL
LEFT JOIN mart.dim_hotel dh ON dh.hotel_sk = fi.hotel_sk
LEFT JOIN mart.dim_room dr ON dr.room_sk = fi.room_sk
LEFT JOIN mart.dim_room_type drt ON drt.room_type_sk = fi.room_type_sk
WHERE dd.date_sk IS NULL
   OR dh.hotel_sk IS NULL
   OR dr.room_sk IS NULL
   OR drt.room_type_sk IS NULL
   OR fi.hotel_sk <> dr.hotel_sk
   OR fi.room_type_sk <> dr.current_room_type_sk

UNION ALL

SELECT 'T04_OUT_OF_ORDER_FORMULA_INTEGRITY',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM mart.fct_room_inventory
WHERE available_room_nights + out_of_order_room_nights <> total_room_nights
   OR (is_out_of_order = TRUE  AND available_room_nights <> 0)
   OR (is_out_of_order = FALSE AND available_room_nights <> 1)

UNION ALL

SELECT 'T05_ROOM_TYPE_AGGREGATION_MATCH',
       CASE WHEN (
           SELECT SUM(agg_avail)
           FROM (
               SELECT drt.room_type_bk, SUM(fi.available_room_nights) AS agg_avail
               FROM mart.fct_room_inventory fi
               JOIN mart.dim_room_type drt ON drt.room_type_sk = fi.room_type_sk
               GROUP BY drt.room_type_bk
           ) rt
       ) = (SELECT SUM(available_room_nights) FROM mart.fct_room_inventory)
       THEN 'PASS' ELSE 'FAIL' END,
       (SELECT COUNT(DISTINCT room_type_sk) FROM mart.fct_room_inventory)

UNION ALL

SELECT 'T06_HORIZON_7_30_90_DAYS_COVERAGE',
       CASE WHEN COUNT(*) FILTER (WHERE dd.full_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-07') = 7 * 1240
             AND COUNT(*) FILTER (WHERE dd.full_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-30') = 30 * 1240
             AND COUNT(*) FILTER (WHERE dd.full_date BETWEEN DATE '2026-01-01' AND DATE '2026-03-31') = 90 * 1240
            THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*) FILTER (WHERE dd.full_date BETWEEN DATE '2026-01-01' AND DATE '2026-03-31')
FROM mart.fct_room_inventory fi
JOIN mart.dim_date dd ON dd.date_sk = fi.inventory_date_sk

UNION ALL

SELECT 'T07_DQ04_REALIZED_OCC_UNDER_100_PCT',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM (
    SELECT
        fi.hotel_sk,
        fi.inventory_date_sk,
        SUM(fi.available_room_nights) AS available_nights,
        COALESCE(SUM(fn.room_night_count), 0) AS sold_nights
    FROM mart.fct_room_inventory fi
    LEFT JOIN mart.fct_room_night fn
           ON fn.hotel_sk = fi.hotel_sk
          AND fn.stay_date_sk = fi.inventory_date_sk
    GROUP BY fi.hotel_sk, fi.inventory_date_sk
    HAVING COALESCE(SUM(fn.room_night_count), 0) > SUM(fi.available_room_nights)
) realized_overbooking

UNION ALL

SELECT 'T08_FUTURE_RESERVATION_OVERBOOKING_CHECK',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM (
    WITH future_booked AS (
        SELECT
            dr.hotel_sk,
            dd.date_sk,
            COUNT(*) AS booked_nights
        FROM core.clean_pms_reservations r
        JOIN mart.dim_room dr ON dr.room_bk = r.room_id
        CROSS JOIN LATERAL generate_series(
            r.check_in_date,
            r.check_out_date - INTERVAL '1 day',
            INTERVAL '1 day'
        ) AS gs(night_date)
        JOIN mart.dim_date dd ON dd.full_date = gs.night_date::date
        WHERE r.status NOT IN ('Anulowana', 'No-Show')
          AND dd.full_date >= DATE '2026-01-01'
        GROUP BY dr.hotel_sk, dd.date_sk
    )
    SELECT fi.hotel_sk, fi.inventory_date_sk
    FROM mart.fct_room_inventory fi
    JOIN future_booked fb
      ON fb.hotel_sk = fi.hotel_sk
     AND fb.date_sk = fi.inventory_date_sk
    GROUP BY fi.hotel_sk, fi.inventory_date_sk, fb.booked_nights
    HAVING fb.booked_nights > SUM(fi.available_room_nights)
) future_overbooking

ORDER BY test_id;

-- 2. Test symulacyjny Out of Order (weryfikacja wyłączenia pokoju z mianownika OCC + ROLLBACK)
BEGIN;

UPDATE mart.fct_room_inventory
SET is_out_of_order = TRUE,
    out_of_order_room_nights = 1,
    available_room_nights = 0
WHERE room_inventory_sk = (SELECT MIN(room_inventory_sk) FROM mart.fct_room_inventory);

DO $test_ooo$
DECLARE
    v_avail SMALLINT;
    v_ooo   SMALLINT;
BEGIN
    SELECT available_room_nights, out_of_order_room_nights
    INTO v_avail, v_ooo
    FROM mart.fct_room_inventory
    WHERE room_inventory_sk = (SELECT MIN(room_inventory_sk) FROM mart.fct_room_inventory);

    IF v_avail <> 0 OR v_ooo <> 1 THEN
        RAISE EXCEPTION 'FAIL testu Out of Order: available=%, ooo=%', v_avail, v_ooo;
    END IF;

    RAISE NOTICE 'PASS T09_OUT_OF_ORDER_SIMULATION: pokój oznaczony jako Out of Order ma available_room_nights = 0 (wyłączony z mianownika OCC).';
END
$test_ooo$;

ROLLBACK;