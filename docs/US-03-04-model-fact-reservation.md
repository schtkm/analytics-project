# US-03-04 – Model faktów rezerwacji i anulacji

## 1. Cel modelu

Celem jest zaprojektowanie tabeli faktów `FactReservation`, umożliwiającej analizowanie rezerwacji i anulacji według hotelu, kanału rezerwacji i okresu.

Model powinien zapewniać jednoznaczne liczenie rezerwacji, bez wielokrotnego uwzględniania tego samego identyfikatora.

## 2. Ziarno tabeli FactReservation

**Ziarno:** jeden rekord tabeli `FactReservation` reprezentuje jedną unikalną rezerwację identyfikowaną przez `reservation_id`, w jej ostatnim znanym stanie.

Założenia:

- Zmiana statusu rezerwacji nie powoduje utworzenia kolejnego rekordu.
- Rezerwacje anulowane i typu no-show pozostają w tabeli faktów.
- Jeden identyfikator rezerwacji może wystąpić w `FactReservation` tylko raz.
- Szczegółowe rozliczenie pokojonocy, jeśli będzie wymagane, zostanie zamodelowane oddzielnie.
- Tabela przechowuje aktualny stan rezerwacji, a nie pełną historię zmian statusów.

## 3. Źródła danych

- `staging.pms_reservations` – identyfikator rezerwacji, hotel, pokój, gość, daty, statusy i kwoty.
- `staging.cm_channels` – kanał sprzedaży i informacje o prowizjach.

Powiązanie źródeł następuje za pomocą `reservation_id`.
