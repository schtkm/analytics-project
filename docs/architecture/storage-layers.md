
# Projekt warstw hurtowni danych – HotelGroup

## 1. Cel dokumentu

Celem dokumentu jest określenie logicznej organizacji hurtowni danych HotelGroup z podziałem na trzy strefy: staging, core i mart.

Podział ten ma zapewnić uporządkowane przetwarzanie danych pochodzących z różnych systemów źródłowych oraz przygotowanie spójnych informacji na potrzeby analiz i raportowania biznesowego.

Dokument opracowano w ramach zadania **US-03-01 – Zaprojektowanie architektury hurtowni danych**, realizowanego w Sprincie 1.

## 2. Założenia architektoniczne

Zgodnie z przyjętymi założeniami hurtownia danych zostanie oparta na PostgreSQL.

Przewiduje się wykorzystanie trzech logicznie oddzielonych schematów bazy danych:

- `staging` – przechowywanie danych pobranych ze źródeł.
- `core` – przechowywanie danych oczyszczonych, zwalidowanych i zintegrowanych.
- `mart` – udostępnianie danych analitycznych w modelu wymiarowym.

Dane będą pozyskiwane z trzech podstawowych źródeł:

| System źródłowy | Format | Zakres danych |
|---|---|---|
| PMS | SQLite | Rezerwacje, pobyty, pokoje, hotele |
| Channel Manager | JSON | Kanały sprzedaży, prowizje |
| System finansowy | CSV | Koszty operacyjne, budżety |

Do integracji danych planuje się wykorzystać Python i SQL, natomiast do przygotowania raportów Power BI.

## 3. Strefa staging

### 3.1. Przeznaczenie

Strefa staging stanowi pierwszą warstwę hurtowni danych. Jej zadaniem jest przyjmowanie danych pobranych z systemów źródłowych.

Dane powinny zachowywać wartości źródłowe, aby możliwe było ich porównanie z oryginalnymi zbiorami.

### 3.2. Zakres odpowiedzialności

- Przyjmowanie danych pochodzących z SQLite, JSON i CSV.
- Przechowywanie danych przed właściwymi transformacjami biznesowymi.
- Zachowanie identyfikatorów źródłowych.
- Rejestrowanie informacji o imporcie, np. identyfikatora i czasu wykonania ładowania.
- Udostępnianie danych do dalszego przetwarzania.

W tej strefie nie powinny być wykonywane transformacje zmieniające znaczenie biznesowe danych.

## 4. Strefa core

### 4.1. Przeznaczenie

Strefa core przechowuje dane oczyszczone, zwalidowane i ujednolicone, pochodzące z różnych systemów źródłowych.

Jej zadaniem jest zapewnienie spójności informacji wykorzystywanych w dalszych analizach.

### 4.2. Zakres odpowiedzialności

- Identyfikowanie i obsługa duplikatów.
- Sprawdzanie kompletności wymaganych danych.
- Walidacja poprawności dat i wartości liczbowych.
- Ujednolicanie formatów dat i walut.
- Powiązanie rezerwacji z kanałami sprzedaży.
- Powiązanie danych finansowych z odpowiednimi hotelami i okresami.
- Zapewnienie spójności identyfikatorów między źródłami.

### 4.3. Obsługa błędnych rekordów

Rekordy niespełniające reguł jakości danych powinny zostać zarejestrowane w mechanizmie obsługi błędów.

Rejestr powinien umożliwiać identyfikację:

- Źródła danych.
- Rekordu, którego dotyczy problem.
- Rodzaju wykrytego błędu.
- Daty i identyfikatora procesu przetwarzania.

Niepoprawne rekordy nie powinny być bez śladu usuwane z procesu przetwarzania.

Szczegółowy mechanizm walidacji i rejestrowania błędów zostanie określony podczas implementacji ETL/ELT.

## 5. Strefa mart

### 5.1. Przeznaczenie

Strefa mart stanowi warstwę analityczną hurtowni danych.

Przechowywane w niej informacje będą przygotowane do wykorzystania w modelu semantycznym i raportach Power BI.

### 5.2. Model wymiarowy

Zgodnie z wymaganiami projektu model analityczny powinien obejmować:

