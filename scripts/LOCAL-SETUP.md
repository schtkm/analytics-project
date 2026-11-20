# HotelGroup — lokalna instalacja hurtowni danych (Windows, PostgreSQL)

## 1. Co robi automatyzacja i czego nie robi

Skrypt `scripts/setup_local.ps1` (można uruchomić z katalogu repozytorium):

1. Odczytuje lokalny `.env` i łączy się z wskazaną instancją PostgreSQL.

2. Tworzy bazę `hotelgroup_dw` oraz schematy `staging`, `core`, `mart` i ich tabele.

3. Generuje trzy lokalne źródła danych: `pms_source.db` (SQLite), `channel_manager.json`, `financial_data.csv`.

4. Importuje źródła do `staging`.

5. Uruchamia migrację, oczyszczanie i walidację US-02-02 w `core`.

6. Tworzy i zasila siedem wymiarów `mart` i tabelę faktów `mart.fct_reservations` (US-03-04 i wymiary pokoi US-03-05).

7. Uruchamia podstawowe kontrole końcowe. Końcowy komunikat `GOTOWE` oznacza, że skrypt dotarł do końca.

**Poza zakresem:** skrypt nie zasila `FactRoomNight` (`mart.fct_room_night`) ani niezależnych, późniejszych elementów projektu. To nie jest instalator wszystkich przyszłych User Stories.

## 2. Wymagania na komputerze

- **Windows** z PowerShell 5.1 lub 7.

- **Git**, **Python** (projekt pierwotnie rozwijany z Python 3.11.9) i **PostgreSQL 18** z narzędziami `psql` oraz `pg_dump`. Python musi być osiągalny przez `python`; jeśli nie ma `.venv`, skrypt utworzy ją samodzielnie.

- Dostęp do repozytorium projektu i wszystkich skryptów migracji, generatorów oraz `requirements.txt` na gałęzi zawierającej automatyzację.

- Lokalnie działający serwer PostgreSQL, znane użytkownikowi hasło, uprawnienia do **tworzenia baz** (np. lokalny `postgres`).

- Wolne miejsce na dane źródłowe, bazę i ewentualne kopie zapasowe.

W PowerShell sprawdź (nie wymagają połączenia z bazą):

```powershell

python --version

git --version

Test-Path .\scripts\setup_local.ps1

Test-Path .\.env.example

```

`Test-Path` powinien zwrócić `True`. Jeśli skryptu nie ma — przełącz się na właściwą gałąź lub pobierz najnowsze zmiany zespołu. **Nie kopiuj przypadkowego pliku z innej wersji repozytorium.**

## 3. Pobranie projektu

Jeżeli projekt nie jest jeszcze lokalny:

```powershell

git clone https://github.com/schtkm/analytics-project.git

cd analytics-project

```

Jeżeli już jest: otwórz folder projektu w VS Code, następnie użyj terminala **PowerShell**. Potwierdź, że pracujesz na wersji zawierającej `scripts/setup_local.ps1` i `scripts/LOCAL-SETUP.md`. W razie braku plików sprawdź gałąź/PR u prowadzącego implementację, zanim zaczniesz.

## 4. Konfiguracja `.env` — indywidualna dla każdej osoby

**Nie uruchamiaj instalatora bez sprawdzenia serwera docelowego.** W katalogu głównym projektu utwórz `.env` na podstawie `.env.example`:

```powershell

if (-not (Test-Path .env)) { Copy-Item .env.example .env }

```

Edytuj własny `.env` lokalnie:

```dotenv

PG_HOST=localhost

PG_PORT=5432

PG_DATABASE=hotelgroup_dw

PG_USER=postgres

PG_PASSWORD=WPISZ_TUTAJ_WLASNE_HASLO

```

- `PG_PORT=5432` to zwyczajowy port standardowej lokalnej instalacji. Jeśli Twoja instancja nasłuchuje na innym porcie (np. `5433`), wpisz **swój rzeczywisty port**.

- `PG_DATABASE` musi mieć dokładnie wartość `hotelgroup_dw`.

- Skrypt dopuszcza tylko lokalne `PG_HOST` (`localhost`, `127.0.0.1`, `::1`).

- Wpisz hasło do **tego konkretnego serwera PostgreSQL**. Nigdy nie wklejaj go do czatu AI, zrzutów ekranu, commita ani Pull Requesta.

- Jeśli plik `.env` już istnieje i dotyczy ważnego środowiska, **nie nadpisuj go**. Wybierz bezpieczną strategię razem z opiekunem technicznym.

- `.env` oraz lokalne kopie konfiguracji muszą być ignorowane przez Git; przed commitem sprawdź `git status` i `.gitignore`.

