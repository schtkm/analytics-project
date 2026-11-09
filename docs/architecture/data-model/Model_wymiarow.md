# US-03-03 | Zaprojektowanie wspólnych wymiarów analitycznych

Aktualizacja: 09.11.2026. EPIC-03. MoSCoW: Must. Sprint 1.

**Status: projekt logiczny zaktualizowany na podstawie poprawionego generatora PMS, przygotowany do odbioru zespołu.** Dokument nie potwierdza akceptacji PO, publikacji w Git ani implementacji ETL.

## Cel i zakres

Jako analityk danych chcę korzystać ze wspólnych wymiarów daty, hotelu, pokoju, kanału sprzedaży i gościa, aby porównywać wskaźniki między hotelami i okresami bez niespójnych definicji.

Zakres obejmuje sześć wymiarów podstawowych i dodatkowy DimSegment, atrybuty, klucze biznesowe i zastępcze, mapowania oraz relacje z planowanymi faktami. Sprint 1 nie wymaga zasilenia wymiarów, DDL ani implementacji faktów. Historyzacja gościa pozostaje w US-03-06. US-03-04/05 nie blokują zaprojektowania relacji.

## Zmiany względem poprzedniej wersji

- Zastąpiono hipotetyczne pola PMS rzeczywistymi nazwami z poprawionego generatora.
- Region to województwo. Dodano jawne mapowania geograficzne.
- Słownik typów: STANDARD, PREMIUM, APARTMENT. Wycofano przykładowe SUPERIOR i SUITE oraz domniemania wyposażenia.
- Słownik segmentów: BUSINESS, LEISURE, FAMILY. Wycofano wcześniejsze pierwszeństwo GROUP. Źródłem segmentu jest rezerwacja.
- DimChannel pozostaje pełnym projektem logicznym. W PMS nie ma danych o kanale; katalog kanałów wymaga przeglądu, a późniejsze zasilenie źródła.
- Wszystkie zestawienia poniżej odpowiadają arkuszom XLSX tej samej aktualizacji.

## Nazewnictwo, klucze i historia

Nazwy tabel Dim + liczba pojedyncza i PascalCase atrybutów zachowano. Dodatnie klucze zastępcze ...Key nadaje hurtownia, niezależnie od źródłowych ID. BK jednoznacznie identyfikuje zwykły rekord; nazwa nie jest kluczem. DimRoom ma BK (HotelCode, RoomCode), przy czym RoomCode przyjmuje globalnie unikalny room_id z tego generatora. RoomNumber nie identyfikuje pokoju między hotelami. Zmiana numeru pokoju w przyszłych źródłach wymaga zachowania tożsamości w mapowaniu; generator nie modeluje takich zmian.

DateKey jest technicznym INTEGER, BK to FullDate. Wartości specjalne: 0 UNKNOWN, -1 NOT_APPLICABLE; ich atrybuty daty mogą być NULL. Nie stosować fikcyjnej daty jako zwykłego dnia. Tak* oznacza wymagalność dla zwykłego rekordu. Specjalny pokój odwołuje się do specjalnego hotelu/typu; zgodność HotelKey faktu z hotelem pokoju dotyczy rzeczywistych pokoi.

GuestBusinessId identyfikuje profil we wskazanej instancji; w modelu bazowym ma jeden rekord. W US-03-06 jeden BK może mieć wiele wersji i odrębne GuestKey. Dane kontaktowe nie są przenoszone do wymiaru. To nie jest dowód pełnej realizacji ochrony danych. Źródłowy guest_id jest globalny w wygenerowanym zbiorze, bez hotel_id w kluczu gościa.

Mapowania mają najwyżej jeden cel dla klucza źródłowego w danym czasie. Dla zmian używać przedziału [ValidFrom, ValidTo); brak końca oznacza bezterminowość. Obecne typy są stałe w całym okresie generatora. Kody mapowań są konfiguracją projektu, a nie dodatkowymi tabelami eksportu PMS.

## Relacje i granice faktów

Wszystkie relacje wymiar–fakt mają krotność 1:N. Wiele ról dat korzysta z jednego wspólnego kalendarza. W modelu BI należy jawnie rozdzielić role dat i nie tworzyć niejednoznacznych aktywnych ścieżek filtrowania.

FactReservation pozostaje jednym wierszem na rezerwację, także przy przyszłym rozszerzeniu na wiele pokoi. Aktualny generator ma jeden pokój na rezerwację, ale nie narzuca tego ograniczenia całemu modelowi. FactRoomNight: fizyczny pokój × noc; FactRoomInventory: pokój × data. Brak OOO w źródle nie pozwala uznać całego zasobu za zawsze dostępny. Definicja OCC należy do US-03-05 i uzgodnień biznesowych.

Typ przydzielonego pokoju jest dostępny; osobny typ zamówiony nie jest zapisany. Nie utożsamiać ich bez jawnego założenia. Segment i kanał są cechami rezerwacji. Inventory nie otrzymuje sztucznego gościa, kanału ani segmentu.

## Ograniczenia generatora istotne dla kolejnych sprintów

Wszystkie 10 testów autora przeszło, ale dodatkowe kontrole wykazały problemy semantyczne: rezerwacje utworzone po snapshot, przekroczenia deklarowanej górnej granicy updated_at i otwarte pobyty z datą odcięcia w actual_check_out. Wyniki zapisano w Weryfikacja. Nie zmieniono kodu generatora. Ograniczenia nie uniemożliwiają projektu wymiarów, lecz muszą być obsłużone przed uznaniem przyszłych analiz i faktów za poprawne. Aktualna data projektu nie zmienia snapshotu 2026-01-01.

## Zestaw wymiarów

