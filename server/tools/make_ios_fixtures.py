"""Capture real server responses as the iOS MockAPI fixtures.

    cd server && uv run python tools/make_ios_fixtures.py

Writes ios/Mealee/Fixtures/league.json, meal.json and plate_fixture.jpg. The plate is a
drawn image, not a photo, with a card rectangle at true credit card proportions so the
real card detector runs against it. Segmentation is stubbed with the drawn shapes.
"""

import io
import sys
import pathlib as _pathlib

sys.path.insert(0, str(_pathlib.Path(__file__).resolve().parents[1]))
import json
import os
import pathlib
import tempfile

tmp = tempfile.mkdtemp(prefix="mealee-fixtures-")
os.environ["SQLITE_PATH"] = f"{tmp}/fixtures.sqlite"
os.environ["UPLOAD_DIR"] = f"{tmp}/uploads"
os.environ["REDIS_URL"] = ""
os.environ["MONGODB_URI"] = ""
os.environ["IFM_API_KEY"] = ""

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app import portions, seed
from app.main import app

FIXTURES = pathlib.Path(__file__).resolve().parents[2] / "ios/Mealee/Fixtures"
W, H = 1200, 900

PIZZA = [(300, 250), (620, 210), (700, 470), (560, 560), (330, 500)]
BROCCOLI_CENTRES = [(880, 300, 90), (960, 420, 80), (830, 440, 70)]
CARD = (120, 640, 120 + 360, 640 + 227)   # 360 x 227 px = 85.6 x 54 mm at 4.2 px/mm


def draw_plate() -> Image.Image:
    image = Image.new("RGB", (W, H), (222, 214, 200))
    draw = ImageDraw.Draw(image)
    draw.ellipse((150, 80, 1100, 640), fill=(248, 247, 243), outline=(200, 200, 195), width=6)
    draw.polygon(PIZZA, fill=(214, 120, 62))
    for x, y in [(400, 330), (520, 300), (470, 430), (600, 400)]:
        draw.ellipse((x - 28, y - 28, x + 28, y + 28), fill=(178, 44, 44))
    for cx, cy, r in BROCCOLI_CENTRES:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(64, 130, 58))
        draw.ellipse((cx - r * 0.6, cy - r * 0.6, cx + r * 0.6, cy + r * 0.6), fill=(88, 160, 72))
    draw.rounded_rectangle(CARD, radius=14, fill=(38, 70, 150), outline=(20, 30, 60), width=4)
    draw.rectangle((CARD[0] + 30, CARD[1] + 60, CARD[0] + 110, CARD[1] + 110), fill=(220, 190, 90))
    return image


def masks_from_drawing(image_bgr):
    pizza = np.zeros((H, W), dtype=np.uint8)
    ImageDraw.Draw(pil := Image.fromarray(pizza)).polygon(PIZZA, fill=1)
    pizza = np.array(pil).astype(bool)
    broccoli = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(broccoli)
    for cx, cy, r in BROCCOLI_CENTRES:
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=1)
    return [("pizza", 0.87, pizza), ("broccoli", 0.74, np.array(broccoli).astype(bool))]


def main() -> None:
    portions.segment = masks_from_drawing
    plate = draw_plate()
    buffer = io.BytesIO()
    plate.save(buffer, "JPEG", quality=88)
    jpeg = buffer.getvalue()

    detected = portions.find_card_px_per_mm(portions.decode_image(jpeg))
    print(f"card detector on drawn plate: {detected and round(detected, 3)} px/mm (drawn at 4.206)")

    seed.seed_demo()
    with TestClient(app) as client:
        league = client.get("/leagues/DEMO").json()
        player_id = league["players"][0]["player_id"]
        response = client.post("/meals", data={"player_id": player_id},
                               files={"image": ("plate.jpg", jpeg, "image/jpeg")})
        assert response.status_code == 200, response.text
        meal = response.json()
        league = client.get("/leagues/DEMO").json()

    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / "league.json").write_text(json.dumps(league, indent=2) + "\n")
    (FIXTURES / "meal.json").write_text(json.dumps(meal, indent=2) + "\n")
    (FIXTURES / "plate_fixture.jpg").write_bytes(jpeg)
    print(f"meal fixture: scale={meal['scale']}, items={[(i['label'], i['grams']) for i in meal['items']]}")
    print(f"wrote {FIXTURES}")


if __name__ == "__main__":
    main()
