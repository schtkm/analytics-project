# HotelGroup — hurtownia danych hotelowych

Projekt akademicki realizowany w Scrum. Obejmuje syntetyczne źródła **PMS (SQLite)**, **Channel Manager (JSON)** oraz **finansów (CSV)**, procesy ETL/ELT (Python i SQL), hurtownię **PostgreSQL** (`staging`, `core`, `mart`) i dokumentację analityczną.

## Struktura repozytorium

| Katalog | Zawartość |
|---|---|
| `database/generator/` | Generatory danych syntetycznych i programy importujące dane do staging |
| `database/schema/` | Definicje SQL/DDL i widoki |
| `database/migrations/` | Migracje zmian struktur |
| `database/seeds/` | Zasilanie wymiarów i faktów |
| `etl/` | Ładowanie, oczyszczanie, walidacja i ładowanie przyrostowe |
| `tests/` | Testy Python i SQL |
| `ops/` | Harmonogram, monitorowanie i zadania operacyjne ETL |
| `docs/` | Dokumentacja analiz, architektury, Scrum i modeli |
| `scripts/` | Lokalny instalator i jego instrukcja |
| `.github/workflows/` | Konfiguracja kontroli CI |

## Uruchomienie lokalne

Pełna instrukcja: [scripts/LOCAL-SETUP.md](scripts/LOCAL-SETUP.md). Przed uruchomieniem **sprawdź, czy w PostgreSQL nie ma już ważnej bazy `hotelgroup_dw`**. Skrypt jest przeznaczony do kontrolowanego odtwarzania środowiska, a jego opcja `-Reset` może usunąć dotychczasową bazę po utworzeniu kopii zapasowej. Nie uruchamiaj go bez przeglądu instrukcji.

Podstawowa procedura dla **nowego, pustego środowiska**:

1. Zainstaluj wymagane wersje Pythona i PostgreSQL opisane w instrukcji.
2. Skopiuj `.env.example` do lokalnego `.env` i wpisz własne dane dostępowe. Nie dodawaj `.env` do repozytorium.
3. Przeczytaj [scripts/LOCAL-SETUP.md](scripts/LOCAL-SETUP.md) i dopiero wtedy uruchom podane tam polecenia w PowerShell.

**Zakres instalatora:** `scripts/setup_local.ps1` odtwarza podstawowy przepływ źródła → staging → core oraz wybrane elementy `mart`. Nie uruchamia automatycznie zasilania wszystkich późniejszych modeli, w tym US-03-05A/05B, ani wszystkich widoków KPI US-04-01. Te elementy wymagają osobnego wdrożenia i weryfikacji.

## Dane syntetyczne

- PMS: [database/generator/Readme.md](database/generator/Readme.md) — plik wykonywalny Pythona nazywa się **`generate_pms_data` (bez rozszerzenia)**.
- Pozostałe źródła: `database/generator/generate_channel_manager.py` oraz `database/generator/generate_financial_data.py`.
- Import do staging: `database/generator/Implementacja_Generatora/`.

Wygenerowane pliki z danymi nie są źródłowym kodem projektu; w razie potrzeby należy odtworzyć je generatorem.

## Testy i dokumentacja

- Testy Python: `python -m pytest tests -v` **po skonfigurowaniu zależności i wymaganego środowiska testowego**; część testów potrzebuje PostgreSQL.
- Testy SQL: `tests/*.sql`. Przed wykonaniem sprawdź zależności konkretnego skryptu, wymagane tabele i docelową bazę.
- CI: `.github/workflows/us-02-02.yml` — jego obecność nie oznacza, że wszystkie testy i wszystkie User Stories są uruchamiane w CI.
- Architektura: [docs/architecture/](docs/architecture/), w tym [rejestr ADR](docs/architecture/adr/README.md).
- Modele pokojonocy i dostępności: `docs/US-03-05A-model-fact-room-night.md` oraz `docs/US-03-05B-model-fact-room-inventory.md`.
- Miary OCC, ADR i RevPAR: [docs/US-04-01_OCC_ADR_RevPAR.md](docs/US-04-01_OCC_ADR_RevPAR.md).
- Przegląd wersjonowania: [docs/US-07-03-audyt-repozytorium.md](docs/US-07-03-audyt-repozytorium.md).

## Zmiany i bezpieczeństwo

Pracuj na gałęziach funkcjonalnych; przygotuj Pull Request do `main` i pozostaw historię autorów oraz opis zmian. Zasady architektoniczne są opisane w [ADR-004](docs/architecture/adr/ADR-004-versioning.md), który w analizowanym eksporcie ma status `Proposed`.

Nie dodawaj prawdziwych haseł, tokenów, `.env`, kopii baz, plików `.backup`, wygenerowanych danych źródłowych ani innych poufnych danych. `.gitignore` ogranicza ryzyko przypadkowego dodania plików, ale **nie zastępuje kontroli commitów i historii repozytorium**.
