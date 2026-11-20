# US-03-05A – Model faktów pokojonocy (`mart.fct_room_night`)

## 1. Cel i zakres modelu
Tabela `mart.fct_room_night` (`FactRoomNight`) przechowuje rzeczywiste wykorzystane pokojonoce w podziale na pojedyncze doby hotelowe. Model stanowi podstawę do wyznaczania wskaźników **OCC** (licznik zajętych pokoi), **ADR** oraz **RevPAR** (implementacja mianownika dostępności pokoi i Out of Order realizowana jest w US-03-05B).

## 2. Ziarno i klucze tabeli
* **Ziarno:** 1 rekord = 1 pokój przypisany do rzeczywistego pobytu × 1 noc pobytu (`stay_bk`, `room_sk`, `stay_date_sk`).
* **Klucz główny:** `room_night_sk` (`SERIAL` / `INTEGER`).
* **Klucz biznesowy i ograniczenie unikalności:** `UNIQUE (stay_bk, room_sk, stay_date_sk)` (`uq_fct_room_night_grain`).
* **Powiązania wymiarowe i faktowe:**
  * `reservation_sk` $\rightarrow$ `mart.fct_reservations(reservation_sk)`
  * `stay_date_sk` $\rightarrow$ `mart.dim_date(date_sk)`
  * `hotel_sk` $\rightarrow$ `mart.dim_hotel(hotel_sk)`
  * `room_sk` $\rightarrow$ `mart.dim_room(room_sk)`
  * `booked_room_type_sk`, `occupied_room_type_sk` $\rightarrow$ `mart.dim_room_type(room_type_sk)`
  * `channel_sk` $\rightarrow$ `mart.dim_channel(channel_sk)`
  * `primary_guest_sk` $\rightarrow$ `mart.dim_guest(guest_sk)`
  * `segment_sk` $\rightarrow$ `mart.dim_segment(segment_sk)`

## 3. Reguły biznesowe i obsługa przypadków brzegowych
1. **Doba hotelowa i przełom miesięcy/lat:** Pobyt o datach `[actual_check_in, actual_check_out)` jest rozwijany na pojedyncze daty od `actual_check_in` włącznie do `actual_check_out - 1 dzień` włącznie. Nocleg na przełomie miesiąca lub roku przypisywany jest do daty rozpoczęcia danej doby hotelowej.
2. **Wykluczenie anulacji i No-Show:** Do zasilenia kwalifikują się wyłącznie rzeczywiste pobyty z `core.clean_pms_stays` powiązane ze statusami `COMPLETED` oraz `IN_PROGRESS`. Statusy `CANCELLED` i `NO_SHOW` nie generują pokojonocy.
3. **Pobyty 0-nocne (day-use):** W danych `core.clean_pms_stays` (97 388 rekordów) występuje 139 pobytów, dla których `actual_check_out = actual_check_in` (0 pełnych dób hotelowych) oraz 97 249 pobytów trwających $\ge 1$ noc. Pobyty 0-nocne nie generują pokojonocy.
4. **Alokacja przychodu (`room_revenue`):** Przychód z rezerwacji dzielony jest równomiernie na liczbę nocy (`TRUNC(room_revenue / nights, 2)`), a reszta z zaokrąglenia przypisywana jest do ostatniej nocy pobytu, co gwarantuje zgodność sumy przychodów co do grosza (`NUMERIC(18,2)`, waluta `PLN`).
5. **Klasyfikacja nocy pobytu:** Każda pokojonoc oznaczona jest flagami `is_arrival_night` (pierwsza noc), `is_stay_over` (noc kontynuowana) oraz `is_last_night` (ostatnia noc przed wymeldowaniem).

## 4. Wyniki weryfikacji i testów akceptacyjnych (`T01`–`T07`)
* **Liczba załadowanych pokojonocy:** 387 074 rekordów z 97 249 pobytów wielodniowych (`385 992` dla `COMPLETED`, `1 082` dla `IN_PROGRESS`).
* **Unikalność ziarna (`T01`):** PASS — 0 duplikatów dla `(stay_bk, room_sk, stay_date_sk)`.
* **Zgodność liczby pokojonocy (`T02`):** PASS — 100% zgodności z sumą dób w `core.clean_pms_stays`.
* **Wykluczenie anulacji i No-Show (`T03`):** PASS — 0 rekordów dla statusów `CANCELLED` i `NO_SHOW`.
* **Podział na przełomie miesięcy (`T04`):** PASS — poprawnie rozbito 9 233 pobyty przekraczające granicę miesiąca lub roku.
* **Integralność kluczy wymiarów (`T05`):** PASS — 0 brakujących powiązań FK.
* **Uzgodnienie przychodów (`T06`):** PASS — łączny przychód `239 318 768,00 PLN` zgodny co do grosza ze źródłem.
* **Spójność flag doby pobytu (`T07`):** PASS — 0 niezgodności dla flag `is_arrival_night`, `is_stay_over` i `is_last_night`.