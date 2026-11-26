# US-07-03 — Weryfikacja kompletności i wersjonowania projektu w Git

**Projekt:** HotelGroup — hurtownia danych hotelowych  
**Data przeglądu:** 26 listopada 2026 r.  
**Epika:** EPIC-07 — Dokumentacja i wdrożenie  
**Powiązanie:** NFR-04; wspierane R-01, R-02, R-03, R-07, US-02-01 i US-03-02  
**Zakres zadania po uzgodnieniach zespołu:** repozytorium z kodem ETL/ELT, SQL/DDL, testami, generatorami, konfiguracją i dokumentacją; historia commitów, gałęzie i Pull Requesty oraz kontrola danych poufnych. **Artefakty modelu BI nie wchodzą do zakresu tej historyjki.**  
**Stan dokumentu:** raport z audytu i rejestr działań końcowych; do uzupełnienia po wdrożeniu trzech korekt i połączeniu PR z `main`.

## 1. Materiał dowodowy i ograniczenia

Przegląd oparto na:

1. Archiwum `analytics-project-main(1).zip`, będącym eksportem gałęzi `main` z 26.11.2026 (120 plików; punkt odniesienia do inwentaryzacji).
2. Widokach GitHub przedstawionych podczas przeglądu gałęzi `feature/us-07-03-git-audit`, w tym zapisanych commitach korygujących dokumentację i konfigurację.
3. Historii pliku `database/schema/01_create_schemas.sql` na `main` oraz szczegółach przykładowego commitu `fdd2f0b`.
4. Zakończonym Pull Requeście [#78 — US-04-01](https://github.com/schtkm/analytics-project/pull/78), w którym potwierdzono review, kontrolę CI i połączenie z `main`.
5. Wstępnym przeglądzie plików tekstowych pod kątem wzorców poufnych danych i widoku `Security and quality` na GitHubie.

**Ograniczenia:** ZIP nie zawiera katalogu `.git`, więc nie pozwala samodzielnie przeskanować całej historycznej zawartości commitów. Wyszukiwanie kodu GitHuba zwróciło komunikat o trwającym indeksowaniu — wynik „0 files” nie był miarodajnym wynikiem kontroli. Nie wykonano kompletnego skanowania historii narzędziem do detekcji sekretów. Nie uruchomiono pełnej procedury odtwarzania hurtowni ani całości testów integracyjnych w ramach tego audytu.

## 2. Inwentaryzacja repozytorium

W archiwalnym zrzucie `main` potwierdzono:

| Obszar | Lokalizacje i przykłady | Wynik |
|---|---|---|
| ETL/ELT | `etl/`, skrypty ładowania w `database/generator/Implementacja_Generatora/` | Obecne |
| SQL/DDL | `database/schema/`, `database/migrations/`, `database/seeds/` | Obecne |
| Generatory syntetyczne | `database/generator/` — PMS, Channel Manager, finanse | Obecne |
| Testy jakości | `tests/` — testy `.py` i `.sql` | Obecne |
| CI | `.github/workflows/us-02-02.yml` | Konfiguracja obecna; nie dowodzi uruchomienia wszystkich testów projektu |
| Konfiguracja | `.env.example`, `.gitignore`, `etl/config.example.json`, pliki zależności | Obecne |
| Dokumentacja | `docs/`, pliki `START-US-02-*`, `scripts/LOCAL-SETUP.md`, `README.md` | Obecne; wykryto i poprawiono częściowo nieaktualne opisy |

Kontrola składniowa wcześniejszego zrzutu wykazała, że 20 skryptów Pythona dało się sparsować bez błędów; nie zastępuje to ich wykonania ani testów uruchomieniowych.

## 3. Weryfikacja historii zmian i procesu Pull Requestów

- Historia w GitHubie pozwala odczytać **autora, datę, identyfikator oraz zmienione pliki i linie**. Przykład: commit `fdd2f0b` autora `Mouinto` z 24.11.2026, wprowadzający trzy nowe linie do `database/schema/01_create_schemas.sql`.
- Dla PR [#78](https://github.com/schtkm/analytics-project/pull/78) potwierdzono gałąź źródłową `feature/us-04-01-occ-adr-revpar`, gałąź docelową `main`, trzy commity, trzy pliki, formalne zatwierdzenie przez `schtkm`, jeden pomyślny check i status **Merged**.
- Weryfikacja jest **reprezentatywną próbką**, nie przeglądem każdego PR w repozytorium. Przykład dowodzi, że projekt umożliwia kontrolowany proces review i odtwarzanie historii zmian.

## 4. Poprawki zapisane na gałęzi `feature/us-07-03-git-audit`

| Zmiana | Dowód | Status |
|---|---|---|
| Rozszerzenie głównego `README.md` o strukturę i instrukcje projektu | Commit `e85b6e4` | Zapisano na gałęzi roboczej |
| Uzupełnienie `.gitignore` o `backups/`, `*.backup`, `*.dump` i reguły konfiguracji | Commit `fb9b6cb` | Zapisano na gałęzi roboczej |
| Zmiana nazwy skryptu PMS `generate_pms_data` → `generate_pms_data.py` | Commit `510d070` | Zapisano na gałęzi roboczej |
| Aktualizacja komunikatu instalatora o zakresie US-03-05A/05B | Commit `448a200` | Zapisano na gałęzi roboczej |
| Korekta informacji o pliku CI i aktualizacja opisu US-02-02 | Commity `84e4db5`, `2807899` | Zapisano na gałęzi roboczej |

Nie potwierdzono jeszcze połączenia gałęzi US-07-03 z `main`. Stan commitów powyżej pochodzi ze zrzutów ekranu wykonanych podczas przeglądu.

## 5. Rejestr pozostałych niezgodności

**Ważne:** po poprawnej zmianie nazwy generatora PMS na `.py` pozostały jeszcze trzy odwołania wymagające korekty. Są to błędy ujawnione na końcowym etapie przeglądu i **muszą zostać poprawione przed uznaniem dokumentacji i odtwarzania za gotowe**.

| ID | Priorytet | Plik | Stan aktualny i konieczna poprawka |
|---|---|---|---|
| US0703-01 | Wysoki | `scripts/setup_local.ps1`, dotychczasowa linia 147 | Instalator odwołuje się do `generate_pms_data` bez rozszerzenia. Zamienić argument ścieżki na `generate_pms_data.py`. Inaczej instalator może nie odnaleźć pliku po zmianie nazwy. |
| US0703-02 | Średni | `docs/US-02-01-instrukcja-uruchomienia.md`, sekcja „Generowanie danych” | Zmienić komendę `...\\generate_pms_data` na `...\\generate_pms_data.py`. |
| US0703-03 | Średni | Główny `README.md`, sekcja „Dane syntetyczne” | Zastąpić informację, że generator PMS ma nazwę bez rozszerzenia, informacją o `generate_pms_data.py`. |

**Dokładna zmiana w `scripts/setup_local.ps1`:**

```diff
- Execute $python @((Join-Path $generatorDir 'generate_pms_data')) 'Generator PMS -> pms_source.db'
+ Execute $python @((Join-Path $generatorDir 'generate_pms_data.py')) 'Generator PMS -> pms_source.db'
```

**Dokładna zmiana w `docs/US-02-01-instrukcja-uruchomienia.md`:**

```diff
- .\.venv\Scripts\python.exe .\database\generator\generate_pms_data
+ .\.venv\Scripts\python.exe .\database\generator\generate_pms_data.py
```

**Zmiana w głównym `README.md`:** nazwę `generate_pms_data` (bez rozszerzenia) zastąpić nazwą `generate_pms_data.py`.

Po zapisaniu tych korekt należy sprawdzić, czy **nie zostały inne wykonywalne odwołania do starej ścieżki**. Nie uruchamiać skryptu z parametrem `-Reset` na bazie z danymi, które powinny być zachowane.

## 6. Kontrola danych poufnych

- Zespół przyjął zasadę: **prawdziwych haseł, tokenów i kluczy nie zapisuje się w Git**. Jest to ustalenie organizacyjne, a nie techniczny dowód braku wycieków.
- `.gitignore` na gałęzi roboczej uwzględnia lokalne pliki środowiskowe, generowane dane i kopie baz. Reguły te nie usuwają sekretów zapisanych w starych commitach.
- W przeanalizowanym zrzucie tekstowym nie znaleziono oczywistych kluczy prywatnych ani typowych prefiksów tokenów. Pliki konfiguracyjne CI zawierają jawne dane wyglądające na **testowe**; należy potwierdzić, że nie zapewniają dostępu do realnego środowiska.
- W sekcji `Security and quality` nie było dostępnej dla użytkownika sekcji alertów **Secret scanning**. `Dependabot alerts` widniało jako wyłączone, a `Code scanning alerts` jako wymagające konfiguracji. Te funkcje nie są równoważne kompletnemu skanowi historii sekretów.

**Ocena kontroli bezpieczeństwa:** wstępna kontrola wykonana i zaakceptowana przez zespół w zakresie projektu akademickiego, **bez gwarancji kompletnego wykluczenia historycznych sekretów**. W przyszłości zaleca się skan całej historii przez właściciela repozytorium oraz weryfikację, czy testowe hasła nie są używane poza CI.

## 7. Odniesienie do checklisty Trello (7 punktów)

| Nr | Zadanie | Status na 26.11.2026 | Uzasadnienie |
|---|---|---|---|
| 1 | Przejrzeć strukturę repozytorium GitHub HotelGroup | **Wykonano** | Inwentaryzacja 120 plików z przekazanego `main` |
| 2 | Potwierdzić ETL/ELT, SQL/DDL i generator | **Wykonano** | Obecność kodu i katalogów potwierdzona |
| 3 | Dokumentacja projektowa i konfiguracja | **W trakcie finalizacji** | Wprowadzono poprawki, ale po zmianie nazwy generatora zostały trzy niespójności z sekcji 5 |
| 4 | Historia commitów i identyfikowalność zmian | **Wykonano w próbie** | Historia pliku i szczegóły commitu potwierdzone |
| 5 | Zasady pracy z gałęziami i PR | **Wykonano w próbie** | PR #78: review, check, merge do `main` |
| 6 | Hasła, tokeny i poufne dane | **Zaakceptowano warunkowo** | Zasada zespołu i wstępny przegląd; skan historii nie był dostępny |
| 7 | Lista braków, uzupełnienie i gotowość przekazania | **W trakcie finalizacji** | Rejestr braków gotowy; trzy korekty i PR do `main` pozostają otwarte |

## 8. Ocena pięciu kryteriów akceptacji

| Kryterium | Wynik |
|---|---|
| 1. Artefakty kodowe i konfiguracyjne znajdują się we właściwych folderach | **Potwierdzono dla zbadanej wersji `main`**; ostatecznie do weryfikacji po aktualizacjach |
| 2. Autor, data i zakres zmian są identyfikowalne | **Potwierdzono** na wybranym commicie i historii pliku |
| 3. Skrypty SQL i ETL są wersjonowane | **Potwierdzono** obecność plików w repozytorium |
| 4. Braki są wykryte i poprawione przed przekazaniem | **Jeszcze nie w pełni** — trzy korekty ścieżki generatora i końcowy PR |
| 5. Brak rzeczywistych sekretów w konfiguracji | **Wstępnie zaakceptowano organizacyjnie**; nie potwierdzono pełnym skanem historii |

## 9. Decyzja o gotowości i zamknięciu US-07-03

**Stan na moment sporządzenia raportu:** kod i dokumentacja zostały zinwentaryzowane, proces wersjonowania oraz review potwierdzono na przykładach, a większość korekt zapisano na gałęzi `feature/us-07-03-git-audit`. **Nie deklarujemy jeszcze pełnej gotowości do przekazania** ze względu na trzy niezakończone poprawki nazw ścieżek generatora oraz brak PR łączącego audyt z `main`.

**Warunki domknięcia w Sprint 2:**

1. Poprawić trzy odwołania do generatora PMS z sekcji 5 i zapisać commity na gałęzi US-07-03.
2. Dodać niniejszy raport w `docs/US-07-03-audyt-repozytorium.md`.
3. Utworzyć PR do `main`, przeprowadzić przegląd i sprawdzić wynik kontroli CI.
4. Po akceptacji zespołu i połączeniu PR uzupełnić Trello o link do PR oraz potwierdzenie wykonanych poprawek.
5. Zachować jawne ograniczenie skanu bezpieczeństwa; pełną ponowną kontrolę repozytorium zaplanować w Sprincie 5, zgodnie z opisem User Story.

**Ocena końcowa dla projektu akademickiego:** prace audytowe w znacznej części wykonane; przekazanie do odbioru po korektach i review. Pełne bezpieczeństwo wszystkich historycznych wersji nie zostało dowiedzione i nie należy go deklarować.
