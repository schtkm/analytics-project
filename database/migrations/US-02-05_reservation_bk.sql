-- Klucz biznesowy używany przy cyklicznym odświeżaniu rezerwacji.
CREATE UNIQUE INDEX IF NOT EXISTS uq_fct_reservations_bk
    ON mart.fct_reservations (reservation_bk);
