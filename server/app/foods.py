"""foods.yaml class list and per-100 g nutrients from data/usda.sqlite.

The sqlite file is produced by data/build_usda.py from the FoodData Central SR Legacy
download. If it is absent the server falls back to data/nutrients_fallback.yaml and
warns loudly, so a failed Friday download cannot take the demo down.
"""

import logging
import sqlite3
from dataclasses import dataclass
from functools import lru_cache

import httpx
import yaml

from app.config import FOODS_YAML_PATH, USDA_API_KEY, USDA_API_URL, USDA_SQLITE_PATH
from app.stats import DayTotals

log = logging.getLogger("mealee.foods")

# FoodData Central nutrient ids.
NUTRIENT_KCAL = 1008
NUTRIENT_PROTEIN = 1003
NUTRIENT_FIBER = 1079
NUTRIENT_SODIUM = 1093
NUTRIENT_CAFFEINE = 1057

GRAM_BAND = 0.30


@dataclass(frozen=True)
class FoodClass:
    label: str
    fdc_id: int
    height_prior_mm: float
    density: float
    veg: bool
    added_sugar_share: float
    caffeine_mg_per_100g: float


@dataclass(frozen=True)
class NutrientsPer100g:
    kcal: float
    protein_g: float
    fiber_g: float
    sodium_mg: float
    caffeine_mg: float


@dataclass(frozen=True)
class FoodSearchResult:
    fdc_id: int
    label: str
    source: str
    kcal: float
    protein_g: float
    fiber_g: float
    sodium_mg: float
    caffeine_mg: float
    is_vegetable: bool = False

    def as_dict(self) -> dict:
        return {
            "fdc_id": self.fdc_id, "label": self.label, "source": self.source,
            "kcal": self.kcal, "protein_g": self.protein_g, "fiber_g": self.fiber_g,
            "sodium_mg": self.sodium_mg, "caffeine_mg": self.caffeine_mg,
            "is_vegetable": self.is_vegetable,
        }


@lru_cache(maxsize=1)
def food_classes() -> dict[str, FoodClass]:
    with open(FOODS_YAML_PATH) as handle:
        raw = yaml.safe_load(handle)["foods"]
    return {entry["label"]: FoodClass(**entry) for entry in raw}


def class_labels() -> list[str]:
    return list(food_classes().keys())


def local_food_search(query: str) -> list[FoodSearchResult]:
    lowered = query.casefold()
    results = []
    for food in food_classes().values():
        if lowered not in food.label.casefold():
            continue
        nutrients = nutrients_per_100g(food.label)
        results.append(FoodSearchResult(
            fdc_id=food.fdc_id, label=food.label, source="Mealee catalog",
            kcal=nutrients.kcal, protein_g=nutrients.protein_g,
            fiber_g=nutrients.fiber_g, sodium_mg=nutrients.sodium_mg,
            caffeine_mg=nutrients.caffeine_mg, is_vegetable=food.veg,
        ))
    return results


async def search_usda(query: str) -> list[FoodSearchResult]:
    params = {
        "api_key": USDA_API_KEY, "query": query, "pageSize": 12,
        "dataType": "Foundation,SR Legacy,Survey (FNDDS)",
    }
    # FoodData Central's edge answers a well-formed request with an nginx 400 on roughly
    # one call in three, at random. Three attempts take a miss from a third to about 4%.
    async with httpx.AsyncClient(timeout=5) as client:
        for attempt in range(3):
            response = await client.get(f"{USDA_API_URL}/foods/search", params=params)
            if response.status_code == httpx.codes.OK:
                break
        response.raise_for_status()
    results = []
    for food in response.json().get("foods", []):
        amounts = {row.get("nutrientId"): row.get("value", 0) for row in food.get("foodNutrients", [])}
        category = food.get("foodCategory", "").casefold()
        results.append(FoodSearchResult(
            fdc_id=int(food["fdcId"]), label=food["description"].strip(),
            source=f"USDA {food.get('dataType', 'FoodData Central')}",
            kcal=float(amounts.get(NUTRIENT_KCAL, 0)),
            protein_g=float(amounts.get(NUTRIENT_PROTEIN, 0)),
            fiber_g=float(amounts.get(NUTRIENT_FIBER, 0)),
            sodium_mg=float(amounts.get(NUTRIENT_SODIUM, 0)),
            caffeine_mg=float(amounts.get(NUTRIENT_CAFFEINE, 0)),
            is_vegetable="vegetable" in category,
        ))
    return results


def usda_available() -> bool:
    return USDA_SQLITE_PATH.exists()


@lru_cache(maxsize=1)
def _fallback_table() -> dict[str, NutrientsPer100g]:
    with open(FOODS_YAML_PATH.parent / "nutrients_fallback.yaml") as handle:
        raw = yaml.safe_load(handle)
    return {label: NutrientsPer100g(**values) for label, values in raw.items()}


@lru_cache(maxsize=64)
def nutrients_per_100g(label: str) -> NutrientsPer100g:
    food = food_classes()[label]
    if not usda_available():
        return _fallback_table()[label]

    connection = sqlite3.connect(f"file:{USDA_SQLITE_PATH}?mode=ro", uri=True)
    rows = connection.execute(
        "SELECT nutrient_id, amount FROM nutrients WHERE fdc_id = ?", (food.fdc_id,)
    ).fetchall()
    connection.close()
    if not rows:
        raise LookupError(f"fdc_id {food.fdc_id} for '{label}' is not in {USDA_SQLITE_PATH}. "
                          f"Run `make verify-foods`.")
    amounts = {nutrient_id: amount for nutrient_id, amount in rows}
    return NutrientsPer100g(
        kcal=amounts.get(NUTRIENT_KCAL, 0.0),
        protein_g=amounts.get(NUTRIENT_PROTEIN, 0.0),
        fiber_g=amounts.get(NUTRIENT_FIBER, 0.0),
        sodium_mg=amounts.get(NUTRIENT_SODIUM, 0.0),
        caffeine_mg=amounts.get(NUTRIENT_CAFFEINE, food.caffeine_mg_per_100g),
    )


def grams_from_area(label: str, area_px: float, px_per_mm: float) -> tuple[float, float, float]:
    food = food_classes()[label]
    area_mm2 = area_px / (px_per_mm * px_per_mm)
    volume_cm3 = area_mm2 * food.height_prior_mm / 1000.0
    grams = volume_cm3 * food.density
    return grams, grams * (1 - GRAM_BAND), grams * (1 + GRAM_BAND)


def add_item_to_totals(totals: DayTotals, label: str, grams: float) -> None:
    food = food_classes()[label]
    per100 = nutrients_per_100g(label)
    scale = grams / 100.0
    totals.kcal += per100.kcal * scale
    totals.protein_g += per100.protein_g * scale
    totals.fiber_g += per100.fiber_g * scale
    totals.sodium_mg += per100.sodium_mg * scale
    totals.caffeine_mg += per100.caffeine_mg * scale
    totals.added_sugar_g += grams * food.added_sugar_share
    if food.veg:
        totals.veg_g += grams
    if label == "coffee":
        totals.water_ml += grams


def warn_if_no_usda() -> None:
    if not usda_available():
        log.warning("data/usda.sqlite not found. Using data/nutrients_fallback.yaml. "
                    "Run `python3 data/build_usda.py` before the demo.")
