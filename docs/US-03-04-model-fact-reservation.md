# US-03-04 – Model faktów rezerwacji i anulacji

## 1. Cel modelu

Celem jest zaprojektowanie tabeli faktów `mart.fct_reservations`, umożliwiającej analizowanie rezerwacji i anulacji według hotelu, kanału rezerwacji i okresu.

Model powinien zapewniać jednoznaczne liczenie rezerwacji, bez wielokrotnego uwzględniania tego samego identyfikatora.

## 2. Ziarno tabeli mart.fct_reservations

**Ziarno:** jeden rekord tabeli `mart.fct_reservations` reprezentuje jedną unikalną rezerwację, identyfikowaną przez `reservation_bk` (pochodzący z `pms_reservations.reservation_id`), w jej ostatnim znanym stanie.

Założenia:

- Zmiana statusu rezerwacji nie powoduje utworzenia kolejnego rekordu.
- Rezerwacje anulowane i typu no-show pozostają w tabeli faktów.
- Jeden identyfikator `reservation_bk` może wystąpić w `mart.fct_reservations` tylko raz.
- Szczegółowe rozliczenie pokojonocy, jeśli będzie wymagane, zostanie zamodelowane oddzielnie.
- Tabela przechowuje aktualny stan rezerwacji, a nie pełną historię zmian statusów.

## 3. Źródła danych

- `staging.pms_reservations` – identyfikator rezerwacji, hotel, pokój, gość, daty, statusy i kwoty.
- `staging.cm_channels` – kanał sprzedaży i informacje o prowizjach.

Powiązanie źródeł następuje za pomocą `reservation_id`.

Wymienione tabele staging stanowią źródła pierwotne. Docelowe zasilenie mart.fct_reservations będzie wykorzystywało dane oczyszczone i uzgodnione w warstwie core, zgodnie z architekturą staging → core → mart. Dokładne tabele wejściowe core zostaną potwierdzone po realizacji zależnych prac ETL.

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
- `commission_amount` stanowi proponowaną miarę finansową tabeli `mart.fct_reservations`
- `commission_rate` pozostaje atrybutem źródłowym; sposób jego wykorzystania w modelu wymaga uzgodnienia.
- Zweryfikowano 140 875 rekordów Channel Managera, bez duplikatów identyfikatorów i bez brakujących powiązań z PMS.

## 5. Projekt struktury tabeli mart.fct_reservations

### 5.1. Założenia modelu

Docelową tabelą faktów rezerwacji jest `mart.fct_reservations`, zgodnie z istniejącym modelem hurtowni HotelGroup. Nazwa `FactReservation` jest stosowana jako określenie biznesowe.

- **Ziarno:** jeden rekord na unikalną rezerwację (`reservation_bk`).
- **Klucz techniczny:** `reservation_sk`.
- **Źródło identyfikatora biznesowego:** `pms_reservations.reservation_id`.
- **Źródła danych:** oczyszczone dane PMS oraz Channel Managera z warstwy `core`.
- **Wymiary:** `DimDate`, `DimHotel`, `DimChannel`, `DimGuest`, `DimSegment`.
- **Historia:** tabela przechowuje ostatni znany stan rezerwacji, bez historii zmian statusów.
- **Integralność:** `reservation_bk` musi być unikalny.

### 5.2. Docelowe atrybuty logiczne

Poniższa struktura wykorzystuje nazewnictwo istniejącej tabeli `mart.fct_reservations` oraz proponowane rozszerzenia wymagane do realizacji US-03-04.

