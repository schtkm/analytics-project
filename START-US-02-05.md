# US-02-05 | Harmonogram ETL i monitoring błędów

Paczka uzupełnia repozytorium schtkm/analytics-project. Rozpakuj ją w głównym katalogu aktualnej kopii main. Wymagany jest Linux z systemd, Python 3 w projektowym .venv, skonfigurowana baza PostgreSQL i istniejąca konfiguracja US-02-02 (w tym etl/config.json). Timer działa na komputerze mającym dostęp do źródeł i tej bazy.

## Okno zasilania

Proponowany start dla PMS, Channel Managera i finansów to codziennie 04:00 czasu Europe/Warsaw. Źródła tworzą wspólną paczkę obsługiwaną przez polecenie US-02-04. Czyszczenie rusza po zakończeniu pobrania wszystkich źródeł. Godzina wymaga potwierdzenia z zespołem. Zmienia się ją w OnCalendar w pliku timer. Persistent=true nadrabia jeden opuszczony termin po uruchomieniu timera. Systemd uruchamia jedną instancję tej samej usługi. Jeśli poprzednia nadal trwa, kolejny termin nie tworzy równoległej instancji.

## Podłączenie poleceń projektu

1. Skopiuj ops/us-02-05/commands.example.json do ops/us-02-05/commands.json. Oba pola są tablicami argumentów, gdzie pierwszy element jest wykonywalnym programem. Przykładowy format polecenia modułu to [".venv/bin/python", "-m", "nazwa_modulu"]. Katalogiem roboczym jest katalog główny repozytorium.
2. W sources_incremental wpisz uzgodnione polecenie US-02-04 pobierające zmiany do staging. W refresh_mart wpisz powtarzalne polecenie odświeżenia wymiarów i faktów z bieżącej paczki. Każde polecenie musi zwrócić kod różny od zera przy awarii. Jeżeli odświeżenie wymaga kilku skryptów, użyj skryptu wykonującego je kolejno i przerywającego przy pierwszym błędzie. SQL uruchamiany przez psql wymaga ON_ERROR_STOP=1.
3. Polecenia środkowe są już podpięte do projektu. Po pobraniu danych runner wykonuje python -m etl.run_cleaning --config etl/config.json z automatyczną kontrolą core. Po udanym odświeżeniu mart wykonuje python tests/test_us_02_03_data_quality.py w domyślnym trybie all. Migracje i pierwsze zasilenie wykonuje się wcześniej zgodnie z dokumentacją projektu.
4. Na dzień 23.11.2026 US-02-04 pozostaje w realizacji. Istniejący US-03-04_load_fct_reservations.sql wymaga pustej tabeli docelowej. Uruchamianie tego skryptu codziennie zatrzymałoby kolejny przebieg. Puste pola w przykładzie powodują błąd konfiguracji przed pobraniem danych. Po awarii wcześniej zakończone kroki mogą być zapisane w bazie. Ponowne uruchomienie wymaga, by źródłowe polecenia obsługiwały powtórzenie tej samej paczki.

## Instalacja na docelowym koncie Linux

Z głównego katalogu repozytorium przygotuj jednostki użytkownika i link do projektu. Przy istniejącym linku sprawdź jego cel za pomocą readlink -f.

```bash
mkdir -p ~/.config/systemd/user ~/.config/hotelgroup-etl ~/.local/share
ln -sT "$PWD" ~/.local/share/hotelgroup-etl
install -m 644 ops/us-02-05/hotelgroup-etl.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
(umask 077 && touch ~/.config/hotelgroup-etl/alerts.env)
chmod 600 ~/.config/hotelgroup-etl/alerts.env
```

W alerts.env ustaw HOTELGROUP_ALERT_WEBHOOK na adres zatwierdzonego przez zespół webhooka HTTPS akceptującego Slack Incoming Webhook JSON z polem text. Dane dostępu do bazy ustaw zgodnie z instrukcją ETL. Usługa nie dziedziczy ustawień interaktywnego terminala. Użyj dedykowanego konta mającego dostęp do źródeł i bazy. Aby timer użytkownika działał po wylogowaniu i po restarcie hosta, administrator może wykonać loginctl enable-linger NAZWA_UZYTKOWNIKA.

## Weryfikacja i włączenie

Automatyczny test lokalny korzysta z katalogów tymczasowych, zastępczych etapów i lokalnego odbiornika HTTP. Sprawdza kolejność, zatrzymanie przy kodach 7 i 2, brak konfiguracji i odbiór treści alertu.

```bash
python3 -m unittest discover -s tests -p 'test_us_02_05_schedule.py' -v
systemd-analyze calendar --iterations=3 '*-*-* 04:00:00 Europe/Warsaw'
```

Na hoście testowym sprawdź najpierw kanał zespołu. Przy pustym commands.json z dwiema pustymi tablicami i skonfigurowanym webhooku uruchom usługę ręcznie. Oczekiwany jest status failed, komunikat na kanale z etapem configuration i zdarzenie alert_delivered z tym samym run_id. Jeśli odbiornik odrzuci żądanie, journal zawiera alert_delivery_failed. Brak skonfigurowanego adresu pozostawia zdarzenie pipeline_failed w dzienniku lokalnym.

```bash
systemctl --user start hotelgroup-etl.service
journalctl --user -u hotelgroup-etl.service -n 40 --no-pager
```

Po uzupełnieniu rzeczywistych poleceń powtórz ręczny przebieg na testowej bazie i sprawdź pipeline_completed. Następnie włącz automatyczny start na docelowym hoście.

```bash
systemctl --user enable --now hotelgroup-etl.timer
systemctl --user list-timers --all hotelgroup-etl.timer
journalctl --user -u hotelgroup-etl.service --since today --no-pager
```

Do zamknięcia karty zachowaj godzinę samoczynnego startu z list-timers i journal, identyfikator udanego przebiegu oraz potwierdzenie odbioru kontrolnego alertu przez zespół. Zatrzymanie przyszłych uruchomień wykonuje systemctl --user disable --now hotelgroup-etl.timer.
