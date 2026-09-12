"""Everything between the routes and the database. No HTTP here, no CV here."""

import json
import random
import uuid
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import battle, identity
from app.config import LOCAL_TZ
from app.db import (CatalogFood, Discovery, Fight, FightTurn, Fighter, IntakeEvent, League, Meal,
                    MealItem, Player)
from app.foods import add_item_to_totals, food_classes
from app.stats import (COFFEE_MG_PER_PRESET, WATER_ML_PER_PRESET, DayTotals, FighterStats,
                       blend_with_yesterday, fighter_from_totals)

LEAGUE_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ"


def today() -> date:
    return datetime.now(ZoneInfo(LOCAL_TZ)).date()


def week_start(day: date) -> date:
    return day - timedelta(days=day.weekday())


ARENA_CODE = "ARENA"


# Everyone plays in one arena. The league table stays because standings, the realtime
# channel and the projector page are all keyed by code; there is simply only ever one.
def ensure_arena(session: Session) -> League:
    league = session.get(League, ARENA_CODE)
    if league is None:
        league = League(code=ARENA_CODE, name="Mealee Arena", week_start=week_start(today()))
        session.add(league)
        session.commit()
    return league


def new_league_code(session: Session) -> str:
    while True:
        code = "".join(random.choices(LEAGUE_CODE_ALPHABET, k=4))
        if session.get(League, code) is None:
            return code


def fold_meal_into_totals(session: Session, totals: DayTotals, meal: Meal) -> list[tuple[str, float]]:
    eaten: list[tuple[str, float]] = []
    for item in session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)):
        eaten.append((item.label, item.grams))
        if item.label in food_classes():
            add_item_to_totals(totals, item.label, item.grams)
        else:
            catalog_food = session.get(CatalogFood, item.fdc_id)
            if catalog_food is not None:
                scale = item.grams / 100.0
                totals.kcal += catalog_food.kcal * scale
                totals.protein_g += catalog_food.protein_g * scale
                totals.fiber_g += catalog_food.fiber_g * scale
                totals.sodium_mg += catalog_food.sodium_mg * scale
                totals.caffeine_mg += catalog_food.caffeine_mg * scale
                if catalog_food.is_vegetable:
                    totals.veg_g += item.grams
    return eaten


def day_totals(session: Session, player_id: str, day: date,
               include_meal_id: str | None = None) -> tuple[DayTotals, bool]:
    totals = DayTotals()
    meals = session.scalars(select(Meal).where(Meal.player_id == player_id)).all()
    meals = [meal for meal in meals
             if meal.status == "confirmed" or meal.id == include_meal_id]
    day_meals = [meal for meal in meals if meal.taken_at.date() == day]
    for meal in day_meals:
        fold_meal_into_totals(session, totals, meal)
    intake = session.scalars(select(IntakeEvent).where(
        IntakeEvent.player_id == player_id, IntakeEvent.day == day)).all()
    for event in intake:
        if event.kind == "water":
            totals.water_ml += WATER_ML_PER_PRESET
        else:
            totals.caffeine_mg += COFFEE_MG_PER_PRESET
            totals.water_ml += WATER_ML_PER_PRESET
    return totals, bool(day_meals) or bool(intake)


def _stats_from_row(row: Fighter) -> FighterStats:
    return FighterStats(row.attack, row.defense, row.stamina, row.speed, row.focus,
                        row.recovery, row.crash_turn, row.hp_max, row.first_strike,
                        json.loads(row.reasons_json))


def fighter_row(session: Session, player_id: str, day: date) -> Fighter | None:
    return session.scalars(select(Fighter).where(
        Fighter.player_id == player_id, Fighter.day == day)).first()


def fighter_stats_for_day(session: Session, player_id: str, day: date,
                          include_meal_id: str | None = None) -> tuple[DayTotals, FighterStats]:
    """Calculate stats without persisting them; a draft meal can be included for preview."""
    totals, has_intake = day_totals(session, player_id, day, include_meal_id)
    stats = fighter_from_totals(totals)
    yesterday = fighter_row(session, player_id, day - timedelta(days=1))
    stats = blend_with_yesterday(stats, _stats_from_row(yesterday) if yesterday else None, has_intake)
    return totals, stats


