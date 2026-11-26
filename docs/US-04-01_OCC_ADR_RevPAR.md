# US-04-01 – Obliczanie OCC, ADR i RevPAR (HotelGroup)

## Status i zakres
Implementacja widoków SQL przygotowana na podstawie **snapshotu `analytics-project-main.zip` przekazanego 26.11.2026**. Widoki nie zostały jeszcze uruchomione na zintegrowanej hurtowni. W lokalnym `hotelgroup_dw` brak tabel `mart.fct_room_night`, `mart.fct_room_inventory`, `mart.dim_date` i `mart.dim_hotel`; **nie uruchamiać skryptu widoków przed wdrożeniem US-03-05**. Testy syntetyczne mogą działać bez tych tabel.

## Definicje KPI
- OCC [%] = `100 * SUM(sold_room_nights) / NULLIF(SUM(available_room_nights),0)`
- ADR [PLN] = `SUM(room_revenue_pln) / NULLIF(SUM(sold_room_nights),0)`
- RevPAR [PLN] = `SUM(room_revenue_pln) / NULLIF(SUM(available_room_nights),0)`
- `NULL` wyświetlać jako **Brak danych**. KPI w widokach bez zaokrąglenia; zaokrąglić tylko przy prezentacji (OCC do 2 miejsc %, ADR/RevPAR do 2 miejsc PLN).
- Liczyć wskaźniki zbiorcze **z sum miar bazowych** po zastosowaniu tych samych filtrów hotelu, daty i typu pokoju; nie robić `AVG(OCC)` ani `AVG(ADR)`.
- Revenue wyłącznie `mart.fct_room_night.room_revenue`; **nie wliczać gastronomii, SPA ani cancellation fee**.
- Miesiąc = data nocy (dzień wymeldowania wykluczony); logika rozwijania pobytów należy do US-03-05A.
- OOO odejmowane od podaży na podstawie `mart.fct_room_inventory.available_room_nights`; w obecnym źródle brak historycznych OOO, a seed ustawia wszystkie pokoje jako dostępne.
- Typ pokoju = **fizyczny typ zajętego pokoju** `occupied_room_type_sk` i `room_type_sk` w dostępności (nie `booked_room_type_sk`).

## Źródła i odporność na błędne złączenia
- `mart.fct_room_night`: ziarno pobyt × pokój × data. Klucze `hotel_sk`, `stay_date_sk`, `occupied_room_type_sk`, miary `room_night_count`, `room_revenue`, `currency_code`.
- `mart.fct_room_inventory`: ziarno pokój × data. Klucze `hotel_sk`, `inventory_date_sk`, `room_type_sk`, miary `available_room_nights`, `out_of_order_room_nights`.
- **Każde źródło jest agregowane oddzielnie do hotel × data × typ**, następnie łączone pełnym złączeniem. Bez łączenia fakt-do-faktu na surowych rekordach.
- Dni z błędem źródła (inny kod waluty niż PLN, przychód bez nocy, sprzedane większe niż dostępność, brak rekordu inwentarza) otrzymują status DQ i **nie publikują KPI**. Widok miesięczny również oznacza błąd.
- Nie przeliczamy innych walut bez reguł kursowych.

## Uruchomienie
1. W lokalnej bazie (`hotelgroup_dw`) można wykonać samodzielny test: `tests/31_us_04_01_synthetic_kpi_tests.sql`, tylko `SELECT`.
2. W środowisku **z zasilonymi faktami US-03-05A/05B** wykonać `database/schema/30_us_04_01_kpi_views.sql` – tworzy dwa widoki `mart.vw_us_04_01_kpi_daily` i `mart.vw_us_04_01_kpi_monthly`.
3. Przykład raportu grupowego: `SELECT SUM(sold_room_nights), SUM(available_room_nights), SUM(room_revenue_pln), ROUND(100 * SUM(sold_room_nights)::NUMERIC / NULLIF(SUM(available_room_nights),0),2) AS occ_pct, ROUND(SUM(room_revenue_pln) / NULLIF(SUM(sold_room_nights),0),2) AS adr_pln, ROUND(SUM(room_revenue_pln) / NULLIF(SUM(available_room_nights),0),2) AS revpar_pln FROM mart.vw_us_04_01_kpi_monthly WHERE kpi_quality_status='OK';`. **Uwaga**: w rzeczywistym raporcie kontrolować i raportować wiersze `INVALID_DATA`, nie pomijać ich bez ostrzeżenia.

## Dowody i ograniczenia
W rozmowie przetestowano ręcznie: wzory OCC/ADR/RevPAR, zero w mianowniku, agregacje hotelowe, granicę miesiąca, OOO, filtry hotel/miesiąc/typ, wyłączenie F&B i SPA oraz `RevPAR = OCC × ADR`. Skrypt `31` zbiera 13 warunków do jednego odtwarzalnego testu (oczekiwane 13 PASS). Nie jest to jeszcze test integracyjny tabel z repozytorium. Do końcowej akceptacji: przegląd z zespołem zasad OOO i definicji przychodu, integracja z US-03-05A/B, weryfikacja historycznych danych i NFR (wydajność, dostęp, dokumentacja) w docelowym środowisku.