| Atrybut | Znaczenie | Status |
|---|---|---|
| `reservation_sk` | Techniczny klucz główny | Istniejący model |
| `reservation_bk` | Biznesowy identyfikator rezerwacji | Istniejący model |
| `hotel_sk` | Klucz wymiaru hotelu | Istniejący model |
| `channel_sk` | Klucz wymiaru kanału | Istniejący model |
| `primary_guest_sk` | Klucz wymiaru gościa | Istniejący model |
| `segment_sk` | Klucz wymiaru segmentu | Istniejący model |
| `booking_date_sk` | Data dokonania rezerwacji | Istniejący model |
| `arrival_date_sk` | Planowana data zameldowania | Istniejący model |
| `departure_date_sk` | Planowana data wymeldowania | Istniejący model |
| `cancellation_date_sk` | Data anulowania, jeśli dostępna | Istniejący model |
| `reservation_status` | Ujednolicony status rezerwacji | Istniejący model |
| `reservation_count` | Liczba rezerwacji: zawsze 1 | Proponowane rozszerzenie |
| `cancellation_count` | Liczba anulacji: 1 lub 0 | Proponowane rozszerzenie |
| `room_revenue` | Wartość rezerwacji | Proponowane rozszerzenie |
| `cancellation_fee` | Opłata za anulowanie | Proponowane rozszerzenie |
| `commission_amount` | Prowizja kanału sprzedaży | Proponowane rozszerzenie |
| `currency_code` | Kod waluty kwot finansowych | Proponowane rozszerzenie |

**Uwagi:** oznaczenie „Istniejący model” odnosi się do definicji w udostępnionym skrypcie SQL, nie potwierdza fizycznego utworzenia tabeli w bazie. Proponowane rozszerzenia wymagają uwzględnienia w aktualizacji schematu.

Nazwy kluczy zastępczych zachowują konwencję `_sk`. Identyfikator rezerwacji z PMS jest mapowany na `reservation_bk`, natomiast `reservation_sk` jest generowany w hurtowni.

### 5.3. Atrybuty wymagające dodatkowych ustaleń

**Data anulowania:** w źródle PMS nie występuje osobne pole daty anulowania. Przyjęto stosowanie kluczy technicznych `UNKNOWN (0)` dla anulacji bez znanej daty oraz `NOT_APPLICABLE (-1)` dla pozostałych rezerwacji. Szczegółowe zasady opisano w sekcji 13. Wymaga to potwierdzenia istnienia odpowiednich rekordów w `DimDate`.

**Waluta:** dane PMS i Channel Managera nie zawierają kodu waluty. Przed implementacją należy ustalić walutę bazową i udokumentować ją zgodnie z zasadami opisanymi w sekcji 14.

**Klucze wymiarów:** przyjęto powiązania z pięcioma wymiarami: `DimDate`, `DimHotel`, `DimChannel`, `DimGuest` i `DimSegment`. Stosujemy nazewnictwo kluczy zastępczych `*_sk`, zgodne z istniejącym modelem `mart.fct_reservations`. Przed implementacją należy potwierdzić ich typy i relacje.

