# Przepływ danych – HotelGroup Analytics

## 1. Cel dokumentu

Celem dokumentu jest opisanie planowanego przepływu danych od systemów źródłowych do warstwy analitycznej i raportowej HotelGroup.

Dokument powstał w ramach zadania **US-03-01 – Zaprojektowanie architektury hurtowni danych**, realizowanego w Sprincie 1.

Opis stanowi uzupełnienie diagramów C4 Context i Container oraz dokumentu `storage-layers.md`.

**Status:** Projekt architektoniczny – do weryfikacji podczas implementacji.

## 2. Źródła danych

W projekcie przyjęto trzy podstawowe źródła danych:

| System | Format | Zakres informacji | Klucze integracyjne |
|---|---|---|---|
| PMS | SQLite | Hotele, pokoje, rezerwacje, pobyty | `hotel_id`, `reservation_id` |
| Channel Manager | JSON | Kanały sprzedaży, prowizje | `reservation_id` |
| System finansowy | CSV | Koszty operacyjne, budżety | `hotel_id`, `month` |

Dane mają charakter syntetyczny i będą przygotowywane na potrzeby projektu.

Zakłada się minimum 24 miesiące danych historycznych oraz 50 000 rezerwacji.

## 3. Pobieranie danych (Extract)

Za pozyskiwanie danych odpowiadają procesy ETL/ELT realizowane z wykorzystaniem Pythona i SQL.

Przewiduje się następujące sposoby pobierania:

- **PMS:** odczyt danych z relacyjnej bazy SQLite.
- **Channel Manager:** odczyt i parsowanie plików JSON.
- **Finanse:** odczyt plików CSV.

Podczas pobierania danych należy zachować identyfikatory źródłowe umożliwiające późniejsze powiązanie rekordów.

Proces powinien rejestrować podstawowe informacje o wykonanym imporcie, takie jak identyfikator uruchomienia, źródło, czas rozpoczęcia oraz liczba odczytanych rekordów.

## 4. Strefa staging (Load)

Dane pozyskane ze źródeł są ładowane do schematu `staging` w PostgreSQL.

Strefa ta przechowuje dane w możliwie oryginalnej postaci, bez transformacji zmieniających ich znaczenie biznesowe.

Główne zadania strefy staging:

- Przechowywanie danych wejściowych.
- Zachowanie kluczy źródłowych.
- Umożliwienie ponownego przetwarzania danych.
- Rejestrowanie informacji o wykonanych importach.
- Udostępnianie danych do walidacji i transformacji.

Wczytanie danych nie oznacza jeszcze uznania ich za poprawne biznesowo.

## 5. Walidacja i transformacja do core

Dane ze staging podlegają walidacji, czyszczeniu i integracji przed udostępnieniem w schemacie `core`.

### 5.1. Walidacja danych

Planowane kontrole obejmują:

- Wykrywanie duplikatów.
- Sprawdzanie wymaganych identyfikatorów.
- Kontrolę poprawności dat.
- Weryfikację wartości liczbowych i kwot.
- Sprawdzanie zgodności identyfikatorów między systemami.
- Kontrolę poprawności kodów walut.

### 5.2. Czyszczenie i ujednolicanie

Przykładowe transformacje:

- Ujednolicanie formatów dat.
- Normalizacja statusów rezerwacji.
- Ujednolicanie kodów i wartości walut.
- Przypisanie kanałów sprzedaży do rezerwacji PMS.
- Powiązanie danych finansowych z hotelem i okresem rozliczeniowym.

W przypadku danych finansowych należy zdefiniować spójne zasady prezentacji walut oraz uzgodnienia wartości przychodów.

### 5.3. Obsługa błędów

Rekordy niespełniające przyjętych reguł jakości powinny zostać zarejestrowane w rejestrze odrzuceń.

Rejestr powinien zawierać co najmniej:

- Nazwę źródła danych.
- Identyfikator rekordu.
- Rodzaj błędu.
- Datę przetwarzania.
- Identyfikator wykonania procesu.

Błędne rekordy nie powinny trafiać do warstwy analitycznej jako poprawne dane.

Szczegółowe reguły walidacji i obsługi błędów zostaną zaimplementowane w zadaniach dotyczących ETL/ELT.

## 6. Przygotowanie danych w strefie mart

Na podstawie oczyszczonych danych `core` przygotowywany jest model wymiarowy w schemacie `mart`.

Model powinien obejmować minimum dwie tabele faktów o różnym ziarnie oraz pięć wymiarów, w tym wymiar daty i hotelu.

Przykładowa planowana struktura:

**Tabele faktów:**
- `fact_reservation` – jeden rekord na rezerwację.
- `fact_room_night` – jeden rekord na pokojonoc powiązaną z rezerwacją.

**Wymiary:**
- `dim_date`
- `dim_hotel`
- `dim_room_type`
- `dim_channel`
- `dim_guest`