STAT_NAMES = ("attack", "defense", "stamina", "speed", "focus", "recovery")
NUTRIENT_NAMES = ("kcal", "protein_g", "fiber_g", "veg_g", "caffeine_mg", "water_ml", "sodium_mg")


def timeline(session: Session, player_id: str, day: date | None = None) -> list[dict]:
    """The day in order: meals and drinks, each with what it added and what it moved."""
    day = day or today()
    meals = [meal for meal in session.scalars(select(Meal).where(Meal.player_id == player_id))
             if meal.status == "confirmed" and meal.taken_at.date() == day]
    drinks = session.scalars(select(IntakeEvent).where(
        IntakeEvent.player_id == player_id, IntakeEvent.day == day)).all()

    events = ([(meal.taken_at, "meal", meal) for meal in meals]
              + [(drink.created_at, "drink", drink) for drink in drinks])
    events.sort(key=lambda event: event[0])

    running = DayTotals()
    entries = []
    for when, kind, row in events:
        before_stats = fighter_from_totals(running)
        before = running.as_dict()

        if kind == "meal":
            eaten = fold_meal_into_totals(session, running, row)
            label = ", ".join(f"{label} {grams:.0f}g" for label, grams in eaten) or "meal"
            items = [{"label": label, "grams": round(grams, 1)} for label, grams in eaten]
        else:
            if row.kind == "water":
                running.water_ml += WATER_ML_PER_PRESET
            else:
                running.caffeine_mg += COFFEE_MG_PER_PRESET
                running.water_ml += WATER_ML_PER_PRESET
            label = "Water" if row.kind == "water" else "Coffee"
            items = []

        after = running.as_dict()
        after_stats = fighter_from_totals(running)
        entries.append({
            "entry_id": f"{kind}-{row.id}",
            "kind": kind,
            "label": label,
            "taken_at": when.isoformat() + "Z",
            "items": items,
            "nutrients": {name: round(after.get(name, 0) - before.get(name, 0), 1)
                          for name in NUTRIENT_NAMES},
            "delta": {name: round(getattr(after_stats, name) - getattr(before_stats, name), 1)
                      for name in STAT_NAMES},
        })
    return entries


def compute_fighter(session: Session, player_id: str, day: date | None = None) -> Fighter:
    day = day or today()
    _, stats = fighter_stats_for_day(session, player_id, day)

    row = fighter_row(session, player_id, day)
    if row is None:
        row = Fighter(id=str(uuid.uuid4()), player_id=player_id, day=day)
        session.add(row)
    row.attack, row.defense, row.stamina = stats.attack, stats.defense, stats.stamina
    row.speed, row.focus, row.recovery = stats.speed, stats.focus, stats.recovery
    row.crash_turn, row.hp_max, row.first_strike = stats.crash_turn, stats.hp_max, stats.first_strike
    row.reasons_json = json.dumps(stats.reasons)
    row.computed_at = datetime.utcnow()
    session.commit()
    return row


def fighter_payload(row: Fighter) -> dict:
    return _stats_from_row(row).as_dict()


def combat_int(value: float) -> int:
    """Truncating conversion shared with Swift's Int(value + 0.5). Never round()."""
    return int(value + 0.5)


def sim_fighter(row: Fighter, name: str) -> battle.Fighter:
    return battle.Fighter(
        name=name,
        attack=combat_int(row.attack),
        defense=combat_int(row.defense),
        stamina=combat_int(row.stamina),
        speed=combat_int(row.speed),
        focus=combat_int(row.focus),
        recovery_milli=combat_int(row.recovery * 1000),
        hp_max=row.hp_max,
        crash_turn=row.crash_turn,
        first_strike=row.first_strike,
    )


def combatant_payload(player: Player, fighter: battle.Fighter) -> dict:
    return {
        "player_id": player.id,
        "name": player.name,
        "emoji": player.emoji,
        "attack": fighter.attack,
        "defense": fighter.defense,
        "stamina": fighter.stamina,
        "speed": fighter.speed,
        "focus": fighter.focus,
        "recovery_milli": fighter.recovery_milli,
        "hp_max": fighter.hp_max,
        "crash_turn": fighter.crash_turn,
        "first_strike": fighter.first_strike,
    }


