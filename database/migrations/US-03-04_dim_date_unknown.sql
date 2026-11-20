-- US-03-04: Obsługa technicznych kluczy dat
-- UNKNOWN = 0, NOT_APPLICABLE = -1

BEGIN;

ALTER TABLE mart.dim_date
    ALTER COLUMN full_date DROP NOT NULL;

INSERT INTO mart.dim_date (date_sk, full_date)
VALUES
    (0, NULL),
    (-1, NULL)
ON CONFLICT (date_sk) DO NOTHING;

COMMIT;