| Wymiar | Ziarno | SK | BK | Źródło / reguła | Zakres |
| --- | --- | --- | --- | --- | --- |
| DimDate | Dzień kalendarzowy | DateKey | FullDate | Kalendarz 2023-01-01–2026-12-31, rozszerzalny | Podstawowy |
| DimHotel | Hotel sieci | HotelKey | HotelCode | pms_hotels.hotel_id → HotelCode (H001–H008) | Podstawowy |
| DimRoomType | Wspólny typ pokoju | RoomTypeKey | RoomTypeCode | pms_rooms.room_type → STANDARD/PREMIUM/APARTMENT | Podstawowy |
| DimRoom | Fizyczny pokój w hotelu | RoomKey | HotelCode + RoomCode | pms_rooms.room_id → RoomCode; hotel_id → HotelKey | Podstawowy |
| DimChannel | Kanał sprzedaży | ChannelKey | ChannelCode | Projekt logiczny; brak pola kanału w PMS; przyszłe źródło do uzgodnienia | Podstawowy |
| DimGuest | Profil gościa bez historii | GuestKey | GuestBusinessId | PMS_SYNTH_V2: + pms_guests.guest_id; identyfikator profilu, bez danych kontaktowych | Podstawowy |
| DimSegment | Segment rezerwacji | SegmentKey | SegmentCode | pms_reservations.guest_segment → BUSINESS/LEISURE/FAMILY | Uzupełniający |

## Słownik atrybutów i ich źródeł

