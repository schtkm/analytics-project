-- US-03-05B | Zasilenie mart.fct_room_inventory dla wszystkich pokoi i dat kalendarzowych.
-- Uruchomić po US-03-05B_fct_room_inventory_migration.sql oraz zasileniu dim_room i dim_date.

BEGIN;

DO $preflight$
DECLARE
    n_rooms         BIGINT;
    n_dates         BIGINT;
    calendar_span   BIGINT;
    n_invalid_rooms BIGINT;
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Niepoprawna baza danych: %. Oczekiwano hotelgroup_dw.', current_database();
    END IF;

    IF to_regclass('mart.fct_room_inventory') IS NULL THEN
        RAISE EXCEPTION 'Brak tabeli mart.fct_room_inventory. Uruchom najpierw skrypt migracji.';
    END IF;

    IF EXISTS (SELECT 1 FROM mart.fct_room_inventory LIMIT 1) THEN
        RAISE EXCEPTION 'Tabela mart.fct_room_inventory nie jest pusta. Wstrzymano INSERT, aby uniknąć duplikatów.';
    END IF;

    SELECT COUNT(*) INTO n_rooms FROM mart.dim_room;
    IF n_rooms = 0 THEN
        RAISE EXCEPTION 'Brak pokoi w mart.dim_room.';
    END IF;

    -- DQ-10: weryfikacja ciągłości kalendarza w mart.dim_date
    SELECT COUNT(*), (MAX(full_date) - MIN(full_date) + 1)
    INTO n_dates, calendar_span
    FROM mart.dim_date
    WHERE full_date IS NOT NULL;

    IF n_dates = 0 OR n_dates <> calendar_span THEN
        RAISE EXCEPTION 'Luki w kalendarzu mart.dim_date: rekordów %, rozpiętość dni %.', n_dates, calendar_span;
    END IF;

    -- DQ-01 / DQ-03: weryfikacja kompletności powiązań pokoi z hotelem i typem pokoju
    SELECT COUNT(*) INTO n_invalid_rooms
    FROM mart.dim_room dr
    LEFT JOIN mart.dim_hotel dh ON dh.hotel_sk = dr.hotel_sk
    LEFT JOIN mart.dim_room_type drt ON drt.room_type_sk = dr.current_room_type_sk
    WHERE dh.hotel_sk IS NULL OR drt.room_type_sk IS NULL;

    IF n_invalid_rooms > 0 THEN
        RAISE EXCEPTION 'Wykryto % pokoi w dim_room bez poprawnego hotel_sk lub current_room_type_sk.', n_invalid_rooms;
    END IF;

    RAISE NOTICE 'PASS preflight: % pokoi × % ciągłych dni kalendarzowych = % oczekiwanych rekordów.',
        n_rooms, n_dates, n_rooms * n_dates;
END
$preflight$;

INSERT INTO mart.fct_room_inventory (
    inventory_date_sk,
    hotel_sk,
    room_sk,
    room_type_sk,
    total_room_nights,
    is_out_of_order,
    out_of_order_room_nights,
    available_room_nights
)
SELECT
    dd.date_sk                AS inventory_date_sk,
    dr.hotel_sk               AS hotel_sk,
    dr.room_sk                AS room_sk,
    dr.current_room_type_sk   AS room_type_sk,
    1::smallint               AS total_room_nights,
    FALSE                     AS is_out_of_order,
    0::smallint               AS out_of_order_room_nights,
    1::smallint               AS available_room_nights
FROM mart.dim_room dr
CROSS JOIN mart.dim_date dd
WHERE dd.full_date IS NOT NULL
ORDER BY dd.date_sk, dr.hotel_sk, dr.room_sk;

DO $verify$
DECLARE
    expected_rows  BIGINT;
    actual_rows    BIGINT;
    duplicate_rows BIGINT;
    inconsistent   BIGINT;
BEGIN
    SELECT (SELECT COUNT(*) FROM mart.dim_room) *
           (SELECT COUNT(*) FROM mart.dim_date WHERE full_date IS NOT NULL)
    INTO expected_rows;

    SELECT COUNT(*) INTO actual_rows FROM mart.fct_room_inventory;

    SELECT COUNT(*) INTO duplicate_rows
    FROM (
        SELECT room_sk, inventory_date_sk
        FROM mart.fct_room_inventory
        GROUP BY room_sk, inventory_date_sk
        HAVING COUNT(*) > 1
    ) d;

    SELECT COUNT(*) INTO inconsistent
    FROM mart.fct_room_inventory
    WHERE available_room_nights + out_of_order_room_nights <> total_room_nights;

    IF duplicate_rows > 0 THEN
        RAISE EXCEPTION 'DQ-02 FAIL: wykryto % zduplikowanych ziaren (room_sk, inventory_date_sk).', duplicate_rows;
    END IF;

    IF actual_rows <> expected_rows OR inconsistent > 0 THEN
        RAISE EXCEPTION 'Błąd spójności ładowania: załadowano %/%, niespójnych wierszy %.',
            actual_rows, expected_rows, inconsistent;
    END IF;

    RAISE NOTICE 'PASS kontrola: załadowano % rekordów dostępności pokoi bez duplikatów.', actual_rows;
END
$verify$;

COMMIT;

-- Podsumowanie dostępności po hotelach:
SELECT
    dh.hotel_bk,
    dh.hotel_name,
    COUNT(DISTINCT fi.room_sk)          AS physical_rooms,
    COUNT(DISTINCT fi.inventory_date_sk) AS calendar_days,
    SUM(fi.total_room_nights)           AS total_room_nights,
    SUM(fi.out_of_order_room_nights)    AS ooo_room_nights,
    SUM(fi.available_room_nights)       AS available_room_nights
FROM mart.fct_room_inventory fi
JOIN mart.dim_hotel dh ON dh.hotel_sk = fi.hotel_sk
GROUP BY dh.hotel_bk, dh.hotel_name
ORDER BY dh.hotel_bk;