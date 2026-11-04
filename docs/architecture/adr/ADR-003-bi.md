# ADR-003 – Warstwa analityczna i raportowa Power BI

| Pole | Wartość |
|---|---|
| Data opracowania | 2026-11-04 |
| Status | Proposed – zapis do przeglądu zespołu |
| Zadanie | US-07-02 |
| Epika | EPIC-07 – Dokumentacja i wdrożenie |
| Powiązania | EPIC-04, EPIC-05, R-03, ADR-001, ADR-002 |

## Kontekst

HotelGroup potrzebuje wspólnych definicji wskaźników oraz raportów wykorzystujących model wymiarowy. Użytkownik potwierdził zestaw Python + SQL, PostgreSQL i Power BI. ADR-001 opisuje wybór bazy, a ADR-002 organizację ELT i warstw. Ten rekord dokumentuje odpowiedzialność warstwy BI, bez ponownego rozstrzygania tych decyzji.

## Rozważane opcje

Poniższe porównanie porządkuje uzasadnienie wyboru; nie jest protokołem wcześniejszego głosowania zespołu.

| Opcja | Korzyści w projekcie | Konsekwencje |
|---|---|---|
| Power BI z modelem semantycznym opartym na mart | Zgodność ze wskazanym zestawem technologii; wspólne miary dla raportów | Wymaga utrzymania modelu, relacji, miar i sposobu udostępniania |
| Raporty SQL i arkusze kalkulacyjne | Bezpośredni dostęp do wyników zapytań | Więcej pracy nad spójnością miar oraz interaktywnymi raportami |
| Osobna aplikacja raportowa w Pythonie | Kontrola nad interfejsem i logiką aplikacji | Dodatkowy zakres implementacji, testowania i utrzymania interfejsu |

## Decyzja

Dokumentujemy wskazany wybór **Power BI** jako narzędzia do tworzenia modelu semantycznego, raportów i dashboardów HotelGroup.

Proponowany podział odpowiedzialności:

- Python i SQL odpowiadają za integrację, czyszczenie i transformacje opisane w ADR-002.
- PostgreSQL w warstwie `mart` udostępnia fakty i wspólne wymiary.
- Model semantyczny Power BI definiuje relacje analityczne i wspólne miary KPI. Raporty korzystają z tych definicji.
- Reguły jakości i integracji danych źródłowych pozostają w procesach hurtowni. Definicje KPI wymagają uzgodnienia biznesowego w EPIC-04.
- Raporty docelowe korzystają z `mart`. Dostęp do `staging` i `core` służący diagnostyce nie zastępuje docelowego modelu raportowego.

Ten ADR nie rozstrzyga trybu Import/DirectQuery, harmonogramu odświeżania, licencji, publikacji w usłudze ani konfiguracji RLS. Te szczegóły wymagają weryfikacji środowiska i odpowiednich wymagań w EPIC-05.

## Konsekwencje

**Korzyści:** jeden wskazany obszar definicji miar; rozdzielenie integracji od prezentacji; możliwość powiązania raportu z tabelami mart i wymaganiami.

**Koszty i ograniczenia:** zmiany kluczy, ziarna lub kolumn mart wymagają przeglądu modelu BI; zespół musi utrzymywać spójne relacje i miary; sposób udostępniania wymaga osobnego sprawdzenia warunków środowiska. Sam wybór narzędzia nie potwierdza realizacji raportów ani poprawności KPI.

## Działania i weryfikacja

1. Osoby realizujące EPIC-03 i EPIC-05 uzgadniają kontrakt tabel mart i ich ziarno.
2. EPIC-04 dokumentuje definicje miar, w tym liczniki, mianowniki i obsługę brakujących danych.
3. EPIC-05 ustala tryb połączenia i sposób uruchomienia raportów.
4. Weryfikacja implementacji obejmuje zgodność przykładowych wyników BI z uzgodnionymi obliczeniami SQL i prawidłowe filtrowanie przez wspólne wymiary. Są to planowane kontrole, nie wyniki wykonanych testów.

## Zatwierdzenie i historia

Wybór Power BI potwierdzono w przekazanym opisie technologii. Formalny przegląd treści tego rekordu i proponowanego podziału odpowiedzialności pozostaje otwarty. Po przeglądzie należy zapisać status, datę i odnośnik do decyzji zespołu lub PR. Zmiany merytoryczne podlegają zasadom rejestru ADR.

| Data | Zmiana |
|---|---|
| 2026-11-04 | Utworzenie rekordu na podstawie wskazanego zestawu technologii i zakresu projektu |

## Dokumenty powiązane

- [ADR-001](ADR-001-platform.md)
- [ADR-002](ADR-002-etl-storage.md)
- [Rejestr ADR](README.md)

