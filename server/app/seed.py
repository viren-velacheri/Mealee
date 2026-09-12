"""Seed a demo league so the standings page is never empty.

Three fake players, six prior days of meals, fighters and nightly fights, plus today's
fighters. Idempotent: running it twice wipes and recreates the DEMO league only.

    make seed
"""

import json
import random
import uuid
from datetime import datetime, timedelta

from sqlalchemy import delete, select

from app import battle, game
from app.db import (Discovery, Fight, FightTurn, Fighter, IntakeEvent, League, Meal, MealItem,
                    Player, get_session, init_db)
from app.foods import food_classes

DEMO_CODE = "DEMO"

DEMO_PLAYERS = [
    ("Protein Pete", "🍗", ["chicken breast", "rice", "broccoli", "eggs"]),
    ("Donut Dana", "🍩", ["bagel", "cookie", "cake", "coffee", "fries"]),
    ("Broccoli Bo", "🥦", ["salad greens", "broccoli", "carrots", "beans", "tofu"]),
]

DAILY_GRAMS = {
    "chicken breast": 180, "rice": 220, "broccoli": 140, "eggs": 110, "bagel": 100,
    "cookie": 60, "cake": 120, "coffee": 240, "fries": 130, "salad greens": 120,
    "carrots": 90, "beans": 160, "tofu": 150,
}


def _square_polygon(seed: int) -> list[list[int]]:
    rng = random.Random(seed)
    cx, cy, r = rng.randint(300, 900), rng.randint(300, 900), rng.randint(90, 160)
    return [[cx - r, cy - r], [cx + r, cy - r], [cx + r, cy + r], [cx - r, cy + r]]


def seed_demo() -> None:
    init_db()
    session = get_session()

    old_players = session.scalars(select(Player).where(Player.league_id == DEMO_CODE)).all()
    old_ids = [p.id for p in old_players]
    old_fights = session.scalars(select(Fight).where(Fight.league_id == DEMO_CODE)).all()
    session.execute(delete(FightTurn).where(FightTurn.fight_id.in_([f.id for f in old_fights])))
    session.execute(delete(Fight).where(Fight.league_id == DEMO_CODE))
    old_meals = session.scalars(select(Meal).where(Meal.player_id.in_(old_ids))).all()
    session.execute(delete(MealItem).where(MealItem.meal_id.in_([m.id for m in old_meals])))
    session.execute(delete(Meal).where(Meal.player_id.in_(old_ids)))
    session.execute(delete(IntakeEvent).where(IntakeEvent.player_id.in_(old_ids)))
    session.execute(delete(Fighter).where(Fighter.player_id.in_(old_ids)))
    session.execute(delete(Discovery).where(Discovery.player_id.in_(old_ids)))
    session.execute(delete(Player).where(Player.league_id == DEMO_CODE))
    session.execute(delete(League).where(League.code == DEMO_CODE))
    session.commit()

    today = game.today()
    session.add(League(code=DEMO_CODE, name="HackCMU Demo", week_start=game.week_start(today)))
    players = []
    for name, emoji, _ in DEMO_PLAYERS:
        player = Player(id=str(uuid.uuid4()), league_id=DEMO_CODE, name=name, emoji=emoji)
        session.add(player)
        players.append(player)
    session.commit()

    rng = random.Random(2026)
    for day_offset in range(6, -1, -1):
        day = today - timedelta(days=day_offset)
        for player, (_, _, menu) in zip(players, DEMO_PLAYERS):
            meal = Meal(id=str(uuid.uuid4()), player_id=player.id,
                        taken_at=datetime.combine(day, datetime.min.time()) + timedelta(hours=12),
                        image_path="seed.jpg", image_w=1200, image_h=1200,
                        scale_ref_type="card", scale_px_per_mm=4.2)
            session.add(meal)
            for label in menu:
                grams = DAILY_GRAMS[label] * rng.uniform(0.7, 1.3)
                session.add(MealItem(
                    id=str(uuid.uuid4()), meal_id=meal.id, label=label,
                    fdc_id=food_classes()[label].fdc_id, grams=grams,
                    grams_low=grams * 0.7, grams_high=grams * 1.3,
                    confidence=rng.uniform(0.55, 0.9), area_px=int(grams * 400),
                    polygon_json=json.dumps(_square_polygon(rng.randint(0, 10_000)))))
            for _ in range(rng.randint(3, 8)):
                session.add(IntakeEvent(player_id=player.id, day=day, kind="water"))
            if "coffee" in menu:
                session.add(IntakeEvent(player_id=player.id, day=day, kind="coffee"))
        session.commit()

        for player in players:
            game.compute_fighter(session, player.id, day)

        if day_offset > 0:
            for player_a, player_b in game.nightly_pairings(players, day):
                if player_b is None:
                    continue
                fight = game.run_fight(session, DEMO_CODE, player_a, player_b, "nightly", day)
                fight.created_at = datetime.combine(day, datetime.min.time()) + timedelta(hours=21)
                session.commit()

    for player, (_, _, menu) in zip(players, DEMO_PLAYERS):
        game.record_discoveries(session, player.id, {label: "seed_thumb.jpg" for label in menu})

    print(f"seeded league {DEMO_CODE} with {len(players)} players")
    for player in players:
        print(f"  {player.emoji} {player.name}  player_id={player.id}")
    session.close()


if __name__ == "__main__":
    seed_demo()
