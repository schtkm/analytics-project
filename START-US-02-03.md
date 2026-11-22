# US-02-03 — Automatyczne testy jakości danych (Instrukcja uruchomienia)



Moduł dodaje automatyczną bramkę jakości danych (**Data Quality Gate**) weryfikującą **10 reguł (`DQ-01` – `DQ-10`)** przed propagacją danych do warstwy analitycznej (`mart`) oraz zapisującą wyniki każdego uruchomienia w tabeli audytowej `core.dq_test_log`.



---



## Wymagania wstępne



1. Odtworzona struktura bazy danych `hotelgroup_dw` (schematy `staging`, `core`, `mart`).

2. Wdrożona migracja z zadania `US-02-02` (`database/schema/02_etl_cleaning.sql`) oraz załadowane dane źródłowe do schematu `staging` (`US-02-01`).

3. Uzupełniony plik `.env` w katalogu głównym repozytorium (utworzony na bazie `.env.example`):



```env

PG_HOST=localhost

PG_PORT=5432

PG_DATABASE=hotelgroup_dw

PG_USER=postgres

PG_PASSWORD=twoje_haslo

```



4. Zainstalowane zależności z plików `requirements.txt` oraz `etl/requirements.txt` (`psycopg[binary]`, `python-dotenv`, `pytest`).



---



## Kolejność kroków do wykonania lokalnie



### Krok 1: Uruchomienie migracji SQL w bazie danych



Otwórz w **pgAdmin 4** (narzędzie *Query Tool* na bazie `hotelgroup_dw`) plik:



```text

database/migrations/US-02-03_dq_test_log.sql

```



Wykonaj skrypt, aby utworzyć tabelę `core.dq_test_log` wraz z indeksami.



---



### Krok 2: Uruchomienie potoku ETL z wbudowaną bramką jakości



Upewnij się, że w folderze `etl/` istnieje plik `etl/config.json` (skopiowany z `etl/config.example.json` z uzupełnioną sekcją `"source_currencies"`), a następnie uruchom w głównym katalogu projektu:



```powershell

python -m etl.run_cleaning --config etl/config.json

```



Po zakończeniu czyszczenia danych automatycznie uruchomi się walidacja `US-02-03`:

* Jeśli wszystkie 10 reguł zakończy się statusem **`PASS`**, proces zwróci kod wyjścia `0`.

* Jeśli którakolwiek reguła o krytyczności `CRITICAL` wykryje naruszenia, proces zatrzyma się ze statusem **`FAIL`**, zwróci kod wyjścia `2` i wstrzyma dalszą propagację danych.



---



### Krok 3: Niezależne uruchomienie samych testów (opcjonalnie / CI)



Testy jakości danych można uruchomić również samodzielnie — bezpośrednio z wiersza poleceń lub za pomocą `pytest`:



```powershell

python tests/test_us_02_03_data_quality.py

```



lub:



```powershell

pytest tests/test_us_02_03_data_quality.py -v

```



---



### Krok 4: Weryfikacja logów audytowych w PostgreSQL



Aby sprawdzić historię uruchomień testów oraz liczbę wykrytych naruszeń w bazie danych, wykonaj w pgAdminie:



```sql

SELECT *

FROM core.dq_test_log

ORDER BY log_id DESC

LIMIT 10;

```
