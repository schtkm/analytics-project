# ADR-001 – Wybór platformy hurtowni danych HotelGroup

## Metadane

| Pole | Wartość |
|---|---|
| ID | ADR-001 |
| Tytuł | Wybór platformy hurtowni danych |
| Data | 2026-10-30 |
| Status | Proposed – oczekuje na zatwierdzenie |
| Sprint | Sprint 1 |
| Powiązane zadanie | US-03-01 |
| Epika | EPIC-03 – Hurtownia i modelowanie danych |
| Powiązane wymagania | R-01, R-03, NFR-04, NFR-05 |

## 1. Kontekst

Projekt HotelGroup zakłada opracowanie rozwiązania analitycznego integrującego dane fikcyjnej sieci hotelowej obejmującej od 5 do 10 obiektów.

Dane pochodzą z różnych systemów źródłowych i muszą zostać zintegrowane w centralnej hurtowni, umożliwiającej przygotowanie analiz i raportów biznesowych.

Wstępnie zaproponowano trzy źródła danych:

- PMS – relacyjna baza SQLite.
- Channel Manager – pliki JSON.
- System finansowy – pliki CSV.

Zgodnie z wymaganiami prowadzącego rozwiązanie musi obsługiwać minimum 24 miesiące danych historycznych oraz minimum 50 000 rezerwacji.

Hurtownia powinna umożliwiać:

- Integrację danych z wielu źródeł.
- Przechowywanie danych w strefach staging, core i mart.
- Implementację modelu wymiarowego.
- Obsługę transformacji i zapytań SQL.
- Integrację z procesami ETL/ELT i narzędziami BI.
- Odtworzenie środowiska przez prowadzącego w czasie krótszym niż 2 godziny.

Zespół pracuje głównie w systemie Windows. Jedna osoba korzysta z Linuxa, ale posiada również dostęp do środowiska Windows.

Ze względu na edukacyjny charakter projektu preferowane jest rozwiązanie o niskich kosztach, możliwe do uruchomienia lokalnie i niewymagające rozbudowanej infrastruktury.

## 2. Rozważane opcje

### Opcja A – PostgreSQL

PostgreSQL jest otwartoźródłowym systemem zarządzania relacyjnymi bazami danych, dostępnym bez opłat licencyjnych.

**Zalety:**
- Bezpłatne wykorzystanie.
- Obsługa systemów Windows i Linux.
- Możliwość lokalnego uruchomienia.
- Obsługa SQL, relacji, widoków i indeksów.
- Możliwość organizacji hurtowni z wykorzystaniem osobnych schematów.
- Integracja z Pythonem i narzędziami BI.
- Możliwość automatyzacji wdrożenia i odtworzenia środowiska.

**Wady:**
- Konieczność konfiguracji serwera bazy danych.
- Konieczność samodzielnego przygotowania procesów integracyjnych.
- Brak wbudowanego, kompletnego środowiska wizualizacji danych.

### Opcja B – Microsoft SQL Server Express

SQL Server Express jest bezpłatną edycją systemu bazodanowego Microsoft.

**Zalety:**
- Integracja z ekosystemem Microsoft.
- Obsługa relacyjnych modeli danych i języka SQL.
- Możliwość lokalnego uruchomienia.
- Dostępność narzędzi administracyjnych.
- Możliwość połączenia z Power BI.

**Wady:**
- Ograniczenia zasobów i maksymalnego rozmiaru bazy danych.
- Dodatkowe zależności związane z ekosystemem Microsoft.
- Mniejsza elastyczność środowiska w porównaniu z przyjętym wariantem PostgreSQL.
- Ograniczenia edycji Express mogą utrudnić późniejsze rozszerzanie rozwiązania.

### Opcja C – Snowflake

Snowflake jest chmurową platformą analityczną przeznaczoną do przechowywania i przetwarzania danych.

**Zalety:**
- Skalowalność zasobów obliczeniowych i przestrzeni danych.
- Rozwiązanie zarządzane przez dostawcę.
- Obsługa zaawansowanych procesów analitycznych.
- Integracja z narzędziami ETL/ELT oraz BI.

**Wady:**
- Model kosztowy zależny od wykorzystania zasobów.
- Zależność od dostępu do Internetu i usług chmurowych.
- Konieczność zarządzania kontem, uprawnieniami i zasobami.
- Większa złożoność organizacyjna niż potrzebna w projekcie.
- Trudniejsze zapewnienie niezależnego, lokalnego odtworzenia środowiska.

## 3. Porównanie wariantów

| Kryterium | PostgreSQL | SQL Server Express | Snowflake |
|---|---|---|---|
| Bezpłatne wykorzystanie podstawowe | Tak | Tak | Ograniczone warunkami usług |
| Uruchomienie lokalne | Tak | Tak | Nie |
| Windows i Linux | Tak | Zależnie od wersji i środowiska | Dostęp przez usługi chmurowe |
| Obsługa SQL | Tak | Tak | Tak |
| Integracja z Pythonem | Tak | Tak | Tak |
| Integracja z Power BI | Tak | Tak | Tak |
| Podział na staging/core/mart | Tak | Tak | Tak |
| Odtworzenie bez konta chmurowego | Tak | Tak | Nie |
| Dopasowanie do projektu | Wysokie | Wysokie | Umiarkowane |

