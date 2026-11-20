-- US-03-05A | Zasilenie mart.fct_room_night z core.clean_pms_stays i mart.fct_reservations.
-- Uruchomić po US-03-05A_fct_room_night_migration.sql oraz zasileniu wymiarów i fct_reservations.
-- Rozbija pobyty wielodniowe (actual_check_in .. actual_check_out - 1 dzień) na pojedyncze noce.

BEGIN;

DO $preflight$
DECLARE
    n_invalid_status BIGINT;
    n_missing_dates BIGINT;
    n_missing_dims BIGINT;
BEGIN
    IF current_database() <> 'hotelgroup_dw' THEN
        RAISE EXCEPTION 'Niepoprawna baza danych: %. Oczekiwano hotelgroup_dw.', current_database();
    END IF;

    IF EXISTS (SELECT 1 FROM mart.fct_room_night LIMIT 1) THEN
        RAISE EXCEPTION 'Tabela mart.fct_room_night nie jest pusta. Wstrzymano INSERT, aby uniknąć duplikatów.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM mart.fct_reservations LIMIT 1) THEN
        RAISE EXCEPTION 'Brak danych w mart.fct_reservations. Uruchom najpierw US-03-04.';
    END IF;

    -- Weryfikacja, czy do core.clean_pms_stays nie trafiły anulacje lub No-Show
    SELECT count(*) INTO n_invalid_status
    FROM core.clean_pms_stays s
    JOIN core.clean_pms_reservations r ON r.reservation_id = s.reservation_id
    WHERE r.status IN ('Anulowana', 'No-Show');

    IF n_invalid_status > 0 THEN
        RAISE EXCEPTION 'Wykryto % pobytów powiązanych z anulacją lub No-Show.', n_invalid_status;
    END IF;

    -- Weryfikacja kompletności dat w mart.dim_date
    SELECT count(DISTINCT gs.night_date::date) INTO n_missing_dates
    FROM core.clean_pms_stays s
    CROSS JOIN LATERAL generate_series(
        s.actual_check_in,
        s.actual_check_out - INTERVAL '1 day',
        INTERVAL '1 day'
    ) AS gs(night_date)
    WHERE s.actual_check_out > s.actual_check_in
      AND NOT EXISTS (SELECT 1 FROM mart.dim_date dd WHERE dd.full_date = gs.night_date::date);

    IF n_missing_dates > 0 THEN
        RAISE EXCEPTION 'Brakuje % dat noclegów w mart.dim_date.', n_missing_dates;
    END IF;

    -- Weryfikacja kompletności powiązań z fct_reservations i dim_room
    SELECT count(*) INTO n_missing_dims
    FROM core.clean_pms_stays s
    JOIN core.clean_pms_reservations r ON r.reservation_id = s.reservation_id
    LEFT JOIN mart.fct_reservations fr ON fr.reservation_bk = s.reservation_id
    LEFT JOIN mart.dim_room dr ON dr.room_bk = s.room_id
    LEFT JOIN mart.dim_room dr_b ON dr_b.room_bk = r.room_id
    WHERE s.actual_check_out > s.actual_check_in
      AND (fr.reservation_sk IS NULL OR dr.room_sk IS NULL OR dr_b.room_sk IS NULL);

    IF n_missing_dims > 0 THEN
        RAISE EXCEPTION 'Brak powiązań z fct_reservations lub dim_room dla % pobytów.', n_missing_dims;
    END IF;

    RAISE NOTICE 'PASS preflight: warunki wejściowe dla mart.fct_room_night spełnione.';
END
$preflight$;

