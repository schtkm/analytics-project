# US-02-05 | Harmonogram potoku ETL i monitoring błędów

Każdy członek zespołu korzysta z własnej lokalnej bazy testowej PostgreSQL. Potok można uruchamiać ręcznie lub codziennie o 04:00 czasu polskiego. Do demonstracji harmonogramu wystarczy jedno stanowisko. Webhook jest opcjonalny.

Potok wykonuje kolejno import PMS, Channel Managera i finansów, czyszczenie `core`, odświeżenie `mart` i pełną kontrolę jakości. Awaria kończy przebieg kodem różnym od zera i zatrzymuje dalsze etapy. Zakończone wcześniej etapy mogą mieć już zatwierdzone zmiany w bazie.

## 1. Przygotowanie wspólne

1. Pobierz wersję repozytorium zawierającą US-02-05 oraz poprawkę DQ-09 z `main`. Na gałęzi US-02-05 przed scaleniem uwzględnij aktualne zmiany z `main`, w tym skrypty US-03-05B. [Repozytorium projektu](https://github.com/schtkm/analytics-project)
2. Skonfiguruj lokalną bazę `hotelgroup_dw` oraz pliki `.env` i `etl/config.json` zgodnie z instrukcją US-02-02. Sprawdź, czy wszystkie skrypty łączą się z tą samą bazą. [Instrukcja US-02-02](https://github.com/schtkm/analytics-project/blob/main/START-US-02-02.md)
3. Umieść pliki z jednego zestawu danych w `database/generator/`: `pms_source.db`, `channel_manager.json` i `financial_data.csv`.
4. Przygotuj schemat bazowy hurtowni, `staging` i warstwę czyszczenia `core`. Przed uruchomieniem potoku zastosuj poniższe migracje na lokalnej bazie testowej. Jeśli baza była już używana, sprawdź, które migracje zostały wcześniej wykonane. [Migracje projektu](https://github.com/schtkm/analytics-project/tree/main/database/migrations)

| Kolejność | Skrypt SQL | Cel |
| --- | --- | --- |
| 1 | `database/migrations/US-02-03_dq_test_log.sql` | Dziennik kontroli jakości |
| 2 | `database/migrations/US-02-04_incremental_load.sql` | Znaczniki i klucze importu przyrostowego |
| 3 | `database/migrations/US-03-04_dim_date_unknown.sql` | Techniczne klucze dat |
| 4 | `database/migrations/US-03-05A_fct_room_night_migration.sql` | Schemat pokojonocy |
| 5 | `database/migrations/US-03-05B_fct_room_inventory_migration.sql` | Schemat dostępności pokoi |
| 6 | `database/migrations/US-02-05_reservation_bk.sql` | Unikalny klucz biznesowy rezerwacji |

Jeśli używasz starszego schematu, sprawdź również, czy `mart.fct_reservations` zawiera sześć kolumn wymaganych przez model US-03-04. Brakujące kolumny uzupełnij przed uruchomieniem ETL, zgodnie z modelem projektu. [Model rezerwacji US-03-04](https://github.com/schtkm/analytics-project/blob/main/docs/US-03-04-model-fact-reservation.md)

| Kolumna | Typ |
| --- | --- |
| `reservation_count` | `SMALLINT NOT NULL DEFAULT 1` |
| `cancellation_count` | `SMALLINT NOT NULL DEFAULT 0` |
| `room_revenue` | `NUMERIC(18,2)` |
| `cancellation_fee` | `NUMERIC(18,2)` |
| `commission_amount` | `NUMERIC(18,2)` |
| `currency_code` | `CHAR(3)` |

### Konfiguracja poleceń potoku

Utwórz `ops/us-02-05/commands.json` w kodowaniu UTF-8 bez BOM. Przykładowy plik w repozytorium zawiera puste tablice.

```json
{
  "sources_incremental": [
    "PYTHON_VENV",
    "-c",
    "import subprocess, sys\nfrom pathlib import Path\nbase = Path('database/generator/Implementacja_Generatora')\nfor name in ('pms', 'channel_manager', 'financial'):\n    result = subprocess.run([sys.executable, str(base / f'load_staging_{name}.py')])\n    if result.returncode:\n        sys.exit(result.returncode)"
  ],
  "refresh_mart": [
    "PYTHON_VENV",
    "ops/us-02-05/refresh_mart.py",
    "--apply"
  ]
}
```

Zastąp oba wpisy `PYTHON_VENV` ścieżką dla swojego systemu.

| System | Wartość w JSON |
| --- | --- |
| Linux | `.venv/bin/python` |
| Windows | `.venv/Scripts/python.exe` |

## 2. Linux

Użyj terminala systemowego i przejdź do głównego katalogu repozytorium. Jeśli masz działające `.venv` utworzone na tym samym hoście, pomiń jego tworzenie.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -u ops/us-02-05/pipeline.py
echo "Kod wyjścia: $?"
```

Jeśli widzisz `pipeline_completed` i kod `0`, zainstaluj usługę i timer użytkownika.

```bash
mkdir -p ~/.config/systemd/user ~/.local/share
ln -sT "$PWD" ~/.local/share/hotelgroup-etl
install -m 644 ops/us-02-05/hotelgroup-etl.service \
  ops/us-02-05/hotelgroup-etl.timer ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user start hotelgroup-etl.service
journalctl --user -u hotelgroup-etl.service -n 50 --no-pager
```

Jeśli link już istnieje, sprawdź jego cel poleceniem `readlink -f ~/.local/share/hotelgroup-etl`. Pomiń `ln`, jeśli link wskazuje na właściwy katalog. Po udanej próbie usługi włącz harmonogram.

```bash
systemctl --user enable --now hotelgroup-etl.timer
systemctl --user list-timers --all hotelgroup-etl.timer
```

Plik timera używa strefy `Europe/Warsaw`. Przy `Persistent=true` timer może nadrobić opuszczony termin po włączeniu. Jeśli ma działać także po wylogowaniu, administrator może włączyć tryb linger dla tego konta poleceniem `sudo loginctl enable-linger "$USER"`. Zatrzymasz przyszłe uruchomienia poleceniem `systemctl --user disable --now hotelgroup-etl.timer`.

## 3. Windows

Otwórz PowerShell w głównym katalogu repozytorium. Jeśli masz już działające środowisko utworzone w Windowsie, pomiń jego tworzenie.

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -u ops/us-02-05/pipeline.py
$LASTEXITCODE
```

Po uzyskaniu `pipeline_completed` i kodu `0` zapisz w głównym katalogu repozytorium plik `run-hotelgroup-etl.cmd`.

```bat
@echo off
cd /d "%~dp0" || exit /b 1
if not exist "logs" mkdir "logs"
".venv\Scripts\python.exe" -u "ops\us-02-05\pipeline.py" >> "logs\hotelgroup-etl.log" 2>&1
exit /b %ERRORLEVEL%
```

Zarejestruj zadanie dla bieżącego użytkownika i uruchom próbę.

```powershell
$repo = (Get-Location).Path
$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\cmd.exe" `
    -Argument '/d /c run-hotelgroup-etl.cmd' `
    -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -Daily -At '04:00'
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive

Register-ScheduledTask -TaskName 'HotelGroup ETL' `
    -Action $action -Trigger $trigger -Principal $principal
Start-ScheduledTask -TaskName 'HotelGroup ETL'
```

Zadanie w tej konfiguracji wymaga zalogowanego użytkownika. Godzina 04:00 odnosi się do lokalnego czasu Windowsa. Ustaw polską strefę czasową, jeśli zadanie ma startować o 04:00 czasu polskiego. [Dokumentacja Harmonogramu zadań](https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtasktrigger)

Po zakończeniu próby sprawdź datę ostatniego wykonania, kod `LastTaskResult` i log.

```powershell
Get-ScheduledTaskInfo -TaskName 'HotelGroup ETL' |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
Get-Content .\logs\hotelgroup-etl.log -Tail 30
```

Sukces oznacza `LastTaskResult = 0` oraz `pipeline_completed` w aktualnym przebiegu. Wyłączysz przyszłe uruchomienia poleceniem `Disable-ScheduledTask -TaskName 'HotelGroup ETL'`.

## 4. Logi, kontrola błędów i alerty

- `pipeline_completed` oznacza, że potok przeszedł wszystkie etapy. Przy poprawnym pełnym przebiegu kontrola końcowa obejmuje DQ-01–DQ-10.
- `pipeline_failed` zawiera nazwę etapu, kod wyjścia i identyfikator przebiegu `run_id`. Szczegółów szukaj w poprzedzających wpisach tego przebiegu.
- `alert_delivered` oznacza, że odbiornik webhooka zaakceptował żądanie. `alert_delivery_failed` wskazuje problem z dostarczeniem.
- Bez podanego webhooka potok zapisuje wyniki w dzienniku systemowym na Linuksie albo w pliku `logs/hotelgroup-etl.log` na Windowsie.

Jeśli chcesz otrzymywać powiadomienia, użyj odbiornika HTTPS obsługującego JSON z polem `text`, np. Slack Incoming Webhook. Na Linuksie wpisz `HOTELGROUP_ALERT_WEBHOOK='adres webhooka'` do lokalnego pliku `~/.config/hotelgroup-etl/alerts.env` i ustaw uprawnienia `chmod 600`. Na Windowsie ustaw `HOTELGROUP_ALERT_WEBHOOK` jako zmienną środowiskową konta uruchamiającego zadanie i zaloguj się ponownie przed próbą. Adres webhooka, plik `.env` oraz logi przechowuj lokalnie.

Do testu awarii bez zmian w bazie możesz wskazać jednorazowo nieistniejący plik konfiguracji. Oczekiwany wynik to `pipeline_failed` na etapie `configuration` i kod różny od zera. Jeśli webhook jest skonfigurowany w środowisku tego uruchomienia, próba wyśle alert.

```bash
HOTELGROUP_PLAN=ops/us-02-05/missing-test-plan.json \
  .venv/bin/python -u ops/us-02-05/pipeline.py
echo "Kod wyjścia: $?"
```

```powershell
$previousPlan = $env:HOTELGROUP_PLAN
try {
    $env:HOTELGROUP_PLAN = 'ops/us-02-05/missing-test-plan.json'
    .\.venv\Scripts\python.exe -u ops/us-02-05/pipeline.py
    "Kod wyjścia: $LASTEXITCODE"
} finally {
    $env:HOTELGROUP_PLAN = $previousPlan
}
```

## 5. Wynik weryfikacji

Pełny automatyczny przebieg został sprawdzony na Linuksie z lokalną bazą testową. Wszystkie reguły DQ-01–DQ-10 zakończyły się wynikiem PASS. Osobno potwierdzono zapis awarii oraz odbiór alertu przez lokalny odbiornik webhooka. Wariant z Harmonogramem zadań wymaga próby na stanowisku z Windowsem.