def run_fight(session: Session, league_code: str, player_a: Player, player_b: Player,
              kind: str, day: date | None = None) -> Fight:
    fight_id = str(uuid.uuid4())
    seed = battle.seed_from_fight_id(fight_id)
    row_a = compute_fighter(session, player_a.id, day)
    row_b = compute_fighter(session, player_b.id, day)
    sim_a, sim_b = sim_fighter(row_a, player_a.name), sim_fighter(row_b, player_b.name)
    outcome = battle.simulate(seed, sim_a, sim_b)

    fight = Fight(
        id=fight_id, league_id=league_code,
        a_player_id=player_a.id, b_player_id=player_b.id,
        a_fighter_id=row_a.id, b_fighter_id=row_b.id,
        seed=seed, kind=kind,
        winner_id=player_a.id if outcome["winner"] == "a" else player_b.id,
        a_damage_dealt=sum(t["damage"] for t in outcome["turns"] if t["actor"] == "a"),
        b_damage_dealt=sum(t["damage"] for t in outcome["turns"] if t["actor"] == "b"),
    )
    session.add(fight)
    for turn in outcome["turns"]:
        session.add(FightTurn(fight_id=fight_id, **turn))
    session.commit()

    identity.record_fight_result(player_a.id, fight_id, fight.winner_id == player_a.id, kind)
    identity.record_fight_result(player_b.id, fight_id, fight.winner_id == player_b.id, kind)
    return fight


def fight_payload(session: Session, fight: Fight) -> dict:
    player_a, player_b = session.get(Player, fight.a_player_id), session.get(Player, fight.b_player_id)
    row_a, row_b = session.get(Fighter, fight.a_fighter_id), session.get(Fighter, fight.b_fighter_id)
    turns = session.scalars(select(FightTurn).where(FightTurn.fight_id == fight.id)
                            .order_by(FightTurn.id)).all()
    return {
        "fight_id": fight.id,
        "seed": fight.seed,
        "kind": fight.kind,
        "league_code": fight.league_id,
        "winner_id": fight.winner_id,
        "created_at": fight.created_at.isoformat() + "Z",
        "a": combatant_payload(player_a, sim_fighter(row_a, player_a.name)),
        "b": combatant_payload(player_b, sim_fighter(row_b, player_b.name)),
        "turns": [{"turn": t.turn, "actor": t.actor, "action": t.action, "damage": t.damage,
                   "a_hp": t.a_hp, "b_hp": t.b_hp, "note": t.note} for t in turns],
    }


def latest_fight(session: Session, league_code: str) -> Fight | None:
    return session.scalars(select(Fight).where(Fight.league_id == league_code)
                           .order_by(Fight.created_at.desc())).first()


def nightly_pairings(players: list[Player], day: date) -> list[tuple[Player, Player | None]]:
    """Deterministic for a given day so the league page can show tonight's card before
    21:00. Odd player count gives one bye."""
    ordered = sorted(players, key=lambda player: player.id)
    random.Random(day.toordinal()).shuffle(ordered)
    pairings: list[tuple[Player, Player | None]] = []
    for index in range(0, len(ordered) - 1, 2):
        pairings.append((ordered[index], ordered[index + 1]))
    if len(ordered) % 2 == 1:
        pairings.append((ordered[-1], None))
    return pairings


