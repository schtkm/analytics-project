-- HotelGroup | US-04-04 | Klasyfikacja kosztow GOP
-- Decyzja projektowa: 2026-11-27
-- Wszystkie 4 kategorie finansowe wchodza do GOP.
-- Zakres: dane syntetyczne HotelGroup.
-- Nie jest to akceptacja rzeczywistego kontrolera.

BEGIN;

DO $$
BEGIN
    IF (
        SELECT COUNT(*)
        FROM core.cost_category
        WHERE category_code IN (
            'MAINTENANCE',
            'PERSONNEL',
            'SALES_MARKETING',
            'UTILITIES'
        )
          AND approval_status = 'APPROVED'
          AND is_active = TRUE
    ) <> 4 THEN
        RAISE EXCEPTION
            'Brak czterech zatwierdzonych kategorii kosztowych.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM mart.dim_cost_category
        WHERE cost_category_bk IN (
            'MAINTENANCE',
            'PERSONNEL',
            'SALES_MARKETING',
            'UTILITIES'
        )
          AND is_active = TRUE
    ) <> 4 THEN
        RAISE EXCEPTION
            'Brak czterech aktywnych kategorii w mart.';
    END IF;
END $$;

UPDATE core.cost_category
SET gop_treatment = 'INCLUDED'
WHERE category_code IN (
    'MAINTENANCE',
    'PERSONNEL',
    'SALES_MARKETING',
    'UTILITIES'
)
  AND approval_status = 'APPROVED'
  AND is_active = TRUE;

UPDATE mart.dim_cost_category
SET gop_treatment = 'INCLUDED'
WHERE cost_category_bk IN (
    'MAINTENANCE',
    'PERSONNEL',
    'SALES_MARKETING',
    'UTILITIES'
)
  AND is_active = TRUE;

COMMIT;