Dla kontroli połączenia bez ujawniania hasła uruchom (podając swój port i użytkownika):

```powershell

& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "SELECT current_user, current_setting('port') AS port;"

```

Jeśli narzędzia `psql` nie ma pod tą ścieżką, sprawdź katalog swojej instalacji PostgreSQL. Test połączenia nie tworzy bazy.

## 5. Pierwsze uruchomienie (zalecane)

**Najpierw upewnij się, że na wybranym porcie nie ma już bazy `hotelgroup_dw` z potrzebnymi danymi.** Można to sprawdzić w pgAdmin lub SQL:

```sql

SELECT datname FROM pg_database WHERE datname = 'hotelgroup_dw';

```

Jeśli wynik to **0 wierszy**, z katalogu głównego repozytorium uruchom:

```powershell

.\scripts\setup_local.ps1

```

Skrypt instaluje zależności do `.venv` (jeśli potrzeba), generuje dane, tworzy bazę i wykonuje ETL. Czekaj na końcowy komunikat `GOTOWE: hotelgroup_dw` — nie oceniaj wyniku po samym komunikacie `CREATE DATABASE`.

Jeśli PowerShell blokuje uruchomienie skryptu, sprawdź obowiązującą politykę i — **tylko w uzasadnionym przypadku, dla zaufanego skryptu** — ustaw wyłącznie dla bieżącej sesji:

```powershell

Set-ExecutionPolicy -Scope Process Bypass

```

Następnie ponów polecenie. Nie zmieniaj polityki globalnie i nie omijaj zabezpieczeń na komputerze firmowym/uczelnianym bez zgody administratora.

## 6. Istniejąca baza i opcje dodatkowe — przeczytaj przed użyciem

**Bez `-Reset` skrypt zatrzymuje się, gdy baza `hotelgroup_dw` już istnieje. To celowe zabezpieczenie.** Nie próbuj „naprawiać” tego błędu przez natychmiastowy reset.

\| Polecenie | Co robi | Kiedy używać |

\|---|---|---|

\| `.\scripts\setup_local.ps1` | Nowa instalacja, nie nadpisuje istniejącej bazy | Domyślna i zalecana opcja |

\| `.\scripts\setup_local.ps1 -SkipInstall` | Pomija `pip install` | Gdy `.venv` i zależności już działają |

\| `.\scripts\setup_local.ps1 -Reset` | Tworzy backup, usuwa istniejącą bazę i odbudowuje ją | **Wyłącznie po świadomym potwierdzeniu utraty danych w docelowej bazie** |

\| `.\scripts\setup_local.ps1 -Reset -ReuseGenerated` | Reset bazy, ale wykorzystuje istniejące lokalne SQLite/JSON/CSV | Tylko gdy te pliki są kompletne i właściwe |

\| `.\scripts\setup_local.ps1 -CoreOnly` | Nowa instalacja tylko przez warstwy staging i core | Przy pracy wyłącznie nad US-02-02; nie tworzy załadowanej tabeli faktów |

W trybie `-Reset` skrypt zapisuje kopię w `backups/` i wymaga wpisania `USUN hotelgroup_dw`. **Backup nie jest gwarancją bezproblemowego przywrócenia.** Nie używaj `-Reset` na bazie współdzielonej ani na bazie, której utrata byłaby problemem. Jeśli reset nie powiedzie się po usunięciu bazy, konieczne może być ręczne odzyskiwanie z backupu.

**Ważne:** generator danych zapisuje pliki do `database/generator/` i może je nadpisać. Jeżeli ktoś zmodyfikował tam własne dane, powinien je wcześniej zachować.

## 7. Kontrola działania w pgAdmin 4

Uruchom pgAdmin 4 i wybierz **właściwy serwer/port** oraz bazę **`hotelgroup_dw`**. Samo podobieństwo nazw baz nie wystarcza: np. `hotelgroup_dw_us0304_test` to inna baza.

Kliknij prawym na bazę → **Query Tool**, potem wykonaj:

```sql

SELECT current_database() AS baza,

       inet_server_port() AS port,

       (SELECT count(*) FROM staging.pms_reservations) AS staging,

       (SELECT count(*) FROM core.clean_pms_reservations) AS core,

       (SELECT count(*) FROM mart.fct_reservations) AS mart;

```

W **potwierdzonym teście integracyjnym z 20.11.2026**, na odrębnej instancji `5433`, otrzymano:

\| Baza | Port testu | Staging | Core | Mart |

\|---|---:|---:|---:|---:|

\| `hotelgroup_dw` | `5433` | 140875 | 140847 | 140847 |

