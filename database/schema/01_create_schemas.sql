-- Utworzenie schematu dla surowych danych wejściowych (bez transformacji)
CREATE SCHEMA IF NOT EXISTS staging;

-- Utworzenie schematu dla ujednoliconych i oczyszczonych danych (Single Source of Truth)
CREATE SCHEMA IF NOT EXISTS core;

-- Utworzenie schematu dla warstwy analitycznej (model gwiazdy: fakty i wymiary)
CREATE SCHEMA IF NOT EXISTS mart;
