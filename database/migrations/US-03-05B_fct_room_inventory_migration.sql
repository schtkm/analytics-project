-- US-03-05B | FactRoomInventory — utworzenie tabeli faktów mart.fct_room_inventory
-- Ziarno: jeden rekord na pokój × data kalendarzowa (room_sk, inventory_date_sk).
-- Uruchamiać w bazie hotelgroup_dw przed US-03-05B_load_fct_room_inventory.sql.

BEGIN;

DO $preflight$
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Oczekiwano bazy hotelgroup_dw, otrzymano %.', current_database();
    END IF;

    IF to_regclass('mart.dim_date') IS NULL
       OR to_regclass('mart.dim_hotel') IS NULL
       OR to_regclass('mart.dim_room') IS NULL
       OR to_regclass('mart.dim_room_type') IS NULL THEN
        RAISE EXCEPTION 'Brak wymaganych tabel wymiarów w schemacie mart (dim_date, dim_hotel, dim_room, dim_room_type).';
    END IF;

    IF to_regclass('mart.fct_room_inventory') IS NOT NULL THEN
        RAISE EXCEPTION 'Tabela mart.fct_room_inventory już istnieje. Migracja została wstrzymana.';
    END IF;
END
$preflight$;

CREATE TABLE mart.fct_room_inventory (
    room_inventory_sk        SERIAL PRIMARY KEY,
    inventory_date_sk        INTEGER  NOT NULL,
    hotel_sk                 INTEGER  NOT NULL,
    room_sk                  INTEGER  NOT NULL,
    room_type_sk             INTEGER  NOT NULL,
    total_room_nights        SMALLINT NOT NULL DEFAULT 1,
    is_out_of_order          BOOLEAN  NOT NULL DEFAULT FALSE,
    out_of_order_room_nights SMALLINT NOT NULL DEFAULT 0,
    available_room_nights    SMALLINT NOT NULL DEFAULT 1,

    CONSTRAINT uq_fct_room_inventory_grain
        UNIQUE (room_sk, inventory_date_sk),

    CONSTRAINT fk_fct_room_inventory_date
        FOREIGN KEY (inventory_date_sk) REFERENCES mart.dim_date (date_sk),
    CONSTRAINT fk_fct_room_inventory_hotel
        FOREIGN KEY (hotel_sk) REFERENCES mart.dim_hotel (hotel_sk),
    CONSTRAINT fk_fct_room_inventory_room
        FOREIGN KEY (room_sk) REFERENCES mart.dim_room (room_sk),
    CONSTRAINT fk_fct_room_inventory_room_type
        FOREIGN KEY (room_type_sk) REFERENCES mart.dim_room_type (room_type_sk),

    CONSTRAINT ck_fct_room_inventory_total
        CHECK (total_room_nights = 1),
    CONSTRAINT ck_fct_room_inventory_ooo_consistency
        CHECK (
            (is_out_of_order = TRUE  AND out_of_order_room_nights = 1 AND available_room_nights = 0)
            OR
            (is_out_of_order = FALSE AND out_of_order_room_nights = 0 AND available_room_nights = 1)
        )
);

CREATE INDEX idx_fct_room_inventory_date_sk
    ON mart.fct_room_inventory (inventory_date_sk);

CREATE INDEX idx_fct_room_inventory_hotel_date
    ON mart.fct_room_inventory (hotel_sk, inventory_date_sk);

CREATE INDEX idx_fct_room_inventory_room_type_date
    ON mart.fct_room_inventory (room_type_sk, inventory_date_sk);

COMMENT ON TABLE mart.fct_room_inventory IS
    'US-03-05B: Dzienna dostępność pokoi (ziarno: room_sk × inventory_date_sk). Pokoje Out of Order mają available_room_nights = 0 i są wyłączane z mianownika OCC.';

COMMIT;