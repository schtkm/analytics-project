# Weryfikacja zgodności architektury z wymaganiami – HotelGroup

## 1. Cel dokumentu

Celem dokumentu jest weryfikacja zgodności zaprojektowanej architektury rozwiązania analitycznego HotelGroup z wymaganiami prowadzącego.

Weryfikację przygotowano w ramach Sprintu 1, podczas realizacji zadania **US-03-01 – Zaprojektowanie architektury hurtowni danych**.

Dokument obejmuje zgodność logicznego projektu architektury. Nie stanowi potwierdzenia ukończenia implementacji.

**Status:** Weryfikacja wstępna – do przeglądu zespołowego.

## 2. Dokumentacja podlegająca weryfikacji

W ramach zadania US-03-01 przygotowano:

| Dokument | Przeznaczenie |
|---|---|
| `data-sources.md` | Rejestr systemów źródłowych i formatów danych |
| `storage-layers.md` | Projekt logiczny stref staging, core i mart |
| `data-flow.md` | Opis przepływu danych od źródeł do BI |
| `c4-context.puml` | Diagram C4 Context |
| `c4-container.puml` | Diagram C4 Container |
| `ADR-001-platform.md` | Decyzja dotycząca platformy hurtowni |
| `ADR-002-etl-storage.md` | Decyzja dotycząca ELT i organizacji składowania |

Diagramy C4 są również przechowywane w formacie SVG.

## 3. Weryfikacja wymagań architektonicznych

| Wymaganie | Wynik weryfikacji | Status |
|---|---|---|
| Minimum 3 systemy źródłowe w różnych formatach | Zaprojektowano PMS (SQLite), Channel Manager (JSON), finanse (CSV) | Uwzględniono |
| Integracja ETL/ELT | Zaprojektowano procesy Python + SQL oraz przepływ danych | Uwzględniono |
| Czyszczenie, walidacja i rejestr odrzuceń | Opisano walidację i obsługę błędnych rekordów | Uwzględniono |
| Warstwy staging/core/mart | Zaprojektowano trzy schematy w PostgreSQL | Uwzględniono |
| Model wymiarowy | Zaplanowano minimum 2 fakty o różnym ziarnie i 5 wymiarów | Wymaga ERD |
| SCD typu 2 | Zaplanowano historię zmian wymiaru gościa | Zaplanowano – wymaga ERD |
| Diagramy C4 Context i Container | Przygotowano oba diagramy | Przygotowano |
| Diagram ERD hurtowni | Wymagany odrębny diagram modelu danych | Do weryfikacji z zespołem |
| Diagram data lineage | Przygotowano opis przepływu; wymagany diagram śledzenia danych | Do uzupełnienia |
| Minimum 4 ADR w projekcie | Przygotowano ADR-001 i ADR-002 | 2 z 4 |
| Warstwa semantyczna i BI | Zaprojektowano wykorzystanie Power BI | Uwzględniono |
| Uruchamialność środowiska | Zaproponowano lokalną architekturę PostgreSQL + Python | Wymaga testu |

## 4. Weryfikacja wymagań funkcjonalnych

| ID | Wymaganie | Uwzględnienie w architekturze | Status |
|---|---|---|---|
| R-01 | Zasilenie z minimum 3 źródeł | SQLite, JSON, CSV oraz procesy integracyjne | Zaprojektowano |
| R-02 | Czyszczenie i walidacja danych | Transformacje oraz rejestr odrzuceń | Zaprojektowano |
| R-03 | Model wymiarowy | Strefa mart, fakty, wymiary, SCD2 | Częściowo – wymaga ERD |
| R-04 | OCC, ADR, RevPAR, Cancellation Rate | Zaplanowano warstwę semantyczną Power BI | Wymaga implementacji |
| R-05 | Dashboard zarządczy | Zaplanowano raportowanie wyników sieci | Wymaga implementacji |
| R-06 | Raport operacyjny | Zaplanowano raportowanie dla dyrektora hotelu | Wymaga implementacji |
| R-07 | Minimum 10 testów jakości danych | Przewidziano mechanizmy walidacji | Wymaga implementacji |
| R-08 | Ładowanie przyrostowe | Opisano proponowaną strategię aktualizacji | Wymaga implementacji |

Pozostałe wymagania funkcjonalne będą uwzględniane w kolejnych etapach projektu zgodnie z Product Backlogiem.