W ocenie zespołu kluczowe znaczenie mają koszt, prostota wdrożenia, zgodność ze środowiskami użytkowników oraz możliwość odtworzenia projektu przez prowadzącego.

## 4. Proponowana decyzja

Rekomenduje się wybór **PostgreSQL** jako centralnej platformy hurtowni danych HotelGroup.

Przemawiają za tym następujące argumenty:

1. Brak kosztów licencyjnych.
2. Możliwość pracy w środowiskach Windows i Linux.
3. Obsługa relacyjnego modelu wymiarowego.
4. Możliwość logicznego podziału danych na strefy staging, core i mart.
5. Integracja z proponowanymi procesami ETL/ELT realizowanymi w Pythonie i SQL.
6. Możliwość połączenia z Power BI.
7. Możliwość odtworzenia środowiska lokalnie, bez obowiązkowego korzystania z usług chmurowych.

Proponuje się wydzielenie w jednej bazie danych PostgreSQL trzech schematów:

- `staging` – dane pobrane ze źródeł.
- `core` – dane oczyszczone, zwalidowane i zintegrowane.
- `mart` – model wymiarowy przeznaczony do analiz.

Ostateczny sposób organizacji warstw i transformacji zostanie opisany w ADR-002.

Wybór PostgreSQL nie oznacza rezygnacji z SQLite jako źródła danych PMS. SQLite będzie pełnić rolę systemu źródłowego, natomiast PostgreSQL będzie docelową hurtownią danych.

## 5. Konsekwencje decyzji

### 5.1. Pozytywne

- Brak konieczności zakupu licencji na serwer bazy danych.
- Spójne środowisko przechowywania danych.
- Możliwość rozbudowy modelu analitycznego.
- Wykorzystanie popularnych narzędzi SQL i Python.
- Możliwość automatyzacji tworzenia struktury bazy.
- Ułatwienie odtworzenia rozwiązania w środowisku lokalnym.

### 5.2. Negatywne i ograniczenia

- Zespół musi samodzielnie skonfigurować PostgreSQL.
- Należy przygotować skrypty tworzenia schematów i tabel.
- Konieczne jest zarządzanie połączeniami oraz danymi dostępowymi.
- Procesy ETL/ELT i walidacji danych wymagają osobnej implementacji.
- Należy zweryfikować wydajność na docelowym zbiorze danych.

### 5.3. Działania wynikające z decyzji

Po zatwierdzeniu wyboru platformy zespół powinien:

1. Ustalić wspólną wersję PostgreSQL.
2. Przygotować konfigurację środowiska.
3. Utworzyć schematy staging, core i mart.
4. Przygotować skrypty SQL do wersjonowania w Git.
5. Skonfigurować połączenia z procesami ETL/ELT.
6. Zweryfikować połączenie z wybranym narzędziem BI.
7. Opracować i przetestować instrukcję odtworzenia środowiska.

## 6. Zgodność z wymaganiami projektu

| Wymaganie | Sposób uwzględnienia |
|---|---|
| R-01 | PostgreSQL będzie przyjmować dane z minimum trzech źródeł przez ETL/ELT |
| R-03 | Platforma umożliwia implementację tabel faktów, wymiarów i SCD typu 2 |
| NFR-04 | Schematy i obiekty bazy będą definiowane w wersjonowanych skryptach SQL |
| NFR-05 | Lokalna instalacja i skrypty wdrożeniowe umożliwią przygotowanie odtwarzalnego środowiska |

Spełnienie wymagań musi zostać potwierdzone podczas implementacji i testów. Sam wybór technologii nie oznacza jeszcze ich realizacji.

## 7. Status i zatwierdzenie

**Status decyzji: Proposed**

Rekomendacja wyboru PostgreSQL wymaga zatwierdzenia przez zespół projektowy.

Po zatwierdzeniu należy:

- Zmienić status na `Accepted`.
- Zapisać datę akceptacji.
- Odnotować ewentualne uwagi zespołu.
- Uaktualnić dokumentację architektury rozwiązania.

## 8. Źródła

1. Dokument wymagań prowadzącego: „Projekt zaliczeniowy: rozwiązanie analityczne dla branży hotelarskiej – lista wymagań”, rozdział 6.
2. Dokumentacja PostgreSQL: https://www.postgresql.org/docs/
3. Licencja PostgreSQL: https://www.postgresql.org/about/licence/
4. Microsoft SQL Server – edycje i ograniczenia: https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-latest
5. Snowflake – informacje o cenach: https://www.snowflake.com/en/pricing-options/
