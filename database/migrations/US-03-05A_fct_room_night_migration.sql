-- US-03-05A | FactRoomNight — migracja struktury tabeli mart.fct_room_night
-- Ziarno: jeden rekord na (stay_bk, room_sk, stay_date_sk).
-- Uruchamiać w bazie hotelgroup_dw przed US-03-05A_load_fct_room_night.sql.

BEGIN;

DO $preflight$
DECLARE
    missing_columns TEXT;
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Oczekiwano bazy hotelgroup_dw, otrzymano %.', current_database();
    END IF;

    IF to_regclass('mart.fct_room_night') IS NULL THEN
        RAISE EXCEPTION 'Brak bazowej tabeli mart.fct_room_night.';
    END IF;

    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
    INTO missing_columns
    FROM (VALUES
        ('room_night_sk'), ('stay_date_sk'), ('hotel_sk'), ('room_sk'),
        ('booked_room_type_sk'), ('occupied_room_type_sk'),
        ('channel_sk'), ('primary_guest_sk'), ('segment_sk'), ('room_revenue')
    ) AS required(column_name)
    LEFT JOIN information_schema.columns AS actual
        ON actual.table_schema = 'mart'
       AND actual.table_name = 'fct_room_night'
       AND actual.column_name = required.column_name
    WHERE actual.column_name IS NULL;

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION 'Niezgodna wersja mart.fct_room_night. Brak kolumn: %', missing_columns;
    END IF;

    IF EXISTS (SELECT 1 FROM mart.fct_room_night LIMIT 1) THEN
        RAISE EXCEPTION 'Tabela mart.fct_room_night nie jest pusta. Migracja wymaga pustej tabeli.';
    END IF;
END
$preflight$;

-- 1. Rozszerzenie tabeli o identyfikator pobytu, FK do rezerwacji, licznik, flagi doby i walutę
ALTER TABLE mart.fct_room_night
    ADD COLUMN IF NOT EXISTS stay_bk VARCHAR(50),
    ADD COLUMN IF NOT EXISTS reservation_sk INTEGER,
    ADD COLUMN IF NOT EXISTS room_night_count SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS is_arrival_night BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_stay_over BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_last_night BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS currency_code CHAR(3) NOT NULL DEFAULT 'PLN';

-- 2. Wymuszenie NOT NULL na kluczach ziarna, wymiarów i miarach
ALTER TABLE mart.fct_room_night
    ALTER COLUMN stay_bk SET NOT NULL,
    ALTER COLUMN reservation_sk SET NOT NULL,
    ALTER COLUMN stay_date_sk SET NOT NULL,
    ALTER COLUMN hotel_sk SET NOT NULL,
    ALTER COLUMN room_sk SET NOT NULL,
    ALTER COLUMN booked_room_type_sk SET NOT NULL,
    ALTER COLUMN occupied_room_type_sk SET NOT NULL,
    ALTER COLUMN channel_sk SET NOT NULL,
    ALTER COLUMN primary_guest_sk SET NOT NULL,
    ALTER COLUMN segment_sk SET NOT NULL,
    ALTER COLUMN room_revenue SET NOT NULL,
    ALTER COLUMN room_revenue TYPE NUMERIC(18,2);

-- 3. Wymuszenie ziarna (stay_bk, room_sk, stay_date_sk) oraz indeksy analityczne
CREATE UNIQUE INDEX IF NOT EXISTS uq_fct_room_night_grain
    ON mart.fct_room_night (stay_bk, room_sk, stay_date_sk);

CREATE INDEX IF NOT EXISTS idx_fct_room_night_stay_date_sk
    ON mart.fct_room_night (stay_date_sk);

CREATE INDEX IF NOT EXISTS idx_fct_room_night_hotel_date
    ON mart.fct_room_night (hotel_sk, stay_date_sk);

CREATE INDEX IF NOT EXISTS idx_fct_room_night_reservation_sk
    ON mart.fct_room_night (reservation_sk);

-- 4. Klucz obcy do mart.fct_reservations oraz ograniczenia spójności
DO $constraints$
DECLARE
    item RECORD;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'mart.fct_room_night'::regclass
          AND conname = 'fk_fct_room_night_reservation'
    ) THEN
        ALTER TABLE mart.fct_room_night
            ADD CONSTRAINT fk_fct_room_night_reservation
            FOREIGN KEY (reservation_sk) REFERENCES mart.fct_reservations (reservation_sk);
    END IF;

    FOR item IN
        SELECT *
        FROM (VALUES
            ('ck_fct_room_night_count', $$CHECK (room_night_count = 1)$$),
            ('ck_fct_room_night_revenue', $$CHECK (room_revenue >= 0)$$),
            ('ck_fct_room_night_currency', $$CHECK (btrim(currency_code) ~ '^[A-Z]{3}$')$$)
        ) AS definitions(constraint_name, constraint_sql)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = 'mart.fct_room_night'::regclass
              AND conname = item.constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE mart.fct_room_night ADD CONSTRAINT %I %s',
                item.constraint_name,
                item.constraint_sql
            );
        END IF;
    END LOOP;
END
$constraints$;

COMMIT;