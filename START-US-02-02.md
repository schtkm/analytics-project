# US-02-02 — zacznij tutaj

Dokument opisuje uruchomienie funkcjonalności US-02-02 w lokalnym środowisku HotelGroup. Pliki źródłowe są wersjonowane w repozytorium GitHub. Uruchomienie migracji i procesów ETL może wprowadzać zmiany w lokalnej bazie PostgreSQL.

1. Rozpakuj pliki do głównego katalogu projektu, zachowując strukturę katalogów.
2. Otwórz **docs/US-02-02-README.md** — zawiera zasady i dokładne polecenia.
3. Zainstaluj zależności z `etl/requirements.txt` i ustaw lokalne połączenie w `.env`.
4. Uruchom `python -m etl.check_staging` — odczyt bez zmian w bazie.
5. Potwierdź waluty źródeł. Przykładowa konfiguracja nie zakłada PLN automatycznie.
6. Następnie wykonaj migrację i ETL według instrukcji.

Weryfikacja: **27 testów zaliczonych**, migracja i zapis sprawdzone silnikiem
PostgreSQL. **7 testów połączenia klient-serwer pozostaje do uruchomienia lokalnie.**
Pełny opis: `docs/US-02-02-WYNIKI-TESTOW.md`.

Istotne: migracja zmienia typy dat/kwot w staging na TEXT. Dane oczyszczone mają
właściwe typy w nowych tabelach `core.clean_*`. Istniejący core i mart nie są nadpisywane.
Plik CI znajduje się obecnie w .github/workflows/us-02-02.yml. Wynik jego uruchomienia należy sprawdzić w zakładce GitHub Actions dla właściwego commitu; sama obecność pliku nie potwierdza zaliczenia testów.
