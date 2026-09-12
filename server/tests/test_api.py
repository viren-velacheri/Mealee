import io
import json

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app import portions
from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(scope="module")
def league(client):
    return client.post("/leagues", json={"name": "Test League"}).json()["code"]


@pytest.fixture(scope="module")
def players(client, league):
    ids = []
    for name, emoji in (("Ann", "🥗"), ("Ben", "🍕")):
        response = client.post("/players", json={"league_code": league, "name": name, "emoji": emoji})
        assert response.status_code == 200, response.text
        ids.append(response.json()["player_id"])
    return ids


def _plate_jpeg(width=1200, height=900) -> bytes:
    image = Image.new("RGB", (width, height), (240, 240, 235))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=85)
    return buffer.getvalue()


def _fake_segment(image_bgr):
    """Two food masks and a fork, in place of YOLO, so the meal path runs without weights."""
    height, width = image_bgr.shape[:2]
    pizza = np.zeros((height, width), dtype=bool)
    pizza[200:500, 200:600] = True
    broccoli = np.zeros((height, width), dtype=bool)
    broccoli[550:800, 300:520] = True
    fork = np.zeros((height, width), dtype=bool)
    fork[100:130, 700:1150] = True
    return [("pizza", 0.81, pizza), ("broccoli", 0.66, broccoli), ("fork", 0.9, fork)]


def test_health(client):
    body = client.get("/health").json()
    assert body["ok"] and body["classes"] == 30


def test_unknown_player_is_422(client):
    response = client.get("/fighters/nope/today")
    assert response.status_code == 422
    assert response.json()["error"] == "unknown player"


def test_new_player_has_a_fighter(client, players):
    fighter = client.get(f"/fighters/{players[0]}/today").json()
    assert fighter["hp_max"] == 100
    assert fighter["reasons"]


def test_meal_without_scale_reference_is_400(client, players, monkeypatch):
    monkeypatch.setattr(portions, "segment", lambda image: [])
    monkeypatch.setattr(portions, "find_card_px_per_mm", lambda image: None)
    response = client.post("/meals", data={"player_id": players[0]},
                           files={"image": ("plate.jpg", _plate_jpeg(), "image/jpeg")})
    assert response.status_code == 400
    assert response.json()["hint"] == "place a card or fork on the plate"


def test_meal_path_end_to_end(client, players, monkeypatch):
    monkeypatch.setattr(portions, "segment", _fake_segment)
    monkeypatch.setattr(portions, "find_card_px_per_mm", lambda image: None)
    response = client.post("/meals", data={"player_id": players[0]},
                           files={"image": ("plate.jpg", _plate_jpeg(), "image/jpeg")})
    assert response.status_code == 200, response.text
    meal = response.json()

    assert meal["scale"]["type"] == "fork"
    assert meal["image_w"] == 1200 and meal["image_h"] == 900
    labels = {item["label"] for item in meal["items"]}
    assert labels == {"pizza slice", "broccoli"}
    for item in meal["items"]:
        assert item["grams_low"] < item["grams"] < item["grams_high"]
        assert 3 <= len(item["polygon"]) <= 40
        assert all(0 <= x <= 1200 and 0 <= y <= 900 for x, y in item["polygon"])
    assert meal["day_totals"]["veg_g"] > 0
    assert meal["fighter"]["attack"] > 0
    assert any("attack" in reason for reason in meal["fighter"]["reasons"])
    assert {item["label"] for item in meal["items"] if item["is_new"]} == labels

    discoveries = client.get(f"/players/{players[0]}/discoveries").json()
    assert {d["label"] for d in discoveries["discovered"]} == labels
    assert discoveries["total"] == 30


