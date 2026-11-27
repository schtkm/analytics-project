-- HotelGroup | US-03-08 | Zasilenie wymiaru kategorii kosztowych
-- Publikujemy wyłącznie zatwierdzone, aktywne kategorie.
-- Klasyfikacja GOP pozostaje TO_REVIEW do US-04-04.

BEGIN;

INSERT INTO mart.dim_cost_category (
    cost_category_bk,
    category_name,
    category_group,
    business_definition,
    gop_treatment,
    is_active
)
SELECT
    c.category_code,
    c.category_name,
    c.category_group,
    c.business_definition,
    c.gop_treatment,
    c.is_active
FROM core.cost_category c
WHERE c.approval_status = 'APPROVED'
  AND c.is_active = TRUE
ON CONFLICT (cost_category_bk)
DO UPDATE SET
    category_name = EXCLUDED.category_name,
    category_group = EXCLUDED.category_group,
    business_definition = EXCLUDED.business_definition,
    gop_treatment = EXCLUDED.gop_treatment,
    is_active = EXCLUDED.is_active;

COMMIT;