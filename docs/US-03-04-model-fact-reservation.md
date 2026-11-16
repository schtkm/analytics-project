# US-03-04 – Model faktów rezerwacji i anulacji

## 1. Cel modelu

Celem jest zaprojektowanie tabeli faktów `FactReservation`, umożliwiającej analizowanie rezerwacji i anulacji według hotelu, kanału rezerwacji i okresu.

Model powinien zapewniać jednoznaczne liczenie rezerwacji, bez wielokrotnego uwzględniania tego samego identyfikatora.

## 2. Ziarno tabeli FactReservation

**Ziarno:** jeden rekord tabeli `FactReservation` reprezentuje jedną unikalną rezerwację identyfikowaną przez `reservation_id`, w jej ostatnim znanym stanie.

Założenia:

- Zmiana statusu rezerwacji nie powoduje utworzenia kolejnego rekordu.
- Rezerwacje anulowane i typu no-show pozostają w tabeli faktów.
- Jeden identyfikator rezerwacji może wystąpić w `FactReservation` tylko raz.
- Szczegółowe rozliczenie pokojonocy, jeśli będzie wymagane, zostanie zamodelowane oddzielnie.
- Tabela przechowuje aktualny stan rezerwacji, a nie pełną historię zmian statusów.

## 3. Źródła danych

- `staging.pms_reservations` – identyfikator rezerwacji, hotel, pokój, gość, daty, statusy i kwoty.
- `staging.cm_channels` – kanał sprzedaży i informacje o prowizjach.

Powiązanie źródeł następuje za pomocą `reservation_id`.

## 4. Analiza danych źródłowych

### 4.1. PMS – rezerwacje

Tabela `staging.pms_reservations` zawiera dane potrzebne do identyfikacji rezerwacji, określenia jej statusu oraz analizy wartości i terminów pobytu.

| Atrybut źródłowy | Znaczenie |
|---|---|
| `reservation_id` | Unikalny identyfikator rezerwacji |
| `hotel_id` | Identyfikator hotelu |
| `guest_id` | Identyfikator gościa |
| `room_id` | Identyfikator pokoju |
| `booking_date` | Data dokonania rezerwacji |
| `check_in_date` | Planowana data zameldowania |
| `check_out_date` | Planowana data wymeldowania |
| `status` | Aktualny status rezerwacji |
| `room_revenue` | Przychód przypisany do rezerwacji |
| `cancellation_fee` | Opłata za anulowanie |
| `updated_at` | Data ostatniej aktualizacji rekordu |

### 4.2. Channel Manager

Tabela `staging.cm_channels` zawiera informacje o kanałach pozyskania rezerwacji i naliczonych prowizjach.

| Atrybut źródłowy | Znaczenie |
|---|---|
| `reservation_id` | Identyfikator rezerwacji, łączący Channel Manager z PMS |
| `channel_code` | Kod kanału sprzedaży (np. DIRECT, BOOKING, EXPEDIA) |
| `commission_rate` | Stawka prowizji kanału |
| `commission_amount` | Kwota prowizji przypisana do rezerwacji |
| `_inserted_at` | Techniczny znacznik czasu załadowania rekordu do staging |

**Wnioski projektowe:**

- Połączenie PMS i Channel Managera odbywa się przez `reservation_id`.
- `channel_code` będzie podstawą powiązania rezerwacji z wymiarem `DimChannel`.
- `commission_amount` może stanowić miarę finansową tabeli `FactReservation`.
- `commission_rate` pozostaje atrybutem źródłowym; sposób jego wykorzystania w modelu wymaga uzgodnienia.
- Zweryfikowano 140 875 rekordów Channel Managera, bez duplikatów identyfikatorów i bez brakujących powiązań z PMS.

## 5. Projekt struktury tabeli FactReservation

### 5.1. Założenia modelu

`FactReservation` stanowi tabelę faktów przechowującą ostatni znany stan każdej rezerwacji.

- Ziarno: jeden rekord na `reservation_id`.
- Źródło podstawowe: `staging.pms_reservations`.
- Źródło uzupełniające: `staging.cm_channels`.
- Wymiary analityczne: `DimDate`, `DimHotel`, `DimChannel`.
- Rezerwacje anulowane oraz no-show pozostają w tabeli.
- Historia zmian statusów nie jest przechowywana w tej tabeli.

### 5.2. Proponowane atrybuty

