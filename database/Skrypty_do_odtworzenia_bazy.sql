CREATE DATABASE hotelgroup_dw;

-- Wrzucie całość do query i po kolei uruchamiajcie każdy skrpt zaznaczając wybrane elementy
-- ==============================================================================
-- 1. UTWORZENIE SCHEMATÓW
-- STRUKTURA BAZY DANYCH HOTELGROUP DW (Staging, Core, Mart)
-- ==============================================================================

-- Utworzenie schematu dla surowych danych wejściowych
CREATE SCHEMA IF NOT EXISTS staging;

-- Utworzenie schematu dla oczyszczonych i ujednoliconych danych
CREATE SCHEMA IF NOT EXISTS core;

-- Utworzenie schematu dla warstwy analitycznej (model gwiazdy: fakty i wymiary)
CREATE SCHEMA IF NOT EXISTS mart;


-- ==============================================================================
-- 2. STAGING (Warstwa surowa - brak restrykcyjnych kluczy obcych)
-- ==============================================================================

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

CREATE TABLE staging.pms_rooms (
    room_id VARCHAR(50),
    hotel_id VARCHAR(50),
    room_number VARCHAR(50),
    room_type VARCHAR(50),
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.pms_reservations (
    reservation_id VARCHAR(50),
    hotel_id VARCHAR(50),
    guest_id VARCHAR(50),
    room_id VARCHAR(50),
    guest_segment VARCHAR(50),
    booking_date DATE,
    check_in_date DATE,
    check_out_date DATE,
    status VARCHAR(50),
    room_revenue NUMERIC(10,2),
    cancellation_fee NUMERIC(10,2),
    updated_at TIMESTAMP,
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.pms_stays (
    stay_id VARCHAR(50),
    reservation_id VARCHAR(50),
    guest_id VARCHAR(50),
    room_id VARCHAR(50),
    actual_check_in DATE,
    actual_check_out DATE,
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Przyszłe źródło: Channel Manager (JSON)
CREATE TABLE staging.cm_channels (
    reservation_id VARCHAR(50),
    channel_code VARCHAR(50),
    commission_rate NUMERIC(5,2),
    commission_amount NUMERIC(10,2),
    _inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Przyszłe źródło: System finansowy (CSV)
CREATE TABLE staging.fin_budgets_costs (
    hotel_id VARCHAR(50),
    month_id VARCHAR(7),
    cost_category VARCHAR(100),
    budget_amount NUMERIC(12,2),
    actual_cost NUMERIC(12,2),
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

-- ==============================================================================
-- 3. CORE (Warstwa centralna - wymuszona integralność i czystość danych)
-- ==============================================================================

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
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(50),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE core.rooms (
    room_id VARCHAR(50) PRIMARY KEY,
    hotel_id VARCHAR(50) REFERENCES core.hotels(hotel_id),
    room_number VARCHAR(50),
    room_type VARCHAR(50),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE core.reservations (
    reservation_id VARCHAR(50) PRIMARY KEY,
    hotel_id VARCHAR(50) REFERENCES core.hotels(hotel_id),
    guest_id VARCHAR(50) REFERENCES core.guests(guest_id),
    room_id VARCHAR(50) REFERENCES core.rooms(room_id),
    guest_segment VARCHAR(50),
    booking_date DATE,
    check_in_date DATE,
    check_out_date DATE,
    status VARCHAR(50),
    room_revenue NUMERIC(10,2),
    cancellation_fee NUMERIC(10,2),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE core.stays (
    stay_id VARCHAR(50) PRIMARY KEY,
    reservation_id VARCHAR(50) REFERENCES core.reservations(reservation_id),
    guest_id VARCHAR(50) REFERENCES core.guests(guest_id),
    room_id VARCHAR(50) REFERENCES core.rooms(room_id),
    actual_check_in DATE,
    actual_check_out DATE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ==============================================================================
-- 4. MART (Warstwa analityczna - Model Wymiarowy dla Power BI)
-- ==============================================================================

CREATE TABLE mart.dim_date (
    date_sk INT PRIMARY KEY,                 -- np. 20261105
    full_date DATE UNIQUE NOT NULL,
    calendar_year INT,
    quarter_number INT,
    month_number INT,
    month_name VARCHAR(50),
    day_of_month INT,
    day_of_week_number INT,
    day_of_week_name VARCHAR(50),
    is_weekend BOOLEAN
);

CREATE TABLE mart.dim_hotel (
    hotel_sk SERIAL PRIMARY KEY,
    hotel_bk VARCHAR(50) NOT NULL,           -- dawny hotel_id
    hotel_name VARCHAR(255),
    city_code VARCHAR(50),
    city_name VARCHAR(100),
    region_code VARCHAR(50),
    region_name VARCHAR(100),
    country_code VARCHAR(10),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE mart.dim_room_type (
    room_type_sk SERIAL PRIMARY KEY,
    room_type_bk VARCHAR(50) NOT NULL,
    room_type_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE mart.dim_room (
    room_sk SERIAL PRIMARY KEY,
    room_bk VARCHAR(50) NOT NULL,            -- dawny room_id
    hotel_sk INT REFERENCES mart.dim_hotel(hotel_sk),
    room_number VARCHAR(50),
    current_room_type_sk INT REFERENCES mart.dim_room_type(room_type_sk),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE mart.dim_channel (
    channel_sk SERIAL PRIMARY KEY,
    channel_bk VARCHAR(50) NOT NULL,
    channel_name VARCHAR(100),
    channel_group_code VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE mart.dim_segment (
    segment_sk SERIAL PRIMARY KEY,
    segment_bk VARCHAR(50) NOT NULL,
    segment_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE mart.dim_guest (
    guest_sk SERIAL PRIMARY KEY,
    guest_bk VARCHAR(50) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMP DEFAULT '9999-12-31 23:59:59'
);

-- 4B. TABELE FAKTÓW
CREATE TABLE mart.fct_reservations (
    reservation_sk SERIAL PRIMARY KEY,
    reservation_bk VARCHAR(50) NOT NULL,
    hotel_sk INT REFERENCES mart.dim_hotel(hotel_sk),
    channel_sk INT REFERENCES mart.dim_channel(channel_sk),
    primary_guest_sk INT REFERENCES mart.dim_guest(guest_sk),
    segment_sk INT REFERENCES mart.dim_segment(segment_sk),
    booking_date_sk INT REFERENCES mart.dim_date(date_sk),
    arrival_date_sk INT REFERENCES mart.dim_date(date_sk),
    departure_date_sk INT REFERENCES mart.dim_date(date_sk),
    cancellation_date_sk INT REFERENCES mart.dim_date(date_sk),
    reservation_status VARCHAR(50)
);

CREATE TABLE mart.fct_room_night (
    room_night_sk SERIAL PRIMARY KEY,
    stay_date_sk INT REFERENCES mart.dim_date(date_sk),
    hotel_sk INT REFERENCES mart.dim_hotel(hotel_sk),
    room_sk INT REFERENCES mart.dim_room(room_sk),
    booked_room_type_sk INT REFERENCES mart.dim_room_type(room_type_sk),
    occupied_room_type_sk INT REFERENCES mart.dim_room_type(room_type_sk),
    channel_sk INT REFERENCES mart.dim_channel(channel_sk),
    primary_guest_sk INT REFERENCES mart.dim_guest(guest_sk),
    segment_sk INT REFERENCES mart.dim_segment(segment_sk),
    room_revenue NUMERIC(10,2)
);