| Wymiar | Atrybut | Typ logiczny | Rola klucza | Wymagany | Znaczenie | Reguła / ograniczenie | Źródło / dostępność |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DimDate | DateKey | INTEGER | PK / SK | Tak | Techniczny klucz daty | Nadawany centralnie; nie zawiera daty źródłowej; 0 = nieznana, -1 = nie dotyczy. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimDate | FullDate | DATE | BK / UNIQUE | Tak* | Data kalendarzowa | Unikalna dla zwykłych rekordów; NULL tylko w rekordach specjalnych. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | CalendarYear | INTEGER | Atrybut | Tak* | Rok kalendarzowy | Wyznaczony z FullDate. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | QuarterNumber | INTEGER | Atrybut | Tak* | Kwartał | 1–4. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | MonthNumber | INTEGER | Atrybut | Tak* | Miesiąc | 1–12; sortowanie MonthName. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | MonthName | TEXT | Atrybut | Tak* | Polska nazwa miesiąca | Jednolity słownik językowy. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | DayOfMonth | INTEGER | Atrybut | Tak* | Dzień miesiąca | 1–31 zgodnie z datą. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | DayOfWeekNumber | INTEGER | Atrybut | Tak* | Numer dnia tygodnia | Poniedziałek = 1, niedziela = 7. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | DayOfWeekName | TEXT | Atrybut | Tak* | Polska nazwa dnia tygodnia | Sortowanie DayOfWeekNumber. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | ISOWeekNumber | INTEGER | Atrybut | Tak* | Tydzień ISO | 1–53; używać razem z ISOWeekYear. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | ISOWeekYear | INTEGER | Atrybut | Tak* | Rok tygodnia ISO | Może różnić się od CalendarYear na przełomie lat. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | MonthStartDate | DATE | Atrybut | Tak* | Pierwszy dzień miesiąca | Pozwala wskazać okres faktu miesięcznego. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimDate | IsWeekend | BOOLEAN | Atrybut | Tak* | Czy sobota lub niedziela | Wynika z DayOfWeekNumber. | Wyliczenie z FullDate; FullDate generowany w kalendarzu. |
| DimHotel | HotelKey | INTEGER | PK / SK | Tak | Techniczny klucz hotelu | Stały przy zmianie nazwy hotelu. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimHotel | HotelCode | TEXT | BK / UNIQUE | Tak* | Stały kod hotelu w sieci | Nie kod nazwy miasta; różne źródłowe ID mapują się na ten sam HotelCode. | pms_hotels.hotel_id |
| DimHotel | HotelName | TEXT | Atrybut | Tak* | Nazwa hotelu | Nazwa nie jest kluczem. | pms_hotels.hotel_name |
| DimHotel | CityCode | TEXT | Atrybut | Tak* | Kod miasta w rejestrze sieci | Identyfikuje miasto w kraju, niezależnie od pisowni nazwy. | Mapowanie miasta w tabeli Mapowania |
| DimHotel | CityName | TEXT | Atrybut | Tak* | Nazwa miasta | CityCode jednoznacznie określa CityName i RegionCode. | pms_hotels.city |
| DimHotel | RegionCode | TEXT | Atrybut | Tak* | Kod regionu w rejestrze sieci | Region oznacza województwo, zgodnie z poprawionym HOTELS_CONFIG. | Mapowanie województwa w tabeli Mapowania |
| DimHotel | RegionName | TEXT | Atrybut | Tak* | Nazwa regionu | RegionCode jednoznacznie określa nazwę i kraj. | pms_hotels.region |
| DimHotel | CountryCode | TEXT | Atrybut | Tak* | Kod kraju hotelu | Jeden ustalony słownik kodów krajów. | Konfiguracja PL dla obecnych 8 hoteli |
| DimHotel | TimeZoneId | TEXT | Atrybut | Tak* | Strefa czasowa hotelu | Używana przy wyznaczaniu lokalnej daty biznesowej; identyfikator zgodny z wybraną platformą. | Konfiguracja Europe/Warsaw dla obecnych 8 hoteli |
| DimHotel | HotelCategory | TEXT | Atrybut | Nie | Kategoria biznesowa hotelu | Np. CITY, RESORT, APARTHOTEL; słownik do uzgodnienia. | Brak w bazie; NULL. type w kodzie opisuje sezonowość, nie kategorię hotelu. |
| DimHotel | IsActive | BOOLEAN | Atrybut | Tak* | Czy hotel jest aktywny | Zamknięcie nie usuwa historii ani nie zwalnia HotelCode do ponownego użycia. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |
| DimRoomType | RoomTypeKey | INTEGER | PK / SK | Tak | Techniczny klucz typu pokoju | Wspólny dla całej sieci. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimRoomType | RoomTypeCode | TEXT | BK / UNIQUE | Tak* | Kod wspólnego typu | STANDARD, PREMIUM, APARTMENT; UNKNOWN, NOT_APPLICABLE techniczne. | Słownik projektu, zgodny z ROOM_TYPES; typ źródłowy w pms_rooms.room_type. |
| DimRoomType | RoomTypeName | TEXT | Atrybut | Tak* | Nazwa wspólnego typu | Jednakowe znaczenie we wszystkich hotelach. | Słownik projektu, zgodny z ROOM_TYPES; typ źródłowy w pms_rooms.room_type. |
| DimRoomType | RoomTypeDescription | TEXT | Atrybut | Tak* | Kryteria zaliczenia do typu | Kategoria syntetyczna z ROOM_TYPES. Mnożniki cen 1.0/1.5/2.5 nie dowodzą wyposażenia. | Słownik projektu, zgodny z ROOM_TYPES; typ źródłowy w pms_rooms.room_type. |
| DimRoomType | IsActive | BOOLEAN | Atrybut | Tak* | Czy typ jest używany | Wycofany typ pozostaje dla historycznych faktów. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |
| DimRoom | RoomKey | INTEGER | PK / SK | Tak | Techniczny klucz fizycznego pokoju | Nigdy nie wyliczać wyłącznie z numeru pokoju. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimRoom | HotelKey | INTEGER | FK → DimHotel.HotelKey | Tak | Hotel będący właścicielem pokoju | Każdy zwykły pokój ma dokładnie jeden hotel. | pms_rooms.hotel_id → DimHotel |
| DimRoom | RoomCode | TEXT | Składnik BK | Tak* | Stały identyfikator pokoju w hotelu | UNIQUE (HotelKey, RoomCode); RoomCode pozostaje stały po zmianie numeru wyświetlanego. | pms_rooms.room_id |
| DimRoom | RoomNumber | TEXT | Atrybut | Tak* | Numer lub oznaczenie pokoju | Np. 101, 01A; tekst zachowuje zera i litery. Nie musi być unikalny między hotelami. | pms_rooms.room_number |
| DimRoom | CurrentRoomTypeKey | INTEGER | FK → DimRoomType.RoomTypeKey | Tak | Bieżący typ fizycznego pokoju | Tylko opis bieżący; typ historyczny pobierany z faktu dla danej daty. | pms_rooms.room_type → DimRoomType |
| DimRoom | FloorLabel | TEXT | Atrybut | Nie | Oznaczenie piętra | Tekst, np. 0, 1, antresola; potwierdzić dostępność. | Brak w obecnym PMS; NULL, atrybut opcjonalny. |
| DimRoom | CapacityAdults | INTEGER | Atrybut | Nie | Bieżąca pojemność dorosłych | Nieujemna liczba; brak nie oznacza zera. | Brak w obecnym PMS; NULL, atrybut opcjonalny. |
| DimRoom | CapacityChildren | INTEGER | Atrybut | Nie | Bieżąca pojemność dzieci | Nieujemna liczba; definicja wieku do uzgodnienia. | Brak w obecnym PMS; NULL, atrybut opcjonalny. |
| DimRoom | IsActive | BOOLEAN | Atrybut | Tak* | Czy pokój należy do aktywnego zasobu | Nie jest statusem OOO dla konkretnego dnia. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |
| DimChannel | ChannelKey | INTEGER | PK / SK | Tak | Techniczny klucz kanału | Wspólny dla źródeł i hoteli. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimChannel | ChannelCode | TEXT | BK / UNIQUE | Tak* | Kod kanału sieci | Np. BOOKING_COM, DIRECT_WEB, DIRECT_PHONE. | Projekt słownika; brak źródłowej wartości w przekazanym PMS. |
| DimChannel | ChannelName | TEXT | Atrybut | Tak* | Nazwa kanału | Jedna nazwa biznesowa po normalizacji kodów. | Projekt słownika; brak źródłowej wartości w przekazanym PMS. |
| DimChannel | ChannelGroupCode | TEXT | Atrybut | Tak* | Grupa dystrybucji | Katalog v1: DIRECT, OTA, AGENCY, GDS, OTHER; grupa wyznaczana przez ChannelCode; techniczne UNKNOWN/NOT_APPLICABLE. | Projekt słownika; brak źródłowej wartości w przekazanym PMS. |
| DimChannel | IsActive | BOOLEAN | Atrybut | Tak* | Czy kanał jest wykorzystywany | Prowizja transakcji nie jest stałą cechą kanału. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |
| DimGuest | GuestKey | INTEGER | PK / SK | Tak | Techniczny klucz rekordu gościa | Docelowo klucz wersji po wdrożeniu SCD2 w US-03-06. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimGuest | GuestBusinessId | TEXT | BK | Tak* | Trwały pseudonim profilu biznesowego | Identyfikator profilu w instancji PMS_SYNTH_V2; nie jest obietnicą anonimizacji. SCD2 w US-03-06. | PMS_SYNTH_V2: + pms_guests.guest_id |
| DimGuest | GuestCountryCode | TEXT | Atrybut | Nie | Kraj zamieszkania gościa | Proponowana jedna definicja: kraj zamieszkania, nie obywatelstwo; do uzgodnienia. | Brak; NULL. Faker pl_PL nie określa kraju zamieszkania. |
| DimGuest | LoyaltyLevelCode | TEXT | Atrybut | Nie | Poziom programu lojalnościowego | Kandydat do historyzacji w US-03-06; brak profilu nie oznacza braku członkostwa. | Brak; NULL, nie NONE. |
| DimGuest | IsActive | BOOLEAN | Atrybut | Tak* | Czy profil pozostaje aktywny | Nie zastępuje obsługi usunięcia danych ani reguł retencji. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |
| DimSegment | SegmentKey | INTEGER | PK / SK | Tak | Techniczny klucz segmentu | Przechowywany w fakcie rezerwacji / pokojonocy. | Klucz nadawany przez hurtownię; brak w PMS. |
| DimSegment | SegmentCode | TEXT | BK / UNIQUE | Tak* | Kod segmentu rynkowego | BUSINESS, LEISURE, FAMILY; bez wcześniejszej reguły pierwszeństwa GROUP. | Słownik projektu; pms_reservations.guest_segment. |
| DimSegment | SegmentName | TEXT | Atrybut | Tak* | Nazwa segmentu | Spójna dla sieci. | Słownik projektu; pms_reservations.guest_segment. |
| DimSegment | SegmentDescription | TEXT | Atrybut | Tak* | Reguła klasyfikacji rezerwacji | Bezpośrednie mapowanie guest_segment tej rezerwacji; segment nie jest stałą cechą gościa. | Słownik projektu; pms_reservations.guest_segment. |
| DimSegment | IsActive | BOOLEAN | Atrybut | Tak* | Czy segment jest używany | Wycofanie nie usuwa historycznych przypisań. | Konfiguracja: true dla obecnego zbioru; brak historii aktywności w PMS. |