| Atrybut logiczny | Znaczenie | Źródło |
|---|---|---|
| `reservation_id` | Unikalny identyfikator rezerwacji | PMS |
| `booking_date_key` | Powiązanie daty rezerwacji z DimDate | PMS / DimDate |
| `check_in_date_key` | Powiązanie planowanego zameldowania z DimDate | PMS / DimDate |
| `check_out_date_key` | Powiązanie planowanego wymeldowania z DimDate | PMS / DimDate |
| `hotel_key` | Powiązanie z DimHotel | PMS / DimHotel |
| `channel_key` | Powiązanie z DimChannel | Channel Manager / DimChannel |
| `reservation_status` | Ujednolicony status rezerwacji | PMS |
| `room_revenue` | Kwota przychodu z rezerwacji | PMS |
| `cancellation_fee` | Opłata za anulowanie | PMS |
| `commission_amount` | Kwota prowizji kanału sprzedaży | Channel Manager |
| `reservation_count` | Miara liczby rezerwacji, przyjmująca wartość 1 | Wyliczana |
| `cancellation_count` | Miara anulacji: 1 dla anulowanych, 0 dla pozostałych | Wyliczana |

### 5.3. Atrybuty wymagające dodatkowych ustaleń

**Data anulowania:** w dotychczasowej strukturze PMS nie ma osobnego pola daty anulowania. Nie należy zastępować go automatycznie przez `updated_at`. Konieczne jest uzgodnienie sposobu pozyskania daty lub udokumentowanie jej niedostępności.

**Waluta:** kolumny kwotowe PMS i Channel Managera nie zawierają kodu waluty. Przed implementacją należy ustalić walutę danych syntetycznych i sposób dokumentowania tego założenia.

**Klucze wymiarów:** nazwy i typy kluczy należy dostosować do zatwierdzonych struktur `DimDate`, `DimHotel` i `DimChannel`.

**Statusy:** przed implementacją należy uzgodnić mapowanie statusów źródłowych na wspólne kategorie analityczne.

### 5.4. Zasady zapobiegania podwójnemu liczeniu

- `reservation_id` musi być unikalny w tabeli faktów.
- Jedna rezerwacja jest liczona dokładnie raz, niezależnie od statusu.
- `reservation_count = 1` dla każdego rekordu.
- `cancellation_count = 1` wyłącznie dla rezerwacji sklasyfikowanych jako anulowane.
- Status no-show nie oznacza automatycznie anulowania.
- Łączenie danych PMS i Channel Managera nie może zwiększać liczby rezerwacji.

## 6. Modelowanie statusów rezerwacji

### 6.1. Mapowanie statusów źródłowych

W tabeli `FactReservation` przechowywany będzie ujednolicony status rezerwacji, umożliwiający spójne raportowanie danych.

| Status PMS | Status analityczny | Znaczenie |
|---|---|---|
| `Oczekująca` | `ACTIVE` | Rezerwacja oczekująca na realizację |
| `W trakcie` | `IN_PROGRESS` | Pobyt w trakcie realizacji |
| `Zakończona` | `COMPLETED` | Pobyt zakończony |
| `Anulowana` | `CANCELLED` | Rezerwacja anulowana |
| `No-Show` | `NO_SHOW` | Gość nie pojawił się w hotelu |

### 6.2. Zasady liczenia rezerwacji i anulacji

Dla każdej rezerwacji definiuje się następujące miary:

| Miara | Reguła |
|---|---|
| `reservation_count` | Zawsze 1 |
| `cancellation_count` | 1 dla `CANCELLED`, w pozostałych przypadkach 0 |

Przykładowo rezerwacja o statusie `NO_SHOW` zwiększa liczbę rezerwacji, ale nie zwiększa liczby anulacji.

### 6.3. Założenia

- W tabeli faktów przechowywany jest ostatni znany status rezerwacji.
- Statusy źródłowe są mapowane na jednoznaczne wartości analityczne.
- `CANCELLED` i `NO_SHOW` stanowią odrębne kategorie.
- Nieznany status źródłowy wymaga obsługi przez reguły jakości danych w procesie ETL.
- Zmiana statusu nie powoduje dodania nowego rekordu do `FactReservation`.
- Powyższe mapowanie jest propozycją do uzgodnienia z zespołem przed implementacją.

## 7. Modelowanie dat rezerwacji i pobytu

### 7.1. Daty wykorzystywane w FactReservation

Tabela faktów będzie przechowywać powiązania z wymiarem `DimDate` dla trzech podstawowych dat.

| Atrybut | Źródło | Znaczenie |
|---|---|---|
| `booking_date_key` | `booking_date` | Data utworzenia rezerwacji |
| `check_in_date_key` | `check_in_date` | Planowana data zameldowania |
| `check_out_date_key` | `check_out_date` | Planowana data wymeldowania |
| `cancellation_date_key` | Do ustalenia | Data anulowania rezerwacji, jeśli jest dostępna |

### 7.2. Powiązanie z wymiarem DimDate

