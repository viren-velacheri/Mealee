"""Everything between the routes and the database. No HTTP here, no CV here."""

import json
import random
import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import battle, identity
from app.config import LOCAL_TZ
from app.db import (Discovery, Fight, FightTurn, Fighter, IntakeEvent, League, Meal,
                    MealItem, Player)
from app.foods import add_item_to_totals, food_classes
from app.stats import (COFFEE_MG_PER_PRESET, WATER_ML_PER_PRESET, DayTotals, FighterStats,
                       blend_with_yesterday, fighter_from_totals)

LEAGUE_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ"


def today() -> date:
    return datetime.now(ZoneInfo(LOCAL_TZ)).date()


def week_start(day: date) -> date:
    return day - timedelta(days=day.weekday())


def new_league_code(session: Session) -> str:
    while True:
        code = "".join(random.choices(LEAGUE_CODE_ALPHABET, k=4))
        if session.get(League, code) is None:
            return code


def day_totals(session: Session, player_id: str, day: date) -> tuple[DayTotals, bool]:
    totals = DayTotals()
    meals = session.scalars(select(Meal).where(
        Meal.player_id == player_id, Meal.status == "confirmed")).all()
    day_meals = [meal for meal in meals if meal.taken_at.date() == day]
    for meal in day_meals:
        for item in session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)):
            if item.label in food_classes():
                add_item_to_totals(totals, item.label, item.grams)
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


def compute_fighter(session: Session, player_id: str, day: date | None = None) -> Fighter:
    day = day or today()
    totals, has_intake = day_totals(session, player_id, day)
    stats = fighter_from_totals(totals)
    yesterday = fighter_row(session, player_id, day - timedelta(days=1))
    stats = blend_with_yesterday(stats, _stats_from_row(yesterday) if yesterday else None, has_intake)

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
    existing = {row.label for row in session.scalars(select(Discovery).where(
        Discovery.player_id == player_id, Discovery.week_start == start))}
    new_labels = []
    for label, thumbnail_path in labels_with_thumbs.items():
        if label in existing or label not in food_classes():
            continue
        session.add(Discovery(player_id=player_id, label=label, week_start=start,
                              thumbnail_path=thumbnail_path))
        identity.record_discovery(player_id, label, start.isoformat())
        new_labels.append(label)
    session.commit()
    return new_labels


def discoveries_payload(session: Session, player_id: str) -> dict:
    start = week_start(today())
    rows = session.scalars(select(Discovery).where(
        Discovery.player_id == player_id, Discovery.week_start == start)).all()
    return {
        "week_start": start.isoformat(),
        "total": len(food_classes()),
        "discovered": [{"label": r.label, "thumbnail_url": f"/uploads/{r.thumbnail_path}"} for r in rows],
    }


def meal_payload(session: Session, meal: Meal, new_labels: list[str] | None = None) -> dict:
    items = session.scalars(select(MealItem).where(MealItem.meal_id == meal.id)).all()
    fighter = compute_fighter(session, meal.player_id)
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
        "fighter": fighter_payload(fighter),
    }