## 5. Weryfikacja wymagań niefunkcjonalnych

| ID | Wymaganie | Uwzględnienie | Status |
|---|---|---|---|
| NFR-01 | Odświeżenie dashboardu poniżej 5 sekund | PostgreSQL i model analityczny pozwalają planować optymalizację | Wymaga testów |
| NFR-02 | Uzgodnienie przychodów z dokładnością do 0,1% | Zaplanowano kontrolę zgodności danych | Wymaga testów |
| NFR-03 | Ochrona danych osobowych | Przewidziano ograniczenie danych osobowych w BI | Wymaga implementacji |
| NFR-04 | Wersjonowanie kodu i modeli | Przyjęto repozytorium Git | Częściowo |
| NFR-05 | Odtworzenie środowiska w czasie poniżej 2 godzin | Wybrano technologie umożliwiające lokalne wdrożenie | Wymaga instrukcji i testu |
| NFR-07 | Dodanie hotelu bez zmian w kodzie | Architektura przewiduje wspólne identyfikatory hoteli | Wymaga weryfikacji |
| NFR-08 | Słownik danych i KPI | Zaplanowano dokumentowanie modelu i wskaźników | Wymaga opracowania |

## 6. Zidentyfikowane zależności

| Obszar | Zależność | Dalsze działanie |
|---|---|---|
| Struktury hurtowni | US-03-02 | Przekazanie projektu stref do implementacji |
| Model wymiarowy | Zadanie dotyczące ERD i modelowania | Potwierdzenie faktów, wymiarów, SCD2 i ziarna |
| Integracja danych | Zadania ETL/ELT | Implementacja pobierania, walidacji i transformacji |
| Raportowanie | Zadania BI | Opracowanie modelu semantycznego i raportów |
| Data lineage | Dokumentacja architektury | Przygotowanie diagramu lub wskazanie odpowiedzialnego |
| Dodatkowe ADR | Cały projekt | Przydzielenie autorów dwóch pozostałych decyzji |
| Odtwarzalność | NFR-05 | Przygotowanie instrukcji i test uruchomienia |

## 7. Ryzyka i kwestie otwarte

### 7.1. Spójność modelu danych

Szczegółowa struktura modelu wymiarowego nie została jeszcze potwierdzona na podstawie gotowego diagramu ERD.

Należy uzgodnić ziarno faktów, wymiary oraz sposób obsługi SCD typu 2.

### 7.2. Dostępność danych do KPI

Do poprawnego wyliczania OCC i RevPAR konieczne jest zapewnienie informacji o dostępnych pokojonocach.

Należy również rozdzielić dane o rezerwacjach od danych o rzeczywistych pobytach, anulacjach i no-show.

### 7.3. Odtwarzalność środowiska

Możliwość odtworzenia środowiska w czasie krótszym niż 2 godziny nie została jeszcze potwierdzona testem.

Należy sprawdzić instalację, konfigurację, ładowanie danych i dostępność raportów.

### 7.4. Kompletność dokumentacji

Cały projekt wymaga diagramu ERD, diagramu data lineage oraz minimum czterech ADR.

Obecnie w ramach US-03-01 przygotowano dwa ADR. Pozostałe elementy wymagają potwierdzenia odpowiedzialności i ukończenia.

### 7.5. Rozszerzenie źródeł

Trzy podstawowe źródła spełniają wymaganie dotyczące różnorodności formatów, ale nie obejmują wszystkich obszarów biznesowych HotelGroup.

Analizy F&B, SPA i lojalności gości mogą wymagać dodatkowych danych POS i CRM.

## 8. Wniosek z weryfikacji

Zaprojektowana architektura HotelGroup uwzględnia główne warstwy rozwiązania wymagane przez prowadzącego:

- Systemy źródłowe.
- Procesy integracyjne ETL/ELT.
- Hurtownię danych PostgreSQL.
- Strefy staging, core i mart.
- Model wymiarowy.
- Warstwę semantyczną i raportową Power BI.

Przygotowano diagramy C4 Context i Container oraz dwa proponowane rekordy decyzji architektonicznych.

Nie potwierdzono jeszcze pełnej zgodności implementacyjnej z wymaganiami R-03 i NFR-05. Konieczne są dalsze prace nad modelem danych, uruchomieniem środowiska oraz weryfikacją jego odtwarzalności.