def league_payload(session: Session, league: League) -> dict:
    players = session.scalars(select(Player).where(Player.league_id == league.code)).all()
    start = week_start(today())
    fights = [f for f in session.scalars(select(Fight).where(Fight.league_id == league.code))
              if f.created_at.date() >= start]

    wins = {p.id: 0 for p in players}
    damage = {p.id: 0 for p in players}
    for fight in fights:
        if fight.winner_id in wins:
            wins[fight.winner_id] += 1
        if fight.a_player_id in damage:
            damage[fight.a_player_id] += fight.a_damage_dealt
        if fight.b_player_id in damage:
            damage[fight.b_player_id] += fight.b_damage_dealt

    discovered = {}
    for row in session.scalars(select(Discovery).where(Discovery.week_start == start)):
        discovered[row.player_id] = discovered.get(row.player_id, 0) + 1

    player_dicts = []
    for player in players:
        today_row = fighter_row(session, player.id, today())
        player_dicts.append({
            "player_id": player.id,
            "name": player.name,
            "emoji": player.emoji,
            "discovered": discovered.get(player.id, 0),
            "fighter": fighter_payload(today_row) if today_row else None,
        })

    standings = sorted(
        [{"player_id": p.id, "name": p.name, "emoji": p.emoji,
          "wins": wins[p.id], "damage": damage[p.id]} for p in players],
        key=lambda entry: (-entry["wins"], -entry["damage"], entry["name"]),
    )
    for rank, entry in enumerate(standings, start=1):
        entry["rank"] = rank

    tonight = []
    for player_a, player_b in nightly_pairings(players, today()):
        tonight.append({
            "a": {"player_id": player_a.id, "name": player_a.name, "emoji": player_a.emoji},
            "b": ({"player_id": player_b.id, "name": player_b.name, "emoji": player_b.emoji}
                  if player_b else None),
        })

    return {
        "code": league.code,
        "name": league.name,
        "week_start": start.isoformat(),
        "players": player_dicts,
        "standings": standings,
        "tonight": tonight,
    }


def record_discoveries(session: Session, player_id: str, labels_with_thumbs: dict[str, str]) -> list[str]:
    start = week_start(today())
    new_labels = undiscovered_labels(session, player_id, labels_with_thumbs)
    for label in new_labels:
        thumbnail_path = labels_with_thumbs[label]
        session.add(Discovery(player_id=player_id, label=label, week_start=start,
                              thumbnail_path=thumbnail_path))
        identity.record_discovery(player_id, label, start.isoformat())
    session.commit()
    return new_labels


def undiscovered_labels(session: Session, player_id: str, labels) -> list[str]:
    start = week_start(today())
    existing = {row.label for row in session.scalars(select(Discovery).where(
        Discovery.player_id == player_id, Discovery.week_start == start))}
    return list(dict.fromkeys(
        label for label in labels if label not in existing and label in food_classes()
    ))


def discoveries_payload(session: Session, player_id: str) -> dict:
    start = week_start(today())
    rows = session.scalars(select(Discovery).where(
        Discovery.player_id == player_id, Discovery.week_start == start)).all()
    return {
        "week_start": start.isoformat(),
        "total": len(food_classes()),
        "discovered": [{"label": r.label, "thumbnail_url": f"/uploads/{r.thumbnail_path}",
                        "found_at": (r.found_at or datetime.combine(r.week_start, time.min)).isoformat() + "Z"}
                       for r in rows],
    }


def meal_payload(session: Session, meal: Meal, new_labels: list[str] | None = None) -> dict:
    items = session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)).all()
    if meal.status == "draft":
        totals, stats = fighter_stats_for_day(session, meal.player_id, today(), meal.id)
        fighter = stats.as_dict()
    else:
        fighter = fighter_payload(compute_fighter(session, meal.player_id))
        totals, _ = day_totals(session, meal.player_id, today())
    return {
        "meal_id": meal.id,
        "image_w": meal.image_w,
        "image_h": meal.image_h,
        "image_url": f"/uploads/{meal.image_path}",
        "items": [{
            "item_id": item.id,
            "label": item.label,
            "fdc_id": item.fdc_id,
            "grams": round(item.grams, 1),
            "grams_low": round(item.grams_low, 1),
            "grams_high": round(item.grams_high, 1),
            "confidence": round(item.confidence, 2),
            "polygon": json.loads(item.polygon_json),
            "is_new": item.label in (new_labels or []),
        } for item in items],
        "scale": {"type": meal.scale_ref_type, "px_per_mm": round(meal.scale_px_per_mm, 3)},
        "day_totals": totals.as_dict(),
        "fighter": fighter,
    }
