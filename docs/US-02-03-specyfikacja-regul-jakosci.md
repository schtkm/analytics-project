# US-02-03 – Specyfikacja biznesowych reguł jakości danych (Data Quality)

## Metadane

| Pole | Wartość |
|---|---|
| Projekt | HotelGroup – rozwiązanie analityczne dla sieci hotelowej |
| Zadanie | US-02-03 – Implementacja zautomatyzowanych testów jakości danych |
| Epika | EPIC-02 – Pozyskiwanie i integracja danych |
| Sprint | Sprint 2 |
| Priorytet MoSCoW | Must |
| Story Points | 8 SP |
| Powiązane wymagania | R-07, NFR-02, US-02-02, US-06-01, US-02-08 |
| Status | Wersja robocza – do weryfikacji z zespołem |

---

## 1. Cel i zakres dokumentu

Dokument definiuje zestaw **10 automatycznych reguł jakości danych (Data Quality)** uruchamianych przy każdym przebiegu potoku ETL/ELT podczas ładowania hurtowni `hotelgroup_dw` (`staging` → `core` → `mart`).

Celem wdrożenia reguł jest:
- Wczesne wykrywanie błędnych, niekompletnych lub niespójnych rekordów przed ich udostępnieniem w warstwie raportowej (`mart`).
- Ochrona kluczowych wskaźników hotelarskich (**OCC**, **ADR**, **RevPAR**, **Cancellation Rate**) przed zniekształceniem (np. obłożeniem przekraczającym 100%).
- Zapewnienie zgodności finansowej między źródłami a hurtownią z tolerancją maksymalnie **0,1%** (`NFR-02`).
- Dostarczenie udokumentowanego kontraktu testowego dla scenariuszy weryfikacyjnych w ramach zadania **US-06-01** oraz pipeline'u CI/CD (**US-02-08**).

---

## 2. Specyfikacja 10 biznesowych reguł jakości danych

Każda reguła jest weryfikowana automatycznie w ramach kroku walidacji potoku danych. Oczekiwanym wynikiem poprawnego przebiegu jest **0 wykrytych naruszeń** dla reguł o krytyczności `CRITICAL`.

| ID | Nazwa reguły | Warstwa / Tabele | Warunek biznesowy (reguła walidacji) | Oczekiwany wynik | Krytyczność i akcja ETL |
|---|---|---|---|---|---|
| **DQ-01** | **Brak pustych kluczy głównych i biznesowych** | `core.*`, `mart.dim_*`, `mart.fct_*` | Wszystkie klucze główne (`_id`, `_sk`) oraz biznesowe (`_bk`, `reservation_id`, `hotel_id`, `room_id`, `guest_id`) są `NOT NULL` oraz nie są pustym ciągiem znaków (`TRIM(kolumna) <> ''`). | `0` rekordów z pustym kluczem | **CRITICAL** – odrzucenie rekordu do tabeli błędów; wstrzymanie ładowania do `mart`. |
| **DQ-02** | **Unikalność ziarna tabel faktów i wymiarów** | `mart.fct_reservations`, `mart.fct_room_night`, `mart.fct_room_inventory` | Brak duplikatów klucza ziarna: 1 wiersz na `reservation_bk` w `fct_reservations`; max. 1 wiersz na parę `(room_sk, stay_date_sk)` w `fct_room_night`; max. 1 wiersz na parę `(room_sk, inventory_date_sk)` w `fct_room_inventory`. | `0` zduplikowanych kluczy ziarna | **CRITICAL** – zatrzymanie propagacji paczki do `mart` i zapis duplikatów do logu. |
| **DQ-03** | **Integralność referencyjna kluczy obcych (FK)** | `mart.fct_*` → `mart.dim_*` | Każdy klucz obcy w tabelach faktów (`hotel_sk`, `guest_sk`, `channel_sk`, `room_sk`, `*_date_sk`) posiada odpowiadający rekord w tabeli wymiaru (w tym rekordy specjalne `0`, `-1`, `-2`), a `hotel_sk` w fakcie jest zgodny z hotelem pokoju w `dim_room`. | `0` osieroconych kluczy obcych | **CRITICAL** – blokada ładowania niespójnych rekordów do `mart` + zapis do logu. |
| **DQ-04** | **Wskaźnik obłożenia hotelu OCC ≤ 100%** | `mart.fct_room_night`, `mart.fct_room_inventory` | Dla każdego hotelu i dnia kalendarzowego liczba sprzedanych fizycznych pokojonocy nie przekracza liczby dostępnych pokojonocy (`sold_room_nights <= available_room_nights`, tj. `OCC <= 100%`). | `0` dni z `OCC > 100%` | **CRITICAL** – wstrzymanie publikacji błędnego zakresu do warstwy raportowej (wykrycie overbookingu lub błędu rozbicia nocy) + alert. |
| **DQ-05** | **Poprawność chronologii i logiki dat pobytu** | `core.reservations`, `mart.fct_reservations`, `mart.fct_room_night` | Data zameldowania jest wcześniejsza niż data wymeldowania (`check_in_date < check_out_date`), data utworzenia rezerwacji nie jest późniejsza niż przyjazd (`booking_date <= check_in_date`), a dzień wyjazdu nie jest liczony jako noc pobytu (`stay_date < check_out_date`). | `0` rekordów z błędną sekwencją dat | **CRITICAL** – odrzucenie błędnych rekordów do logu z podaniem przyczyny. |
| **DQ-06** | **Spójność statusów rezerwacji z realizacją pobytów** | `mart.fct_reservations`, `mart.fct_room_night` | Rezerwacje ze statusem `Anulowana` lub `No-Show` nie posiadają żadnych rekordów zrealizowanych pokojonocy w `fct_room_night`. Rezerwacje anulowane posiadają poprawny klucz daty anulacji (`cancellation_date_sk <> -1`). | `0` pokojonocy dla anulacji i no-show | **CRITICAL** – blokada błędnych pokojonocy przed wejściem do `mart` + wpis w logu. |
| **DQ-07** | **Standaryzacja słowników i waluty PLN** | `core.*`, `mart.*` | Wszystkie kwoty finansowe w hurtowni mają przypisany kod waluty `PLN`. Wartości atrybutów słownikowych (`status`, `room_type`, `guest_segment`, `cost_category`) należą wyłącznie do zamkniętych słowników projektu (`US-03-03`, `US-03-07`). | `0` rekordów spoza słownika lub z obcą walutą | **CRITICAL** – odrzucenie rekordu z nieznanym kodem lub obcą walutą do logu błędów. |
| **DQ-08** | **Nieujemne kwoty finansowe i zakres prowizji** | `core.reservations`, `mart.fct_reservations`, `mart.fct_room_night` | Przychód pokojowy oraz opłata za anulację są nieujemne (`room_revenue >= 0`, `cancellation_fee >= 0`), a prowizja z Channel Managera spełnia warunek `0 <= commission_amount <= room_revenue`. | `0` rekordów z ujemną kwotą lub błędną prowizją | **CRITICAL** – zapis naruszenia finansowego do logu i zatrzymanie rekordu przed `mart`. |
| **DQ-09** | **Uzgodnienie przychodów źródło ↔ mart (NFR-02)** | `staging.*` vs `mart.fct_reservations` / `fct_room_night` | Względna różnica między sumą przychodów w `staging` (pomniejszoną o przychód z rekordów zapisanych w tabeli odrzuceń) a sumą przychodów w `mart` nie przekracza **0,1%**: `ABS(Rev_staging_valid - Rev_mart) / Rev_staging_valid <= 0.001`. | Odchylenie `<= 0,1%` | **CRITICAL** – zatrzymanie zakończenia potoku ETL i wygenerowanie błędu rozliczenia finansowego. |
| **DQ-10** | **Kompletność wymiaru czasu (`dim_date`)** | `mart.dim_date`, `mart.fct_*` | Tabela `mart.dim_date` zawiera ciągły kalendarz bez luk dla całego zakresu dat historycznych i przyszłych występujących w tabelach faktów (minimum od `2023-01-01` do maksymalnej daty `check_out_date` w bazie). | `0` brakujących dat kalendarza | **CRITICAL** (gdy brakuje daty używanej w fakcie) / **WARNING** (gdy kończy się zapas dat przyszłych). |

