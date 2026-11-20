-- US-03-05 / wsparcie US-03-03: zasilenie wymiarow pokoi
-- Wymaga: core.clean_pms_rooms i zasilonego mart.dim_hotel.
-- Uruchomic po US-03-04_load_dimensions.sql, przed zasileniem fct_room_night.
-- Przy ponownym uruchomieniu pomija istniejace rekordy.
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Oczekiwana baza hotelgroup_dw, aktualna: %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.clean_pms_rooms) THEN
        RAISE EXCEPTION 'Brak oczyszczonych pokoi w core.clean_pms_rooms';
    END IF;
    IF EXISTS (
        SELECT room_id FROM core.clean_pms_rooms
        GROUP BY room_id HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Nieunikalne room_id w core.clean_pms_rooms';
    END IF;
    IF EXISTS (
        SELECT 1 FROM core.clean_pms_rooms r
        LEFT JOIN mart.dim_hotel h ON h.hotel_bk = r.hotel_id
        WHERE h.hotel_sk IS NULL OR r.room_type IS NULL OR r.room_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Brak mapowania hotelu, typu lub identyfikatora pokoju';
    END IF;
    IF EXISTS (SELECT hotel_bk FROM mart.dim_hotel GROUP BY hotel_bk HAVING COUNT(*) > 1) THEN
        RAISE EXCEPTION 'Powielone hotel_bk w mart.dim_hotel';
    END IF;
    IF EXISTS (SELECT room_type_bk FROM mart.dim_room_type GROUP BY room_type_bk HAVING COUNT(*) > 1) THEN
        RAISE EXCEPTION 'Powielone room_type_bk w mart.dim_room_type';
    END IF;
    IF EXISTS (SELECT room_bk FROM mart.dim_room GROUP BY room_bk HAVING COUNT(*) > 1) THEN
        RAISE EXCEPTION 'Powielone room_bk w mart.dim_room';
    END IF;
END $$;

INSERT INTO mart.dim_room_type (room_type_bk, room_type_name)
SELECT DISTINCT r.room_type, r.room_type
FROM core.clean_pms_rooms r
WHERE NOT EXISTS (
    SELECT 1 FROM mart.dim_room_type t WHERE t.room_type_bk = r.room_type
);

INSERT INTO mart.dim_room (room_bk, hotel_sk, room_number, current_room_type_sk)
SELECT r.room_id, h.hotel_sk, r.room_number, t.room_type_sk
FROM core.clean_pms_rooms r
JOIN mart.dim_hotel h ON h.hotel_bk = r.hotel_id
JOIN mart.dim_room_type t ON t.room_type_bk = r.room_type
WHERE NOT EXISTS (
    SELECT 1 FROM mart.dim_room d WHERE d.room_bk = r.room_id
);

DO $$
DECLARE
    source_count bigint;
    matched_count bigint;
BEGIN
    SELECT COUNT(*) INTO source_count FROM core.clean_pms_rooms;
    SELECT COUNT(*) INTO matched_count
    FROM core.clean_pms_rooms r
    JOIN mart.dim_room d ON d.room_bk = r.room_id
    JOIN mart.dim_hotel h ON h.hotel_sk = d.hotel_sk AND h.hotel_bk = r.hotel_id
    JOIN mart.dim_room_type t ON t.room_type_sk = d.current_room_type_sk AND t.room_type_bk = r.room_type
    WHERE d.room_number IS NOT DISTINCT FROM r.room_number;
    IF source_count <> matched_count THEN
        RAISE EXCEPTION 'Niezgodnosc wymiarow pokoi: source=%, matched=%', source_count, matched_count;
    END IF;
    RAISE NOTICE 'PASS: % pokoi ma zgodne powiazania z hotelem i typem pokoju', matched_count;
END $$;

COMMIT;

SELECT 'dim_room_type' AS wymiar, COUNT(*) AS rekordy FROM mart.dim_room_type
UNION ALL
SELECT 'dim_room', COUNT(*) FROM mart.dim_room;
