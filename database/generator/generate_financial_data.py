"""
HOTELGROUP – GENERATOR DANYCH FINANSOWYCH CSV

Zadanie: US-02-01
Źródło identyfikatorów hoteli: PMS (SQLite)
Wynik: financial_data.csv

Generuje miesięczne koszty operacyjne i budżety
dla wszystkich hoteli HotelGroup.

Dane są syntetyczne i odtwarzalne.
"""

import csv
import random
import sqlite3
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent

PMS_DB = BASE_DIR / "pms_source.db"
OUTPUT_FILE = BASE_DIR / "financial_data.csv"

SEED = 42

START_YEAR = 2024
START_MONTH = 1
END_YEAR = 2026
END_MONTH = 6

# Kategorie i bazowe miesięczne koszty na pokój.
COST_CATEGORIES = {
    "PERSONNEL": 1200,
    "UTILITIES": 350,
    "MAINTENANCE": 250,
    "MARKETING": 150,
}


def generate_months():
    """Zwraca miesiące od 2024-01 do 2026-06."""

    year, month = START_YEAR, START_MONTH

    while (year, month) <= (END_YEAR, END_MONTH):
        yield date(year, month, 1).strftime("%Y-%m")

        month += 1

        if month > 12:
            month = 1
            year += 1


def round_amount(value):
    """Zaokrągla kwotę do dwóch miejsc po przecinku."""

    return Decimal(str(value)).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_UP,
    )


def generate_financial_data():

    if not PMS_DB.is_file():
        raise FileNotFoundError(
            f"Nie znaleziono bazy PMS: {PMS_DB}"
        )

    rng = random.Random(SEED)

    uri = PMS_DB.resolve().as_uri() + "?mode=ro"

    with sqlite3.connect(uri, uri=True) as conn:

        hotels = conn.execute("""
            SELECT
                h.hotel_id,
                COUNT(r.room_id) AS room_count
            FROM pms_hotels h
            JOIN pms_rooms r
                ON h.hotel_id = r.hotel_id
            GROUP BY h.hotel_id
            ORDER BY h.hotel_id
        """).fetchall()

    if not hotels:
        raise ValueError("Brak hoteli w bazie PMS.")

    records = []

    for hotel_id, room_count in hotels:

        for month_id in generate_months():

            for category, base_cost in COST_CATEGORIES.items():

                # Budżet zależny od liczby pokoi hotelu.
                budget = round_amount(
                    room_count * base_cost
                )

                # Syntetyczne odchylenie kosztów
                # rzeczywistych od budżetu: +/- 10%.
                deviation = Decimal(
                    str(rng.uniform(0.90, 1.10))
                )

                actual_cost = round_amount(
                    budget * deviation
                )

                records.append({
                    "hotel_id": hotel_id,
                    "month_id": month_id,
                    "cost_category": category,
                    "budget_amount": str(budget),
                    "actual_cost": str(actual_cost),
                })

    with OUTPUT_FILE.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as file:

        writer = csv.DictWriter(
            file,
            fieldnames=[
                "hotel_id",
                "month_id",
                "cost_category",
                "budget_amount",
                "actual_cost",
            ],
        )

        writer.writeheader()
        writer.writerows(records)

    print("Generowanie danych finansowych zakończone.")
    print(f"Liczba hoteli: {len(hotels)}")
    print(f"Liczba rekordów: {len(records)}")
    print(f"Plik: {OUTPUT_FILE}")


if __name__ == "__main__":
    generate_financial_data()