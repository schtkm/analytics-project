-- US-02-02. Apply transactionally after US-02-01. No source rows are removed.

CREATE SCHEMA IF NOT EXISTS core;

SET LOCAL DateStyle = 'ISO, YMD';

SELECT "hotel_id", "hotel_name", "city", "region" FROM staging.pms_hotels LIMIT 0;

SELECT "guest_id", "first_name", "last_name", "email", "phone" FROM staging.pms_guests LIMIT 0;

SELECT "room_id", "hotel_id", "room_number", "room_type" FROM staging.pms_rooms LIMIT 0;

SELECT "reservation_id", "hotel_id", "guest_id", "room_id", "guest_segment", "booking_date", "check_in_date", "check_out_date", "status", "room_revenue", "cancellation_fee", "updated_at" FROM staging.pms_reservations LIMIT 0;

SELECT "stay_id", "reservation_id", "guest_id", "room_id", "actual_check_in", "actual_check_out" FROM staging.pms_stays LIMIT 0;

SELECT "reservation_id", "channel_code", "commission_rate", "commission_amount" FROM staging.cm_channels LIMIT 0;

SELECT "hotel_id", "month_id", "cost_category", "budget_amount", "actual_cost" FROM staging.fin_budgets_costs LIMIT 0;

ALTER TABLE staging.pms_reservations ALTER COLUMN booking_date TYPE TEXT USING booking_date::text;

ALTER TABLE staging.pms_reservations ALTER COLUMN check_in_date TYPE TEXT USING check_in_date::text;

ALTER TABLE staging.pms_reservations ALTER COLUMN check_out_date TYPE TEXT USING check_out_date::text;

ALTER TABLE staging.pms_reservations ALTER COLUMN room_revenue TYPE TEXT USING room_revenue::text;

ALTER TABLE staging.pms_reservations ALTER COLUMN cancellation_fee TYPE TEXT USING cancellation_fee::text;

ALTER TABLE staging.pms_reservations ALTER COLUMN updated_at TYPE TEXT USING updated_at::text;

ALTER TABLE staging.pms_stays ALTER COLUMN actual_check_in TYPE TEXT USING actual_check_in::text;

ALTER TABLE staging.pms_stays ALTER COLUMN actual_check_out TYPE TEXT USING actual_check_out::text;

ALTER TABLE staging.cm_channels ALTER COLUMN commission_rate TYPE TEXT USING commission_rate::text;

ALTER TABLE staging.cm_channels ALTER COLUMN commission_amount TYPE TEXT USING commission_amount::text;

ALTER TABLE staging.fin_budgets_costs ALTER COLUMN month_id TYPE TEXT USING month_id::text;

ALTER TABLE staging.fin_budgets_costs ALTER COLUMN budget_amount TYPE TEXT USING budget_amount::text;

ALTER TABLE staging.fin_budgets_costs ALTER COLUMN actual_cost TYPE TEXT USING actual_cost::text;


CREATE TABLE IF NOT EXISTS core.etl_runs (
 run_id UUID PRIMARY KEY,
 started_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 finished_at TIMESTAMPTZ,
 status TEXT NOT NULL CHECK (status IN ('running','completed','completed_with_rejections','blocked','failed')),
 config JSONB NOT NULL,
 report JSONB,
 error_code TEXT
);
CREATE TABLE IF NOT EXISTS core.etl_rejected_records (
 rejection_id BIGSERIAL PRIMARY KEY,
 run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
 source_table TEXT NOT NULL,
 source_row BIGINT NOT NULL,
 outcome TEXT NOT NULL CHECK (outcome IN ('rejected','duplicate')),
 business_key JSONB NOT NULL,
 row_hash TEXT NOT NULL,
 raw_record JSONB NOT NULL,
 reasons JSONB NOT NULL,
 rejected_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(run_id, source_table, source_row)
);
CREATE INDEX IF NOT EXISTS ix_etl_rejected_run ON core.etl_rejected_records(run_id,source_table);
REVOKE ALL ON core.etl_rejected_records FROM PUBLIC;
REVOKE ALL ON core.etl_runs FROM PUBLIC;


CREATE TABLE IF NOT EXISTS core.clean_pms_hotels (
    hotel_id TEXT NOT NULL,
    hotel_name TEXT NOT NULL,
    city TEXT,
    region TEXT,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (hotel_id)
);

CREATE TABLE IF NOT EXISTS core.clean_pms_guests (
    guest_id TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (guest_id)
);

CREATE TABLE IF NOT EXISTS core.clean_pms_rooms (
    room_id TEXT NOT NULL,
    hotel_id TEXT NOT NULL,
    room_number TEXT NOT NULL,
    room_type TEXT NOT NULL,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (room_id),
    FOREIGN KEY (hotel_id) REFERENCES core.clean_pms_hotels(hotel_id)
);

CREATE TABLE IF NOT EXISTS core.clean_pms_reservations (
    reservation_id TEXT NOT NULL,
    hotel_id TEXT NOT NULL,
    guest_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    guest_segment TEXT NOT NULL,
    booking_date DATE NOT NULL,
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    status TEXT NOT NULL,
    room_revenue NUMERIC(12,2) NOT NULL CHECK (room_revenue >= 0),
    cancellation_fee NUMERIC(12,2) NOT NULL CHECK (cancellation_fee >= 0),
    updated_at TIMESTAMPTZ NOT NULL,
    currency VARCHAR(3) NOT NULL,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (reservation_id),
    FOREIGN KEY (hotel_id) REFERENCES core.clean_pms_hotels(hotel_id),
    FOREIGN KEY (guest_id) REFERENCES core.clean_pms_guests(guest_id),
    FOREIGN KEY (room_id) REFERENCES core.clean_pms_rooms(room_id)
);

CREATE TABLE IF NOT EXISTS core.clean_pms_stays (
    stay_id TEXT NOT NULL,
    reservation_id TEXT NOT NULL,
    guest_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    actual_check_in DATE NOT NULL,
    actual_check_out DATE,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (stay_id),
    FOREIGN KEY (reservation_id) REFERENCES core.clean_pms_reservations(reservation_id),
    FOREIGN KEY (guest_id) REFERENCES core.clean_pms_guests(guest_id),
    FOREIGN KEY (room_id) REFERENCES core.clean_pms_rooms(room_id)
);

CREATE TABLE IF NOT EXISTS core.clean_cm_channels (
    reservation_id TEXT NOT NULL,
    channel_code TEXT NOT NULL,
    commission_rate NUMERIC(5,4) NOT NULL CHECK (commission_rate BETWEEN 0 AND 1),
    commission_amount NUMERIC(12,2) NOT NULL CHECK (commission_amount >= 0),
    currency VARCHAR(3) NOT NULL,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (reservation_id),
    FOREIGN KEY (reservation_id) REFERENCES core.clean_pms_reservations(reservation_id)
);

CREATE TABLE IF NOT EXISTS core.clean_fin_budgets_costs (
    hotel_id TEXT NOT NULL,
    month_id DATE NOT NULL,
    cost_category TEXT NOT NULL,
    budget_amount NUMERIC(12,2) NOT NULL CHECK (budget_amount >= 0),
    actual_cost NUMERIC(12,2) NOT NULL CHECK (actual_cost >= 0),
    currency VARCHAR(3) NOT NULL,
    _etl_run_id UUID NOT NULL REFERENCES core.etl_runs(run_id),
    PRIMARY KEY (hotel_id, month_id, cost_category),
    FOREIGN KEY (hotel_id) REFERENCES core.clean_pms_hotels(hotel_id)
);
