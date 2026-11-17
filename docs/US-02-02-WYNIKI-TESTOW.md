# US-02-02 — wynik weryfikacji (17.11.2026)

## Wykonane

- Python 3.12: 27 testów jednostkowych/reguł zakończonych powodzeniem.
- Kompilacja składni `etl` i `tests`: powodzenie.
- `pip check`: brak uszkodzonych zależności w użytym środowisku.
- Próba wolumenowa funkcji transformującej: 50 000 rezerwacji + 50 000 prowizji +
  4 rekordy referencyjne/finansowe, łącznie 100 004 wiersze; wszystkie przyjęte,
  rozliczenie liczby i sum poprawne; 4,74 s na tym środowisku.
  To czas transformacji w pamięci, nie pełnego importu/zapisu PostgreSQL.
- Silnik PostgreSQL 16.2 w trybie standalone (`--single`): zastosowanie migracji,
  ponowne zastosowanie tej samej migracji, utworzenie wszystkich siedmiu tabel,
  zapis znormalizowanych danych z testowej paczki, sprawdzenie daty i kwoty,
  zapis dwóch odrzuceń (duplikat i błędna data), kontrola rollbacku DELETE.
  Końcowe potwierdzenie: `US0202_SQL_CHECK_OK`; brak ERROR/FATAL w udanym przebiegu.

W testowej paczce rezerwacji podano trzy rekordy: poprawny, jego duplikat i rekord
z datą `31.02.2026`. Wynik: jedna poprawna rezerwacja, dwa wpisy logu;
kwota w bazie 1234,50 i data przyjazdu 2026-11-17.

## Niewykonane / wymagające uruchomienia u użytkownika

- Siedem testów `tests/test_postgres.py` oznaczono SKIPPED — środowisko nie pozwala
  otworzyć gniazda serwera PostgreSQL (PermissionError). Nie wykonano więc pełnej
  ścieżki `psycopg -> run() -> PostgreSQL` przez połączenie klient-serwer.
- Osobny test SQL na rzeczywistym silniku nie zastępuje tych siedmiu testów.
- PostgreSQL 18: przewidziany w pliku CI, ale tutaj nieuruchomiony.
- Uruchomienie migracji i transformacji na lokalnej bazie użytkownika.
- Potwierdzenie walut źródeł i zgodności rzeczywistej struktury staging.
- Pełne uzgodnienie źródła z modelem mart dla NFR-02.
- PR, GitHub Actions, code review — nie wykonano zmian na GitHubie zgodnie z poleceniem.

Łączny wynik `unittest discover`: 34 testy znalezione, **27 PASS, 7 SKIPPED**.
Nie przedstawiać tego wyniku jako 34 zaliczonych testów ani zakończonego CI/CD.

## Zakres siedmiu testów integracyjnych

1. Cały przepływ, odrzucenia i ponowienie bez duplikacji wyników.
2. Błąd podczas publikacji, rollback wszystkich tabel i trwały status failed.
3. Puste źródło nie usuwa starego wyniku.
4. Całkowicie odrzucona paczka jest logowana bez publikacji.
5. Migracja danych z dotychczasowych typów DATE/NUMERIC i powtórzenie migracji.
6. Jawna kolumna waluty ma pierwszeństwo przed konfiguracją źródła.
7. Brak wymaganej kolumny blokuje przetwarzanie przed zmianami wyniku.

Instrukcja uruchomienia: `docs/US-02-02-README.md`.