## Wspólne słowniki

| Wymiar | Wartość źródłowa | Kod wspólny | Nazwa | Definicja / grupa | Status źródła |
| --- | --- | --- | --- | --- | --- |
| DimRoomType | Standard | STANDARD | Standard | Kategoria generatora; mnożnik ceny 1.0. Bez założeń o aneksie, metrażu lub łóżkach. | Obecne w kodzie |
| DimRoomType | Premium | PREMIUM | Premium | Kategoria generatora; mnożnik ceny 1.5. Bez założeń o aneksie, metrażu lub łóżkach. | Obecne w kodzie |
| DimRoomType | Apartament | APARTMENT | Apartament | Kategoria generatora; mnożnik ceny 2.5. Bez założeń o aneksie, metrażu lub łóżkach. | Obecne w kodzie |
| DimSegment | Biznes | BUSINESS | Biznes | Segment pojedynczej rezerwacji; kategorie rozłączne według wartości źródłowej. | Obecne w kodzie |
| DimSegment | Turystyczny | LEISURE | Turystyczny | Segment pojedynczej rezerwacji; kategorie rozłączne według wartości źródłowej. | Obecne w kodzie |
| DimSegment | Rodzinny | FAMILY | Rodzinny | Segment pojedynczej rezerwacji; kategorie rozłączne według wartości źródłowej. | Obecne w kodzie |
| DimChannel | Brak w PMS | DIRECT_WEB | Strona hotelu | DIRECT | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | DIRECT_PHONE | Telefon | DIRECT | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | DIRECT_EMAIL | E-mail | DIRECT | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | WALK_IN | Recepcja | DIRECT | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | BOOKING_COM | Booking.com | OTA | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | EXPEDIA | Expedia | OTA | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | OTA_OTHER | Inne OTA | OTA | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | TRAVEL_AGENCY | Biuro podróży | AGENCY | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | GDS | GDS | GDS | Katalog projektowy; do przeglądu z zespołem |
| DimChannel | Brak w PMS | OTHER | Inny rozpoznany kanał | OTHER | Katalog projektowy; do przeglądu z zespołem |
| DimRoomType | Wartość techniczna | UNKNOWN | Nieznane; SK=0 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |
| DimRoomType | Wartość techniczna | NOT_APPLICABLE | Nie dotyczy; SK=-1 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |
| DimChannel | Wartość techniczna | UNKNOWN | Nieznane; SK=0 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |
| DimChannel | Wartość techniczna | NOT_APPLICABLE | Nie dotyczy; SK=-1 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |
| DimSegment | Wartość techniczna | UNKNOWN | Nieznane; SK=0 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |
| DimSegment | Wartość techniczna | NOT_APPLICABLE | Nie dotyczy; SK=-1 | UNKNOWN przy braku danych; NOT_APPLICABLE tylko gdy wymiar nie ma zastosowania. | Reguła projektu |

## Mapowania źródłowe

