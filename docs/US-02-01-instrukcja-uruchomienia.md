# US-02-01 – Instrukcja uruchomienia integracji danych HotelGroup

## 1. Cel

Dokument opisuje odtworzenie lokalnego procesu zasilania hurtowni PostgreSQL z trzech źródeł:

- PMS – SQLite.
- Channel Manager – JSON.
- System finansowy – CSV.

Proces realizuje podejście ELT. Dane źródłowe są ładowane do schematu `staging`, bez zaawansowanych transformacji biznesowych.

## 2. Wymagania środowiskowe

- Python 3.11.9.
- PostgreSQL – lokalna instancja (środowisko testowe: PostgreSQL 18).
- Git.
- Biblioteki Python wymienione w `requirements.txt`.

## 3. Przygotowanie środowiska

Sklonować repozytorium GitHub i przejść do jego katalogu głównego.

Utworzyć środowisko wirtualne:

```powershell
python -m venv .venv
```

Zainstalować zależności:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Skopiować `.env.example` do `.env` i uzupełnić własne hasło PostgreSQL.

Plik `.env` nie jest wersjonowany w Git.

## 4. Przygotowanie PostgreSQL

Utworzyć lokalną bazę danych:

`hotelgroup_dw`

Odtworzyć struktury bazy za pomocą obowiązujących skryptów SQL z repozytorium.

Przed importem muszą istnieć schematy `staging`, `core`, `mart` oraz odpowiednie tabele staging:

- `pms_hotels`
- `pms_guests`
- `pms_rooms`
- `pms_reservations`
- `pms_stays`
- `cm_channels`
- `fin_budgets_costs`

Skrypty SQL należy uruchamiać zgodnie z uzgodnioną kolejnością migracji. Utworzenie samej bazy nie tworzy automatycznie tabel.

## 5. Generowanie danych

Wszystkie polecenia wykonywać z głównego katalogu repozytorium.

### PMS – SQLite

```powershell
.\.venv\Scripts\python.exe .\database\generator\generate_pms_data.py
```

Wynik: `database/generator/pms_source.db`.

### Channel Manager – JSON

```powershell
.\.venv\Scripts\python.exe .\database\generator\generate_channel_manager.py
```

Wynik: `database/generator/channel_manager.json`.

### System finansowy – CSV

```powershell
.\.venv\Scripts\python.exe .\database\generator\generate_financial_data.py
```

Wynik: `database/generator/financial_data.csv`.

Generatory wykorzystują stałe ziarno losowości `SEED = 42`. Odtwarzalność identycznych danych wymaga zachowania tej samej wersji generatorów, konfiguracji i zależności.

## 6. Ładowanie do PostgreSQL

Import PMS:

```powershell
.\.venv\Scripts\python.exe .\database\generator\Implementacja_Generatora\load_staging_pms.py
```

Import Channel Managera:

```powershell
.\.venv\Scripts\python.exe .\database\generator\Implementacja_Generatora\load_staging_channel_manager.py
```

Import danych finansowych:

```powershell
.\.venv\Scripts\python.exe .\database\generator\Implementacja_Generatora\load_staging_financial.py
```

Każdy import stosuje pełne odświeżenie odpowiednich tabel staging w transakcji PostgreSQL. Proces nie realizuje ładowania przyrostowego.

## 7. Weryfikacja danych

Po zakończeniu importu należy sprawdzić liczby rekordów i poprawność identyfikatorów źródłowych.

W testowanym środowisku uzyskano:

| Źródło | Tabela | Rekordy |
|---|---|---:|
| PMS | pms_hotels | 8 |
| PMS | pms_guests | 20 000 |
| PMS | pms_rooms | 1 240 |
| PMS | pms_reservations | 140 875 |
| PMS | pms_stays | 97 413 |
| Channel Manager | cm_channels | 140 875 |
| Finanse | fin_budgets_costs | 960 |

Łącznie: **401 371 rekordów**.

Zweryfikowano również brak niepowiązanych identyfikatorów Channel Managera i danych finansowych oraz brak duplikatów według przyjętych kluczy.

## 8. Ponowne uruchomienie i błędy

Procesy importu można uruchamiać ponownie. W przeprowadzonych testach ponowne ładowanie zakończyło się bez błędów i nie zwiększyło liczby rekordów.

W przypadku nieprawidłowej kwoty w pliku finansowym skrypt zgłasza błąd i nie rozpoczyna zapisu do PostgreSQL.

Transakcyjne wycofywanie zmian jest zaimplementowane, natomiast test błędu występującego w trakcie transakcji wymaga osobnego potwierdzenia.

## 9. Ograniczenia

- Dane mają charakter syntetyczny.
- Ładowanie przyrostowe nie jest realizowane w ramach tej implementacji.
- Zaawansowane czyszczenie, deduplikacja, normalizacja dat i walut oraz rejestr odrzuconych rekordów należą do US-02-02.
- Skrypty wymagają istniejącej struktury tabel zgodnej z US-03-02.
- Weryfikacja odtworzenia środowiska od zera przez innego członka zespołu pozostaje do wykonania.

## 10. Powiązania

- User Story: US-02-01.
- Epika: EPIC-02 – Pozyskiwanie i integracja danych.
- Wymagania: R-01, NFR-04; wspierane NFR-05.
- Zależności: US-02-06, US-02-07, US-03-01, US-03-02.
