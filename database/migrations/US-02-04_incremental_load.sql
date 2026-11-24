-- ============================================================================
-- US-02-04: Ładowanie przyrostowe (Incremental Load / Watermarking / UPSERT)
-- ============================================================================

-- 1. Tabela stanu ładowania przyrostowego
CREATE TABLE IF NOT EXISTS core.etl_watermark (
    watermark_id      SERIAL PRIMARY KEY,
    source_system     VARCHAR(50)  NOT NULL,
    table_name        VARCHAR(100) NOT NULL,
    last_watermark_ts TIMESTAMP    NOT NULL DEFAULT '1970-01-01 00:00:00',
    last_run_id       VARCHAR(64),
    rows_extracted    INT          NOT NULL DEFAULT 0,
    rows_upserted     INT          NOT NULL DEFAULT 0,
    status            VARCHAR(30)  NOT NULL DEFAULT 'SUCCESS',
    updated_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_etl_watermark_source_table UNIQUE (source_system, table_name)
);

-- 2. Kolumny techniczne do śledzenia zmian (CDC) w tabelach staging
ALTER TABLE staging.pms_hotels        ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.pms_guests        ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.pms_rooms         ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.pms_reservations  ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.pms_stays         ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.cm_channels       ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
ALTER TABLE staging.fin_budgets_costs ADD COLUMN IF NOT EXISTS _updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);

-- 3. Klucze unikalne na kluczach biznesowych w staging (wymagane dla ON CONFLICT / UPSERT)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_pms_hotels_bk') THEN
        ALTER TABLE staging.pms_hotels ADD CONSTRAINT uq_stg_pms_hotels_bk UNIQUE (hotel_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_pms_guests_bk') THEN
        ALTER TABLE staging.pms_guests ADD CONSTRAINT uq_stg_pms_guests_bk UNIQUE (guest_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_pms_rooms_bk') THEN
        ALTER TABLE staging.pms_rooms ADD CONSTRAINT uq_stg_pms_rooms_bk UNIQUE (room_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_pms_reservations_bk') THEN
        ALTER TABLE staging.pms_reservations ADD CONSTRAINT uq_stg_pms_reservations_bk UNIQUE (reservation_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_pms_stays_bk') THEN
        ALTER TABLE staging.pms_stays ADD CONSTRAINT uq_stg_pms_stays_bk UNIQUE (stay_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_cm_channels_bk') THEN
        ALTER TABLE staging.cm_channels ADD CONSTRAINT uq_stg_cm_channels_bk UNIQUE (reservation_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stg_fin_budgets_costs_bk') THEN
        ALTER TABLE staging.fin_budgets_costs ADD CONSTRAINT uq_stg_fin_budgets_costs_bk UNIQUE (hotel_id, month_id, cost_category);
    END IF;
END $$;

-- 4. Wpisy startowe w rejestrze watermarków
INSERT INTO core.etl_watermark (source_system, table_name, last_watermark_ts)
VALUES
    ('pms', 'pms_hotels',              '1970-01-01 00:00:00'),
    ('pms', 'pms_guests',              '1970-01-01 00:00:00'),
    ('pms', 'pms_rooms',               '1970-01-01 00:00:00'),
    ('pms', 'pms_reservations',        '1970-01-01 00:00:00'),
    ('pms', 'pms_stays',               '1970-01-01 00:00:00'),
    ('channel_manager', 'cm_channels', '1970-01-01 00:00:00'),
    ('financial', 'fin_budgets_costs', '1970-01-01 00:00:00')
ON CONFLICT (source_system, table_name) DO NOTHING;