| Obiekt | Źródło | Wartość źródłowa | Cel | Wartość docelowa | Reguła |
| --- | --- | --- | --- | --- | --- |
| Hotel / geografia | pms_hotels | H001 / Kraków / Małopolskie | HotelCode / CityCode / RegionCode | H001 / PL-KRK / PL-MAL | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H002 / Warszawa / Mazowieckie | HotelCode / CityCode / RegionCode | H002 / PL-WAW / PL-MAZ | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H003 / Gdańsk / Pomorskie | HotelCode / CityCode / RegionCode | H003 / PL-GDN / PL-POM | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H004 / Wrocław / Dolnośląskie | HotelCode / CityCode / RegionCode | H004 / PL-WRO / PL-DOL | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H005 / Poznań / Wielkopolskie | HotelCode / CityCode / RegionCode | H005 / PL-POZ / PL-WLK | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H006 / Zakopane / Małopolskie | HotelCode / CityCode / RegionCode | H006 / PL-ZAK / PL-MAL | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H007 / Sopot / Pomorskie | HotelCode / CityCode / RegionCode | H007 / PL-SOP / PL-POM | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| Hotel / geografia | pms_hotels | H008 / Karpacz / Dolnośląskie | HotelCode / CityCode / RegionCode | H008 / PL-KAR / PL-DOL | Kody miasta i regionu są wewnętrznymi kodami projektu, nie kodami urzędowymi. |
| DimRoomType | PMS_SYNTH_V2 | Standard | DimRoomType.RoomTypeCode | STANDARD | Jawne mapowanie wartości, wspólne dla całego generatora. |
| DimRoomType | PMS_SYNTH_V2 | Premium | DimRoomType.RoomTypeCode | PREMIUM | Jawne mapowanie wartości, wspólne dla całego generatora. |
| DimRoomType | PMS_SYNTH_V2 | Apartament | DimRoomType.RoomTypeCode | APARTMENT | Jawne mapowanie wartości, wspólne dla całego generatora. |
| DimSegment | PMS_SYNTH_V2 | Biznes | DimSegment.SegmentCode | BUSINESS | Jawne mapowanie wartości, wspólne dla całego generatora. |
| DimSegment | PMS_SYNTH_V2 | Turystyczny | DimSegment.SegmentCode | LEISURE | Jawne mapowanie wartości, wspólne dla całego generatora. |
| DimSegment | PMS_SYNTH_V2 | Rodzinny | DimSegment.SegmentCode | FAMILY | Jawne mapowanie wartości, wspólne dla całego generatora. |
| Pokój | pms_rooms | room_id | DimRoom.RoomCode | wartość room_id | ID globalne w zbiorze; dodatkowo hotel_id. |
| Gość | pms_guests | guest_id | DimGuest.GuestBusinessId | PMS_SYNTH_V2:<guest_id> | Jeden profil globalny w zbiorze; nie scalać po e-mailu. |
| Kanał | Brak | Brak | DimChannel.ChannelKey | 0 / UNKNOWN przy przyszłym zasileniu bez kanału | Nie przypisywać DIRECT ani OTA na podstawie segmentu. |

## Kontrakt źródeł

| Źródło | Pola | Mapowanie / rola | Ograniczenie |
| --- | --- | --- | --- |
| pms_hotels | hotel_id, hotel_name, city, region | DimHotel; region to województwo | Kody geograficzne, kraj i strefa z konfiguracji. |
| pms_rooms | room_id, hotel_id, room_number, room_type | DimRoom, DimRoomType | Typ stały w wygenerowanym okresie; brak historii i pojemności. |
| pms_guests | guest_id, first_name, last_name, email, phone | DimGuest z guest_id; dane kontaktowe poza mart | Brak kraju i lojalności; nie wyprowadzać ich z generatora nazw. |
| pms_reservations | reservation_id, hotel_id, guest_id, room_id, guest_segment | Identyfikator rezerwacji; hotel, gość, pokój i segment | Jedna rezerwacja dotyczy jednego pokoju w tym generatorze. |
| pms_reservations | booking_date, check_in_date, check_out_date, status | Role DimDate oraz status faktu | Brak cancellation_date, kanału i waluty. |
| pms_reservations | room_revenue, cancellation_fee, updated_at | Miary i znacznik źródłowy dla przyszłego ETL | Nie mylić room_revenue oczekującej rezerwacji z przychodem zrealizowanym. updated_at nie jest datą anulacji. |
| pms_stays | stay_id, reservation_id, guest_id, room_id, actual_check_in, actual_check_out | Powiązania przyszłej FactRoomNight | Dla W trakcie actual_check_out to data odcięcia, a nie faktyczny wyjazd. |
| Konfiguracja integracji | SourceSystemCode=PMS_SYNTH_V2 | Przestrzeń nazw dla nowej wersji zbioru | Nie dopisywać nowego wygenerowanego zbioru jako przyrostu poprzedniej bazy na podstawie samych RES/G ID. |
| Kalendarz | FullDate od 2023-01-01 do 2026-12-31 | DimDate i role dat | Zakres obejmuje wyprzedzenie rezerwacji i rok planowania; rozszerzać po profilowaniu nowych źródeł. |
| Przyszła integracja kanału | reservation_id + channel_code oraz zakres instancji | Docelowo mapowanie DimChannel | Kontrakt projektowy, nie istniejące pola PMS. Maksymalnie jeden kanał pozyskania na rezerwację. |

## Planowane fakty

| Fakt | Zadanie | Ziarno | Powiązanie PMS | Ograniczenie |
| --- | --- | --- | --- | --- |
| FactReservation | US-03-04, Sprint 2 | Jeden aktualny wiersz na rezerwację | PMS_SYNTH_V2 + reservation_id | Nie mnożyć przez pokoje/noce. Brak kanału i daty anulacji w PMS. |
| FactRoomNight | US-03-05, Sprint 2 | Pokój fizyczny × noc | room_id, stay_id, reservation_id; przedział [przyjazd,wyjazd) | Plan i realizacja rozróżnione; nie dublować tej samej pokojonocy. |
| FactRoomInventory | US-03-05, Sprint 2 | Pokój fizyczny × data | pms_rooms + kalendarz + przyszłe stany dostępności | Brak OOO i historii aktywności. Brak rezerwacji nie dowodzi dostępności. |
| FactFinanceMonthly | Dalsze modelowanie | Hotel × miesiąc × kategoria × scenariusz | Poza PMS | Wstępny kontrakt; brak źródła w generatorze. |
| FactAncillaryRevenue | Dalsze modelowanie | Pozycja transakcji usługi/POS | Poza PMS | Wstępny kontrakt; brak źródła w generatorze. |

## Macierz relacji

