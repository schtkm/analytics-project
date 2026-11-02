
# Rejestr źródeł danych – HotelGroup

## 1. Cel dokumentu

Celem dokumentu jest identyfikacja systemów źródłowych wykorzystywanych w projekcie rozwiązania analitycznego HotelGroup oraz określenie formatów, zakresu i sposobu integracji danych.

Dokument opracowano w ramach Sprintu 1, podczas realizacji zadania **US-03-01 – Zaprojektowanie architektury hurtowni danych**.

**Status:** Wersja robocza – oczekuje na zatwierdzenie przez zespół.

## 2. Systemy źródłowe

W projekcie zaproponowano wykorzystanie trzech systemów źródłowych, reprezentujących różne formaty danych.

| System | Format | Zakres danych | Klucze integracyjne |
|---|---|---|---|
| PMS (Property Management System) | SQLite | Hotele, pokoje, rezerwacje, pobyty, anulacje | `hotel_id`, `reservation_id` |
| Channel Manager | JSON | Kanały sprzedaży, rezerwacje, prowizje | `reservation_id` |
| System finansowy | CSV | Koszty, budżety, okresy rozliczeniowe | `hotel_id`, `month` |

### 2.1. PMS – Property Management System

System odpowiedzialny za obsługę rezerwacji i pobytów gości w hotelach.

**Zakres danych:**
- Informacje o hotelach i pokojach.
- Rezerwacje i terminy pobytów.
- Statusy rezerwacji, w tym anulacje i no-show.
- Przychody z noclegów.
- Dostępność pokoi.

**Format danych:** relacyjna baza SQLite.

**Klucze integracyjne:**
- `hotel_id` – identyfikator hotelu.
- `reservation_id` – identyfikator rezerwacji.

### 2.2. Channel Manager

System odpowiedzialny za obsługę kanałów sprzedaży, takich jak Booking.com, Expedia i rezerwacje bezpośrednie.

**Zakres danych:**
- Kanały pozyskania rezerwacji.
- Powiązania kanałów z rezerwacjami.
- Stawki i wartości prowizji.
- Informacje o kosztach pozyskania rezerwacji.

**Format danych:** pliki JSON.

**Klucz integracyjny:**
- `reservation_id` – identyfikator rezerwacji powiązanej z PMS.

### 2.3. System finansowy

System dostarczający danych finansowych poszczególnych obiektów hotelowych.

**Zakres danych:**
- Koszty operacyjne hoteli.
- Kategorie kosztów.
- Budżety finansowe.
- Okresy rozliczeniowe.
- Dane potrzebne do analizy odchyleń od budżetu.

**Format danych:** pliki CSV.

**Klucze integracyjne:**
- `hotel_id` – identyfikator hotelu.
- `month` – miesiąc rozliczeniowy.

## 3. Założenia dotyczące danych

Na podstawie wymagań projektowych przyjęto następujące założenia:

- Dane będą syntetyczne, wygenerowane na potrzeby projektu.
- Sieć HotelGroup będzie obejmować od 5 do 10 hoteli.
- Dane historyczne będą obejmować minimum 24 miesiące.
- Zbiór danych będzie zawierać minimum 50 000 rezerwacji.
- Identyfikatory `hotel_id` i `reservation_id` będą spójne pomiędzy odpowiednimi źródłami.
- Dane zostaną zintegrowane w hurtowni za pomocą procesów ETL/ELT.

## 4. Planowana integracja danych

Dane z poszczególnych źródeł będą pobierane i przetwarzane przez procesy ETL/ELT, a następnie umieszczane w hurtowni danych.

Przewiduje się następujący przepływ:

1. Pobranie danych z PMS, Channel Managera i systemu finansowego.
2. Załadowanie danych do strefy `staging`.
3. Walidacja, czyszczenie i integracja danych w strefie `core`.
4. Przygotowanie modelu wymiarowego w strefie `mart`.
5. Udostępnienie danych warstwie semantycznej i narzędziom BI.

Szczegółowe rozwiązania technologiczne oraz zasady przetwarzania zostaną określone w kolejnych etapach zadania US-03-01.

## 5. Możliwości rozszerzenia

Architektura powinna umożliwiać późniejsze dołączenie dodatkowych źródeł:

- **POS (Point of Sale)** – dane gastronomiczne, sprzedaż w barach i usługach SPA.
- **CRM (Customer Relationship Management)** – dane gości, program lojalnościowy i segmentacja klientów.

Integracja dodatkowych źródeł będzie zależeć od zakresu funkcjonalnego przyjętego na kolejne sprinty.

## 6. Powiązanie z wymaganiami

| ID | Wymaganie | Sposób uwzględnienia |
|---|---|---|
| R-01 | Zasilenie hurtowni z minimum 3 źródeł w różnych formatach | Zaplanowano PMS (SQLite), Channel Manager (JSON) i finanse (CSV) |
| R-03 | Model wymiarowy hurtowni | Źródła będą podstawą do budowy faktów i wymiarów |
| NFR-05 | Odtwarzalność środowiska | Planowane wykorzystanie źródeł i danych możliwych do odtworzenia lokalnie |

**Uwaga:** Dokument opisuje planowaną realizację wymagań, a nie potwierdza ich implementacji.

## 7. Status uzgodnień

| Obszar | Status |
|---|---|
| Wybór trzech źródeł | Zaproponowano |
| Format danych PMS | Oczekuje na potwierdzenie |
| Format danych Channel Manager | Oczekuje na potwierdzenie |
| Format danych finansowych | Oczekuje na potwierdzenie |
| Wspólne identyfikatory | Oczekują na potwierdzenie |
| Technologie ETL/ELT i BI | Do ustalenia |