**Statusy:** przyjęto mapowanie pięciu statusów PMS na `ACTIVE`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED` i `NO_SHOW`. Reguły opisano w sekcji 6 i wymagają one weryfikacji podczas Code Review.

### 5.4. Zasady zapobiegania podwójnemu liczeniu

- `reservation_bk` musi być unikalny w tabeli faktów.
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

Tabela `mart.fct_reservations` wykorzystuje cztery klucze dat zgodne z istniejącym modelem hurtowni.

| Atrybut | Źródło | Znaczenie |
|---|---|---|
| `booking_date_sk` | `booking_date` | Data dokonania rezerwacji |
| `arrival_date_sk` | `check_in_date` | Planowana data zameldowania |
| `departure_date_sk` | `check_out_date` | Planowana data wymeldowania |
| `cancellation_date_sk` | Brak jednoznacznego pola w PMS | Data anulowania, jeśli jest dostępna |

Wszystkie klucze wskazują na wymiar `DimDate`, pełniący różne role analityczne.

Data anulowania pozostaje niedostępna w obecnym źródle PMS. Nie należy zastępować jej polem `updated_at`. Sposób reprezentowania brakującej daty musi być zgodny z regułami przyjętymi w słowniku wymiarów.

### 7.2. Powiązanie z wymiarem DimDate

Wszystkie klucze dat będą wskazywać na ten sam wymiar `DimDate`, pełniący różne role analityczne (role-playing dimension).

Pozwoli to analizować rezerwacje według daty ich utworzenia oraz terminów planowanego pobytu.

Szczegółowe nazwy, typy i wartości kluczy muszą być zgodne z zatwierdzoną strukturą `DimDate`.

### 7.3. Obsługa daty anulowania

Aktualny model źródłowy PMS nie udostępnia jednoznacznego pola `cancellation_date`.

Przyjmuje się następujące założenia projektowe:

- Nie należy utożsamiać `updated_at` z datą anulowania.
- Dla kolumny cancellation_date_sk przyjęto wartości techniczne UNKNOWN (0) i NOT_APPLICABLE (-1), zgodnie z regułami opisanymi w sekcji 13. Ich wykorzystanie wymaga przygotowania odpowiednich rekordów w mart.dim_date.
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

### 8.4. Kwestie wymagające potwierdzenia

Przed implementacją należy:

1. Ustalić i udokumentować walutę bazową danych syntetycznych.
2. Potwierdzić zgodność generatorów PMS i Channel Managera z regułami opisanymi w sekcjach 14.5 i 14.6.
3. Potwierdzić przechowywanie `currency_code` bezpośrednio w `mart.fct_reservations`.
4. Zweryfikować poprawność kwot podczas zasilania tabeli faktów.

Interpretację `room_revenue`, `cancellation_fee` i `commission_amount` opisano w sekcji 14. Dane syntetyczne nie stanowią potwierdzonych zapisów księgowych.

## 9. Relacje FactReservation z wymiarami

### 9.1. Powiązania z wymiarami

Tabela `mart.fct_reservations` jest powiązana z pięcioma wymiarami analitycznymi.

| Atrybut tabeli faktów | Wymiar | Identyfikator lub atrybut źródłowy |
|---|---|---|
| `hotel_sk` | `DimHotel` | `pms_reservations.hotel_id` |
| `channel_sk` | `DimChannel` | `cm_channels.channel_code` |
| `primary_guest_sk` | `DimGuest` | `pms_reservations.guest_id` |
| `segment_sk` | `DimSegment` | `pms_reservations.guest_segment` |
| `booking_date_sk` | `DimDate` | `pms_reservations.booking_date` |
| `arrival_date_sk` | `DimDate` | `pms_reservations.check_in_date` |
| `departure_date_sk` | `DimDate` | `pms_reservations.check_out_date` |
| `cancellation_date_sk` | `DimDate` | Data anulowania, jeśli dostępna |

Identyfikatory źródłowe są wykorzystywane do wyszukiwania odpowiednich kluczy zastępczych (`*_sk`) w wymiarach.

Dokładne mapowanie kodów kanałów oraz sposób obsługi brakujących powiązań muszą zostać uzgodnione ze słownikiem wymiarów i procesem transformacji danych.

Połączenie z wymiarami nie może zmieniać liczby unikalnych rezerwacji.

### 9.2. Zasady przypisywania kluczy

- `hotel_id` jest identyfikatorem źródłowym, na podstawie którego wyszukiwany jest odpowiedni rekord `DimHotel`.
- `channel_code` jest identyfikatorem źródłowym wykorzystywanym do przypisania `DimChannel`.
- Daty źródłowe są mapowane na odpowiednie rekordy `DimDate`.
- Tabela faktów przechowuje klucze zastępcze (`*_sk`) odpowiednich wymiarów, a identyfikatory źródłowe służą do wyszukania właściwych rekordów wymiarowych.
- Dla wymiarów przechowujących historię zmian należy zastosować zasady wyboru właściwej wersji rekordu uzgodnione z zespołem.

### 9.3. Obsługa brakujących powiązań

Podczas ładowania tabeli faktów należy wykrywać sytuacje, w których:

- Rezerwacja wskazuje hotel nieistniejący w `DimHotel`.
- Kod kanału nie ma odpowiednika w `DimChannel`.
- Data rezerwacji lub pobytu nie występuje w `DimDate`.
- Połączenie z wymiarem zwraca więcej niż jeden niezamierzony rekord.

Takie przypadki muszą być raportowane przez testy jakości danych.

Sposób obsługi brakujących powiązań (odrzucenie rekordu, zastosowanie rekordu technicznego `UNKNOWN` lub inna uzgodniona reguła) zostanie ustalony przed implementacją.

### 9.4. Integralność i zachowanie ziarna

- Każdy rekord `FactReservation` musi odpowiadać dokładnie jednej rezerwacji PMS.
- Powiązanie z wymiarami nie może powodować zwielokrotnienia rezerwacji.
- Klucze wymiarów powinny mieć odpowiedniki w tabelach wymiarowych zgodnie z przyjętymi regułami obsługi braków.
- Liczba rezerwacji po powiązaniu z wymiarami musi zostać uzgodniona z liczbą poprawnych rekordów źródłowych.
- Każde odrzucenie rezerwacji przez reguły jakości powinno zostać udokumentowane.

### 9.5. Zależności implementacyjne

Przed utworzeniem fizycznej tabeli `FactReservation` należy potwierdzić:

1. Struktury oraz klucze `DimDate`, `DimHotel`, `DimChannel`, `DimGuest` i `DimSegment`.
2. Dostępność oczyszczonych danych PMS i Channel Managera.
3. Uzgodnione reguły obsługi brakujących powiązań.
4. Zgodność nazw i typów kluczy z modelem hurtowni.

Dokument przedstawia projekt logiczny relacji, który wymaga weryfikacji z aktualną implementacją wymiarów.

## 10. Obsługa rezerwacji wielopokojowych i pokojonocy

### 10.1. Ziarno FactReservation

Tabela `FactReservation` zachowuje ziarno jednego rekordu na `reservation_id`, niezależnie od liczby pokoi przypisanych do rezerwacji.

Oznacza to, że:
- Jedna rezerwacja wielopokojowa nadal jest liczona jako jedna rezerwacja.
- Status oraz informacja o anulowaniu są przechowywane na poziomie całej rezerwacji.
- Kwoty przypisane do rezerwacji nie mogą być powielane przy analizie poszczególnych pokoi.

### 10.2. Aktualna struktura danych PMS

W obecnym źródle `pms_reservations` występuje pojedynczy atrybut `room_id` przypisany do `reservation_id`.

Na podstawie dostępnej struktury przyjmujemy, że pojedynczy rekord źródłowy reprezentuje rezerwację jednego pokoju. Nie potwierdzono osobnego mechanizmu przechowywania wielu pokoi w ramach jednej rezerwacji.

Przed rozszerzeniem modelu należy zweryfikować to założenie z generatorem PMS.

### 10.3. Proponowany model pokojonocy

Szczegółowość pobytów na poziomie pokojonocy została wydzielona do osobnego modelu faktów `FactRoomNight`, realizowanego w US-03-05. W ramach US-03-04 dokumentujemy wyłącznie zasady dekompozycji rezerwacji.

**Proponowane ziarno:** jeden rekord na kombinację `reservation_id`, `room_id` i daty noclegu.

Przykład:

Rezerwacja `R001` obejmuje dwa pokoje na trzy noce.

- `mart.fct_reservations`: 1 rekord.
- `FactRoomNight`: 6 rekordów (2 pokoje × 3 noce).
- `reservation_count`: 1, a nie 6.

W przykładzie `R001` jest wartością biznesowego identyfikatora rezerwacji (`reservation_bk`).

### 10.4. Zasady agregacji

- Liczbę rezerwacji i anulacji oblicza się na poziomie `FactReservation`.
- Liczbę pokojonocy oblicza się na poziomie `FactRoomNight`.
- Nie należy sumować miary `reservation_count` po połączeniu z rekordami pokojonocy bez wcześniejszej agregacji lub deduplikacji.
- Przychód przypisany całej rezerwacji nie może być kopiowany do każdej pokojonocy bez odpowiedniej reguły alokacji.
- Ewentualny podział przychodu na pokoje i noce wymaga uzgodnienia zasad biznesowych.

### 10.5. Zakres implementacji

W ramach US-03-04 implementowana jest tabela `FactReservation` z ziarnem pojedynczej rezerwacji.

Tabela faktów pokojonocy (FactRoomNight) jest objęta osobną historią użytkownika US-03-05. W ramach US-03-04 dokumentujemy sposób zachowania ziarna rezerwacji i zasady zapobiegania podwójnemu liczeniu. Implementacja pokojonocy pozostaje w zakresie US-03-05.

## 11. Decyzja projektowa – zgodność z istniejącym modelem hurtowni

W ramach US-03-04 przyjęto rozszerzenie istniejącej tabeli `mart.fct_reservations`, zamiast tworzenia osobnej tabeli `FactReservation`.

Zachowane zostają istniejące nazwy kluczy technicznych i powiązań z wymiarami (`*_sk`). Ziarno tabeli wynosi jeden rekord na `reservation_bk`, a jego unikalność zostanie wymuszona ograniczeniem `UNIQUE`.

Model zostanie uzupełniony o miary liczby rezerwacji i anulacji oraz kwoty przychodów, opłat za anulowanie i prowizji. Uwzględnione zostaną także powiązania z `DimGuest` i `DimSegment`.

Dane do tabeli faktów będą pochodzić z oczyszczonej warstwy `core`, zgodnie z architekturą `staging → core → mart`.

**Przed implementacją fizyczną** należy potwierdzić zgodność struktur wymiarów, mapowania kanałów sprzedaży, walutę oraz dostępność danych o anulacjach.

Niniejsza decyzja stanowi propozycję implementacyjną US-03-04 podlegającą Code Review zespołu. Zmiany istniejącego schematu SQL będą realizowane w ramach osobnego commita po weryfikacji zależności.

## 12. Mapowanie kanałów sprzedaży

### 12.1. Mapowanie kodów źródłowych

Generator Channel Managera wykorzystuje trzy kody kanałów sprzedaży. Słownik wymiarów US-03-03 przewiduje bardziej szczegółową klasyfikację.

Przyjęto następujące proponowane mapowanie:

| Kod źródłowy | Kod docelowy DimChannel | Grupa |
|---|---|---|
| `DIRECT` | `DIRECT` | DIRECT |
| `BOOKING` | `BOOKING_COM` | OTA |
| `EXPEDIA` | `EXPEDIA` | OTA |

Kod `DIRECT` zostanie dodany do słownika `DimChannel` jako ogólny kanał sprzedaży bezpośredniej. Nie będzie utożsamiany z `DIRECT_WEB`, `DIRECT_PHONE` ani `DIRECT_EMAIL`, ponieważ dane źródłowe nie pozwalają na takie rozróżnienie.

### 12.2. Zasady mapowania

- Każdej rezerwacji przypisuje się maksymalnie jeden kanał pozyskania.
- Mapowanie powinno następować przed przypisaniem `channel_sk`.
- Nieznany kod źródłowy należy zgłosić w kontroli jakości.
- Brak kanału nie oznacza automatycznie rezerwacji bezpośredniej.
- Mapowanie nie może zwiększać liczby rezerwacji.
- Proponowane rozszerzenie słownika o `DIRECT` wymaga uwzględnienia w US-03-03 i przeglądu przez zespół.

### 12.3. Weryfikacja

Podczas implementacji należy sprawdzić, czy wszystkie kody źródłowe mają jednoznaczne odpowiedniki w `DimChannel` oraz czy każda rezerwacja otrzymuje dokładnie jeden właściwy klucz kanału.

## 13. Obsługa brakującej daty anulowania

### 13.1. Reguły przypisywania daty

W aktualnych danych PMS brak jednoznacznego atrybutu określającego datę anulowania rezerwacji.

Zgodnie z konwencją technicznych wartości wymiaru `DimDate` przyjmuje się następujące zasady:

| Warunek | Wartość `cancellation_date_sk` |
|---|---|
| Rezerwacja anulowana, brak daty anulowania | `0` (`UNKNOWN`) |
| Rezerwacja nieanulowana | `-1` (`NOT_APPLICABLE`) |
| Rezerwacja anulowana, znana data anulowania | Klucz odpowiedniej daty w `DimDate` |

### 13.2. Zasady jakości danych

- `updated_at` nie jest traktowane jako data anulowania.
- Nie generuje się sztucznej daty anulowania.
- Status `NO_SHOW` nie jest równoznaczny z anulowaniem.
- Wymiar `DimDate` musi zawierać odpowiednie rekordy techniczne dla kluczy `0` i `-1`.
- Brak rzeczywistej daty anulowania ogranicza możliwość analizowania anulacji według dnia ich wystąpienia.
- Liczba anulacji nadal może być analizowana według daty dokonania rezerwacji, planowanego pobytu, hotelu i kanału.

### 13.3. Weryfikacja

Podczas testów należy potwierdzić, że każda rezerwacja otrzymuje odpowiedni klucz daty anulowania, a przypisanie wartości technicznych nie narusza integralności referencyjnej.

Reguła zostanie zweryfikowana z fizyczną implementacją `DimDate` przed zasileniem tabeli faktów.


## 14. Zasady interpretacji kwot i waluty

### 14.1. Waluta danych

Dane źródłowe PMS i Channel Managera nie zawierają jawnego kodu waluty.

Przyjęto następujące zasady projektowe:

- Wszystkie kwoty w `mart.fct_reservations` muszą być wyrażone w jednej, udokumentowanej walucie.
- Waluta zostanie potwierdzona na podstawie generatorów i ustaleń dotyczących danych syntetycznych.
- Atrybut `currency_code` będzie przechowywał kod waluty zgodny z ISO 4217.
- Do czasu potwierdzenia waluty nie przypisuje się arbitralnie kodu `PLN` ani `EUR`.
- Ewentualne przeliczanie walut wymaga osobno określonych reguł oraz źródła kursów.

### 14.2. Interpretacja miar finansowych

| Miara | Interpretacja |
|---|---|
| `room_revenue` | Źródłowa wartość przypisana do rezerwacji; nie jest automatycznie uznawana za przychód zrealizowany |
| `cancellation_fee` | Opłata związana z anulowaniem rezerwacji |
| `commission_amount` | Prowizja kanału sprzedaży przypisana do rezerwacji |

Kwoty należy przechowywać jako wartości dziesiętne, np. `NUMERIC(18,2)`.

### 14.3. Zasady raportowania

- Kwoty można agregować wyłącznie przy zachowaniu jednego rekordu na `reservation_bk` oraz zgodności waluty.
- Anulowane rezerwacje i no-show pozostają w tabeli faktów.
- `room_revenue` nie może być automatycznie interpretowane jako rzeczywisty przychód hotelu.
- `cancellation_fee` i `commission_amount` pozostają odrębnymi miarami.
- Nie wylicza się przychodu netto bez uzgodnionej definicji biznesowej.
- Przed wdrożeniem należy sprawdzić sposób wyznaczania kwot w generatorach danych PMS i Channel Managera.

### 14.4. Warunki zatwierdzenia

Przed implementacją należy potwierdzić walutę syntetycznych danych PMS i Channel Managera.

Reguły generowania i interpretacji kwot zostały opisane w sekcjach 14.5 i 14.6. Ich zgodność z kodem generatorów oraz poprawność odwzorowania w tabeli faktów zostaną zweryfikowane podczas implementacji i testów.

### 14.5. Weryfikacja reguł finansowych generatora PMS

Analiza kodu generatora `generate_pms_data` potwierdziła następujące zasady:

| Status źródłowy | `room_revenue` | `cancellation_fee` |
|---|---|---|
| `Zakończona` | Wartość pobytu | 0 |
| `W trakcie` | Wartość pobytu | 0 |
| `Oczekująca` | Wartość planowanego pobytu | 0 |
| `Anulowana` | 0 | 0 lub 30% wartości rezerwacji |
| `No-Show` | 0 | 100% wartości rezerwacji |

Wartości są wyliczane syntetycznie na podstawie ceny pokoju, długości pobytu i sezonowości.

**Wnioski:**

- `room_revenue` zawiera zarówno wartości pobytów zakończonych, jak i niezakończonych.
- Nie należy prezentować sumy `room_revenue` jako faktycznie zrealizowanego przychodu.
- `cancellation_fee` obejmuje również opłaty no-show, dlatego nazwa źródłowa nie odzwierciedla w pełni znaczenia biznesowego tej miary.
- Do rozdzielania wartości według statusów należy stosować `reservation_status`.
- Generator nie określa kodu waluty. Wybór waluty bazowej pozostaje decyzją projektową wymagającą udokumentowania.

### 14.6. Reguły finansowe Channel Managera

W ramach US-02-01 przyjęto syntetyczny model prowizji zależny od kanału sprzedaży.

| Kod kanału | Stawka prowizji |
|---|---:|
| `DIRECT` | 0% |
| `BOOKING` | 15% |
| `EXPEDIA` | 18% |

Prowizja jest wyliczana na podstawie `room_revenue`. Dla rezerwacji anulowanych oraz no-show przyjęto prowizję równą 0.

**Zasady modelowania:**

- `commission_amount` jest przechowywana jako odrębna miara finansowa w `mart.fct_reservations`.
- Kwota prowizji jest przypisana do pojedynczej rezerwacji.
- Stawka prowizji nie stanowi miary addytywnej i nie powinna być sumowana.
- Rezerwacje z kanału `DIRECT` nie generują prowizji.
- Prowizji nie należy automatycznie traktować jako kosztu faktycznie zaksięgowanego.
- Reguły są założeniami generatora danych syntetycznych, a nie uniwersalnymi zasadami rozliczeń hotelowych.

Podczas implementacji należy porównać sumy `commission_amount` między źródłem Channel Managera a tabelą faktów oraz sprawdzić, czy połączenie źródeł nie powoduje powielania kwot.

## 15. Specyfikacja techniczna mart.fct_reservations
### 15.1. Proponowane typy danych

| Kolumna | Proponowany typ PostgreSQL | Ograniczenia |
|---|---|---|
| `reservation_sk` | `INTEGER` (`SERIAL`) | PRIMARY KEY |
| `reservation_bk` | `VARCHAR(50)` | NOT NULL, UNIQUE |
| `hotel_sk` | `INTEGER` | FK → DimHotel |
| `channel_sk` | `INTEGER` | FK → DimChannel |
| `primary_guest_sk` | `INTEGER` | FK → DimGuest |
| `segment_sk` | `INTEGER` | FK → DimSegment |
| `booking_date_sk` | `INTEGER` | FK → DimDate |
| `arrival_date_sk` | `INTEGER` | FK → DimDate |
| `departure_date_sk` | `INTEGER` | FK → DimDate |
| `cancellation_date_sk` | `INTEGER` | FK → DimDate |
| `reservation_status` | `VARCHAR(50)` | NOT NULL |
| `reservation_count` | `SMALLINT` | NOT NULL, DEFAULT 1 |
| `cancellation_count` | `SMALLINT` | NOT NULL, DEFAULT 0 |
| `room_revenue` | `NUMERIC(18,2)` | Kwota nieujemna |
| `cancellation_fee` | `NUMERIC(18,2)` | Kwota nieujemna |
| `commission_amount` | `NUMERIC(18,2)` | Kwota nieujemna |
| `currency_code` | `CHAR(3)` | Kod waluty ISO 4217 |

Typy istniejących kolumn dostosowano do definicji zawartych w pliku `Skrypty_do_odtworzenia_bazy.sql`. Kolumna `reservation_sk` wykorzystuje mechanizm `SERIAL`, odpowiadający typowi `INTEGER` z automatycznym generowaniem wartości. Klucze obce mają typ `INTEGER`, zgodny z istniejącym modelem wymiarowym.

Kolumny `reservation_count`, `cancellation_count`, `room_revenue`, `cancellation_fee`, `commission_amount` i `currency_code` stanowią proponowane rozszerzenie istniejącej tabeli `mart.fct_reservations`.

Ostateczne ograniczenia, dopuszczalność wartości `NULL` oraz zgodność kluczy obcych z kluczami głównymi wymiarów zostaną zweryfikowane przed implementacją SQL.

### 15.2. Ograniczenia integralności

Docelowa implementacja powinna zapewniać:

- Unikalność `reservation_bk`.
- Poprawne powiązania z wymiarami.
- Dopuszczenie wyłącznie pięciu uzgodnionych statusów analitycznych.
- `reservation_count = 1` dla każdej rezerwacji.
- `cancellation_count = 1` wyłącznie dla statusu `CANCELLED`, w pozostałych przypadkach 0.
- Nieujemne kwoty finansowe.
- Zgodność `currency_code` z ustaloną walutą danych.

Reguły brakujących powiązań i dopuszczalność wartości NULL zostaną ostatecznie ustalone po weryfikacji fizycznych struktur wymiarów.

### 15.3. Zasada wdrożenia

Implementacja zostanie wykonana przez rozszerzenie istniejącej tabeli `mart.fct_reservations`, bez tworzenia równoległej tabeli faktów.

Przed przygotowaniem migracji SQL należy zweryfikować typy istniejących kolumn, ograniczenia oraz zależności z pozostałymi elementami modelu hurtowni.

Zależność od DimDate: obecna definicja mart.dim_date wymaga wartości full_date DATE UNIQUE NOT NULL, dlatego nie umożliwia bezpośredniego dodania dwóch rekordów technicznych bez rzeczywistej daty. Przed wykorzystaniem kluczy 0 (UNKNOWN) i -1 (NOT_APPLICABLE) należy uzgodnić z właścicielem wymiaru modyfikację tej definicji oraz przygotowanie odpowiednich rekordów technicznych. Nie należy stosować fikcyjnych dat kalendarzowych jako zastępstwa brakujących informacji.

## 16. Plan testów akceptacyjnych

Testy zostaną wykonane po utworzeniu i zasileniu tabeli `mart.fct_reservations`. Poniższe przypadki testowe wynikają z kryteriów akceptacji US-03-04.

| ID | Test | Oczekiwany rezultat |
|---|---|---|
| T01 | Unikalność `reservation_bk` | Brak duplikatów identyfikatorów rezerwacji |
| T02 | Zgodność liczby rezerwacji | Liczba rekordów faktu zgodna z liczbą zaakceptowanych rezerwacji źródłowych |
| T03 | Mapowanie statusów | Wszystkie rezerwacje mają jeden z pięciu uzgodnionych statusów |
| T04 | Liczenie rezerwacji | `reservation_count = 1` dla każdego rekordu |
| T05 | Liczenie anulacji | `cancellation_count = 1` wyłącznie dla statusu `CANCELLED` |
| T06 | Integralność wymiarów | Brak niedozwolonych lub nieistniejących kluczy wymiarów |
| T07 | Mapowanie kanałów | Wszystkie kody kanałów są poprawnie przypisane do `DimChannel` |
| T08 | Zakres historyczny | Dane obejmują minimum 24 miesiące historii |
| T09 | Liczebność danych | Minimum 50 000 rezerwacji źródłowych; wszystkie odrzucenia udokumentowane |
| T10 | Kwoty finansowe | Zgodność sum kwot z zaakceptowanymi danymi źródłowymi |
| T11 | Data anulowania | Poprawne przypisanie daty lub wartości `UNKNOWN` / `NOT_APPLICABLE` |
| T12 | Ponowne zasilenie | Ponowne uruchomienie nie powoduje niezamierzonych duplikatów |

### 16.1. Zasady weryfikacji

- Testy dotyczą faktycznie załadowanych danych, a nie wyłącznie definicji tabeli.
- Każdy wynik należy udokumentować jako PASS lub FAIL.
- Różnice liczebności między źródłem a tabelą faktów muszą być wyjaśnione.
- Testy powiązań obejmują `DimDate`, `DimHotel`, `DimChannel`, `DimGuest` i `DimSegment`.
- Wyniki testów powinny zostać dołączone do dokumentacji implementacji lub Pull Requesta.

### 16.2. Status testów

Wszystkie testy T01–T12 mają obecnie status **NOT RUN**.

Weryfikacja liczebności i spójności danych źródłowych wykonana w US-02-01 nie zastępuje testów docelowej tabeli `mart.fct_reservations`.