| Tabela podrzędna | Kolumna FK | Wymiar nadrzędny | Kolumna PK | Krotność | Znaczenie / rola | Reguła |
| --- | --- | --- | --- | --- | --- | --- |
| DimRoom | HotelKey | DimHotel | HotelKey | N:1 | Własność fizycznego pokoju | Zgodność HotelKey faktu z hotelem pokoju; relacja strukturalna, nie druga aktywna ścieżka filtrowania w BI. |
| DimRoom | CurrentRoomTypeKey | DimRoomType | RoomTypeKey | N:1 | Bieżący typ pokoju | Nie stosować do odtwarzania typu historycznego faktu. |
| FactReservation | BookingDateKey | DimDate | DateKey | N:1 | Data utworzenia | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactReservation | ArrivalDateKey | DimDate | DateKey | N:1 | Planowany przyjazd | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactReservation | DepartureDateKey | DimDate | DateKey | N:1 | Planowany wyjazd | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactReservation | CancellationDateKey | DimDate | DateKey | N:1 | Data anulowania; -1 dla nieanulowanej | Anulowana bez daty → 0; nieanulowana → -1. Nie używać updated_at jako daty anulacji. |
| FactReservation | HotelKey | DimHotel | HotelKey | N:1 | Hotel rezerwacji | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactReservation | ChannelKey | DimChannel | ChannelKey | N:1 | Kanał rezerwacji | Brak kanału w PMS: 0 / UNKNOWN; mapowanie z dalszej integracji. Nie oznacza pełnej analizy kanałów. |
| FactReservation | PrimaryGuestKey | DimGuest | GuestKey | N:1 | Gość główny; nie lista wszystkich gości | guest_id → profil PMS_SYNTH_V2; jeden wskazany gość, nie lista uczestników. |
| FactReservation | SegmentKey | DimSegment | SegmentKey | N:1 | Segment tej rezerwacji | Mapowanie guest_segment rezerwacji; nie z bieżącego profilu gościa. |
| FactRoomNight | StayDateKey | DimDate | DateKey | N:1 | Noc pobytu; dzień wyjazdu wyłączony | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomNight | HotelKey | DimHotel | HotelKey | N:1 | Hotel pobytu | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomNight | RoomKey | DimRoom | RoomKey | N:1 | Fizyczny pokój przypisany do nocy | RoomKey > 0 dla faktu o ziarnie pokój × noc. Nie scalać nieprzydzielonych rezerwacji pod RoomKey=-2. |
| FactRoomNight | BookedRoomTypeKey | DimRoomType | RoomTypeKey | N:1 | Typ zamówiony | Brak typu zamówionego. Domyślnie UNKNOWN; utożsamienie z typem przydzielonym tylko po jawnym uzgodnieniu braku upgrade. |
| FactRoomNight | OccupiedRoomTypeKey | DimRoomType | RoomTypeKey | N:1 | Typ fizycznego pokoju obowiązujący w nocy pobytu | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomNight | ChannelKey | DimChannel | ChannelKey | N:1 | Kanał przypisany do rezerwacji | Brak kanału w PMS: 0 / UNKNOWN; mapowanie z dalszej integracji. Nie oznacza pełnej analizy kanałów. |
| FactRoomNight | PrimaryGuestKey | DimGuest | GuestKey | N:1 | Gość główny pobytu | guest_id → profil PMS_SYNTH_V2; jeden wskazany gość, nie lista uczestników. |
| FactRoomNight | SegmentKey | DimSegment | SegmentKey | N:1 | Segment rezerwacji obowiązujący dla tej pozycji | Mapowanie guest_segment rezerwacji; nie z bieżącego profilu gościa. |
| FactRoomInventory | InventoryDateKey | DimDate | DateKey | N:1 | Data dostępności | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomInventory | HotelKey | DimHotel | HotelKey | N:1 | Hotel zasobu | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomInventory | RoomKey | DimRoom | RoomKey | N:1 | Fizyczny pokój | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactRoomInventory | RoomTypeKey | DimRoomType | RoomTypeKey | N:1 | Typ zasobu obowiązujący w tej dacie | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactFinanceMonthly | MonthDateKey | DimDate | DateKey | N:1 | Pierwszy dzień miesiąca; nie data dowolnej transakcji | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactFinanceMonthly | HotelKey | DimHotel | HotelKey | N:1 | Hotel wyniku finansowego | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactAncillaryRevenue | SaleDateKey | DimDate | DateKey | N:1 | Lokalna data sprzedaży | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactAncillaryRevenue | HotelKey | DimHotel | HotelKey | N:1 | Hotel sprzedaży | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactAncillaryRevenue | RoomKey | DimRoom | RoomKey | N:1 | Tylko jeśli transakcja ma powiązanie; inaczej -1 | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |
| FactAncillaryRevenue | GuestKey | DimGuest | GuestKey | N:1 | Tylko jeśli transakcja ma powiązanie; inaczej -1 | Dokładnie jeden rekord wymiaru na FK, w tym rekord specjalny. |

## Reguły wspólne

