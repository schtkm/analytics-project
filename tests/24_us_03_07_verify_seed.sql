-- HotelGroup | US-03-07 | Weryfikacja utrwalenia zasad i slownika (tylko SELECT).
-- Uruchom PO 23_us_03_07_seed_dictionary.sql. Bez zmian danych.

-- A. Kontrola, czy pracujemy na bazie HotelGroup.
SELECT current_database() AS baza;

-- B. Kontrola uzgodnionych zasad finansowych.
SELECT config_key, reporting_currency, amount_scale,
       shared_cost_dictionary, explicit_local_mapping,
       separate_budget_actual, unresolved_mapping_action,
       currency_source_note
FROM core.finance_reporting_settings;

-- C. Oczekiwane dziewiec wspolnych kategorii (na razie DRAFT).
SELECT category_code, category_name, approval_status, gop_treatment
FROM core.cost_category
WHERE category_code IN ('PERSONNEL','UTILITIES','HOUSEKEEPING',
 'MAINTENANCE','FNB_COGS','SALES_MARKETING','CHANNEL_FEES',
 'ADMIN','OTHER_REVIEWED')
ORDER BY category_code;

-- D. Robocze przyklady mapowan; nie sa zatwierdzone.
SELECT m.hotel_id, m.local_cost_code, c.category_code AS standard_code,
       m.decision_status, m.approval_note
FROM core.hotel_cost_category_mapping m
JOIN core.cost_category c ON c.cost_category_id = m.cost_category_id
WHERE m.source_system = 'FINANCE_CSV'
  AND m.hotel_id IN ('H001','H002','H003')
  AND m.approval_note LIKE 'Robocze mapowanie syntetyczne.%'
ORDER BY m.hotel_id, m.local_cost_code;

-- E. Powinno byc 0: niezatwierdzone przyklady nie moga byc aktywnymi mapowaniami.
SELECT COUNT(*) AS nieprawidlowo_zatwierdzone_mapowania
FROM core.hotel_cost_category_mapping m
WHERE m.source_system = 'FINANCE_CSV'
  AND m.approval_note LIKE 'Robocze mapowanie syntetyczne.%'
  AND m.decision_status <> 'DRAFT';

-- F. Liczebnosci katalogu i przykladow (oczekiwane: 9 i 5 na swiezej bazie).
SELECT
  (SELECT COUNT(*) FROM core.cost_category
   WHERE category_code IN ('PERSONNEL','UTILITIES','HOUSEKEEPING',
    'MAINTENANCE','FNB_COGS','SALES_MARKETING','CHANNEL_FEES',
    'ADMIN','OTHER_REVIEWED')) AS liczba_kategorii,
  (SELECT COUNT(*) FROM core.hotel_cost_category_mapping
   WHERE source_system='FINANCE_CSV'
     AND approval_note LIKE 'Robocze mapowanie syntetyczne.%') AS liczba_przykladowych_mapowan;
