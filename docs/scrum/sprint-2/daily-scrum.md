# Daily #1
**J.M.:**
Jestem w trakcie robienia US-03-07

**K.S:**
Hej
Zakończyłem implementację US-02-01, integrując trzy źródła danych z PostgreSQL (401 371 rekordów). Przeprowadziłem testy i przygotowałem dokumentację. Dodatkowo usunąłem hasło zapisane bezpośrednio w kodzie - wszystkie importery korzystają teraz z lokalnego pliku .env, który nie trafia na GitHub. Dodałem .env.example dla zespołu. Utworzyłem PR.
Rozpocząłem również US-03-04. Przygotowałem dokumentację modelu mart.fct_reservations, obejmującą strukturę tabeli, ziarno, statusy, daty, relacje z wymiarami, miary finansowe oraz plan testów. Zmiany znajdują się w osobnym PR.
Dalej: implementacja SQL i testy US-03-04 po weryfikacji zależności z modelem zespołu.
Blockery: Brak technicznych. Oczekuję na Code Review oraz uzgodnienie waluty, mapowania kanałów i rekordów technicznych DimDate.

**G.Z.:**
Jestem w trakcie działań nad
US-02-02 | Czyszczenie, walidacja danych i obsługa błędów w procesie ETL
nie mam uwag

**S.G.:**
Przegląd zmian w plikach na githubie i ich akceptacja, czekam na wykonanie pierwszych backlogów abym mógł ruszyć ze swoimi, więcej uwag nie mam

**K.K:**
Jestem w trakcie US-03-05A | Zamodelowanie pokojonocy. Nie napotkałem żadnych problemów.

# Daily #2
**J.M.:**
Juz prawie skończyłem US-03-07 i zbierać sie bede za kolejne zadanie.

**K.S:**
W ramach US-03-04 przygotowałem migrację SQL rozszerzającą tabelę faktów rezerwacji i anulacji. Utworzyłem osobną bazę testową PostgreSQL i pomyślnie przeprowadziłem testy migracji, sprawdzając m.in. poprawność struktury, unikalność rezerwacji, walidację statusów, liczniki anulacji, ograniczenia finansowe i klucze obce. Potwierdziłem również możliwość wielokrotnego uruchamiania migracji bez błędów. Dodatkowo zatwierdziłem PLN jako walutę bazową projektu i uwzględniłem tę decyzję w dokumentacji. Na ten moment lokalne testy są zakończone, a do pełnego zamknięcia US-03-04 pozostaje weryfikacja rzeczywistych danych i powiązań po zakończeniu US-02-02 oraz zasileniu wymiarów.

**G.Z.:**
Jestem w trakcie weryfikowania możliwości wykonania US-02-05

**S.G.:**
Nie mam obecnie uwag czekam dalej

**K.K:**
Nie mam żadnych uwag

# Daily #3
**J.M.:**
Na ten moment nie mam uwag

**K.S:**
Na ten moment nie mam uwag

**G.Z.:**
Na ten moment nie mam uwag, czekam na Gnarcotic

**S.G.:**
Wykonywałem ostatnio US-02-03 (Automatyczne testy jakości danych):
Zaimplementowałem 10 reguł jakości (DQ-01–DQ-10) w tests/test_us_02_03_data_quality.py, migrację tabeli audytowej core.dq_test_log (database/migrations/US-02-03_dq_test_log.sql) oraz bramkę walidacyjną w etl/run_cleaning.py.
Przetestowałem cały potok lokalnie na pełnym zbiorze danych ze wszystkich trzech źródeł (PMS, Channel Manager, Finanse).
Wdrożyłem poprawki po Code Review od Grześka na PR #64: tryb fail-closed przy brakujących lub pustych tabelach, spójne zapisywanie statusu blocked w core.etl_runs i JSON, podział reguł na etapy core (DQ-01–DQ-08) i mart (DQ-09–DQ-10) oraz testy jednostkowe w unittest pod CI.
Zmiany zostały wypchnięte na gałąź feature/US-02-03-data-quality-tests i czekają na ponowne zatwierdzenie.

**K.K:**
Ukończono:
US-03-05A – model i zasilenie tabeli mart.fct_room_night (rzeczywiste pokojonoce, rozbicie pobytów na przełomie miesięcy, flagi przyjazdu i wyjazdu),
US-03-05B – model i zasilenie tabeli mart.fct_room_inventory (dzienna dostępność pokoi, obsługa Out of Order pod mianownik OCC, pokrycie horyzontu 7/30/90 dni oraz wykrywanie overbookingu).
Do obu zadań dodałem migracje DDL, skrypty ETL, dokumentację w docs/ oraz testy akceptacyjne i DQ (wszystkie przechodzą na PASS). Pliki są na Githubie.

# Daily #4
**J.M.:**
Jestem w trakcie robienia zadania US-04-01 | Obliczanie OCC, ADR i RevPAR

**K.S:**
Brak uwag czekam na zakończenie prac

**G.Z.:**
Brak uwag czekam na zakończenie prac

**S.G.:**
Dokończyłem swoje prace a wczoraj przeprowadziliśmy zmiany w paru skryptach w razem z Kamilem i Grześkiem by były zgodnie z wymaganiami w backlogu
Obecnie czekam na zakończenie reszty prac

**K.K:**
Nie mam żadnych uwag.
