# US-02-02 — Czyszczenie, walidacja i obsługa błędów ETL

## Status i podstawa implementacji

Przygotowano kod, migrację, testy i instrukcję do lokalnego PostgreSQL.
Nie wprowadzono zmian do GitHuba ani do bazy użytkownika. Nie wystawiono PR i nie uruchomiono GitHub Actions.

Kontrakt wejściowy pochodzi z `schtkm/analytics-project`, PR #54 (US-02-01),
commit `5de61e1921a46f49c745567b7220beb01783af0f`, odczyt 17.11.2026.
Źródła: `database/Skrypty_do_odtworzenia_bazy.sql`, generatory i importery trzech źródeł.
Stary `database/schema/01_create_schemas.sql` zawiera inny, niepełny wariant rezerwacji
(`total_amount` zamiast `room_revenue` i brak części tabel). Nie jest wystarczającą podstawą do tej implementacji.
Migracja nie próbuje zgadywać mapowania między tymi wariantami: zgłasza brakujące kolumny.

US-02-01 ma w eksporcie Trello status Review/Test, a PR #54 jest otwarty.
Do uruchomienia pełnego procesu potrzebne są jego struktury i załadowane trzy źródła.
Kod można przeglądać i testować niezależnie od zamknięcia tamtego PR.

## Co jest w paczce

| Plik | Funkcja |
|---|---|
| `etl/cleaning.py` | Reguły, deduplikacja, relacje, rozliczenie rekordów i kwot |
| `etl/run_cleaning.py` | Transakcyjny zapis na lokalnym PostgreSQL i rejestr przebiegów |
| `etl/check_staging.py` | Odczyt struktury staging; bez zmian i bez danych osobowych |
| `etl/config.example.json` | Strefa czasowa i jawna konfiguracja waluty źródeł |
| `etl/.env.example` | Wzór lokalnego połączenia |
| `etl/requirements.txt` | Osobne zależności tej funkcjonalności |
| `database/schema/02_etl_cleaning.sql` | Migracja staging i utworzenie tabel wyniku oraz logów |
| `database/schema/03_verify_cleaning.sql` | Zapytania sprawdzające wynik |
| `tests/test_cleaning.py` | Testy reguł bez bazy |
| `tests/test_postgres.py` | Testy integracyjne wyłącznie w odrębnej bazie testowej |
| `.github/workflows/us-02-02.yml` | Przygotowany plik CI — nieopublikowany |
| `docs/US-02-02-WYNIKI-TESTOW.md` | Rzeczywiście wykonane testy i ograniczenia |

## Wspólny standard i reguły

### Daty i czas

- Daty dzienne mają typ PostgreSQL `DATE`; wymiana/wyświetlanie ISO `YYYY-MM-DD`.
- Wejście: `YYYY-MM-DD`, `DD.MM.YYYY`, `YYYY/MM/DD`, `DD/MM/YYYY`.
  Zapis z ukośnikiem zaczynający się od dnia jest zawsze DMY, nigdy amerykańskim MDY.
- Niepoprawne daty kalendarzowe są odrzucane. Nie ma automatycznej korekty na kolejny miesiąc.
- `month_id`: `YYYY-MM`, `MM.YYYY`, `MM/YYYY` lub pełna data pierwszego dnia miesiąca;
  wynik to `DATE` pierwszego dnia miesiąca. Nie obcina się dowolnej daty do miesiąca.
- `updated_at`: wejście ISO datetime; wynik `TIMESTAMPTZ` w UTC.
  Czas bez offsetu interpretuje się według `source_timezone` (przykład: `Europe/Warsaw`).
  Niejednoznaczna lub nieistniejąca godzina przy zmianie czasu jest odrzucana;
  jawny offset usuwa niejednoznaczność. Strefa dotyczy znacznika czasu, nie dat pobytu.
- Rezerwacja: `booking_date <= check_in_date < check_out_date`.
- Pobyt: `actual_check_out >= actual_check_in`; NULL wymeldowania dozwolony dla otwartego pobytu.

### Kwoty i waluty

- Kwoty: `Decimal` w Pythonie, `NUMERIC(12,2)` w bazie, bez obliczeń na float.
- Obsługiwane formaty to m.in. `1234.50`, `1234,50`, `1 234,50`, `1.234,50`, `1,234.50`.
  Spacja tysięcy musi tworzyć grupy po trzy cyfry; obsługiwane są również spacje niełamliwe.
- Dodatkowe miejsca dziesiętne, NaN, Infinity, ujemne wartości i niejednoznaczny zapis
  `1.234`/`1,234` są odrzucane. Brak zaokrąglania źródła w ciszy.
  Zakres: od 0 do 9 999 999 999,99. Ujemne korekty wymagają odrębnego kontraktu;
  obecne generatory US-02-01 dostarczają nieujemne przychody/prowizje/koszty.
