# Daily #1
**J.M.:**
jestem w trakcie robienia “US-03-09 | Udokumentowanie ERD, data lineage i słownika modelu”
Nie mam żadnych uwag

**K.S:**
Czekam na akcept wybranych technologii i źródeł danych w historyjce US-03-01.
Poza tym na razie nie mam uwag

**G.Z.:**
Jestem w trakcie wykonywania:
US-03-03 | Zaprojektowanie wspólnych wymiarów analitycznych
Nie mam aktualnie żadnych uwag.

**S.G.:**
Na obecną chwilę przygotowywuje
US-03-02 | Utworzenie struktur hurtowni i stref staging/core/mart.
Nie napotkałem problemów

**K.K:**
Jestem w trakcie wykonywania
US-02-06 | Generowanie syntetycznych danych źródłowych HotelGroup
Nie mam żadnych uwag

# Daily #2
**K.S.:**
Mój update:
Przygotowałem dokumentację architektury hurtowni HotelGroup w ramach US-03-01.
Informacyjnie: W dniu 04.11.2026 zmieniono mechanizm przechowywania estymacji Story Points z pól niestandardowych Trello na etykiety w formacie SP: X. Dostosowano synchronizację Google Apps Script i zweryfikowano zgodność estymacji wszystkich 75 kart. Zachowano strukturę arkusza oraz mechanizm historycznych pomiarów wykorzystywanych do obliczania metryk SCRUM.

**K.K.:**
kontynuuje prace nad
US-02-06 | Generowanie syntetycznych danych źródłowych HotelGroup
Nie mam żadnych uwag

**G.Z.:**
wykonano US-07-02 i US-07-01
Nie mam żadnych uwag

**S.G.:**
Odbyliśmy chwilowy call z Kamilem odnoście ustaleń architektonicznych bazy danych, pobraliśmy program na którym będziemy pracować i go testowaliśmy. Utworzone zostały do niego instrukcje i struktur definicje schematów.
Przez następne dni będę przygotowywał resztę zadań z US-03-02.
Jeżeli chodzi o uwagi to na spotkaniu Backlog Refinement przedstawimy narzędzie i wytłumaczymy jego działanie będę prosił o uwagę w tej kwestii na tym spotkaniu.

**J.M.:**
Kontynuje robienia “US-03-09 | Udokumentowanie ERD, data lineage i słownika modelu”
Nie mam żadnych uwag

# Daily #3
**J.M:**
Wykonano US-03-09
Nie mam żadnych uwag

**K.S:**
Uwagi do US-02-06
Przejrzałem generator danych PMS pod kątem wymagań projektu HotelGroup.
Ogólnie jest OK - mamy 8 hoteli, 55 000 rezerwacji, 20 000 gości, SQLite i powtarzalność dzięki SEED = 42.
Są jednak rzeczy, które warto poprawić teraz, żeby później nie było problemów przy ETL, hurtowni PostgreSQL i raportach Power BI.
Najważniejsze poprawki:
Brak pokoi i ich dostępności - generator powinien zawierać tabelę pms_rooms z fizycznymi pokojami przypisanymi do hoteli. Potrzebujemy informacji o dostępnych pokojonocach do obliczania OCC i RevPAR.
Brak rozróżnienia rezerwacji i rzeczywistego pobytu - obecnie mamy tylko pms_reservations. Powinniśmy rozróżnić rezerwację od faktycznie zrealizowanego pobytu, np. przez tabelę pms_stays. Anulacje i no-show nie mogą zwiększać liczby sprzedanych pokojonocy.
Brak kontroli nakładających się rezerwacji - generator losuje daty niezależnie od dostępności pokoi. Trzeba uniknąć przypadkowego przekroczenia pojemności hotelu albo jawnie oznaczać przypadki overbookingu.
Brak daty utworzenia rezerwacji - dodać booking_date, żeby można było liczyć booking lead time. Przyda się też updated_at do przyszłego ładowania przyrostowego.
Nielogiczne statusy historyczne - obecnie statusy W trakcie i Oczekująca są losowane również dla starych rezerwacji. Status powinien wynikać z dat oraz przyjętego momentu odniesienia danych.
Przychody z anulacji i no-show - obecne total_amount łączy różne rodzaje kwot. Trzeba rozdzielić przychody z noclegów od opłat za anulację/no-show, żeby poprawnie obliczać ADR i RevPAR.
Zakres dat - obecna logika nie generuje przyjazdów po 16 grudnia 2025. Trzeba poprawić generowanie dat, żeby historia obejmowała pełne 24 miesiące, również pobyty przechodzące między miesiącami i latami.
Integralność SQLite - to_sql() nie tworzy automatycznie odpowiednich PK, FK i ograniczeń. Warto zdefiniować strukturę tabel i relacje, żeby baza pilnowała spójności danych.
Realizm danych -warto uwzględnić sezonowość zależną od lokalizacji, różną liczbę pokoi w hotelach i zróżnicowane ceny. Dzięki temu analizy porównawcze i sezonowe będą bardziej wiarygodne.
Testy generatora - dodać automatyczną kontrolę liczby rekordów, unikalności ID, poprawności dat, relacji między tabelami, dostępności pokoi i powtarzalności generowania.
Nie chodzi o przebudowanie całego rozwiązania. Chodzi o to, żeby dane PMS były od razu przygotowane pod nasze wymagania R-03, R-04 i R-07 oraz planowany model fact_reservation / fact_room_night.
Najważniejsze są punkty 1–8 i 10. Sezonowość można dopracować w drugiej kolejności.
Po zmianach dobrze byłoby uruchomić generator, sprawdzić wyniki testów i dopiero wtedy zrobić Pull Request.
@kacperkapon jak będziesz potrzebował pomocy daj znać 😉

**G.Z.:**
Czekam na poprawiony generator danych PMS aby móc kontynuować US-03-03.

**K.K.:**
Poprawiłem generator danych PMS i ostateczną wersję wraz z instrukcją wgrałem na github.
US-02-06 ukończone

**S.G:**
Przejrzałem zaktualizowane pliki i resztę wykonanego backlogu wszystko wydaje się być wykonane poprawnie nie mam dodatkowych uwag. W następnych dniach testować generator

# Daily #4
**K.S:**
Nie mam uwag dobra robota chłopaki 😁

**S.G:**
Nie mam obecnie uwag, przed jutrzejszym spotkaniem wykonam ostatni backlog

**J.M.:**
Nie mam obecnie uwag.

**K.K:**
Nie mam żadnych uwag

**G.Z.:**
Nie mam aktualnie żadnych uwag