| ID | Obszar | Reguła |
| --- | --- | --- |
| C-01 | Klucze | Dodatnie SK nadaje hurtownia; 0 UNKNOWN, -1 NOT_APPLICABLE. RoomKey=-2 tylko do planu bez przydziału, nie jako fizyczny pokój w ziarnie pokój × noc. |
| C-02 | Typ pokoju | Standard→STANDARD, Premium→PREMIUM, Apartament→APARTMENT. Nie stosować starej klasyfikacji SUPERIOR/SUITE ani kryteriów aneksu. |
| C-03 | Segment | Biznes→BUSINESS, Turystyczny→LEISURE, Rodzinny→FAMILY. Segment w rezerwacji; nie oznacza statusu rodzinnego gościa. |
| C-04 | Hotel | HotelCode→CityCode→RegionCode→CountryCode; region oznacza województwo. |
| C-05 | Źródło | PMS_SYNTH_V2 oznacza bieżącą wersję syntetycznego zbioru. Zmiana konfiguracji generatora może zmieniać przypisania kolejnych ID. |
| C-06 | Gość | Bez imienia, nazwiska, e-maila i telefonu w DimGuest. guest_id pozwala na kontrolowane powiązanie, nie gwarantuje anonimowości. SCD2 osobno. |
| C-07 | Kanał | Słownik i relacje zaprojektowane. W PMS brak kanału. UNKNOWN jest oznaczeniem braku, nie dowodem realizacji analiz kanałowych. |
| C-08 | Daty | Daty pobytu są lokalnymi datami; dzień wyjazdu nie jest nocą pobytu. Snapshot generatora 2026-01-01, niezależnie od daty uruchomienia. |
| C-09 | Historia | Typ pokoju stały w tym zbiorze. Zmiana typu w kolejnych źródłach wymaga mapowania według daty; nie odtwarzać historii ze stanu bieżącego. |
| C-10 | BI | Relacje N:1; role DimDate osobno. Nie tworzyć dwóch aktywnych ścieżek Hotel→Room→Fact i Hotel→Fact. |
| C-11 | Braki | Pojemność, piętro, kraj gościa i lojalność: NULL. IsActive=true to założenie obecnego syntetycznego zbioru, nie historia OOO. |
| C-12 | Konfiguracja | Słowniki i mapowania są konfiguracją projektu; nie oznaczają istniejących tabel źródłowych. Nowe kody wymagają jawnego mapowania. |

## Scenariusze weryfikacji

| ID | Warunek | Oczekiwany wynik | Rodzaj weryfikacji |
| --- | --- | --- | --- |
| P-01 | room_type=Premium | PREMIUM, bez klasyfikowania jako SUPERIOR | Przegląd mapowania |
| P-02 | guest_segment=Rodzinny | FAMILY przypisany do rezerwacji | Przegląd mapowania |
| P-03 | Ten sam guest_id w rezerwacjach o różnych segmentach | Jeden profil gościa, różne SegmentKey w faktach | Przegląd ziarna |
| P-04 | Pokój nr 1 w H001 i H002 | Dwa różne RoomKey | Przegląd kluczy |
| P-05 | Brak pola kanału | UNKNOWN; bez przypisania do Direct | Przegląd reguły |
| P-06 | Anulowana bez cancellation_date | CancellationDateKey=0; nie updated_at | Przegląd reguły |
| P-07 | Pobyt kończy się 1 lutego | Ostatnia noc 31 stycznia | Scenariusz dla ETL |
| P-08 | Przyszła rezerwacja utworzona po snapshot | Nie wchodzi do rezerwacji znanych as-of snapshot | Scenariusz dla ETL |
| P-09 | W trakcie; actual_check_out=snapshot | Wyjazd niepotwierdzony; nie liczyć jako zakończonego pobytu | Scenariusz dla ETL |
| P-10 | Przyszła rezerwacja bez pokoju w innym źródle | Plan pozycji rezerwacji; nie scalać wielu pozycji w RoomKey=-2 × data | Scenariusz dla US-03-05 |

## Wyniki weryfikacji

| ID | Kontrola | Wynik | Dowód / ograniczenie |
| --- | --- | --- | --- |
| V-01 | 7 wymiarów z BK/SK i atrybutami | Projekt sprawdzony | 6 podstawowych i dodatkowy DimSegment; tabela Atrybuty. |
| V-02 | Hierarchia hotel–miasto–region | Potwierdzono w wygenerowanej bazie | 8 hoteli, 5 województw; nowy generator. |
| V-03 | Rozróżnienie pokoju i typu | Potwierdzono | room_id odrębne od room_type; 1240 pokoi, 3 kategorie. |
| V-04 | Liczebność nowego zbioru | 8 hoteli; 20 000 gości; 140 875 rezerwacji; 97 413 pobytów | Lokalne uruchomienie kodu 09.11.2026; nie dane ze starego pms_source.db. |
| V-05 | Testy dostarczonego generatora | 10/10 zaliczone | Nie obejmują wszystkich ograniczeń opisanych w Uzgodnienia. |
| V-06 | Klucze obce SQLite | 0 naruszeń | PRAGMA foreign_key_check w nowej bazie. |
| V-07 | Zakres dat | booking_date od 2023-10-03; wyjazdy do 2026-06-30; 30 miesięcy przyjazdów | Kalendarz projektu 2023–2026 obejmuje zakres. |
| V-08 | Relacje z planowanymi faktami | Przegląd logiczny | Ziarna zgodne z US-03-04/05; nie testowano nieistniejącego ETL. |
| V-09 | Spójność snapshotu | 20 151 rezerwacji utworzonych po 2026-01-01 | Dla analizy as-of nie wolno użyć całego zbioru jako znanego w dniu snapshotu. |
| V-10 | Górna granica updated_at | 25 819 przekroczeń min(check_in, snapshot) o północy | Własna kontrola; komentarz w kodzie nie jest gwarancją. |
| V-11 | Pobyty w trakcie | 139 przedziałów actual_check_out <= actual_check_in | Dla W trakcie wyjazd nie nastąpił; nie interpretować daty odcięcia jako rzeczywistego wyjazdu. |

## Uzgodnienia i dalsze działania

