-- US-03-04 | Zasilenie mart.fct_reservations z core.clean_*.
-- Uruchom WYŁĄCZNIE w bazie hotelgroup_dw po US-02-02 i zasileniu 5 wymiarów.
-- Bez usuwania/aktualizacji faktów: uruchomienie wymaga pustej tabeli docelowej.
-- Jedna transakcja: każdy wykryty problem powoduje ROLLBACK.

BEGIN;

DO $preflight$
DECLARE
    n_source bigint;
    n_joined bigint;
    n_unique bigint;
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Niepoprawna baza danych: %. Oczekiwano hotelgroup_dw.', current_database();
    END IF;

    IF EXISTS (SELECT 1 FROM mart.fct_reservations) THEN
        RAISE EXCEPTION 'mart.fct_reservations nie jest pusta. Wstrzymano INSERT, aby uniknac duplikatow.';
    END IF;

    SELECT count(*), count(DISTINCT reservation_id)
      INTO n_source, n_unique
      FROM core.clean_pms_reservations;
    IF n_source = 0 OR n_source <> n_unique THEN
        RAISE EXCEPTION 'Brak danych lub powtorzone reservation_id: % rekordow, % unikalnych.', n_source, n_unique;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.clean_pms_reservations r
        LEFT JOIN core.clean_cm_channels cm ON cm.reservation_id = r.reservation_id
        WHERE r.currency IS DISTINCT FROM 'PLN'
           OR cm.currency IS DISTINCT FROM 'PLN'
    ) THEN
        RAISE EXCEPTION 'Wykryto brak CM lub walute inna niz PLN. Wstrzymano zapis.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM core.clean_pms_reservations
        WHERE status NOT IN ('Oczekująca', 'W trakcie', 'Zakończona', 'Anulowana', 'No-Show')
           OR length(reservation_id) > 50
    ) THEN
        RAISE EXCEPTION 'Nieobslugiwany status lub zbyt dlugi reservation_id.';
    END IF;

    SELECT count(*) INTO n_joined
    FROM core.clean_pms_reservations r
    JOIN core.clean_cm_channels cm ON cm.reservation_id = r.reservation_id
    JOIN mart.dim_hotel h ON h.hotel_bk = r.hotel_id
    JOIN mart.dim_guest g ON g.guest_bk = r.guest_id
    JOIN mart.dim_segment s ON s.segment_bk = r.guest_segment
    JOIN mart.dim_channel c ON c.channel_bk = CASE WHEN cm.channel_code = 'BOOKING' THEN 'BOOKING_COM' ELSE cm.channel_code END
    JOIN mart.dim_date db ON db.full_date = r.booking_date
    JOIN mart.dim_date da ON da.full_date = r.check_in_date
    JOIN mart.dim_date dd ON dd.full_date = r.check_out_date;

    IF n_joined <> n_source THEN
        RAISE EXCEPTION 'Niepelne lub powielone powiazania wymiarowe: source=%, join=%.', n_source, n_joined;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM mart.dim_date WHERE date_sk = 0 AND full_date IS NULL)
       OR NOT EXISTS (SELECT 1 FROM mart.dim_date WHERE date_sk = -1 AND full_date IS NULL) THEN
        RAISE EXCEPTION 'Brakuje technicznych dat UNKNOWN (0) / NOT_APPLICABLE (-1).';
    END IF;

    RAISE NOTICE 'PASS preflight: % unikalnych rezerwacji, kompletne powiazania i PLN.', n_source;
END;
$preflight$;

INSERT INTO mart.fct_reservations (
    reservation_bk,
    hotel_sk, channel_sk, primary_guest_sk, segment_sk,
    booking_date_sk, arrival_date_sk, departure_date_sk, cancellation_date_sk,
    reservation_status, reservation_count, cancellation_count,
    room_revenue, cancellation_fee, commission_amount, currency_code
)
SELECT
    r.reservation_id,
    h.hotel_sk, c.channel_sk, g.guest_sk, s.segment_sk,
    db.date_sk, da.date_sk, dd.date_sk,
    CASE WHEN r.status = 'Anulowana' THEN 0 ELSE -1 END,
    CASE r.status
        WHEN 'Oczekująca' THEN 'ACTIVE'
        WHEN 'W trakcie' THEN 'IN_PROGRESS'
        WHEN 'Zakończona' THEN 'COMPLETED'
        WHEN 'Anulowana' THEN 'CANCELLED'
        WHEN 'No-Show' THEN 'NO_SHOW'
    END,
    1,
    CASE WHEN r.status = 'Anulowana' THEN 1 ELSE 0 END,
    r.room_revenue, r.cancellation_fee, cm.commission_amount, 'PLN'
FROM core.clean_pms_reservations r
JOIN core.clean_cm_channels cm ON cm.reservation_id = r.reservation_id
JOIN mart.dim_hotel h ON h.hotel_bk = r.hotel_id
JOIN mart.dim_guest g ON g.guest_bk = r.guest_id
JOIN mart.dim_segment s ON s.segment_bk = r.guest_segment
JOIN mart.dim_channel c ON c.channel_bk = CASE WHEN cm.channel_code = 'BOOKING' THEN 'BOOKING_COM' ELSE cm.channel_code END
JOIN mart.dim_date db ON db.full_date = r.booking_date
JOIN mart.dim_date da ON da.full_date = r.check_in_date
JOIN mart.dim_date dd ON dd.full_date = r.check_out_date;

DO $verify$
DECLARE
    n_source bigint;
    n_fact bigint;
    n_cancellations bigint;
    n_expected_cancellations bigint;
    src_revenue numeric;
    fact_revenue numeric;
    src_fee numeric;
    fact_fee numeric;
    src_commission numeric;
    fact_commission numeric;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE status = 'Anulowana'), sum(room_revenue), sum(cancellation_fee)
    INTO n_source, n_expected_cancellations, src_revenue, src_fee
    FROM core.clean_pms_reservations;

    SELECT count(*), sum(cancellation_count), sum(room_revenue), sum(cancellation_fee), sum(commission_amount)
    INTO n_fact, n_cancellations, fact_revenue, fact_fee, fact_commission
    FROM mart.fct_reservations;

    SELECT sum(commission_amount) INTO src_commission FROM core.clean_cm_channels;

    IF n_fact <> n_source OR n_cancellations <> n_expected_cancellations
       OR src_revenue IS DISTINCT FROM fact_revenue
       OR src_fee IS DISTINCT FROM fact_fee
       OR src_commission IS DISTINCT FROM fact_commission THEN
        RAISE EXCEPTION 'Niezgodnosc faktu ze zrodlem: rekordy %/%; anulacje %/%; przychod %/%; oplaty %/%; prowizje %/%.',
            n_fact, n_source, n_cancellations, n_expected_cancellations,
            fact_revenue, src_revenue, fact_fee, src_fee, fact_commission, src_commission;
    END IF;

    RAISE NOTICE 'PASS kontrola: % rezerwacji, % anulacji; wszystkie trzy sumy finansowe zgodne.', n_fact, n_cancellations;
END;
$verify$;

COMMIT;

-- Podsumowanie po udanym COMMIT:
SELECT reservation_status, count(*) AS reservations, sum(cancellation_count) AS cancellations
FROM mart.fct_reservations
GROUP BY reservation_status
ORDER BY reservation_status;
