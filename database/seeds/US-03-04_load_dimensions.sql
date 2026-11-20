-- US-03-04 | Zasilenie pieciu wymiarow wykorzystywanych przez mart.fct_reservations.
-- Wymaga: US-02-02 (core.clean_*), migracji US-03-04_dim_date_unknown.sql.
-- Uruchom w hotelgroup_dw, PRZED US-03-04_load_fct_reservations.sql.
-- Nie modyfikuje juz istniejacych rekordow; brakujace rekordy dopisuje.
-- Uwaga: wymiar DimGuest w tym zakresie zawiera tylko jeden rekord na guest_bk
-- (brak wersjonowania SCD w ramach tego zasilenia).

BEGIN;

DO $preflight$
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Oczekiwano bazy hotelgroup_dw, otrzymano %.', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.clean_pms_reservations)
       OR NOT EXISTS (SELECT 1 FROM core.clean_pms_hotels)
       OR NOT EXISTS (SELECT 1 FROM core.clean_pms_guests)
       OR NOT EXISTS (SELECT 1 FROM core.clean_cm_channels) THEN
        RAISE EXCEPTION 'Brak oczyszczonych danych core.clean_*.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (
            SELECT hotel_bk FROM mart.dim_hotel GROUP BY hotel_bk HAVING count(*) > 1
            UNION ALL SELECT guest_bk FROM mart.dim_guest GROUP BY guest_bk HAVING count(*) > 1
            UNION ALL SELECT channel_bk FROM mart.dim_channel GROUP BY channel_bk HAVING count(*) > 1
            UNION ALL SELECT segment_bk FROM mart.dim_segment GROUP BY segment_bk HAVING count(*) > 1
        ) duplicates
    ) THEN
        RAISE EXCEPTION 'Istniejace wymiary zawieraja niejednoznaczne klucze biznesowe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM mart.dim_date WHERE date_sk = 0 AND full_date IS NULL)
       OR NOT EXISTS (SELECT 1 FROM mart.dim_date WHERE date_sk = -1 AND full_date IS NULL) THEN
        RAISE EXCEPTION 'Najpierw wykonaj migracje US-03-04_dim_date_unknown.sql.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM core.clean_cm_channels
        WHERE channel_code IS NULL OR channel_code NOT IN ('BOOKING','DIRECT','EXPEDIA')
    ) THEN
        RAISE EXCEPTION 'Wykryto nieobslugiwany kod kanalu.';
    END IF;
END;
$preflight$;

INSERT INTO mart.dim_segment (segment_bk, segment_name)
SELECT DISTINCT r.guest_segment, r.guest_segment
FROM core.clean_pms_reservations r
WHERE r.guest_segment IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM mart.dim_segment d WHERE d.segment_bk = r.guest_segment);

WITH channels AS (
    SELECT DISTINCT
        CASE channel_code WHEN 'BOOKING' THEN 'BOOKING_COM' ELSE channel_code END AS bk,
        CASE channel_code WHEN 'BOOKING' THEN 'Booking.com'
             WHEN 'DIRECT' THEN 'Sprzedaż bezpośrednia'
             WHEN 'EXPEDIA' THEN 'Expedia' END AS channel_name,
        CASE channel_code WHEN 'DIRECT' THEN 'DIRECT' ELSE 'OTA' END AS group_code
    FROM core.clean_cm_channels
)
INSERT INTO mart.dim_channel (channel_bk, channel_name, channel_group_code)
SELECT c.bk, c.channel_name, c.group_code
FROM channels c
WHERE NOT EXISTS (SELECT 1 FROM mart.dim_channel d WHERE d.channel_bk = c.bk);

INSERT INTO mart.dim_hotel (hotel_bk, hotel_name, city_name, region_name)
SELECT h.hotel_id, h.hotel_name, h.city, h.region
FROM core.clean_pms_hotels h
WHERE NOT EXISTS (SELECT 1 FROM mart.dim_hotel d WHERE d.hotel_bk = h.hotel_id);

INSERT INTO mart.dim_guest (guest_bk, first_name, last_name)
SELECT g.guest_id, g.first_name, g.last_name
FROM core.clean_pms_guests g
WHERE NOT EXISTS (SELECT 1 FROM mart.dim_guest d WHERE d.guest_bk = g.guest_id);

WITH dates AS (
    SELECT booking_date AS d FROM core.clean_pms_reservations
    UNION
    SELECT check_in_date FROM core.clean_pms_reservations
    UNION
    SELECT check_out_date FROM core.clean_pms_reservations
)
INSERT INTO mart.dim_date (
    date_sk, full_date, calendar_year, quarter_number, month_number,
    month_name, day_of_month, day_of_week_number, day_of_week_name, is_weekend
)
SELECT
    to_char(d, 'YYYYMMDD')::int,
    d,
    extract(year from d)::int,
    extract(quarter from d)::int,
    extract(month from d)::int,
    to_char(d, 'TMMonth'),
    extract(day from d)::int,
    extract(isodow from d)::int,
    to_char(d, 'TMDay'),
    extract(isodow from d) IN (6,7)
FROM dates
WHERE d IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM mart.dim_date old WHERE old.full_date = dates.d);

DO $verify$
DECLARE
    source_count bigint;
    joined_count bigint;
BEGIN
    SELECT count(*) INTO source_count FROM core.clean_pms_reservations;
    SELECT count(*) INTO joined_count
    FROM core.clean_pms_reservations r
    JOIN mart.dim_hotel h ON h.hotel_bk = r.hotel_id
    JOIN mart.dim_guest g ON g.guest_bk = r.guest_id
    JOIN mart.dim_segment s ON s.segment_bk = r.guest_segment
    JOIN core.clean_cm_channels cm ON cm.reservation_id = r.reservation_id
    JOIN mart.dim_channel c ON c.channel_bk = CASE cm.channel_code WHEN 'BOOKING' THEN 'BOOKING_COM' ELSE cm.channel_code END
    JOIN mart.dim_date db ON db.full_date = r.booking_date
    JOIN mart.dim_date da ON da.full_date = r.check_in_date
    JOIN mart.dim_date dd ON dd.full_date = r.check_out_date;
    IF joined_count <> source_count THEN
        RAISE EXCEPTION 'Niezgodna liczba polaczonych rezerwacji: % vs %.', joined_count, source_count;
    END IF;
    RAISE NOTICE 'PASS: wszystkie % rezerwacji maja jednoznaczne powiazania wymiarowe.', source_count;
END;
$verify$;

COMMIT;

SELECT 'dim_date' AS wymiar, count(*) AS rekordy FROM mart.dim_date
UNION ALL SELECT 'dim_hotel', count(*) FROM mart.dim_hotel
UNION ALL SELECT 'dim_channel', count(*) FROM mart.dim_channel
UNION ALL SELECT 'dim_guest', count(*) FROM mart.dim_guest
UNION ALL SELECT 'dim_segment', count(*) FROM mart.dim_segment
ORDER BY wymiar;
