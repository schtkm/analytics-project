-- US-03-05A | Zestaw testów akceptacyjnych dla mart.fct_room_night

SELECT 'T01_GRAIN_UNIQUENESS' AS test_id,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*) AS invalid_rows
FROM (
    SELECT stay_bk, room_sk, stay_date_sk
    FROM mart.fct_room_night
    GROUP BY stay_bk, room_sk, stay_date_sk
    HAVING COUNT(*) > 1
) dup

UNION ALL

SELECT 'T02_TOTAL_ROOM_NIGHTS_MATCH',
       CASE WHEN (SELECT COUNT(*) FROM mart.fct_room_night) = (
           SELECT SUM(s.actual_check_out - s.actual_check_in)
           FROM core.clean_pms_stays s
           JOIN mart.fct_reservations fr ON fr.reservation_bk = s.reservation_id
           WHERE fr.reservation_status IN ('COMPLETED', 'IN_PROGRESS')
             AND s.actual_check_out > s.actual_check_in
       ) THEN 'PASS' ELSE 'FAIL' END,
       (SELECT COUNT(*) FROM mart.fct_room_night)

UNION ALL

SELECT 'T03_NO_CANCELLED_OR_NOSHOW',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM mart.fct_room_night fn
JOIN mart.fct_reservations fr ON fr.reservation_sk = fn.reservation_sk
WHERE fr.reservation_status NOT IN ('COMPLETED', 'IN_PROGRESS')

UNION ALL

SELECT 'T04_CROSS_MONTH_BOUNDARY_SPLIT',
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM (
    SELECT fn.stay_bk
    FROM mart.fct_room_night fn
    JOIN mart.dim_date dd ON dd.date_sk = fn.stay_date_sk
    GROUP BY fn.stay_bk
    HAVING COUNT(DISTINCT (dd.calendar_year, dd.month_number)) > 1
) cross_month

UNION ALL

SELECT 'T05_DIMENSION_FK_INTEGRITY',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM mart.fct_room_night fn
LEFT JOIN mart.fct_reservations fr ON fr.reservation_sk = fn.reservation_sk
LEFT JOIN mart.dim_date dd ON dd.date_sk = fn.stay_date_sk AND dd.full_date IS NOT NULL
LEFT JOIN mart.dim_hotel dh ON dh.hotel_sk = fn.hotel_sk
LEFT JOIN mart.dim_room dr ON dr.room_sk = fn.room_sk
LEFT JOIN mart.dim_room_type brt ON brt.room_type_sk = fn.booked_room_type_sk
LEFT JOIN mart.dim_room_type ort ON ort.room_type_sk = fn.occupied_room_type_sk
LEFT JOIN mart.dim_channel dc ON dc.channel_sk = fn.channel_sk
LEFT JOIN mart.dim_guest dg ON dg.guest_sk = fn.primary_guest_sk
LEFT JOIN mart.dim_segment ds ON ds.segment_sk = fn.segment_sk
WHERE fr.reservation_sk IS NULL OR dd.date_sk IS NULL OR dh.hotel_sk IS NULL
   OR dr.room_sk IS NULL OR brt.room_type_sk IS NULL OR ort.room_type_sk IS NULL
   OR dc.channel_sk IS NULL OR dg.guest_sk IS NULL OR ds.segment_sk IS NULL

UNION ALL

SELECT 'T06_REVENUE_RECONCILIATION',
       CASE WHEN (SELECT SUM(room_revenue) FROM mart.fct_room_night) = (
           SELECT SUM(fr.room_revenue)
           FROM core.clean_pms_stays s
           JOIN mart.fct_reservations fr ON fr.reservation_bk = s.reservation_id
           WHERE fr.reservation_status IN ('COMPLETED', 'IN_PROGRESS')
             AND s.actual_check_out > s.actual_check_in
       ) THEN 'PASS' ELSE 'FAIL' END,
       0

UNION ALL

SELECT 'T07_STAY_NIGHT_FLAGS_CONSISTENCY',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       COUNT(*)
FROM (
    SELECT stay_bk
    FROM mart.fct_room_night
    GROUP BY stay_bk
    HAVING COUNT(*) FILTER (WHERE is_arrival_night) <> 1
        OR COUNT(*) FILTER (WHERE is_last_night) <> 1
        OR COUNT(*) FILTER (WHERE is_stay_over) <> GREATEST(COUNT(*) - 2, 0)
) bad_flags

ORDER BY test_id;