---

## 3. Zasady obsługi naruszeń i wstrzymywania propagacji

1. **Integracja z mechanizmem odrzuceń (`US-02-02`):** Każde naruszenie reguły `DQ-01` – `DQ-10` jest rejestrowane w tabeli logu błędów/odrzuceń wraz z identyfikatorem reguły (`rule_id`), nazwą tabeli, identyfikatorem rekordu (`record_id`), opisem błędu oraz znacznikiem czasu uruchomienia potoku (`run_timestamp`).
2. **Wstrzymanie propagacji (`Fail-Fast` dla warstwy `mart`):** Jeśli dowolny test o krytyczności `CRITICAL` zwróci liczbę naruszeń większą niż `0`, krok ładowania do schematu `mart` zostaje przerwany (lub wycofany transakcyjnie), a proces kończy się statusem błędu (`exit code != 0`), uniemożliwiając zasilenie raportów Power BI niespójnymi danymi.
3. **Brak duplikacji z testami technicznymi `US-02-02`:** Reguły zdefiniowane w `US-02-03` koncentrują się na logice biznesowej, integralności modelu wymiarowego (`core` → `mart`) oraz spójności wskaźników operacyjnych i finansowych, uzupełniając walidację formatów wejściowych z `US-02-02`.

---

## 4. Punkty do potwierdzenia z zespołem przed finalizacją SQL

| Obszar | Pytanie / uzgodnienie | Osoba odpowiedzialna | Status |
|---|---|---|---|
| Mianownik OCC (`DQ-04`) | Czy w `mart.fct_room_inventory` pokoje *Out of Order* (`is_out_of_order = TRUE`) mają `available_room_nights = 0` i są wyłączane z mianownika OCC? | Kacper Kapłon (`US-03-05B`), Jakub Małkowski (`US-04-01`) | Do potwierdzenia |
| Tabela logu błędów (`DQ-01`–`DQ-10`) | Potwierdzenie docelowej nazwy i struktury kolumn tabeli odrzuceń utworzonej w `US-02-02` na potrzeby zapisu naruszeń reguł DQ. | Grzegorz Zając (`US-02-02`) | Do potwierdzenia |
| Nazewnictwo tabel `mart` | Weryfikacja nazw tabel faktów w `mart` po zmergowaniu `US-03-05A` (`fct_room_night`) i `US-03-05B` (`fct_room_inventory`). | Kacper Kapłon, Kamil Suchta | Do potwierdzenia |