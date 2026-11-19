-- HotelGroup | US-03-07 | Utrwalenie zasad i roboczego katalogu kosztow.
-- Uruchom w bazie hotelgroup_dw po 20_us_03_07_cost_categories.sql.
-- Skrypt jest powtarzalny, nie usuwa tabel ani danych i nie nadpisuje istniejacych kategorii.
-- UWAGA: kody lokalne i kategorie robocze maja status DRAFT.
-- Nie potwierdzono waluty zrodlowej strumienia finansowego; NIE tworzymy polityk per hotel.

BEGIN;

-- 0. BEZPIECZNIK - najpierw weryfikacja bazy i struktury.
DO $$
BEGIN
  IF current_database() <> 'hotelgroup_dw' THEN
    RAISE EXCEPTION 'PRZERWANO: skrypt mozna uruchomic wylacznie w hotelgroup_dw.';
  END IF;
  IF to_regclass('core.cost_category') IS NULL
     OR to_regclass('core.hotel_cost_category_mapping') IS NULL
     OR to_regclass('core.finance_currency_policy') IS NULL
     OR to_regclass('mart.dim_cost_category') IS NULL THEN
    RAISE EXCEPTION 'PRZERWANO: brak wymaganych tabel. Najpierw uruchom skrypt 20.';
  END IF;
END $$;

-- 1. Zapis globalnych zasad finansowych (odrebnych od walut zrodlowych hoteli).
CREATE TABLE IF NOT EXISTS core.finance_reporting_settings (
  config_key VARCHAR(30) PRIMARY KEY
    CHECK (config_key = 'HOTELGROUP'),
  reporting_currency CHAR(3) NOT NULL
    CHECK (reporting_currency = 'PLN'),
  amount_scale SMALLINT NOT NULL DEFAULT 2
    CHECK (amount_scale = 2),
  shared_cost_dictionary BOOLEAN NOT NULL DEFAULT TRUE
    CHECK (shared_cost_dictionary = TRUE),
  explicit_local_mapping BOOLEAN NOT NULL DEFAULT TRUE
    CHECK (explicit_local_mapping = TRUE),
  separate_budget_actual BOOLEAN NOT NULL DEFAULT TRUE
    CHECK (separate_budget_actual = TRUE),
  unresolved_mapping_action VARCHAR(20) NOT NULL DEFAULT 'REVIEW'
    CHECK (unresolved_mapping_action = 'REVIEW'),
  currency_source_note TEXT NOT NULL
);

INSERT INTO core.finance_reporting_settings
  (config_key, reporting_currency, amount_scale, shared_cost_dictionary,
   explicit_local_mapping, separate_budget_actual,
   unresolved_mapping_action, currency_source_note)
VALUES
  ('HOTELGROUP', 'PLN', 2, TRUE, TRUE, TRUE, 'REVIEW',
   'Raportowanie w PLN. Waluta zrodlowa wymaga potwierdzenia; dla innej niz PLN potrzebne sa kurs, data i reguly przeliczenia.')
ON CONFLICT (config_key) DO NOTHING;

DO $$
BEGIN
 IF NOT EXISTS (
    SELECT 1 FROM core.finance_reporting_settings
    WHERE config_key = 'HOTELGROUP'
      AND reporting_currency = 'PLN'
      AND amount_scale = 2
      AND shared_cost_dictionary
      AND explicit_local_mapping
      AND separate_budget_actual
      AND unresolved_mapping_action = 'REVIEW'
  ) THEN
    RAISE EXCEPTION 'Konflikt z istniejaca polityka finansowa. Nie nadpisano ustawien.';
 END IF;
END $$;

-- 2. Robocze kategorie standardowe. Status DRAFT nie udaje zatwierdzenia
--    ich szczegolowego zakresu. GOP pozostaje TO_REVIEW.
INSERT INTO core.cost_category
 (category_code, category_name, category_group, business_definition,
  gop_treatment, approval_status, is_active)
