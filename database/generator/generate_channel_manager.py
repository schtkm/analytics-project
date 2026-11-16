"""
HOTELGROUP – GENERATOR DANYCH CHANNEL MANAGERA

Zadanie: US-02-01
Źródło: PMS (SQLite)
Wynik: Channel Manager (JSON)

Generator przypisuje każdej rezerwacji PMS jeden kanał
sprzedaży i syntetyczną prowizję.

Założenia testowe:
- DIRECT: 0% prowizji
- BOOKING: 15% prowizji
- EXPEDIA: 18% prowizji
- Prowizja naliczana od dodatniego room_revenue.
- Jeden rekord Channel Managera na rezerwację PMS.

Stawki i rozkład kanałów są założeniami syntetycznymi,
a nie wymaganiami narzuconymi przez prowadzącego.
"""

import json
import random
import sqlite3
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


# ============================================================
# 1. KONFIGURACJA
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

PMS_DB = BASE_DIR / "pms_source.db"
OUTPUT_FILE = BASE_DIR / "channel_manager.json"

SEED = 42

CHANNELS = {
    "DIRECT": Decimal("0.00"),
    "BOOKING": Decimal("0.15"),
    "EXPEDIA": Decimal("0.18"),
}

CHANNEL_WEIGHTS = [40, 40, 20]


# ============================================================
# 2. GENEROWANIE DANYCH
# ============================================================

def generate_channel_manager():

    if not PMS_DB.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono bazy PMS: {PMS_DB}"
        )

    rng = random.Random(SEED)

    channel_codes = list(CHANNELS.keys())
    records = []
    reservation_ids = set()

    # Połączenie tylko do odczytu.
    db_uri = PMS_DB.resolve().as_uri() + "?mode=ro"

    with sqlite3.connect(db_uri, uri=True) as conn:

        cursor = conn.execute("""
            SELECT reservation_id, room_revenue
            FROM pms_reservations
            ORDER BY reservation_id
        """)

        for reservation_id, room_revenue in cursor:

            if not reservation_id:
                raise ValueError("Brak reservation_id w PMS")

            if reservation_id in reservation_ids:
                raise ValueError(
                    f"Duplikat rezerwacji: {reservation_id}"
                )

            reservation_ids.add(reservation_id)

            channel = rng.choices(
                channel_codes,
                weights=CHANNEL_WEIGHTS,
                k=1,
            )[0]

            rate = CHANNELS[channel]

            revenue = Decimal(str(room_revenue or 0))

            if revenue < 0:
                raise ValueError(
                    f"Ujemny przychód: {reservation_id}"
                )

            commission = (
                revenue * rate
            ).quantize(
                Decimal("0.01"),
                rounding=ROUND_HALF_UP,
            )

            records.append({
                "reservation_id": reservation_id,
                "channel_code": channel,
                "commission_rate": float(rate),
                "commission_amount": float(commission),
            })

    if not records:
        raise ValueError("Brak rezerwacji do wygenerowania")

    # Zapis pliku JSON.
    with OUTPUT_FILE.open(
        "w", encoding="utf-8"
    ) as file:
        json.dump(
            records,
            file,
            ensure_ascii=False,
            indent=2,
        )

    print("Generowanie Channel Manager zakończone.")
    print(f"Liczba rekordów: {len(records)}")
    print(f"Plik: {OUTPUT_FILE}")

    for channel in channel_codes:
        count = sum(
            1 for item in records
            if item["channel_code"] == channel
        )
        print(f"{channel}: {count}")


# ============================================================
# 3. URUCHOMIENIE
# ============================================================

if __name__ == "__main__":
    generate_channel_manager()