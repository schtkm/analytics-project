# Rejestr decyzji architektonicznych HotelGroup

Data przeglądu: 2026-11-04. Zadanie: **US-07-02 | Skompletowanie dokumentacji decyzji architektonicznych ADR**.

## Rejestr

| ID | Temat | Zadanie | Status dokumentu |
|---|---|---|---|
| [ADR-001](ADR-001-platform.md) | Platforma PostgreSQL | US-03-01 | W pliku Accepted; sprzeczne zapisy o oczekiwaniu na akceptację wymagają uporządkowania |
| [ADR-002](ADR-002-etl-storage.md) | ELT i staging/core/mart | US-03-01 | Proposed |
| [ADR-003](ADR-003-bi.md) | Power BI i odpowiedzialność warstwy analitycznej | US-07-02 | Proposed; narzędzie potwierdzone przez użytkownika, treść do przeglądu |
| [ADR-004](ADR-004-versioning.md) | Git i historia artefaktów oraz decyzji | US-07-02 | Proposed |

Łącznie: cztery rekordy, w tym dwa dotychczasowe i dwa nowe. Nie oznacza to czterech formalnie zatwierdzonych decyzji. Niniejszy pakiet dodaje ADR-003, ADR-004 i rejestr do istniejącego katalogu; nie powiela plików ADR-001 i ADR-002. Po dodaniu plików do istniejącego repozytorium odnośniki do tych rekordów powinny prowadzić do oryginałów.

## Granice decyzji

- ADR-001: wybór platformy bazy danych.
- ADR-002: ELT, podział pracy Python/SQL i warstwy przechowywania.
- ADR-003: narzędzie BI oraz odpowiedzialność modelu semantycznego i raportów.
- ADR-004: wersjonowanie i zachowanie historii rozwiązania.

Nie wydzielono osobnego ADR tylko dla wyboru Pythona, ponieważ opisano go już w ADR-002. Unikamy sztucznego dzielenia jednej decyzji w celu osiągnięcia wymaganej liczby.

## Wynik przeglądu źródeł

Przeczytano przekazane ADR-001-platform.md, ADR-002-etl-storage.md, data-sources.md oraz opisy US-03-01 i US-07-02. Oba istniejące ADR zawierają kontekst, opcje, decyzję i konsekwencje. Nie zweryfikowano aktualnej gałęzi repozytorium ani faktycznej implementacji.

| Dokument | Ustalenie | Dalsza czynność |
|---|---|---|
| ADR-001 | Metadane i sekcja 7: Accepted; sekcja 4: proponowana decyzja; sekcja 7: wymaga zatwierdzenia i zmiany na Accepted | Autor potwierdza akceptację. Jeśli nastąpiła: ujednolicić tekst jako podjętą decyzję, dopisać prawdziwą datę i odnośnik. Jeśli nie: skorygować status na Proposed |
| ADR-002 | Spójnie Proposed; wskazane ELT i jedna baza z trzema schematami | Potwierdzić akceptację szczegółów; deklaracja stosowania technologii nie zastępuje zatwierdzenia całego ADR |
| data-sources.md | Technologie ETL/ELT i BI nadal „Do ustalenia” | Uzupełnić o Python + SQL, PostgreSQL i Power BI zgodnie z przekazaną informacją |
| data-sources.md i backlog ETL | Rejestr proponuje PMS, Channel Manager i finanse; backlog integracji wskazuje również POS | Uzgodnić docelowy zestaw źródeł i kolejność integracji; nie uznawać finansów za automatyczny zamiennik POS |
| data-sources.md | Formaty i identyfikatory pozostają niepotwierdzone | Uzgodnić kontrakty z autorami integracji; wybór stosu nie potwierdza kontraktów danych |
| Dokumenty wymienione w ADR-002 | storage-layers.md, data-flow.md i diagramy C4 nie zostały dostarczone do tego przeglądu | Sprawdzić ich zgodność i odnośniki w repozytorium |

Powyższe uwagi nie oznaczają automatycznej zmiany dokumentów autorów. Są listą konkretnych korekt do wspólnego PR.

## Zasady utrzymania

Stosujemy numerację ADR-001, ADR-002 itd., nazwy `ADR-NNN-krotki-temat.md`, statusy Proposed / Accepted / Rejected / Superseded. Nie zmieniamy numerów dotychczasowych dokumentów. Dokładny cykl życia opisuje ADR-004; do akceptacji pozostaje propozycją procedury zespołu.

Nowy ADR zawiera: ID, datę, status, powiązaną historyjkę, kontekst, alternatywy, decyzję, konsekwencje, działania oraz historię. Po akceptacji uzupełnia się datę i dowód decyzji. Merytoryczne zastąpienie decyzji zapisuje się w nowym rekordzie z linkami w obu kierunkach. Commit i PR wyjaśniają przyczynę zmiany.

## Kryteria akceptacji US-07-02

| Kryterium | Ocena na etapie przygotowania pakietu |
|---|---|
| Minimum 4 ADR dotyczące kluczowych decyzji | Cztery rekordy po połączeniu dwóch istniejących z dwoma nowymi; zatwierdzenie propozycji pozostaje otwarte |
| Kontekst, opcje, decyzja, konsekwencje | Obecne w obu źródłowych i obu nowych rekordach |
| Brak duplikowania US-03-01 | Zachowano ADR-001 i ADR-002 jako oryginalne rekordy; nowe mają odrębne tematy |
| Odtwarzalna historia zmiany w repozytorium | Procedura opisana; publikacja PR i rzeczywista historia Git wymagają wykonania w repozytorium |

## Lista zadań – rzetelny status

| Zadanie z karty | Status |
|---|---|
| Przejrzeć dotychczasowe decyzje architektoniczne i dokumentację z US-03-01 | Częściowo: przekazane ADR i rejestr źródeł przeczytano; brak pozostałych dokumentów architektury |
| Zweryfikować kompletność istniejących rekordów ADR i ustalić brakujące obszary | Wykonano dla przekazanych ADR; uwagi powyżej |
| Uzgodnić z zespołem kluczowe decyzje wymagające dodatkowego udokumentowania | Do wykonania przez zespół; przygotowano propozycje |
| Przygotować lub uzupełnić rekordy ADR do wymaganej liczby minimum czterech | Przygotowano: 2 istniejące + 2 nowe |
| Sprawdzić, czy każdy ADR zawiera kontekst, rozważane opcje, decyzję i konsekwencje | Wykonano dla 4 dokumentów |
| Zweryfikować zgodność dokumentów ADR z przyjętą architekturą i zastosowanymi technologiami | Zgodność ze wskazanym stosem sprawdzona; implementacja i brakujące dokumenty do weryfikacji |
| Uporządkować numerację, nazewnictwo i statusy dokumentów ADR | Rejestr przygotowany; sprzeczny status ADR-001 do rozstrzygnięcia z autorem |
| Zapisać kompletny rejestr ADR w Git i udostępnić go zespołowi | Do wykonania; pakiet przygotowany do PR |