VALUES
 ('PERSONNEL', 'Koszty osobowe', 'PERSONNEL',
  'Wynagrodzenia i powiazane koszty personelu wedlug wspolnej definicji.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('UTILITIES', 'Media i energia', 'OPERATIONS',
  'Energia elektryczna, cieplo, woda i inne media wedlug wspolnej definicji.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('HOUSEKEEPING', 'Utrzymanie czystosci', 'ROOMS',
  'Materialy, pralnia oraz uslugi utrzymania czystosci.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('MAINTENANCE', 'Naprawy i konserwacja', 'OPERATIONS',
  'Serwis, konserwacja oraz biezace naprawy.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('FNB_COGS', 'Koszt produktow gastronomicznych', 'FNB',
  'Zuzycie produktow i surowcow gastronomicznych.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('SALES_MARKETING', 'Marketing i promocja', 'SALES',
  'Kampanie i uzgodnione koszty marketingowe.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('CHANNEL_FEES', 'Prowizje i oplaty kanalow', 'DISTRIBUTION',
  'Prowizje OTA i pozostale koszty kanalow dystrybucji.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('ADMIN', 'Koszty administracyjne', 'ADMIN',
  'Koszty ogolnoadministracyjne wedlug wspolnej definicji.', 'TO_REVIEW', 'DRAFT', TRUE),
 ('OTHER_REVIEWED', 'Pozostale rozpoznane koszty', 'OTHER',
  'Kategoria uzywana tylko po jawnym rozpatrzeniu; nie domyslna dla brakow mapowania.', 'TO_REVIEW', 'DRAFT', TRUE)
ON CONFLICT (category_code) DO NOTHING;

-- 3. Robocze przyklady mapowan dla hoteli H001-H003 ze zbioru syntetycznego PMS.
--    Nie twierdzimy, ze te lokalne kody rzeczywiscie wystepuja w finansowym CSV.
--    Status DRAFT: nie sa uwzgledniane przez walidacje jako mapowania zatwierdzone.
INSERT INTO core.hotel_cost_category_mapping
 (source_system, hotel_id, local_cost_code, cost_category_id,
  valid_from, valid_to, decision_status, approved_by, approval_note)
SELECT 'FINANCE_CSV', example.hotel_id, example.local_code, c.cost_category_id,
       DATE '2024-01-01', NULL::date, 'DRAFT', NULL::varchar,
       'Robocze mapowanie syntetyczne. Zweryfikowac z plikami finansowymi.'
FROM (VALUES
 ('H001', 'PENSJE', 'PERSONNEL'),
 ('H002', 'WYNAGRODZENIA', 'PERSONNEL'),
 ('H001', 'PRAD', 'UTILITIES'),
 ('H002', 'ENERGIA', 'UTILITIES'),
 ('H003', 'PLACE', 'PERSONNEL')
) AS example(hotel_id, local_code, target_code)
JOIN core.cost_category c ON c.category_code = example.target_code
ON CONFLICT (source_system, hotel_id, local_cost_code, valid_from) DO NOTHING;

-- Nie zapisujemy zatwierdzonych polityk waluty zrodlowej: brak danych
-- o rzeczywistej walucie poszczegolnych strumieni z plikow finansowych.
-- Nie publikujemy tez wpisow DRAFT do mart.dim_cost_category.

DO $$
DECLARE cat_count INTEGER;
DECLARE draft_mapping_count INTEGER;
BEGIN
 SELECT COUNT(*) INTO cat_count
 FROM core.cost_category
 WHERE category_code IN ('PERSONNEL', 'UTILITIES', 'HOUSEKEEPING',
   'MAINTENANCE', 'FNB_COGS', 'SALES_MARKETING', 'CHANNEL_FEES',
   'ADMIN', 'OTHER_REVIEWED');
 IF cat_count <> 9 THEN
   RAISE EXCEPTION 'Niekompletny katalog: znaleziono % z 9 kategorii.', cat_count;
 END IF;
 SELECT COUNT(*) INTO draft_mapping_count
 FROM core.hotel_cost_category_mapping
 WHERE source_system = 'FINANCE_CSV'
   AND hotel_id IN ('H001', 'H002', 'H003')
   AND approval_note LIKE 'Robocze mapowanie syntetyczne.%';
 RAISE NOTICE 'US-03-07: katalog 9 kategorii zapisany; przykladowe mapowania robocze: %.', draft_mapping_count;
 RAISE NOTICE 'Polityka sieci: PLN. Mapowania DRAFT nie sa publikowane do mart.';
END $$;

COMMIT;