| ID | Temat | Stan | Właściciel / etap | Wpływ na US-03-03 |
| --- | --- | --- | --- | --- |
| U-01 | Struktura PMS i identyfikatory | Odczytano poprawiony kod, uruchomiono i sprawdzono schemat | US-03-03 / US-02-06 | Mapowania źródłowe udokumentowane. |
| U-02 | Województwa i segmenty | Dostępne w poprawionym generatorze | Przegląd projektu przez zespół | Zastąpiono wcześniejsze przykłady. |
| U-03 | Kanał sprzedaży | Brak w PMS; katalog projektowy i UNKNOWN opisane | EPIC-02 / autor źródła kanałów, przed zasileniem faktów | Nie blokuje samego projektu logicznego; akceptacja katalogu i planu źródła przy odbiorze. |
| U-04 | Przegląd i odbiór | Brak potwierdzenia akceptacji w przekazanych materiałach | Zespół / PO | Wymagany do potwierdzenia uzgodnień; nie oznaczono automatycznie Done. |
| U-05 | As-of, updated_at, pobyty w trakcie | Dodatkowe kontrole wykazały ograniczenia; V-09–V-11 | Autor generatora / ETL / US-03-05 | Nie zmieniają struktur wymiarów; do poprawy lub jawnej obsługi przed użyciem faktów. |
| U-06 | OOO, waluta, data anulacji, typ zamówiony | Brak w źródle; bez zgadywania wartości | US-03-04/05 i ETL | Poza zasileniem wymiarów Sprintu 1. |
| U-07 | Stabilność przy ponownym generowaniu | Seed=42; nie wykonano porównania dwóch przebiegów | US-02-06 | Zakres źródła wersjonowany; nie traktować przebudowy jako przyrostu. |
| U-08 | Publikacja w Git i przekazanie US-03-09 | Pliki przygotowane; publikacji nie wykonano | Właściciel zadania | Dodać aktualne MD/XLSX do dokumentacji projektu. |

## Lista zadań zgodna z kartą

| Podpunkt zadania | Status pracy | Dowód / co pozostaje |
| --- | --- | --- |
| Zidentyfikować atrybuty wymiarów na podstawie danych źródłowych | Projekt wykonany i udokumentowany | Mapowania do rzeczywistych kolumn poprawionego generatora; pola niedostępne oznaczone. |
| Uzgodnić strukturę i nazewnictwo tabel wymiarów | Przygotowano do uzgodnienia | Nazwy zachowane; przegląd i uzgodnienie z zespołem pozostają do potwierdzenia. |
| Zaprojektować wymiar daty (DimDate) | Projekt wykonany i udokumentowany | Kalendarz 2023–2026, role dat, BK/SK. |
| Zaprojektować wymiar hotelu (DimHotel) z hierarchią hotel → miasto → region | Projekt wykonany i udokumentowany | Województwa z HOTELS_CONFIG; jawne mapowanie 8 hoteli. |
| Zaprojektować wymiary typu pokoju (DimRoomType) i pokoju fizycznego (DimRoom) | Projekt wykonany i udokumentowany | Typy STANDARD/PREMIUM/APARTMENT; room_id identyfikuje pokój. |
| Zaprojektować wymiar kanału sprzedaży (DimChannel) | Projekt wykonany i udokumentowany | Kompletny projekt; brak kanału PMS i dalsze źródło jawnie udokumentowane. |
| Zaprojektować podstawowy wymiar gościa (DimGuest) bez implementacji SCD2 | Projekt wykonany i udokumentowany | Profil z guest_id; segment wyłącznie przy rezerwacji; SCD2 osobno. |
| Zdefiniować klucze biznesowe i zastępcze dla wymiarów | Projekt wykonany i udokumentowany | BK/SK i przestrzeń nazw źródła, rekordy specjalne. |
| Zweryfikować relacje wymiarów z planowanymi tabelami faktów | Projekt wykonany i udokumentowany | Relacje N:1 i ziarna US-03-04/05; brak zależności od implementacji faktów. |
| Udokumentować model wymiarów i sprawdzić zgodność z wymaganiem R-03 | Projekt wykonany i udokumentowany | MD i XLSX z dowodami; pełne R-03 wymaga dodatkowo faktów i SCD2. |

## Źródła i wersje

| Źródło | Wersja / data | Wykorzystanie |
| --- | --- | --- |
| generate_pms_data (1).py | SHA256 490b29aea0b285546882150798e341cf6dbfd9a881af72525ebcc77e7860e060 | Aktualne DDL, słowniki, identyfikatory i konfiguracja. |
| Lokalny wynik generatora | 09.11.2026; seed=42; Faker 40.46.0; pandas 2.2.3 | Weryfikacja schematu, liczebności i ograniczeń. |
| pms_source.db otrzymany wcześniej | Poprzednia wersja generatora | Nie stanowi dowodu nowych pól i regionów; wymaga ponownego wygenerowania. |
| US-03-03 i US-03-04/05 | Treści przekazane w rozmowie | Zakres projektu logicznego i planowane ziarna faktów. |
| US-03-03_Model_wymiarow.md / XLSX | Poprzednia wersja 02.11.2026 | Zachowano nazwy wymiarów, klucze, atrybuty i checklistę; zastąpiono przykładowe słowniki aktualnymi. |

## Ocena kryteriów akceptacji i odbiór

1. Co najmniej 5 wymiarów, w tym data i hotel, atrybuty, BK/SK oraz relacje: przygotowano 7 wymiarów; źródłowe mapowania PMS sprawdzono. Kanał pozostaje jawnym kontraktem projektowym do przeglądu, bez danych źródłowych.
2. Hotel → miasto → region bez utraty tożsamości: zapewniają HotelCode, CityCode i RegionCode; potwierdzono województwa w nowym źródle.
3. Pokój fizyczny odrębny od typu: oddzielne DimRoom i DimRoomType oraz FK; potwierdzono odrębne pola room_id i room_type.

Do formalnego zakończenia: zespół potwierdza strukturę i słowniki (w tym katalog projektowy kanałów oraz plan jego źródła), właściciel zapisuje pliki w Git i przekazuje je do US-03-09. Nie trzeba czekać na fizyczne ładowanie ani implementację faktów. Brak tych operacji nie jest blokerem Sprintu 1. Pełne R-03 obejmuje również fakty i SCD2 w odrębnych historiach. Powiązania wspierające US-03-03: R-06, R-29, R-38 i NFR-07; ich pełnej realizacji nie potwierdza sam projekt wymiarów.
