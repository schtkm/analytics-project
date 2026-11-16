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

## 4. Analiza danych źródłowych

### 4.1. PMS – rezerwacje

Tabela `staging.pms_reservations` zawiera dane potrzebne do identyfikacji rezerwacji, określenia jej statusu oraz analizy wartości i terminów pobytu.

| Atrybut źródłowy | Znaczenie |
|---|---|
| `reservation_id` | Unikalny identyfikator rezerwacji |
| `hotel_id` | Identyfikator hotelu |
| `guest_id` | Identyfikator gościa |
| `room_id` | Identyfikator pokoju |
| `booking_date` | Data dokonania rezerwacji |
| `check_in_date` | Planowana data zameldowania |
| `check_out_date` | Planowana data wymeldowania |
| `status` | Aktualny status rezerwacji |
| `room_revenue` | Przychód przypisany do rezerwacji |
| `cancellation_fee` | Opłata za anulowanie |
| `updated_at` | Data ostatniej aktualizacji rekordu |

### 4.2. Channel Manager

Tabela `staging.cm_channels` zawiera informacje o kanałach pozyskania rezerwacji i naliczonych prowizjach.

| Atrybut źródłowy | Znaczenie |
|---|---|
| `reservation_id` | Identyfikator rezerwacji, łączący Channel Manager z PMS |
| `channel_code` | Kod kanału sprzedaży (np. DIRECT, BOOKING, EXPEDIA) |
| `commission_rate` | Stawka prowizji kanału |
| `commission_amount` | Kwota prowizji przypisana do rezerwacji |
| `_inserted_at` | Techniczny znacznik czasu załadowania rekordu do staging |

**Wnioski projektowe:**

- Połączenie PMS i Channel Managera odbywa się przez `reservation_id`.
- `channel_code` będzie podstawą powiązania rezerwacji z wymiarem `DimChannel`.
- `commission_amount` może stanowić miarę finansową tabeli `FactReservation`.
- `commission_rate` pozostaje atrybutem źródłowym; sposób jego wykorzystania w modelu wymaga uzgodnienia.
- Zweryfikowano 140 875 rekordów Channel Managera, bez duplikatów identyfikatorów i bez brakujących powiązań z PMS.