- `commission_rate` jest ułamkiem 0–1, np. `0.15`, a nie `15`; do czterech miejsc dziesiętnych.
- Waluty: kody ISO `PLN`, `EUR`, `USD`, `GBP`, `CHF`, `CZK`, wielkie litery.
  Aliasami są `zł`/`zl`, `€`, `£`. Sam `$` jest niejednoznaczny i zostaje odrzucony.
- Kwota może mieć zgodny przedrostek/przyrostek waluty, np. `1234,50 zł` przy walucie PLN.
  Niezgodność kwoty i kolumny waluty powoduje odrzucenie.
- W źródłach PR #54 **nie ma kolumny waluty**. Nie wywnioskowano jej z lokalizacji hoteli.
  W takim przypadku operator musi jawnie wpisać kod dla każdej tabeli finansowej w konfiguracji.
  Brak konfiguracji powoduje odrzucenia i blokadę publikacji pustego wyniku.
- Jeśli źródło ma kolumnę `currency`, używana jest jej wartość. Puste pole w istniejącej
  kolumnie nie jest zastępowane domyślną walutą — trafia do logu.
- Nie przelicza się EUR na PLN. Nie ma zatwierdzonej tabeli kursów, daty kursu ani reguły przeliczeń.
  Wszystkie waluty mają wspólny **format**, a sumy pozostają rozdzielone według waluty.
  Jest to zgodne z T-04-NFR-13 z dostarczonych kart EPIC-04: różne waluty agreguje się
  dopiero po zatwierdzonym przeliczeniu.

### Braki i klucze

Spacje na brzegach są usuwane, pusty tekst staje się NULL. Zera w identyfikatorach,
np. numer pokoju `001`, pozostają zachowane. Tekst nie jest globalnie zamieniany na wielkie litery.
Klucze, daty i kwoty nie są zastępowane zerem ani sztucznym identyfikatorem.

| Tabela staging | Klucz biznesowy | Pola wymagane |
|---|---|---|
| pms_hotels | hotel_id | hotel_id, hotel_name |
| pms_guests | guest_id | guest_id |
| pms_rooms | room_id | room_id, hotel_id, room_number, room_type |
| pms_reservations | reservation_id | Wszystkie pola kontraktu, w tym waluta z danych lub konfiguracji |
| pms_stays | stay_id | Wszystkie poza actual_check_out |
| cm_channels | reservation_id | Wszystkie, w tym waluta |
| fin_budgets_costs | hotel_id + month_id + cost_category | Wszystkie, w tym waluta |

Dane opisowe hotelu/gościa mogą pozostać NULL. Walidacja kontaktów, OCC i pełny zestaw
biznesowych reguł jakości z US-02-03 nie są zastępowane przez tę historię.

### Duplikaty i relacje

- Identyczne po normalizacji rekordy o tym samym kluczu: pozostaje jeden.
- Metadane importu (`_inserted_at`) nie wpływają na wykrywanie duplikatów.
- Różne poprawne rekordy z tym samym kluczem: **wszystkie** wersje są odrzucane jako
  `CONFLICTING_BUSINESS_KEY`. Brak zatwierdzonej reguły wybierania najnowszej wersji.
- Błędny rekord z tym samym kluczem nie usuwa poprawnej wersji; jest osobno odrzucany.
- Duplikaty są usuwane z wyniku, a nie ze staging. Mają osobny wynik `duplicate` w logu.
- Rodzice sprawdzani są względem zaakceptowanego bieżącego zbioru, nie starego core.
- Sprawdzane są relacje hotel/pokój/gość/rezerwacja/pobyt/CM/finanse,
  zgodność hotelu pokoju z rezerwacją i zgodność gościa/pokoju pobytu z rezerwacją.
- Nie usuwa się danych między różnymi tabelami: rezerwacja PMS i jej prowizja CM to różne fakty.

## Warstwa wynikowa i ochrona istniejącego modelu

Oczyszczone dane trafiają do siedmiu tabel `core.clean_<nazwa_tabeli_staging>`:
`clean_pms_hotels`, `clean_pms_guests`, `clean_pms_rooms`, `clean_pms_reservations`,
`clean_pms_stays`, `clean_cm_channels`, `clean_fin_budgets_costs`.
Mają typy dat/kwot, klucze główne i obce oraz `_etl_run_id`.

W repozytorium występują niespójne definicje `core.reservations` oraz powtórzone
CREATE TABLE dla hoteli i gości. Dlatego ta migracja udostępnia jednoznaczne tabele
oczyszczone i nie nadpisuje istniejącego `core.hotels/core.reservations` ani `mart`.
Dalsze zasilanie modelu wymiarowego powinno czytać nowe `core.clean_*`.
Nie jest to gotowe zasilenie faktów/wymiarów ani podmiana źródła obecnych raportów.

