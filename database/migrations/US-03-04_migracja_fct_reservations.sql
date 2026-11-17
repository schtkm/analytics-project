-- US-03-04 | FactReservation — migracja struktury tabeli mart.fct_reservations
-- Podstawa: database/schema/Skrypty_do_odtworzenia_bazy.sql (nowszy model).
-- Cel: uzupełnić istniejącą tabelę faktów, NIE tworzyć drugiej tabeli.
-- Zależności: istnieją mart.fct_reservations i jej tabele wymiarów.
-- Celowo NIE zasilamy danych — to wymaga ukończenia US-02-02 i wymiarów.
-- Waluta PLN jest propozycją do Code Review: nie ustawiamy jej automatycznie.
-- Uruchamiać w bazie hotelgroup_dw; skrypt nie tworzy bazy ani schematów.
--
-- UWAGA: w repozytorium występuje też starszy plik 01_create_schemas.sql,
-- który definiuje inną strukturę mart.fct_reservations. Ten skrypt wymaga
-- nowszego modelu i przerwie wykonanie w przypadku brakujących kolumn.
--
-- Strategia bezpiecznego wdrożenia:
--   1. DDL wykonujemy przed pierwszym zasileniem faktu (tabela musi być pusta).
--   2. Nie usuwamy i nie aktualizujemy żadnych wierszy biznesowych.
--   3. Transakcja cofa wszystkie zmiany po błędzie.
--   4. Ponowne wykonanie na pustej tabeli nie dodaje duplikatów ograniczeń.

BEGIN;

-- 1. Sprawdzenie wersji bazowego schematu i pustej tabeli faktów.
DO $preflight$
DECLARE
    missing_columns TEXT;
BEGIN
    IF to_regclass('mart.fct_reservations') IS NULL THEN
        RAISE EXCEPTION 'Brak mart.fct_reservations. Utwórz najpierw nowszy schemat bazy.';
    END IF;

    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
    INTO missing_columns
    FROM (VALUES
        ('reservation_sk'), ('reservation_bk'),
        ('hotel_sk'), ('channel_sk'), ('primary_guest_sk'), ('segment_sk'),
        ('booking_date_sk'), ('arrival_date_sk'), ('departure_date_sk'),
        ('cancellation_date_sk'), ('reservation_status')
    ) AS required(column_name)
    LEFT JOIN information_schema.columns AS actual
        ON actual.table_schema = 'mart'
       AND actual.table_name = 'fct_reservations'
       AND actual.column_name = required.column_name
    WHERE actual.column_name IS NULL;

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'Niezgodna wersja mart.fct_reservations. Brak kolumn: %',
            missing_columns;
    END IF;

    IF EXISTS (SELECT 1 FROM mart.fct_reservations LIMIT 1) THEN
        RAISE EXCEPTION
            'Tabela mart.fct_reservations zawiera już dane. Migracja wymaga odrębnego planu dla istniejących rekordów.';
    END IF;
END
$preflight$;

-- 2. Rozszerzenie faktu o miary liczbowe, kwoty i kod waluty.
ALTER TABLE mart.fct_reservations
    ADD COLUMN IF NOT EXISTS reservation_count SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS cancellation_count SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS room_revenue NUMERIC(18,2),
    ADD COLUMN IF NOT EXISTS cancellation_fee NUMERIC(18,2),
    ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(18,2),
    ADD COLUMN IF NOT EXISTS currency_code CHAR(3);

-- Zachowanie reguł nawet wtedy, gdy kolumna istniała przed migracją.
ALTER TABLE mart.fct_reservations
    ALTER COLUMN reservation_count SET DEFAULT 1,
    ALTER COLUMN reservation_count SET NOT NULL,
    ALTER COLUMN cancellation_count SET DEFAULT 0,
    ALTER COLUMN cancellation_count SET NOT NULL,
    ALTER COLUMN reservation_status SET NOT NULL;

-- 3. Unikalność biznesowego identyfikatora rezerwacji.
--    PK reservation_sk i dotychczasowe FK pozostają bez zmian.
CREATE UNIQUE INDEX IF NOT EXISTS uq_fct_reservations_reservation_bk
    ON mart.fct_reservations (reservation_bk);

-- 4. Ograniczenia spójności. IF NOT EXISTS nie jest dostępne dla
--    ADD CONSTRAINT, dlatego sprawdzamy katalog pg_constraint.
DO $constraints$
DECLARE
    item RECORD;
BEGIN
    FOR item IN
        SELECT *
        FROM (VALUES
            (
                'ck_fct_reservations_status',
                $$CHECK (reservation_status IN (
                    'ACTIVE', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
                ))$$
            ),
            (
                'ck_fct_reservations_count',
                $$CHECK (reservation_count = 1)$$
            ),
            (
                'ck_fct_reservations_cancellation_count',
                $$CHECK (
                    cancellation_count = CASE
                        WHEN reservation_status = 'CANCELLED' THEN 1
                        ELSE 0
                    END
                )$$
            ),
            (
                'ck_fct_reservations_room_revenue',
                $$CHECK (room_revenue >= 0)$$
            ),
            (
                'ck_fct_reservations_cancellation_fee',
                $$CHECK (cancellation_fee >= 0)$$
            ),
            (
                'ck_fct_reservations_commission_amount',
                $$CHECK (commission_amount >= 0)$$
            ),
            (
                'ck_fct_reservations_currency_code',
                $$CHECK (currency_code IS NULL OR btrim(currency_code) ~ '^[A-Z]{3}$')$$
            )
        ) AS definitions(constraint_name, constraint_sql)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conrelid = 'mart.fct_reservations'::regclass
              AND conname = item.constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE mart.fct_reservations ADD CONSTRAINT %I %s',
                item.constraint_name,
                item.constraint_sql
            );
        END IF;
    END LOOP;
END
$constraints$;

-- 5. Uwagi implementacyjne:
-- - Bez zgody zespołu nie ustawiamy DEFAULT 'PLN' dla currency_code.
-- - Ograniczenie waluty sprawdza FORMAT 3 liter, nie listę kodów ISO 4217.
-- - cancellation_date_sk: 0=UNKNOWN dla anulowanej bez daty,
--   -1=NOT_APPLICABLE dla pozostałych; wymagane są rekordy w mart.dim_date.
-- - Obecny mart.dim_date.full_date DATE NOT NULL uniemożliwia takie rekordy
--   z NULL; zmianę wymiaru musi zatwierdzić właściciel US-03-03.
-- - Obecnych kolumn FK nie ustawiamy na NOT NULL, dopóki nie zostaną
--   potwierdzone reguły brakujących powiązań i rekordy techniczne wymiarów.
-- - Poprawność wartości FK, reguł cancellation_date_sk i zgodność waluty
--   sprawdzimy podczas testów T01-T12 po zasileniu mart z warstwy core.

COMMIT;
