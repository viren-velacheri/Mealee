"""Build data/usda.sqlite from the FoodData Central SR Legacy CSV release.

Run once on Friday night, on a machine that can reach fdc.nal.usda.gov:

    python3 data/build_usda.py            # download, build, then verify
    python3 data/build_usda.py --verify   # only print what each foods.yaml id resolves to

Only the fdc_ids named in foods.yaml are kept, so the result is a few hundred rows,
not the full 7000 food dataset. No live nutrition API is ever called by the server.
"""

import csv
import io
import pathlib
import sqlite3
import sys
import urllib.request
import zipfile

import yaml

DATA_DIR = pathlib.Path(__file__).resolve().parent
FOODS_YAML = DATA_DIR / "foods.yaml"
SQLITE_PATH = DATA_DIR / "usda.sqlite"
SR_LEGACY_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"

WANTED_NUTRIENTS = {1008: "kcal", 1003: "protein_g", 1079: "fiber_g", 1093: "sodium_mg", 1057: "caffeine_mg"}


def wanted_ids() -> dict[int, str]:
    foods = yaml.safe_load(FOODS_YAML.read_text())["foods"]
    return {int(entry["fdc_id"]): entry["label"] for entry in foods}


def build() -> None:
    ids = wanted_ids()
    print(f"downloading {SR_LEGACY_URL}")
    with urllib.request.urlopen(SR_LEGACY_URL, timeout=120) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))

    member_names = {pathlib.Path(name).name: name for name in archive.namelist()}
    food_rows = csv.DictReader(io.TextIOWrapper(archive.open(member_names["food.csv"]), encoding="utf-8"))
    nutrient_rows = csv.DictReader(io.TextIOWrapper(archive.open(member_names["food_nutrient.csv"]), encoding="utf-8"))

    if SQLITE_PATH.exists():
        SQLITE_PATH.unlink()
    connection = sqlite3.connect(SQLITE_PATH)
    connection.executescript("""
        CREATE TABLE foods (fdc_id INTEGER PRIMARY KEY, description TEXT NOT NULL);
        CREATE TABLE nutrients (fdc_id INTEGER, nutrient_id INTEGER, amount REAL,
                                PRIMARY KEY (fdc_id, nutrient_id));
    """)
    connection.executemany(
        "INSERT INTO foods VALUES (?, ?)",
        ((int(row["fdc_id"]), row["description"]) for row in food_rows if int(row["fdc_id"]) in ids),
    )
    connection.executemany(
        "INSERT OR REPLACE INTO nutrients VALUES (?, ?, ?)",
        ((int(row["fdc_id"]), int(row["nutrient_id"]), float(row["amount"]))
         for row in nutrient_rows
         if int(row["fdc_id"]) in ids and int(row["nutrient_id"]) in WANTED_NUTRIENTS),
    )
    connection.commit()
    connection.close()
    print(f"wrote {SQLITE_PATH}")


def verify() -> int:
    if not SQLITE_PATH.exists():
        print(f"{SQLITE_PATH} does not exist. Run without --verify first.")
        return 1
    ids = wanted_ids()
    connection = sqlite3.connect(SQLITE_PATH)
    problems = 0
    print(f"{'label':<16} {'fdc_id':>7}  description")
    for fdc_id, label in ids.items():
        row = connection.execute("SELECT description FROM foods WHERE fdc_id = ?", (fdc_id,)).fetchone()
        nutrient_count = connection.execute(
            "SELECT COUNT(*) FROM nutrients WHERE fdc_id = ?", (fdc_id,)).fetchone()[0]
        if row is None:
            print(f"{label:<16} {fdc_id:>7}  MISSING: not in the SR Legacy release")
            problems += 1
            continue
        flag = "" if nutrient_count >= 3 else f"  (only {nutrient_count} nutrients)"
        print(f"{label:<16} {fdc_id:>7}  {row[0][:70]}{flag}")
    connection.close()
    print(f"\n{problems} missing. Read every description above and fix any that do not match its label.")
    return 1 if problems else 0


if __name__ == "__main__":
    if "--verify" in sys.argv:
        raise SystemExit(verify())
    build()
    raise SystemExit(verify())