WITH eligible_stays AS (
    SELECT
        s.stay_id AS stay_bk,
        fr.reservation_sk,
        fr.hotel_sk,
        dr.room_sk,
        dr_booked.current_room_type_sk AS booked_room_type_sk,
        dr.current_room_type_sk AS occupied_room_type_sk,
        fr.channel_sk,
        fr.primary_guest_sk,
        fr.segment_sk,
        s.actual_check_in,
        s.actual_check_out,
        (s.actual_check_out - s.actual_check_in) AS total_nights,
        COALESCE(fr.room_revenue, 0.00) AS total_room_revenue,
        COALESCE(fr.currency_code, 'PLN') AS currency_code
    FROM core.clean_pms_stays s
    JOIN core.clean_pms_reservations r
      ON r.reservation_id = s.reservation_id
    JOIN mart.fct_reservations fr
      ON fr.reservation_bk = s.reservation_id
    JOIN mart.dim_room dr
      ON dr.room_bk = s.room_id
    JOIN mart.dim_room dr_booked
      ON dr_booked.room_bk = r.room_id
    WHERE fr.reservation_status IN ('COMPLETED', 'IN_PROGRESS')
      AND s.actual_check_out IS NOT NULL
      AND s.actual_check_out > s.actual_check_in
),
expanded_nights AS (
    SELECT
        es.*,
        gs.night_date::date AS stay_date,
        ROW_NUMBER() OVER (
            PARTITION BY es.stay_bk, es.room_sk
            ORDER BY gs.night_date::date
        ) AS night_seq
    FROM eligible_stays es
    CROSS JOIN LATERAL generate_series(
        es.actual_check_in,
        es.actual_check_out - INTERVAL '1 day',
        INTERVAL '1 day'
    ) AS gs(night_date)
)
INSERT INTO mart.fct_room_night (
    stay_bk,
    reservation_sk,
    stay_date_sk,
    hotel_sk,
    room_sk,
    booked_room_type_sk,
    occupied_room_type_sk,
    channel_sk,
    primary_guest_sk,
    segment_sk,
    room_night_count,
    is_arrival_night,
    is_stay_over,
    is_last_night,
    room_revenue,
    currency_code
)
SELECT
    en.stay_bk,
    en.reservation_sk,
    dd.date_sk AS stay_date_sk,
    en.hotel_sk,
    en.room_sk,
    en.booked_room_type_sk,
    en.occupied_room_type_sk,
    en.channel_sk,
    en.primary_guest_sk,
    en.segment_sk,
    1::smallint AS room_night_count,
    (en.night_seq = 1) AS is_arrival_night,
    (en.night_seq > 1 AND en.night_seq < en.total_nights) AS is_stay_over,
    (en.night_seq = en.total_nights) AS is_last_night,
    CASE
        WHEN en.night_seq < en.total_nights
            THEN TRUNC(en.total_room_revenue / en.total_nights, 2)
        ELSE
            en.total_room_revenue - (TRUNC(en.total_room_revenue / en.total_nights, 2) * (en.total_nights - 1))
    END AS room_revenue,
    en.currency_code
FROM expanded_nights en
JOIN mart.dim_date dd
  ON dd.full_date = en.stay_date;

DO $verify$
DECLARE
    expected_nights BIGINT;
    actual_nights BIGINT;
    expected_revenue NUMERIC(18,2);
    actual_revenue NUMERIC(18,2);
    duplicate_grains BIGINT;
BEGIN
    SELECT
        COALESCE(SUM(s.actual_check_out - s.actual_check_in), 0),
        COALESCE(SUM(fr.room_revenue), 0.00)
    INTO expected_nights, expected_revenue
    FROM core.clean_pms_stays s
    JOIN mart.fct_reservations fr ON fr.reservation_bk = s.reservation_id
    WHERE fr.reservation_status IN ('COMPLETED', 'IN_PROGRESS')
      AND s.actual_check_out > s.actual_check_in;

    SELECT
        COUNT(*),
        COALESCE(SUM(room_revenue), 0.00)
    INTO actual_nights, actual_revenue
    FROM mart.fct_room_night;

    SELECT COUNT(*) INTO duplicate_grains
    FROM (
        SELECT stay_bk, room_sk, stay_date_sk
        FROM mart.fct_room_night
        GROUP BY stay_bk, room_sk, stay_date_sk
        HAVING COUNT(*) > 1
    ) d;

    IF duplicate_grains > 0 THEN
        RAISE EXCEPTION 'Wykryto % zduplikowanych ziaren w mart.fct_room_night.', duplicate_grains;
    END IF;

    IF actual_nights <> expected_nights OR actual_revenue IS DISTINCT FROM expected_revenue THEN
        RAISE EXCEPTION 'Niezgodność ze źródłem: pokojonoce %/% | przychód %/%.',
            actual_nights, expected_nights, actual_revenue, expected_revenue;
    END IF;

    RAISE NOTICE 'PASS kontrola: załadowano % pokojonocy, łączny przychód % PLN zgodny co do grosza.',
        actual_nights, actual_revenue;
END
$verify$;

COMMIT;

-- Podsumowanie po udanym COMMIT:
SELECT
    fr.reservation_status,
    COUNT(DISTINCT fn.stay_bk) AS distinct_stays,
    COUNT(*) AS total_room_nights,
    SUM(fn.room_revenue) AS total_room_revenue_pln,
    COUNT(*) FILTER (WHERE fn.is_arrival_night) AS arrival_nights,
    COUNT(*) FILTER (WHERE fn.is_stay_over) AS stay_over_nights,
    COUNT(*) FILTER (WHERE fn.is_last_night) AS departure_nights
FROM mart.fct_room_night fn
JOIN mart.fct_reservations fr ON fr.reservation_sk = fn.reservation_sk
GROUP BY fr.reservation_status
ORDER BY fr.reservation_status;