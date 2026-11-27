# US-03-08 – Model kosztów rzeczywistych i budżetów

## Cel
Utworzenie miesięcznego modelu finansowego HotelGroup,
umożliwiającego analizę kosztów rzeczywistych i budżetowych.

## Źródło danych
`core.clean_fin_budgets_costs`

Zakres danych:
- 8 hoteli
- 30 miesięcy (2024-01 – 2026-06)
- 4 źródłowe kategorie kosztowe
- 960 rekordów źródłowych
- waluta PLN

## Model analityczny
Tabela: `mart.fct_finance_monthly`

Ziarno:
hotel × miesiąc × kategoria kosztowa × scenariusz.

Scenariusze:
- ACTUAL – koszty rzeczywiste
- BUDGET – koszty budżetowe

Powiązania:
- `mart.dim_hotel`
- `mart.dim_date`
- `mart.dim_cost_category`

## Mapowanie kategorii
- MAINTENANCE → MAINTENANCE
- MARKETING → SALES_MARKETING
- PERSONNEL → PERSONNEL
- UTILITIES → UTILITIES

Zatwierdzono 32 mapowania (8 hoteli × 4 kategorie)
decyzją projektową przedstawiciela zespołu z 2026-11-27.
Nie jest to akceptacja rzeczywistego kontrolera finansowego.

Klasyfikacja kosztów do GOP pozostaje `TO_REVIEW`
i zostanie rozstrzygnięta w US-04-04.

## Kontrole ETL
- Walidacja waluty PLN.
- Wymagane zatwierdzone mapowania kategorii.
- Kontrola istnienia wymiarów hotelu i miesiąca.
- Unikalność ziarna faktu.
- Idempotentne zasilanie przez UPSERT.

## Wyniki testów
- Rekordy ACTUAL: 960
- Rekordy BUDGET: 960
- Razem: 1 920
- Suma ACTUAL: 72 719 416,61 PLN
- Suma BUDGET: 72 540 000,00 PLN
- Różnice względem core: 0,00 PLN
- Duplikaty: 0
- Niepoprawne kwoty: 0
- Niepoprawne waluty: 0
- Ponowne uruchomienie ETL: PASS

## Ograniczenia
- Dane są syntetyczne.
- Obsługiwana jest waluta PLN.
- Brak zatwierdzonej klasyfikacji kosztów do GOP.
- Model nie uwzględnia ujemnych korekt kosztów.

## Powiązane historyjki
- US-03-07 – słownik kategorii kosztowych.
- US-04-04 – GOP i marża GOP.
- US-05-02 – porównania budżetowe w Power BI.