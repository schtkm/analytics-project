# US-03-05B – Model dziennej dostępności pokoi (`mart.fct_room_inventory`)

## 1. Cel i zakres modelu
Tabela `mart.fct_room_inventory` (`FactRoomInventory`) modeluje dzienną dostępność fizycznych pokoi we wszystkich hotelach sieci w podziale na doby kalendarzowe. Stanowi mianownik wskaźnika **OCC** oraz podstawę do obliczania **RevPAR** we współpracy z tabelą `mart.fct_room_night` (`US-03-05A`).

## 2. Ziarno, klucze i relacje
* **Ziarno:** 1 rekord = 1 fizyczny pokój × 1 dzień kalendarzowy (`room_sk`, `inventory_date_sk`).
* **Klucz główny:** `room_inventory_sk` (`SERIAL PRIMARY KEY`).
* **Klucz biznesowy i ograniczenie unikalności (`DQ-02`):** `UNIQUE (room_sk, inventory_date_sk)` (`uq_fct_room_inventory_grain`).
* **Klucze obce (`DQ-03`):**
  * `inventory_date_sk` $\rightarrow$ `mart.dim_date(date_sk)`
  * `hotel_sk` $\rightarrow$ `mart.dim_hotel(hotel_sk)` (spójny z przypisaniem pokoju w `mart.dim_room`)
  * `room_sk` $\rightarrow$ `mart.dim_room(room_sk)`
  * `room_type_sk` $\rightarrow$ `mart.dim_room_type(room_type_sk)` (umożliwia bezpośrednią agregację dostępności według typu pokoju)

## 3. Reguły biznesowe, Out of Order i mianownik OCC
1. **Zasada mianownika OCC (`DQ-04`):**
   * `total_room_nights = 1` — fizyczna pojemność pokoju w danej dobie.
   * `is_out_of_order = TRUE` $\Rightarrow$ `out_of_order_room_nights = 1` oraz `available_room_nights = 0` (pokój wyłączony z użytkowania nie wchodzi do mianownika OCC).
   * `is_out_of_order = FALSE` $\Rightarrow$ `out_of_order_room_nights = 0` oraz `available_room_nights = 1`.
   * Spójność egzekwowana ograniczeniem `ck_fct_room_inventory_ooo_consistency`.
2. **Dane źródłowe PMS:** W tabelach `staging.pms_rooms` oraz `core.clean_pms_rooms` nie występuje osobny rejestr wyłączeń technicznych pokoi, dlatego przy zasilaniu początkowym ustawiane jest `is_out_of_order = FALSE` (`available_room_nights = 1`), przy pełnej gotowości struktury na aktualizacje stanów *Out of Order*.
3. **Horyzont czasowy (7, 30 i 90 dni):** Tabela pokrywa ciągły kalendarz `mart.dim_date` od `2023-10-03` do `2026-06-30` (1 002 dni dla 1 240 pokoi = 1 242 480 rekordów), obejmując pełne okna analityczne 7, 30 i 90 dni w przód względem daty odcięcia pobytów (`2026-01-01`).
4. **Wykrywanie potencjalnego overbookingu (`DQ-04`):** Zestawienie `mart.fct_room_inventory` z `mart.fct_room_night` (pobyty zrealizowane/w trakcie) lub `core.clean_pms_reservations` (rezerwacje przyszłe) pozwala wykryć przekroczenia pojemności per hotel i dzień (`sold_room_nights > available_room_nights`, tj. `OCC > 100%`) oraz przypisania do pokoi wyłączonych z użytkowania.