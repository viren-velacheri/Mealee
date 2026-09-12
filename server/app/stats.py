"""Day totals to fighter stats. Frozen after hour 4; do not tune without telling the team.

Every stat is 0 to 100 except recovery, which is HP per turn. Every change comes with a
reason string, because the phone shows why each bar moved.
"""

import math
from dataclasses import dataclass, field

TARGET_KCAL = 2000
TARGET_PROTEIN_G = 100
TARGET_FIBER_G = 30
TARGET_VEG_G = 400
TARGET_ADDED_SUGAR_G = 36
TARGET_WATER_ML = 2500
TARGET_CAFFEINE_MG = 200
TARGET_SODIUM_MG = 2300

WATER_ML_PER_PRESET = 250
COFFEE_MG_PER_PRESET = 95


@dataclass
class DayTotals:
    kcal: float = 0.0
    protein_g: float = 0.0
    fiber_g: float = 0.0
    veg_g: float = 0.0
    added_sugar_g: float = 0.0
    caffeine_mg: float = 0.0
    water_ml: float = 0.0
    sodium_mg: float = 0.0

    def as_dict(self) -> dict:
        return {k: round(v, 1) for k, v in vars(self).items()}


@dataclass
class FighterStats:
    attack: float
    defense: float
    stamina: float
    speed: float
    focus: float
    recovery: float
    crash_turn: int | None
    hp_max: int
    first_strike: bool
    reasons: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "attack": round(self.attack, 1),
            "defense": round(self.defense, 1),
            "stamina": round(self.stamina, 1),
            "speed": round(self.speed, 1),
            "focus": round(self.focus, 1),
            "recovery": round(self.recovery, 2),
            "crash_turn": self.crash_turn,
            "hp_max": self.hp_max,
            "first_strike": self.first_strike,
            "reasons": list(self.reasons),
        }


def _clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def fighter_from_totals(totals: DayTotals) -> FighterStats:
    attack = 100 * min(totals.protein_g / TARGET_PROTEIN_G, 1) ** 0.8
    defense = 60 * min(totals.veg_g / TARGET_VEG_G, 1) + 40 * min(totals.fiber_g / TARGET_FIBER_G, 1)
    stamina = 100 * max(0.0, 1 - abs(totals.kcal / TARGET_KCAL - 1))
    speed = 50 + min(totals.added_sugar_g, 50)
    crash_turn = None if totals.added_sugar_g < 20 else max(3, 10 - math.floor(totals.added_sugar_g / 10))
    focus = (70 + 15 * min(totals.caffeine_mg / TARGET_CAFFEINE_MG, 1)
             - 20 * max(0.0, (totals.caffeine_mg - 400) / 400))
    recovery = (10 * min(totals.water_ml / TARGET_WATER_ML, 1)
                - 5 * max(0.0, (totals.sodium_mg - TARGET_SODIUM_MG) / TARGET_SODIUM_MG))
    first_strike = totals.caffeine_mg >= 100

    attack, defense, stamina = _clamp(attack), _clamp(defense), _clamp(stamina)
    speed, focus = _clamp(speed), _clamp(focus)
    recovery = _clamp(recovery, 0.0, 10.0)
    hp_max = 100 + round(stamina)

    reasons = [
        f"Protein {totals.protein_g:.0f} g: attack {attack:.0f}",
        f"Vegetables {totals.veg_g:.0f} g, fiber {totals.fiber_g:.0f} g: defense {defense:.0f}",
        f"{totals.kcal:.0f} kcal of {TARGET_KCAL}: stamina {stamina:.0f}, HP {hp_max}",
    ]
    if crash_turn is None:
        reasons.append(f"Added sugar {totals.added_sugar_g:.0f} g: speed {speed:.0f}")
    else:
        reasons.append(f"Added sugar {totals.added_sugar_g:.0f} g: speed {speed:.0f}, crash on turn {crash_turn}")
    if first_strike:
        reasons.append(f"Caffeine {totals.caffeine_mg:.0f} mg: focus {focus:.0f}, first strike")
    else:
        reasons.append(f"Caffeine {totals.caffeine_mg:.0f} mg: focus {focus:.0f}")
    reasons.append(f"Water {totals.water_ml:.0f} ml, sodium {totals.sodium_mg:.0f} mg: recovers {recovery:.1f} HP a turn")

    return FighterStats(attack, defense, stamina, speed, focus, recovery,
                        crash_turn, hp_max, first_strike, reasons)


def blend_with_yesterday(today: FighterStats, yesterday: FighterStats | None,
                         has_meals_today: bool) -> FighterStats:
    """0.8 today + 0.2 yesterday. With no meals today the fighter is yesterday * 0.2,
    weak but never zero, so a lapsed player still shows up to the nightly fight."""
    if yesterday is None:
        return today
    if not has_meals_today:
        blended = FighterStats(
            attack=yesterday.attack * 0.2, defense=yesterday.defense * 0.2,
            stamina=yesterday.stamina * 0.2, speed=yesterday.speed * 0.2,
            focus=yesterday.focus * 0.2, recovery=yesterday.recovery * 0.2,
            crash_turn=None, hp_max=100 + round(yesterday.stamina * 0.2),
            first_strike=False, reasons=["No meals logged today: fighting at 20% of yesterday"],
        )
        return blended
    blended = FighterStats(
        attack=0.8 * today.attack + 0.2 * yesterday.attack,
        defense=0.8 * today.defense + 0.2 * yesterday.defense,
        stamina=0.8 * today.stamina + 0.2 * yesterday.stamina,
        speed=0.8 * today.speed + 0.2 * yesterday.speed,
        focus=0.8 * today.focus + 0.2 * yesterday.focus,
        recovery=0.8 * today.recovery + 0.2 * yesterday.recovery,
        crash_turn=today.crash_turn,
        hp_max=100 + round(0.8 * today.stamina + 0.2 * yesterday.stamina),
        first_strike=today.first_strike,
        reasons=list(today.reasons) + ["Includes 20% carry-over from yesterday"],
    )
    return blended