Dla wybranego wymiaru, np. `dim_guest`, należy zastosować mechanizm SCD typu 2, umożliwiający przechowywanie historii zmian atrybutów.

Szczegółowa struktura modelu, klucze oraz ziarno faktów zostaną potwierdzone w odrębnym projekcie modelu wymiarowego i diagramie ERD.

Do obliczania wskaźników OCC i RevPAR konieczne jest również zapewnienie danych o dostępnych pokojonocach dla hoteli i okresów.

## 7. Warstwa semantyczna i raportowanie

Dane ze strefy `mart` będą udostępniane narzędziu Power BI.

W Power BI zostanie przygotowany model semantyczny zawierający relacje, miary i definicje wskaźników KPI.

Podstawowe wskaźniki:

| KPI | Definicja |
|---|---|
| OCC | Sprzedane pokojonoce / dostępne pokojonoce |
| ADR | Przychód z pokoi / sprzedane pokojonoce |
| RevPAR | Przychód z pokoi / dostępne pokojonoce |
| Cancellation Rate | Anulowane rezerwacje / wszystkie rezerwacje |

Raporty powinny umożliwiać analizę wyników dla wybranego hotelu i okresu.

Zakłada się przygotowanie dashboardu zarządczego oraz raportu operacyjnego.

Dane osobowe gości nie powinny być udostępniane w warstwie raportowej w postaci umożliwiającej ich bezpośrednią identyfikację.

## 8. Strategia ładowania danych

Przewiduje się dwa etapy zasilania hurtowni.

### 8.1. Ładowanie początkowe

Podczas pierwszego uruchomienia procesu zostanie załadowana pełna historia dostępnych danych.

Proces obejmie wszystkie trzy źródła i przygotuje dane w strefach staging, core oraz mart.

### 8.2. Ładowanie przyrostowe

W kolejnych uruchomieniach planuje się przetwarzanie nowych i zmienionych rekordów zamiast pełnego przeładowywania zbiorów.

Możliwe mechanizmy obejmują:

- Wykorzystanie znacznika ostatniej modyfikacji rekordu, jeżeli jest dostępny.
- Porównywanie identyfikatorów i zawartości rekordów.
- Rejestrowanie ostatniego poprawnie zakończonego ładowania.

Sposób realizacji ładowania przyrostowego zostanie uzgodniony z zespołem ETL/ELT.

Proces powinien uwzględniać również aktualizacje i anulacje istniejących rezerwacji.

## 9. Monitorowanie i kontrola poprawności

Planowana architektura powinna umożliwiać:

- Rejestrowanie rozpoczęcia i zakończenia procesów.
- Zliczanie rekordów wejściowych, przetworzonych i odrzuconych.
- Identyfikację błędów integracji.
- Ponowne uruchomienie procesu po błędzie.
- Wykonywanie testów jakości danych.
- Porównanie przychodów w hurtowni z danymi źródłowymi.

Docelowa implementacja musi zapewniać zgodność sum przychodów ze źródłami z dokładnością do 0,1%.

## 10. Przepływ end-to-end

Docelowy przepływ danych:

1. PMS (SQLite), Channel Manager (JSON) i finanse (CSV) dostarczają dane.
2. Python odczytuje dane i ładuje je do PostgreSQL.
3. Schemat `staging` przechowuje dane wejściowe.
4. Procesy SQL/Python walidują, czyszczą i integrują dane.
5. Schemat `core` przechowuje ujednolicone dane.
6. Procesy transformacyjne przygotowują model wymiarowy w `mart`.
7. Power BI odczytuje dane analityczne i udostępnia model semantyczny.
8. Użytkownicy biznesowi korzystają z dashboardów i raportów.

Procesy ETL/ELT wykonują operacje pomiędzy strefami; same schematy bazy danych nie realizują automatycznie transferu rekordów.

## 11. Powiązanie z wymaganiami

| ID | Zakres | Uwzględnienie w projekcie |
|---|---|---|
| R-01 | Minimum trzy źródła | SQLite, JSON, CSV |
| R-02 | Czyszczenie i walidacja | Kontrole jakości oraz rejestr odrzuceń |
| R-03 | Model wymiarowy | Fakty, wymiary i SCD2 |
| R-04 | Podstawowe KPI | Dane i model semantyczny dla OCC, ADR, RevPAR i anulacji |
| R-08 | Ładowanie przyrostowe | Planowana strategia aktualizacji danych |
| NFR-02 | Zgodność przychodów | Kontrola uzgodnienia ze źródłami |
| NFR-03 | Ochrona danych | Pseudonimizacja lub maskowanie w raportowaniu |
| NFR-05 | Odtwarzalność | Wersjonowane skrypty i dokumentacja uruchomienia |

## 12. Status dokumentu

**Status: Projekt – do weryfikacji zespołowej.**

Dokument opisuje docelowe założenia architektoniczne, a nie potwierdzoną implementację.

Szczegóły techniczne będą doprecyzowane podczas realizacji zadań ETL/ELT, modelowania wymiarowego i przygotowania raportów.