Wszystkie klucze dat będą wskazywać na ten sam wymiar `DimDate`, pełniący różne role analityczne (role-playing dimension).

Pozwoli to analizować rezerwacje według daty ich utworzenia oraz terminów planowanego pobytu.

Szczegółowe nazwy, typy i wartości kluczy muszą być zgodne z zatwierdzoną strukturą `DimDate`.

### 7.3. Obsługa daty anulowania

Aktualny model źródłowy PMS nie udostępnia jednoznacznego pola `cancellation_date`.

Przyjmuje się następujące założenia projektowe:

- Nie należy utożsamiać `updated_at` z datą anulowania.
- `cancellation_date_key` pozostaje opcjonalnym atrybutem logicznym do czasu uzgodnienia źródła danych.
- Nie wolno generować fikcyjnej daty anulowania na potrzeby raportowania rzeczywistych zdarzeń.
- Jeśli data anulowania nie będzie dostępna, należy udokumentować ograniczenie analizy anulacji w czasie.

### 7.4. Zasady poprawności dat

Podczas późniejszej implementacji należy zweryfikować:

- Czy daty rezerwacji i pobytu mają poprawny format.
- Czy `check_out_date` jest późniejsza niż `check_in_date`.
- Czy wszystkie wymagane daty mają odpowiedniki w `DimDate`.
- Czy brakujące lub nieprawidłowe daty są wykrywane przez testy jakości.
- Czy zakres dat obejmuje wymagane minimum 24 miesiące historii.

Szczegółowe reguły czyszczenia i obsługi odrzuconych rekordów zostaną uzgodnione z procesem ETL.

### 7.5. Ograniczenia

`FactReservation` przechowuje daty graniczne pobytu, a nie osobne rekordy dla każdej pokojonocy.

Analizy zajętości i przychodów w rozbiciu na poszczególne noce wymagają odrębnego modelu faktów pokojonocy.

## 8. Modelowanie waluty i kwot finansowych

### 8.1. Miary finansowe

Tabela `FactReservation` będzie przechowywać następujące kwoty na poziomie pojedynczej rezerwacji.

| Atrybut | Źródło | Znaczenie |
|---|---|---|
| `room_revenue` | `pms_reservations.room_revenue` | Wartość przychodu przypisana do rezerwacji |
| `cancellation_fee` | `pms_reservations.cancellation_fee` | Opłata naliczona za anulowanie rezerwacji |
| `commission_amount` | `cm_channels.commission_amount` | Kwota prowizji kanału sprzedaży |

Miary będą przechowywane z dokładnością do dwóch miejsc po przecinku, w typie liczbowym odpowiednim dla kwot finansowych, np. `NUMERIC(18,2)` w PostgreSQL.

### 8.2. Waluta

Dostępne pola źródłowe nie zawierają jawnego kodu waluty. W związku z tym:

- Przed implementacją należy uzgodnić jedną walutę bazową danych syntetycznych.
- Nie należy zakładać, że kwoty są wyrażone w PLN bez potwierdzenia tego założenia.
- Wszystkie miary finansowe w tabeli faktów muszą być wyrażone w uzgodnionej walucie.
- W projekcie logicznym przewiduje się atrybut `currency_code`, np. zgodny z ISO 4217.
- Jeśli źródła będą wykorzystywać różne waluty, konieczne będzie zdefiniowanie zasad przeliczania i dokumentowania kursów.

### 8.3. Zasady agregacji

- Kwoty finansowe są przypisane do jednej rezerwacji i nie mogą być powielane przez połączenia z innymi tabelami.
- `room_revenue`, `cancellation_fee` oraz `commission_amount` można sumować na poziomie rezerwacji, hotelu i kanału, pod warunkiem zachowania ziarna faktu i wspólnej waluty.
- `commission_rate` jest wskaźnikiem procentowym i nie należy sumować jego wartości.
- Nie należy automatycznie utożsamiać `room_revenue - commission_amount` z zaksięgowanym przychodem netto.
- Opłata za anulowanie jest przechowywana odrębnie od wartości rezerwacji, aby uniknąć podwójnego liczenia.

### 8.4. Kwestie wymagające uzgodnienia

Przed implementacją należy potwierdzić:

1. Walutę bazową danych PMS i Channel Managera.
2. Czy `room_revenue` oznacza wartość rezerwacji, czy faktycznie zrealizowany przychód.
3. Sposób interpretacji kwot dla rezerwacji anulowanych i no-show.
4. Czy `currency_code` będzie przechowywany bezpośrednio w tabeli faktów, czy za pomocą osobnego wymiaru waluty.

Do czasu uzgodnienia powyższych kwestii model finansowy pozostaje projektem logicznym.