def test_relabel_recomputes_grams_and_fighter(client, players, monkeypatch):
    monkeypatch.setattr(portions, "segment", _fake_segment)
    monkeypatch.setattr(portions, "find_card_px_per_mm", lambda image: 4.5)
    meal = client.post("/meals", data={"player_id": players[1]},
                       files={"image": ("plate.jpg", _plate_jpeg(), "image/jpeg")}).json()
    assert meal["scale"]["type"] == "card"
    pizza = next(item for item in meal["items"] if item["label"] == "pizza slice")
    attack_before = meal["fighter"]["attack"]

    response = client.patch(f"/meals/{meal['meal_id']}/items/{pizza['item_id']}", json={"label": "chicken breast"})
    assert response.status_code == 200, response.text
    updated = response.json()
    chicken = next(item for item in updated["items"] if item["item_id"] == pizza["item_id"])
    assert chicken["label"] == "chicken breast"
    assert chicken["grams"] != pizza["grams"]
    assert updated["fighter"]["attack"] > attack_before

    bad = client.patch(f"/meals/{meal['meal_id']}/items/{pizza['item_id']}", json={"label": "haggis"})
    assert bad.status_code == 400


def test_intake_presets(client, players):
    before = client.get(f"/fighters/{players[0]}/today").json()
    for _ in range(4):
        response = client.post("/intake", json={"player_id": players[0], "kind": "water"})
        assert response.status_code == 200
    body = client.post("/intake", json={"player_id": players[0], "kind": "coffee"}).json()
    assert body["day_totals"]["water_ml"] == 5 * 250
    assert body["day_totals"]["caffeine_mg"] == 95
    assert body["fighter"]["recovery"] > before["recovery"]
    assert body["fighter"]["focus"] > before["focus"]


def test_quick_match_is_replayable_from_the_response(client, players):
    response = client.post("/fights", json={"a_player_id": players[0], "b_player_id": players[1], "kind": "quick"})
    assert response.status_code == 200, response.text
    fight = response.json()
    assert fight["winner_id"] in players
    assert fight["turns"] and fight["turns"][-1]["turn"] <= 20
    assert fight["a"]["player_id"] == players[0]

    from app.battle import Fighter, simulate
    combatant = lambda c: Fighter(c["name"], c["attack"], c["defense"], c["stamina"], c["speed"], c["focus"],
                                  c["recovery_milli"], c["hp_max"], c["crash_turn"], c["first_strike"])
    replay = simulate(fight["seed"], combatant(fight["a"]), combatant(fight["b"]))
    assert replay["turns"] == fight["turns"]
    assert (replay["winner"] == "a") == (fight["winner_id"] == players[0])

    same = client.get(f"/fights/{fight['fight_id']}").json()
    assert same == fight
    latest = client.get(f"/leagues/{fight['league_code']}/latest-fight").json()
    assert latest["fight_id"] == fight["fight_id"]


def test_league_standings_and_tonight(client, league, players):
    body = client.get(f"/leagues/{league}").json()
    assert [p["player_id"] for p in body["players"]] == players
    assert body["standings"][0]["rank"] == 1
    assert sum(s["wins"] for s in body["standings"]) == 1
    assert len(body["tonight"]) == 1 and body["tonight"][0]["b"] is not None
    assert body["players"][0]["discovered"] == 2


def test_fight_between_leagues_is_400(client, players):
    other = client.post("/leagues", json={"name": "Other"}).json()["code"]
    stranger = client.post("/players", json={"league_code": other, "name": "Zed", "emoji": "🐍"}).json()["player_id"]
    response = client.post("/fights", json={"a_player_id": players[0], "b_player_id": stranger, "kind": "quick"})
    assert response.status_code == 400


def test_websocket_receives_fight_events(client, league, players):
    with client.websocket_connect(f"/ws/league/{league}") as socket:
        client.post("/fights", json={"a_player_id": players[0], "b_player_id": players[1], "kind": "quick"})
        message = json.loads(socket.receive_text())
        assert message["type"] == "fight_started"
        assert message["fight"]["turns"]


def test_arena_page_serves(client, league):
    response = client.get(f"/arena/{league}")
    assert response.status_code == 200
    assert "Mealee" in response.text and "WebSocket" in response.text


def test_unhandled_error_never_leaks_a_trace(client, monkeypatch):
    from app import game
    monkeypatch.setattr(game, "league_payload", lambda *args: 1 / 0)
    response = client.get("/leagues/DEMO", headers={})
    assert response.status_code in (404, 500)
    assert "Traceback" not in response.text
