# Instrukcja: Pierwsze ładowanie danych PMS do strefy Staging (US-02-07)

Dokument opisuje proces przeniesienia surowych danych z wygenerowanej bazy SQLite (PMS) do docelowej hurtowni danych PostgreSQL (schemat staging). Proces realizuje podejście ELT (Extract, Load, Transform).

## Krok 1: Wygenerowanie danych źródłowych (Zależność od US-02-06)

Zanim rozpoczniesz proces ładowania, musisz fizycznie posiadać plik z danymi źródłowymi oraz samą bazę danych.

* Zaimportuj ze skryptu Skrypty_do_odtworzenia_bazy.sql bazę danych.
* Zapoznaj się z instrukcją Readme.md z folderu wcześniej przygotowaną przez Kacpra, która wygeneruje dane.
* Uruchom skrypt generate_pms_data.py, aby wygenerować syntetyczne dane hotelowe.
* Upewnij się, że w Twoim folderze roboczym pojawił się plik pms_source.db. Będzie on źródłem dla naszego procesu.

## Krok 2: Uruchomienie skryptu ładującego (Python)

Za przeniesienie danych z SQLite do PostgreSQL odpowiada skrypt korzystający z bibliotek pandas i sqlalchemy.

* Otwórz terminal (PowerShell lub CMD) w folderze, w którym znajduje się plik pms_source.db.
* Zainstaluj wymagane pakiety do obsługi bazy danych, wpisując komendę:

  python -m pip install pandas sqlalchemy psycopg2-binary

* Pobierz plik load_staging_pms.py i przenieś go do tego samego folderu.
* Uruchom skrypt w terminalu poleceniem:

  python load_staging_pms.py

## Krok 3: Weryfikacja poprawności danych (pgAdmin 4)

Po zakończeniu działania skryptu, należy upewnić się, że dane prawidłowo wylądowały w PostgreSQL.

* Uruchom program pgAdmin 4 i połącz się ze swoją bazą hotelgroup_dw.
* Otwórz narzędzie zapytań (Query Tool) dla tej bazy.
* Wklej i uruchom poniższy kod SQL (klawisz F5), aby sprawdzić liczbę załadowanych rekordów. Powinna ona zgadzać się z logami wygenerowanymi przez skrypt Kacpra (m.in. 50 000+ rezerwacji i 20 000 gości).

  -- 1. Zbiorcze sprawdzenie liczby wierszy we wszystkich załadowanych tabelach 
  SELECT 'pms_hotels' AS tabela, COUNT(*) AS liczba_rekordow FROM staging.pms_hotels UNION ALL 
  SELECT 'pms_guests', COUNT(*) FROM staging.pms_guests UNION ALL 
  SELECT 'pms_rooms', COUNT(*) FROM staging.pms_rooms UNION ALL 
  SELECT 'pms_reservations', COUNT(*) FROM staging.pms_reservations UNION ALL 
  SELECT 'pms_stays', COUNT(*) FROM staging.pms_stays; 

* Uruchom poniższe zapytanie, aby upewnić się, że struktura kolumn i wartości (np. kwoty i daty) załadowały się poprawnie i nie zawierają błędów kodowania:

  -- 2. Szybki podgląd 10 losowych rezerwacji wraz z datą ich załadowania (kolumna _inserted_at) 
  SELECT  
      reservation_id,  
      hotel_id,  
      status,  
      room_revenue, 
      _inserted_at  
  FROM  
      staging.pms_reservations  
  LIMIT 10;
