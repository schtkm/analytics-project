# Generator Danych Syntetycznych PMS (US-02-06)

Ten folder zawiera skrypt w języku Python służący do wygenerowania syntetycznych danych testowych dla systemu PMS (Property Management System) w formacie bazy SQLite. 

Wygenerowane dane imitują system hotelowy i zawierają ponad 50 000 rezerwacji, 8 hoteli oraz 30 miesięcy historii (w tym rezerwacje przyszłe on-the-books).

## Wymagania wstępne
Aby uruchomić skrypt, musisz posiadać na swoim komputerze:
- Zainstalowany interpreter **Python** (w wersji 3.8 lub nowszej).
- Dostęp do systemowego terminala (np. PowerShell, Wiersz poleceń lub terminal w VS Code).

## Instrukcja uruchomienia krok po kroku

**Krok 1: Otwórz terminal w folderze z projektem**
Uruchom terminal i upewnij się, że znajdujesz się tam, gdzie plik `generate_pms_data.py`.

**Krok 2: Zainstaluj wymagane biblioteki**
Skrypt do działania potrzebuje biblioteki `pandas` oraz `faker`. Wpisz w terminalu poniższą komendę i wciśnij Enter:
> pip install pandas faker

**Krok 3: Uruchom generator**
Po pomyślnej instalacji bibliotek wpisz komendę uruchamiającą skrypt:
> python generate_pms_data.py

**Krok 4: Poczekaj na wygenerowanie bazy i testy**
Skrypt wygeneruje dane i automatycznie uruchomi pakiet 14 testów walidacyjnych.

## Wynik działania skryptu
W folderze pojawi się plik bazy danych **`pms_source.db`**. Baza posiada włączone klucze obce (PRAGMA foreign_keys = ON) i zawiera 5 tabel przygotowanych pod procesy ETL:
* `pms_hotels` (hotele przypisane do województw)
* `pms_guests` (dane gości z podziałem na segmenty biznesowe/turystyczne)
* `pms_rooms` (ponad 1200 fizycznych pokoi)
* `pms_reservations` (rezerwacje z rozbiciem na zrealizowany `room_revenue` i przyszły `planned_room_revenue`)
* `pms_stays` (wyłącznie zrealizowane pobyty, wolne od zjawiska overbookingu)

## Walidacja Jakości Danych (Data Quality)
Skrypt ma wbudowany moduł testujący, który na końcu działania weryfikuje 14 twardych reguł biznesowych (m.in. bezwzględny brak nakładających się terminów dla pojedynczego pokoju, spójność dat `updated_at` względem snapshotu, prawidłowe naliczanie przychodów dla statusu "W trakcie"). 

**Uwaga o powtarzalności:** Skrypt posiada zdefiniowane stałe ziarno losowości (`SEED = 42`). Za każdym uruchomieniem wygeneruje dokładnie ten sam zbiór danych, zachowując spójność kluczy głównych. Zapewnia to stabilne środowisko do budowy docelowej hurtowni PostgreSQL.