To **wynik referencyjny z tego testu**, nie uniwersalna obietnica identycznych liczb przy każdej regeneracji danych; generatory mogą wprowadzać zmienność. Poprawność ustalaj także na podstawie logów, kompletności wymiarów, braku duplikatów i relacji.

Dodatkowy szybki test duplikatów/anulacji:

```sql

SELECT count(*) AS rezerwacje,

       count(DISTINCT reservation_bk) AS unikalne,

       count(*) - count(DISTINCT reservation_bk) AS duplikaty,

       sum(cancellation_count) AS anulacje

FROM mart.fct_reservations;

```

W testowanym przebiegu wynik wyniósł `140847 / 140847 / 0 / 13903`. **Identyfikator w `mart` nazywa się `reservation_bk`, nie `reservation_id`.**

Jeżeli w repozytorium jest skrypt `HotelGroup_audyt_zbiorczy.sql`, można uruchomić go w Query Tool, aby otrzymać zbiorcze kontrole PASS/FAIL/INFO. W teście z 20.11.2026 uzyskano **37 PASS, 0 FAIL i 1 INFO** (`FactRoomNight` poza automatyzacją). Jeśli skryptu audytu nie ma w repozytorium, nie zakładaj, że jest dostępny na komputerze każdego członka zespołu.

## 8. Typowe problemy

\| Objaw | Co sprawdzić |

\|---|---|

\| `Test-Path .\scripts\setup_local.ps1` → `False` | Zła gałąź Git, stara wersja repozytorium, uruchomienie poza katalogiem projektu |

\| `relacja staging.pms_reservations nie istnieje` | Czy w pgAdmin wybrano właściwą bazę **i port**? Czy instalator ukończył etap schematów? |

\| `password authentication failed` / brak połączenia | Czy PostgreSQL działa? Poprawny port, użytkownik i hasło właściwej instancji |

\| „Baza już istnieje” | To bezpieczny stop. **Nie uruchamiaj `-Reset` bez oceny konsekwencji.** Możesz zamiast tego utworzyć oddzielną instancję developerską |

\| Błąd składni PowerShell | Sprawdź, czy używasz aktualnej, przetestowanej wersji `scripts/setup_local.ps1`; nie kopiuj starej paczki |

\| `No module named ...` | Sprawdź `.venv`, Python i zależności; normalnie instalator uruchamia `pip install -r requirements.txt` |

\| ETL `completed_with_rejections` | To dopuszczalny status, **jeśli** odrzucenia wynikają z reguł walidacji i kontrola końcowa przechodzi |

\| Błąd podczas SQL / importu | Zachowaj komunikaty od ostatniego `==>`; nie uruchamiaj kolejnych migracji ręcznie na ślepo |

## 9. Zasady bezpieczeństwa i informacji do zespołu

- Wszystkie komendy `SELECT` są tylko do odczytu. Skrypt instalacyjny **tworzy i zapisuje dane** w bazie wskazanej przez `.env`.

- **Nie udostępniaj pliku `.env` ani haseł**; przesyłaj wyłącznie nazwy zmiennych i niesekretne wartości (`PG_HOST`, `PG_PORT`, `PG_DATABASE`, `PG_USER`).

- Nie commituj `.env`, `.env.test`, `.env.backup`, `etl/config.json`, baz SQLite, wygenerowanych JSON/CSV ani plików z `backups/`.

- Jeżeli poprzedni przebieg utworzył już bazę i potem się zatrzymał, kolejny przebieg bez `-Reset` może odmówić działania. **Nie kasuj jej automatycznie**; najpierw ustal stan i sposób odzyskania.

- `mart.fct_reservations` może być załadowana mimo braku `FactRoomNight` — to odrębny zakres funkcjonalny.

- Raportuj zespołowi: wersję/gałąź Git, system, wersję Pythona, PostgreSQL i port, ostatni etap `==>`, komunikat błędu oraz wynik SQL (bez haseł).

## 10. Potwierdzenie testu integracyjnego

**20.11.2026:** przeprowadzono pełną instalację od zera na osobnej instancji PostgreSQL 18.7 (`localhost:5433`), podczas gdy podstawowa instancja działała na `5432`. Generator PMS: 140875 rezerwacji; po oczyszczeniu 140847; tabela `mart.fct_reservations`: 140847; anulacje: 13903. Kontrola zbiorcza zwróciła **37 PASS, 0 FAIL, 1 INFO**. Oryginalny plik `.env` został po teście przywrócony. W trakcie testów poprawiono błędy składni PowerShell i obsługę pustego wyniku zapytania o istnienie bazy; **do repozytorium należy wysłać poprawioną lokalną wersję skryptu**, a nie pierwotny plik z paczki.