- Minimum dwie tabele faktów o różnym ziarnie.
- Minimum pięć wymiarów.
- Wymiar daty.
- Wymiar hotelu z hierarchią hotel – miasto – region.
- Minimum jeden wymiar wolnozmienny SCD typu 2.
- Jawnie określone ziarno każdej tabeli faktów.

Wstępnie przewiduje się wykorzystanie:

**Przykładowych tabel faktów:**
- Fakt rezerwacji – jeden rekord na rezerwację.
- Fakt pokojonocy – jeden rekord na pokojonoc powiązaną z rezerwacją.

**Przykładowych wymiarów:**
- Data.
- Hotel.
- Typ pokoju.
- Kanał sprzedaży.
- Gość.

Dla prawidłowego obliczania obłożenia i RevPAR konieczne będzie również zapewnienie danych o dostępnych pokojonocach.

Szczegółowa struktura tabel faktów i wymiarów, ich klucze oraz zasady implementacji SCD typu 2 zostaną uzgodnione z osobą odpowiedzialną za model wymiarowy.

### 5.3. Wykorzystanie danych

Strefa mart będzie udostępniać dane potrzebne do obliczania wskaźników, takich jak:

- Occupancy (OCC).
- Average Daily Rate (ADR).
- Revenue per Available Room (RevPAR).
- Cancellation Rate.
- Przychody według hoteli i okresów.
- Porównanie wyników finansowych z budżetem.

Definicje i obliczenia KPI zostaną udokumentowane w słowniku biznesowym projektu.

## 6. Przepływ danych między warstwami

Przewiduje się następujący kierunek przepływu danych:

1. Dane z PMS (SQLite), Channel Managera (JSON) i systemu finansowego (CSV) są pobierane przez proces ETL/ELT.
2. Dane źródłowe trafiają do strefy staging.
3. Dane są walidowane, oczyszczane i integrowane w strefie core.
4. Na podstawie danych core przygotowywane są fakty i wymiary w strefie mart.
5. Warstwa semantyczna Power BI korzysta z danych analitycznych strefy mart.
6. Użytkownicy biznesowi analizują informacje za pomocą raportów i dashboardów.

Docelowo należy zapewnić możliwość ładowania przyrostowego, aby uniknąć konieczności każdorazowego przetwarzania całej historii danych.

## 7. Podział odpowiedzialności

| Obszar | Odpowiedzialność |
|---|---|
| Projekt logiczny warstw | US-03-01 |
| Diagramy architektury C4 | US-03-01 |
| Decyzje architektoniczne ADR | US-03-01 |
| Utworzenie schematów PostgreSQL | US-03-02 |
| Skrypty DDL i fizyczne struktury | US-03-02 |
| Pobieranie i ładowanie danych | Zadania integracyjne ETL/ELT |
| Szczegółowy model faktów i wymiarów | Zadanie dotyczące modelu wymiarowego |
| Raporty i miary KPI | Zadania dotyczące BI |

Dokument definiuje logiczne założenia architektury, a nie gotową implementację bazy danych.

## 8. Powiązanie z wymaganiami

| ID | Wymaganie | Sposób uwzględnienia |
|---|---|---|
| R-01 | Minimum 3 źródła danych w różnych formatach | SQLite, JSON, CSV |
| R-02 | Czyszczenie i walidacja danych | Walidacja w procesie zasilania core i rejestrowanie błędów |
| R-03 | Model wymiarowy hurtowni | Fakty, wymiary i SCD2 w strefie mart |
| R-04 | Podstawowe KPI hotelarskie | Dane w mart przygotowane do obliczania KPI |
| R-08 | Ładowanie przyrostowe | Uwzględnione w projektowanym przepływie |
| NFR-03 | Ochrona danych osobowych | Planowane ograniczenie danych osobowych udostępnianych warstwie BI |
| NFR-05 | Odtwarzalność środowiska | PostgreSQL i wersjonowane skrypty wdrożeniowe |

Wskazane elementy stanowią założenia projektowe. Ich faktyczna realizacja będzie weryfikowana podczas implementacji i testów.

## 9. Status dokumentu

**Status: Projekt logiczny – do przeglądu z zespołem.**

Przed rozpoczęciem implementacji należy potwierdzić zgodność podziału warstw z zadaniem US-03-02 oraz planowanymi procesami ETL/ELT i modelem wymiarowym.

Dokument stanowi podstawę przygotowania diagramu C4 Container oraz decyzji architektonicznej ADR-002.