Źródła staging pozostają w całości. Migracja zmienia tylko ich kolumny dat, czasu,
kwot, stawki i miesiąca na TEXT, aby mogły przechować niepoprawną wartość do walidacji.
Istniejące poprawne wartości są zachowywane w postaci tekstowej. Migracja nie odzyska
wartości już wcześniej odrzuconych/zaokrąglonych przez importer lub typ NUMERIC.
Nie dodaje pustej kolumny waluty do źródeł bez takiej informacji.

**Wpływ na inne zadania:** zapytania czytające daty/kwoty bezpośrednio ze staging będą
musiały używać `core.clean_*` albo jawnych rzutowań. Nie uruchamiać migracji podczas importu.
Zmiany importerów odrzucających błędy jeszcze przed staging wymagają osobnej integracji
z US-02-01; ta implementacja realizuje scenariusz „dane znajdują się w staging”.

## Log i przebiegi

- `core.etl_runs`: UUID przebiegu, start/koniec, konfiguracja bez hasła, status, raport,
  kod błędu technicznego. Przebieg zapisuje się przed transformacją.
- `core.etl_rejected_records`: przebieg, tabela, pozycja w odczytanym snapshotcie,
  klucz biznesowy, SHA-256, surowy rekord JSONB, lista pól i kodów błędów, czas.
- `source_row` jest identyfikatorem w ramach danego przebiegu, nie trwałym numerem
  wiersza w pliku źródłowym. Hash i zapis raw pomagają porównać kolejne przebiegi.
- Log zawiera również duplikaty. Każdy wiersz ma dokładnie jedną klasyfikację.
- Przebiegi i odrzucenia są historią: ponowienie może dodać drugi log tego samego błędu,
  ale nie dubluje oczyszczonych rekordów. Nowy `_etl_run_id` dokumentuje odświeżenie.
- Surowy log może zawierać dane osobowe gości. Nie udostępniać go roli raportowej ani w PR.
  Migracja odbiera prawa PUBLIC; uprawnienia nadane wcześniej konkretnym rolom oraz
  zasady retencji muszą zostać sprawdzone przez administratora lokalnej bazy.

Całość publikacji siedmiu tabel jest jedną transakcją. Błąd zapisu cofa wszystkie zmiany
tej publikacji; status `failed` zostaje zapisany osobno. Błąd techniczny przed commit
cofa także odrzucenia tej próby. Zatrzymanie procesu/utrata połączenia może pozostawić
`running`, co wymaga sprawdzenia operatora.

Przebieg blokuje równoległe transformacje advisory lockiem oraz blokuje zapis do
wszystkich tabel staging na czas odczytu/przetwarzania. Domyślnie 30 s oczekiwania
na blokadę. Importy trzech źródeł trzeba zakończyć przed startem ETL — istniejące
importery nie mają wspólnego batch_id, więc ETL nie potwierdzi sam spójności wersji importu.

Pełne odświeżenie usuwa poprzedni wynik `core.clean_*`, a potem wstawia nowy w tej
samej transakcji. Pusta/całkowicie odrzucona tabela inna niż `pms_stays` blokuje publikację
całej paczki (`blocked`), zachowując wcześniejszy wynik i logując odrzucenia.
Przy częściowych odrzuceniach poprawne rekordy są publikowane (`completed_with_rejections`).
Tej warstwy nie należy rozszerzać zewnętrznymi FK bez dostosowania strategii odświeżania.

## Uzgodnienie finansowe i NFR-02

Raport liczy dla każdej tabeli wejście = przyjęte + duplikaty + odrzucone.
Dla każdej kwoty i waluty rozlicza identyczny podział sum. Nieparsowalne kwoty lub
nieznane waluty są jawnie wykazane jako `unparseable_amounts`, nie jako zero.
Po zapisie sprawdzana jest niezależnie liczba rekordów i suma kwot w PostgreSQL
względem zaakceptowanych rekordów; wymagane jest dokładne uzgodnienie (silniejsze od 0,1%).

Usunięte duplikaty i odrzucenia mogą prawidłowo powodować różnicę między surową sumą
staging a sumą core. Raport pokazuje jej składniki. Nie oznacza to automatycznie
zaliczenia NFR-02 dla całego systemu źródłowego i mart. Końcowe porównanie wymaga tego
samego zakresu, waluty i zasad ujęcia; próg wynosi 0,1%, a dla źródła zero — zgodność do zera.

## Uruchomienie na Windows / PowerShell

