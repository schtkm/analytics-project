# ADR-002 – Podejście ELT i organizacja warstw hurtowni danych

## Metadane

| Pole | Wartość |
|---|---|
| ID | ADR-002 |
| Tytuł | Podejście ELT i organizacja warstw składowania |
| Data | 2026-11-02 |
| Status | Proposed – do zatwierdzenia |
| Sprint | Sprint 1 |
| Powiązane zadanie | US-03-01 |
| Epika | EPIC-03 – Hurtownia i modelowanie danych |
| Powiązane wymagania | R-01, R-02, R-03, R-08, NFR-05 |

## 1. Kontekst

Projekt HotelGroup wymaga integracji danych z różnych systemów źródłowych:

- PMS – baza SQLite.
- Channel Manager – pliki JSON.
- System finansowy – pliki CSV.

Dane źródłowe różnią się strukturą, formatami oraz zakresem informacji.

Konieczne jest zaprojektowanie procesu integracji, który umożliwi pobieranie, walidację, czyszczenie i przekształcanie danych oraz przygotowanie ich do analiz biznesowych.

W ADR-001 zaproponowano PostgreSQL jako platformę centralnej hurtowni danych.

Należy określić sposób przetwarzania danych oraz logiczną organizację warstw składowania.

## 2. Rozważane warianty przetwarzania

### Opcja A – ETL (Extract, Transform, Load)

Dane są pobierane ze źródeł, przekształcane poza hurtownią, a następnie ładowane w postaci docelowej.

**Zalety:**
- Możliwość kontroli danych przed ich załadowaniem.
- Ograniczenie ilości danych wymagających przetwarzania w hurtowni.
- Możliwość realizacji transformacji w Pythonie.

**Wady:**
- Większa odpowiedzialność zewnętrznego procesu za transformacje.
- Trudniejsze odtworzenie oryginalnych danych w przypadku niezachowania kopii źródłowej.
- Potencjalne powielanie logiki transformacji poza bazą.

### Opcja B – ELT (Extract, Load, Transform)

Dane są pobierane i ładowane do warstwy wejściowej hurtowni, a następnie transformowane.

**Zalety:**
- Zachowanie danych źródłowych w staging.
- Możliwość ponownego wykonania transformacji.
- Wykorzystanie SQL do przetwarzania danych.
- Łatwiejsze rozdzielenie etapów pobierania, walidacji i modelowania.
- Możliwość kontroli danych na kolejnych etapach przepływu.

**Wady:**
- Konieczność przechowywania dodatkowej kopii danych.
- Większe wymagania dotyczące zarządzania strefą staging.
- Konieczność odpowiedniego zabezpieczenia danych źródłowych.

## 3. Rozważane warianty organizacji składowania

### Opcja A – Jedna baza PostgreSQL z trzema schematami

W jednej bazie danych zostają utworzone schematy:

- `staging`
- `core`
- `mart`

**Zalety:**
- Prostsze zarządzanie środowiskiem.
- Brak konieczności utrzymywania wielu baz.
- Możliwość rozdzielenia danych według etapu przetwarzania.
- Łatwiejsze zarządzanie skryptami SQL i wdrożeniem.

**Wady:**
- Współdzielenie zasobów jednej instancji bazy.
- Konieczność prawidłowego skonfigurowania uprawnień.
- Mniejsza izolacja niż w przypadku osobnych baz danych.

### Opcja B – Osobne bazy danych dla każdej strefy

Strefy staging, core i mart zostają umieszczone w oddzielnych bazach danych.

**Zalety:**
- Większa izolacja danych i uprawnień.
- Możliwość niezależnego zarządzania środowiskami.
- Oddzielenie zasobów i konfiguracji przy zastosowaniu osobnych instancji.

**Wady:**
- Bardziej złożone wdrożenie.
- Konieczność zarządzania połączeniami między bazami.
- Większy nakład administracyjny.
- Nadmierna złożoność w stosunku do skali projektu.

## 4. Proponowana decyzja

Rekomenduje się wykorzystanie podejścia **ELT** z trzema logicznymi strefami w jednej bazie PostgreSQL.

Docelowy przepływ danych:

1. Pobranie danych z SQLite, JSON i CSV za pomocą Pythona.
2. Załadowanie danych do schematu `staging`.
3. Walidacja, czyszczenie i integracja danych z wykorzystaniem SQL oraz, w razie potrzeby, Pythona.
4. Zapis danych ujednoliconych w schemacie `core`.
5. Przygotowanie tabel faktów i wymiarów w schemacie `mart`.
6. Udostępnienie danych analitycznych narzędziu Power BI.

Podejście ma charakter ELT, ponieważ główne transformacje biznesowe są wykonywane po załadowaniu danych do hurtowni.

Podstawowe kontrole techniczne mogą odbywać się już podczas ekstrakcji i ładowania.

## 5. Przeznaczenie poszczególnych stref

### Staging

Przechowywanie danych pozyskanych ze źródeł w możliwie oryginalnej postaci.

### Core

Przechowywanie danych oczyszczonych, zwalidowanych i zintegrowanych.

### Mart

Przechowywanie modelu wymiarowego wykorzystywanego przez warstwę semantyczną i raportową.

Szczegółowe założenia opisano w dokumencie `storage-layers.md`.

## 6. Konsekwencje decyzji

### 6.1. Pozytywne

- Rozdzielenie odpowiedzialności poszczególnych warstw.
- Możliwość ponownego przetworzenia danych ze staging.
- Prostsze śledzenie błędów transformacji.
- Wykorzystanie PostgreSQL i SQL do przygotowania danych analitycznych.
- Możliwość stopniowej rozbudowy hurtowni.
- Ułatwienie odtwarzania środowiska.

### 6.2. Negatywne

- Większe wykorzystanie przestrzeni dyskowej.
- Konieczność utrzymywania spójności danych między warstwami.
- Potrzeba implementacji monitorowania procesów.
- Konieczność odpowiedniego zarządzania dostępem do danych źródłowych.

### 6.3. Działania wynikające z decyzji

Po zatwierdzeniu architektury należy:

1. Utworzyć schematy PostgreSQL w ramach US-03-02.
2. Przygotować procesy ekstrakcji i ładowania danych.
3. Zaimplementować walidację i rejestr odrzuconych rekordów.
4. Przygotować transformacje do core i mart.
5. Ustalić strategię ładowania przyrostowego.
6. Przygotować testy jakości danych.
7. Zweryfikować poprawność przepływu od źródeł do BI.

## 7. Zgodność z wymaganiami

| ID | Sposób uwzględnienia |
|---|---|
| R-01 | Integracja minimum trzech źródeł danych |
| R-02 | Walidacja, czyszczenie i rejestr błędów |
| R-03 | Model wymiarowy w strefie mart |
| R-08 | Możliwość realizacji ładowania przyrostowego |
| NFR-05 | Jedna baza danych i wersjonowane skrypty wdrożeniowe |

Decyzja architektoniczna określa sposób planowanej realizacji wymagań. Ich spełnienie musi zostać zweryfikowane podczas implementacji.
