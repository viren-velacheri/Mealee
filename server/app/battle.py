"""Deterministic auto-battle. The same seed and the same two fighters always produce
the same turn log, here and in ios/Mealee/Models/BattleSim.swift.

All combat arithmetic is integer. HP is tracked in thousandths of a hit point so that
Python and Swift cannot drift apart in a low bit and fail the cross-language log test.
"""

from dataclasses import dataclass

MASK32 = 0xFFFFFFFF
MAX_TURNS = 20


class Mulberry32:
    def __init__(self, seed: int) -> None:
        self.state = seed & MASK32

    def next_u32(self) -> int:
        self.state = (self.state + 0x6D2B79F5) & MASK32
        t = ((self.state ^ (self.state >> 15)) * (self.state | 1)) & MASK32
        t = (((t + (((t ^ (t >> 7)) * (t | 61)) & MASK32)) & MASK32) ^ t) & MASK32
        return (t ^ (t >> 14)) & MASK32


@dataclass
class Fighter:
    name: str
    attack: int
    defense: int
    stamina: int
    speed: int
    focus: int
    recovery_milli: int
    hp_max: int
    crash_turn: int | None
    first_strike: bool


def seed_from_fight_id(fight_id: str) -> int:
    """FNV-1a over the fight id. Reimplemented in Swift, so it cannot use hash()."""
    h = 0x811C9DC5
    for byte in fight_id.encode("utf-8"):
        h = ((h ^ byte) * 0x01000193) & MASK32
    return h


def _display_hp(hp_milli: int) -> int:
    if hp_milli <= 0:
        return 0
    return (hp_milli + 500) // 1000


def simulate(seed: int, fighter_a: Fighter, fighter_b: Fighter) -> dict:
    rng = Mulberry32(seed)

    speed = {"a": fighter_a.speed, "b": fighter_b.speed}
    stamina = {"a": fighter_a.stamina, "b": fighter_b.stamina}
    hp_milli = {"a": fighter_a.hp_max * 1000, "b": fighter_b.hp_max * 1000}
    hp_max_milli = {"a": fighter_a.hp_max * 1000, "b": fighter_b.hp_max * 1000}
    fighters = {"a": fighter_a, "b": fighter_b}

    turns: list[dict] = []
    winner: str | None = None

    def log(turn: int, actor: str, action: str, damage_milli: int, note: str) -> None:
        turns.append({
            "turn": turn,
            "actor": actor,
            "action": action,
            "damage": _display_hp(damage_milli),
            "a_hp": _display_hp(hp_milli["a"]),
            "b_hp": _display_hp(hp_milli["b"]),
            "note": note,
        })

    for turn in range(1, MAX_TURNS + 1):
        if fighter_a.first_strike != fighter_b.first_strike:
            order = ["a", "b"] if fighter_a.first_strike else ["b", "a"]
        elif speed["a"] != speed["b"]:
            order = ["a", "b"] if speed["a"] > speed["b"] else ["b", "a"]
        else:
            order = ["a", "b"] if seed % 2 == 0 else ["b", "a"]

        for actor in order:
            target = "b" if actor == "a" else "a"

            if fighters[actor].crash_turn == turn:
                speed[actor] = speed[actor] // 2
                stamina[actor] = stamina[actor] - 20
                log(turn, actor, "crash", 0,
                    f"Sugar crash: speed halved to {speed[actor]}")

            if rng.next_u32() % 1000 < fighters[actor].focus * 10:
                variance = 850 + rng.next_u32() % 300
                damage_milli = fighters[actor].attack * (200 - fighters[target].defense) * variance // 200
                hp_milli[target] -= damage_milli
                log(turn, actor, "hit", damage_milli,
                    f"{fighters[actor].name} hits for {_display_hp(damage_milli)}")
            else:
                log(turn, actor, "miss", 0, f"{fighters[actor].name} misses")

            if hp_milli[target] <= 0:
                hp_milli[target] = 0
                winner = actor
                break

        if winner is not None:
            break

        for actor in ("a", "b"):
            healed = min(fighters[actor].recovery_milli, hp_max_milli[actor] - hp_milli[actor])
            if healed <= 0:
                continue
            hp_milli[actor] += healed
            log(turn, actor, "recover", 0,
                f"{fighters[actor].name} recovers {_display_hp(healed)}")

    if winner is None:
        left = hp_milli["a"] * hp_max_milli["b"]
        right = hp_milli["b"] * hp_max_milli["a"]
        if left != right:
            winner = "a" if left > right else "b"
        else:
            winner = "a" if seed % 2 == 0 else "b"

    return {
        "seed": seed,
        "winner": winner,
        "a_hp": _display_hp(hp_milli["a"]),
        "b_hp": _display_hp(hp_milli["b"]),
        "turns": turns,
    }
