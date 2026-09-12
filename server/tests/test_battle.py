import json
import pathlib

from app.battle import Fighter, Mulberry32, seed_from_fight_id, simulate

FIXTURES = pathlib.Path(__file__).resolve().parents[2] / "ios/Mealee/Fixtures/battle_fixtures.json"


def test_rng_matches_canonical_mulberry32():
    rng = Mulberry32(1)
    assert [rng.next_u32() for _ in range(3)] == [2693262067, 11749833, 2265367787]


def test_fixtures_still_reproduce():
    for fixture in json.loads(FIXTURES.read_text()):
        outcome = simulate(fixture["seed"], Fighter(**fixture["a"]), Fighter(**fixture["b"]))
        assert outcome == fixture["expected"], fixture["fight_id"]


def test_seed_is_stable_for_a_fight_id():
    assert seed_from_fight_id("quick-demo-001") == 2967037554


def test_two_empty_fighters_still_produce_a_winner_within_twenty_turns():
    empty = Fighter("Empty", 0, 0, 0, 50, 70, 0, 100, None, False)
    outcome = simulate(7, empty, empty)
    assert outcome["winner"] in ("a", "b")
    assert outcome["turns"][-1]["turn"] <= 20


def test_first_strike_goes_first_regardless_of_speed():
    slow_caffeinated = Fighter("Slow", 50, 50, 50, 10, 100, 0, 150, None, True)
    fast = Fighter("Fast", 50, 50, 50, 99, 100, 0, 150, None, False)
    outcome = simulate(3, slow_caffeinated, fast)
    assert outcome["turns"][0]["actor"] == "a"
