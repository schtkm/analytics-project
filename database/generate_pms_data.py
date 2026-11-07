import pandas as pd
import sqlite3
import random
from faker import Faker
from datetime import datetime, timedelta

# 1. KONFIGURACJA I ZIARNO LOSOWOŚCI (Kryterium Akceptacji 3)
fake = Faker('pl_PL')
SEED = 42
Faker.seed(SEED)
random.seed(SEED)

# Parametry generatora (Kryterium Akceptacji 1 i 2)
NUM_HOTELS = 8
NUM_GUESTS = 20000
NUM_RESERVATIONS = 55000
START_DATE = datetime(2024, 1, 1) # Minimum 24 miesiące historii
END_DATE = datetime(2025, 12, 31)

# Statusy rezerwacji i typy pokoi
STATUS_WEIGHTS = ['Zakończona', 'Anulowana', 'No-Show', 'W trakcie', 'Oczekująca']
STATUS_PROBS = [0.75, 0.15, 0.05, 0.03, 0.02] 
ROOM_TYPES = ['Standard', 'Premium', 'Apartament', 'Rodzinny']

# 2. GENEROWANIE DANYCH HOTELI (pms_hotels)
print("Generowanie danych hoteli...")
hotels = []
cities = ['Kraków', 'Warszawa', 'Gdańsk', 'Wrocław', 'Poznań', 'Zakopane', 'Sopot', 'Karpacz']
regions = ['Małopolskie', 'Mazowieckie', 'Pomorskie', 'Dolnośląskie', 'Wielkopolskie', 'Małopolskie', 'Pomorskie', 'Dolnośląskie']

for i in range(NUM_HOTELS):
    hotel_id = f"H{str(i+1).zfill(3)}"
    hotels.append({
        'hotel_id': hotel_id,
        'hotel_name': f"HotelGroup {cities[i]}",
        'city': cities[i],
        'region': regions[i]
    })
df_hotels = pd.DataFrame(hotels)

# 3. GENEROWANIE DANYCH GOŚCI (pms_guests)
print("Generowanie danych gości...")
guests = []
for i in range(NUM_GUESTS):
    guest_id = f"G{str(i+1).zfill(6)}"
    guests.append({
        'guest_id': guest_id,
        'first_name': fake.first_name(),
        'last_name': fake.last_name(),
        'email': fake.ascii_free_email(),
        'phone': fake.phone_number()
    })
df_guests = pd.DataFrame(guests)

# 4. GENEROWANIE DANYCH REZERWACJI (pms_reservations)
print(f"Generowanie {NUM_RESERVATIONS} rezerwacji...")
reservations = []
time_between_dates = END_DATE - START_DATE

for i in range(NUM_RESERVATIONS):
    reservation_id = f"RES{str(i+1).zfill(8)}"
    
    # Losowanie powiązań (zachowanie logiki z US-03-01 i schematu DB)
    hotel_id = random.choice(hotels)['hotel_id']
    guest_id = random.choice(guests)['guest_id']
    room_type = random.choice(ROOM_TYPES)
    status = random.choices(STATUS_WEIGHTS, weights=STATUS_PROBS)[0]
    
    # Logika dat (check_out zawsze po check_in)
    random_days_offset = random.randrange(time_between_dates.days - 14) 
    check_in_date = START_DATE + timedelta(days=random_days_offset)
    length_of_stay = random.randint(1, 14)
    check_out_date = check_in_date + timedelta(days=length_of_stay)
    
    # Logika cenowa oparta na typie pokoju i długości pobytu
    base_price = {'Standard': 250, 'Premium': 400, 'Apartament': 750, 'Rodzinny': 500}
    total_amount = base_price[room_type] * length_of_stay * random.uniform(0.85, 1.15)
    
    # Anulacje i No-show mogą mieć kwotę 0 lub zaliczkę
    if status in ['Anulowana', 'No-Show']:
         total_amount = total_amount * random.choice([0, 0.2, 0.5])

    reservations.append({
        'reservation_id': reservation_id,
        'hotel_id': hotel_id,
        'guest_id': guest_id,
        'room_type': room_type,
        'check_in_date': check_in_date.strftime('%Y-%m-%d'),
        'check_out_date': check_out_date.strftime('%Y-%m-%d'),
        'status': status,
        'total_amount': round(total_amount, 2)
    })
df_reservations = pd.DataFrame(reservations)

# 5. ZAPIS DO BAZY SQLITE (PMS)
db_path = 'pms_source.db'
print(f"Zapisywanie danych do bazy SQLite: {db_path}...")
conn = sqlite3.connect(db_path)

# Zapis DataFrames do tabel odpowiadających stagingowi
df_hotels.to_sql('pms_hotels', conn, if_exists='replace', index=False)
df_guests.to_sql('pms_guests', conn, if_exists='replace', index=False)
df_reservations.to_sql('pms_reservations', conn, if_exists='replace', index=False)

conn.close()
print("Zakończono! Zbiór testowy jest gotowy.")