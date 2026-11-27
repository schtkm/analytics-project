# US-04-04 – GOP i marża GOP

## Cel
Obliczanie zysku operacyjnego brutto (GOP) i marży GOP
dla hoteli HotelGroup.

## Definicje
GOP = przychody operacyjne − koszty operacyjne GOP.

Marża GOP [%] = GOP / przychody × 100.

Przy zerowych przychodach marża ma wartość NULL
(„Brak danych”), natomiast GOP nadal jest obliczany.

## Źródła danych
- `mart.fct_room_night` – przychody z noclegów.
- `mart.fct_finance_monthly` – rzeczywiste koszty.
- `mart.dim_cost_category` – klasyfikacja kosztów GOP.
- `mart.dim_date` i `mart.dim_hotel` – okresy i hotele.

## Zasady biznesowe
- Okres analizy: styczeń 2024 – grudzień 2025.
- Ziarno wyniku: hotel × miesiąc.
- Przychody przypisywane do miesiąca noclegu.
- Koszty przypisywane do miesiąca finansowego.
- Uwzględniamy wyłącznie scenariusz ACTUAL.
- Kategorie INCLUDED: MAINTENANCE, PERSONNEL,
  SALES_MARKETING, UTILITIES.
- Klasyfikacja obowiązuje jednakowo we wszystkich
  8 hotelach i została zatwierdzona jako decyzja
  projektowa 27.11.2026.

## Implementacja
- `database/schema/30_us_04_04_gop_categories.sql`
  – klasyfikacja kosztów.
- `database/schema/31_us_04_04_gop_monthly_view.sql`
  – widok `mart.v_gop_monthly`.
- `tests/US-04-04_gop_tests.sql`
  – testy akceptacyjne i integralności obliczeń.

## Wyniki testów
- 192 rekordy (8 hoteli × 24 miesiące).
- Brak duplikatów.
- Brak błędnych obliczeń GOP i marży.
- GOP = 150 000 PLN, marża = 30%: PASS.
- GOP = −20 000 PLN, marża = −20%: PASS.
- Zerowe przychody, marża NULL: PASS.

## Ograniczenia
Model oblicza uproszczony GOP na danych syntetycznych.
Przychody obejmują noclegi, bez innych potencjalnych
strumieni operacyjnych (np. gastronomii).
Koszty obejmują cztery dostępne kategorie, dlatego
wynik nie stanowi pełnego księgowego GOP hotelu.

## Zależności
- US-03-07 – słownik kategorii kosztowych.
- US-03-08 – model kosztów ACTUAL/BUDGET.
- US-04-04 – implementacja wskaźników GOP.

## Uzgodnienie przychodów z PMS

Przeprowadzono kontrolę zgodności przychodów pomiędzy
`core.clean_pms_reservations`, `mart.fct_room_night`
oraz `mart.v_gop_monthly`.

Wyniki:
- Uzgodnione rezerwacje PMS: 97 249.
- Przychód PMS: 239 318 768,00 PLN.
- Przychód z noclegów: 239 318 768,00 PLN.
- Porównane kombinacje hotel × miesiąc: 192.
- Brakujące okresy: 0.
- Niezgodne okresy: 0.
- Różnica przychodów: 0,00 PLN.

Wynik: PASS.

Kontrola PMS obejmuje rezerwacje posiadające rekordy
w tabeli noclegów. Nie stanowi audytu wszystkich
rezerwacji ani niezależnej weryfikacji danych źródłowych.

Skrypt umożliwiający ponowne wykonanie kontroli:
`tests/US-04-04_revenue_reconciliation.sql`.