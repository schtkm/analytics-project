-- Wrzucie całość do query i po kolei uruchamiajcie każdy skrpt zaznaczając wybrane elementy

CREATE DATABASE hotelgroup_dw;


-- Utworzenie schematu dla surowych danych wejściowych
CREATE SCHEMA IF NOT EXISTS staging;

-- Utworzenie schematu dla oczyszczonych i ujednoliconych danych
CREATE SCHEMA IF NOT EXISTS core;

-- Utworzenie schematu dla warstwy analitycznej (model gwiazdy: fakty i wymiary)
CREATE SCHEMA IF NOT EXISTS mart;


-- STAGING: Dane z systemu PMS
CREATE TABLE staging.pms_hotels (
    hotel_id VARCHAR(50),
    hotel_name VARCHAR(255),
    city VARCHAR(100),
    region VARCHAR(100),
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.pms_guests (
    guest_id VARCHAR(50),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(50),
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.pms_reservations (
    reservation_id VARCHAR(50),
    hotel_id VARCHAR(50),
    guest_id VARCHAR(50),
    room_type VARCHAR(50),
    check_in_date DATE,
    check_out_date DATE,
    status VARCHAR(20),
    total_amount NUMERIC(10,2),
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CORE: Ujednolicone dane referencyjne
CREATE TABLE core.hotels (
    hotel_id VARCHAR(50) PRIMARY KEY,
    hotel_name VARCHAR(255) NOT NULL,
    city VARCHAR(100),
    region VARCHAR(100),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE core.guests (
    guest_id VARCHAR(50) PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CORE: Dane transakcyjne z twardymi relacjami
CREATE TABLE core.reservations (
    reservation_id VARCHAR(50) PRIMARY KEY,
    hotel_id VARCHAR(50) REFERENCES core.hotels(hotel_id),
    guest_id VARCHAR(50) REFERENCES core.guests(guest_id),
    room_type VARCHAR(50),
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    status VARCHAR(20),
    total_amount NUMERIC(10,2),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- MART: Wymiary (Słowniki)
CREATE TABLE mart.dim_hotel (
    hotel_sk SERIAL PRIMARY KEY,        -- Klucz zastępczy (Surrogate Key) wygenerowany przez bazę
    hotel_bk VARCHAR(50) NOT NULL,      -- Klucz biznesowy ze źródła (dawny hotel_id)
    hotel_name VARCHAR(255),
    city VARCHAR(100),
    region VARCHAR(100)
);

CREATE TABLE mart.dim_guest (
    guest_sk SERIAL PRIMARY KEY,
    guest_bk VARCHAR(50) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    -- Zgodnie z US-03-06 planujemy tu SCD2, więc dodajemy flagi historyzacji:
    is_active BOOLEAN DEFAULT TRUE,
    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMP DEFAULT '9999-12-31 23:59:59'
);

-- MART: Tabela Faktów
CREATE TABLE mart.fct_reservations (
    reservation_sk SERIAL PRIMARY KEY,
    reservation_bk VARCHAR(50) NOT NULL,
    hotel_sk INT REFERENCES mart.dim_hotel(hotel_sk),    -- Łączenie po kluczu zastępczym
    guest_sk INT REFERENCES mart.dim_guest(guest_sk),
    check_in_date_sk INT,                                -- Klucz do wymiaru czasu (np. 20261105)
    check_out_date_sk INT,
    status VARCHAR(20),
    revenue_amount NUMERIC(10,2)                         -- Zgodnie z konwencją nazewnictwa dla finansów
);
