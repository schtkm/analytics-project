# ADR-004 – Wersjonowanie artefaktów i historii decyzji w Git

| Pole | Wartość |
|---|---|
| Data opracowania | 2026-11-04 |
| Status | Proposed – do uzgodnienia z zespołem |
| Zadanie | US-07-02 |
| Epika | EPIC-07 – Dokumentacja i wdrożenie |
| Powiązania | NFR-04, NFR-05, US-03-01, ADR-001, ADR-002, ADR-003 |

## Kontekst

Projekt obejmuje kod Python i SQL, model hurtowni, materiały Power BI oraz dokumentację. Zespół potrzebuje identyfikowalnej wersji rozwiązania oraz historii uzasadnień. US-07-02 wymaga odtworzenia zmian decyzji w repozytorium, a NFR-04 dotyczy wersjonowania kodu i artefaktów BI. Użycie Git wynika z wymagań; szczegóły poniższej organizacji są propozycją do akceptacji.

## Rozważane opcje

| Opcja | Zalety | Ograniczenia |
|---|---|---|
| Git: kod i dokumentacja tekstowa oraz tekstowa reprezentacja projektu BI | Powiązane zmiany, przegląd różnic i odtworzenie historii | Wymaga dyscypliny przeglądu oraz sprawdzenia sposobu zapisu BI |
| Git: kod i dokumentacja, BI wyłącznie jako plik binarny | Prostsze przekazywanie pojedynczego pliku BI | Utrudniona ocena zmian miar i modelu; niewystarczające wobec oczekiwania tekstowego wersjonowania BI |
| Rozproszone foldery i załączniki | Łatwe udostępnianie pojedynczych dokumentów | Trudność ustalenia obowiązującej wersji i związku dokumentacji z kodem |

## Proponowana decyzja

Git stanowi źródło obowiązujących wersji kodu i dokumentacji. Zmiany są przeglądane przez pull request i powiązane z identyfikatorem User Story.

- Kod Python, SQL, konfiguracja przykładowa i instrukcja odtworzenia są wersjonowane w repozytorium.
- ADR są plikami Markdown w `docs/architecture/adr/`, ze wspólnym rejestrem `README.md`.
- Dla Power BI należy utrzymywać tekstową reprezentację projektu/modelu (PBIP/TMDL zgodnie z wymaganiem NFR-04), po sprawdzeniu jej obsługi w przyjętym środowisku. Sam plik PBIX nie zastępuje tekstowej historii modelu. Konkretną organizację plików uzgadnia osoba odpowiedzialna za BI.
- Dane syntetyczne mają odtwarzalny generator, parametry i ziarno losowości. Duże pliki wynikowe nie są domyślnie dodawane do Git; sposób przekazania zbioru dokumentuje instrukcja uruchomienia.
- Hasła, tokeny i lokalne pliki konfiguracyjne z sekretami pozostają poza repozytorium. Repozytorium zawiera jedynie przykładowe wartości i opis konfiguracji.

## Cykl życia ADR

1. Nowy rekord otrzymuje kolejny wolny numer i status `Proposed`.
2. Po decyzji zespołu otrzymuje `Accepted`, datę i odnośnik do PR lub protokołu potwierdzającego akceptację. Samo przygotowanie dokumentu nie jest akceptacją.
3. Poprawki redakcyjne wprowadza się w istniejącym pliku przez PR.
4. Zmiana przyjętego rozwiązania wymaga nowego ADR z odniesieniem „zastępuje ADR-XXX”. Stary rekord zachowuje uzasadnienie i otrzymuje `Superseded` wraz z odnośnikiem do następcy i datą.
5. Odrzuconą propozycję zachowuje się ze statusem `Rejected` i przyczyną. Numerów nie używa się ponownie.
6. Rejestr aktualizuje się w tym samym PR co rekord. Opis PR zawiera powód zmiany i wpływ na implementację oraz dokumentację.

## Konsekwencje

**Korzyści:** dostępna historia zmian; możliwość przeglądu kodu i dokumentacji razem; śledzenie związku decyzji z wdrażanym rozwiązaniem.

**Koszty i ograniczenia:** konieczność rozwiązywania konfliktów i aktualizowania rejestru; obowiązek utrzymywania instrukcji odtworzenia; zapis tekstowy BI wymaga sprawdzenia w używanym środowisku. Git nie zastępuje kopii bazy, testów ani automatycznie nie gwarantuje odtworzenia w czasie wymaganym przez NFR-05.

## Weryfikacja i dalsze działania

- W przeglądzie PR sprawdzić obecność kodu, instrukcji, dokumentacji i tekstowych artefaktów BI stosownie do etapu implementacji.
- Odtworzyć środowisko z oznaczonego commitu według instrukcji i zapisać wynik w zadaniu testowym. Kontrola jest planowana, nie wykonana przez przygotowanie ADR.
- Przy pierwszej rzeczywistej zmianie decyzji sprawdzić dwustronne odnośniki poprzednika i następcy oraz historię PR.
- Uzgodnić osoby zatwierdzające zmiany i potwierdzić format projektu BI. ADR nie wprowadza obowiązku automatycznego CI/CD poza zakresem uzgodnionego backlogu.

## Historia

| Data | Zmiana |
|---|---|
| 2026-11-04 | Przygotowanie propozycji; brak potwierdzonej akceptacji zespołu |

## Dokumenty powiązane

- [Rejestr ADR](README.md)
- [ADR-003](ADR-003-bi.md)
- Katalog wymagań HotelGroup: NFR-04 i NFR-05.

