# ==========================================
# UWAGA WAŻNE!!!!
# W pg_conn_string istnieje potrzeba abyście wpisali swoje hasło, które ustawiliście do logowania się do bazy danych 
# inaczej jak odpalicie kod, dane się nie zaimportują! (Dokładnie zamiast "hotelgroup2026" wpisujecie swoje hasło).
# ==========================================






import sqlite3
import pandas as pd
from sqlalchemy import create_engine

# ==========================================
# KONFIGURACJA POŁĄCZEŃ
# ==========================================
# Plik źródłowy SQLite (wynik zadania US-02-06)
sqlite_db_path = 'pms_source.db'

# Ciąg połączeniowy do PostgreSQL (Host: localhost, Port: 5432, Baza: hotelgroup_dw)
# Format: postgresql+psycopg2://<użytkownik>:<hasło>@<host>:<port>/<baza>
pg_conn_string = 'postgresql+psycopg2://postgres:hotelgroup2026@localhost:5432/hotelgroup_dw'

def load_data_to_staging():
    print("Rozpoczynam proces ekstrakcji i ładowania (ELT)...")
    
    # 1. Nawiązanie połączeń
    sqlite_conn = sqlite3.connect(sqlite_db_path)
    pg_engine = create_engine(pg_conn_string)
    
    # 2. Lista tabel do przeniesienia z PMS do Staging
    tables_to_load = [
        'pms_hotels', 
        'pms_guests', 
        'pms_rooms', 
        'pms_reservations', 
        'pms_stays'
    ]
    
    # 3. Kopiowanie danych tabela po tabeli
    for table in tables_to_load:
        print(f"Pobieranie danych z tabeli źródłowej: {table}...")
        df = pd.read_sql_query(f"SELECT * FROM {table}", sqlite_conn)
        
        # W strefie staging użyliśmy "_inserted_at" ze zdefiniowanym DEFAULT CURRENT_TIMESTAMP.
        # Skrypt automatycznie doda pozostałe kolumny.
        print(f"Ładowanie {len(df)} rekordów do schematu 'staging' w PostgreSQL...")
        
        df.to_sql(
            name=table, 
            con=pg_engine, 
            schema='staging', 
            if_exists='append',  # 'append' pozwala dodawać kolejne rekordy przyrostowo
            index=False
        )
        print(f"✅ Tabela {table} załadowana pomyślnie!\n")

    sqlite_conn.close()
    print("🎉 Zakończono pierwsze ładowanie danych do hurtowni (US-02-07)!")

if __name__ == "__main__":
    load_data_to_staging()