1. Rozpakować zawartość paczki do głównego katalogu lokalnego projektu (z katalogami
   `etl`, `tests`, `database`, `docs`). Paczka nie zastępuje kodu generatorów/importerów.
2. W katalogu projektu utworzyć środowisko i zainstalować zależności:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r etl/requirements.txt
```

3. Użyć istniejącego `.env` z US-02-01 albo skopiować `etl/.env.example` do `.env`
   w katalogu projektu. Uzupełnić własne dane PostgreSQL; nie wysyłać pliku `.env`.
4. **Najpierw odczyt bez zmian:**

```powershell
.\.venv\Scripts\python.exe -m etl.check_staging
```

Jeżeli pojawia się `missing_required_columns`, nie uruchamiać migracji: potrzebny
jest wynik tego polecenia i struktury z US-02-01. Ten raport nie drukuje rekordów ani hasła.
5. Skopiować `etl/config.example.json` do `etl/config.json`. Potwierdzić walutę
   źródeł i strefę. Przykład **wyłącznie jeżeli wszystkie źródła są w PLN**:

```json
{
  "source_timezone": "Europe/Warsaw",
  "source_currencies": {
    "pms_reservations": "PLN",
    "cm_channels": "PLN",
    "fin_budgets_costs": "PLN"
  }
}
```

6. Po sprawdzeniu struktury wykonać lokalny backup bazy w pgAdmin. Zakończyć importy.
   Zastosować migrację (to polecenie zmienia lokalną bazę, ale jeszcze nie uruchamia ETL):

```powershell
.\.venv\Scripts\python.exe -m etl.run_cleaning --config etl/config.json --migrate
```

7. Uruchomić transformację i ponowić ją w celu sprawdzenia powtarzalności:

```powershell
.\.venv\Scripts\python.exe -m etl.run_cleaning --config etl/config.json
```

8. W pgAdmin wykonać `database/schema/03_verify_cleaning.sql`.
   `completed`/`completed_with_rejections` = opublikowano, `blocked` = wynik zachowany,
   `failed` = błąd techniczny i rollback. Kod wyjścia CLI: odpowiednio 0, 2 i 1.
   Kod 0 z odrzuceniami nie znaczy „brak problemów jakości”.

Linux: te same polecenia z `.venv/bin/python` zamiast `.venv\Scripts\python.exe`.
Nie ma potrzeby udostępniania bazy przez internet.

## Testy lokalne i CI

Bez bazy:

```powershell
.\.venv\Scripts\python.exe -m unittest tests.test_cleaning -v
```

Do testów integracyjnych w pgAdmin utworzyć **osobną, pustą bazę** `hotelgroup_etl_test`.
Testy usuwają w niej schematy `staging` i `core`; nigdy nie wskazywać właściwej bazy projektu.
Kod dodatkowo odmawia działania, gdy nazwa bazy nie kończy się `_etl_test`.

```powershell
$env:ETL_TEST_DATABASE_URL = 'postgresql://postgres:TWOJE_HASLO@localhost:5432/hotelgroup_etl_test'
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
Remove-Item Env:ETL_TEST_DATABASE_URL
```

W URL znaki specjalne hasła wymagają kodowania URL. Testy są niezależne od `ETL_DATABASE_URL`.
Bez `ETL_TEST_DATABASE_URL` siedem testów integracyjnych jest oznaczonych SKIPPED;
nie traktować takiego wyniku jako potwierdzenia integracji.
Plik GitHub Actions uruchamia oba zestawy na PostgreSQL 18, ale w tej pracy nie został
wysłany do repozytorium ani wykonany.

## Checklista i co pozostaje do zamknięcia historii

| Pozycja | Status |
|---|---|
| Reguły dat i walut | Zaimplementowane i opisane; trzeba potwierdzić walutę historycznych źródeł |
| Deduplikacja | Zaimplementowana, testy reguł zaliczone |
| Tabela odrzucenia | Migracja i zapis przygotowane, silnik PostgreSQL sprawdzony lokalnie |
| Walidacja kluczowych kolumn | Zaimplementowana, kontrola kontraktu i testy |
| PR i CI/CD | Plik CI przygotowany; PR nieutworzony zgodnie z poleceniem użytkownika |
| Uruchomienie na bazie użytkownika | Do wykonania po kontroli struktury |
| Code Review / Done | Do wykonania przez zespół po testach lokalnych i późniejszym PR |

Do domknięcia potrzeba: potwierdzenia walut i strefy, zgodnej struktury staging,
wyniku siedmiu testów integracyjnych oraz uruchomienia na lokalnych danych.
Brak któregokolwiek źródła US-02-01 blokuje pełną integrację. Nie oznaczać zadania Done
wyłącznie na podstawie tej paczki.
