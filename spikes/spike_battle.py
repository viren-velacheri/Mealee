"""Spike 3: prove the battle is deterministic, ends inside 20 turns, and produces a log
the Swift implementation can be pinned to.

Writes ios/Mealee/Fixtures/battle_fixtures.json. BattleSimTests.swift loads that file and
asserts its own log matches turn for turn. If you change battle.py, rerun this script and
commit the regenerated fixture, or the iOS test will fail.

    python3 spikes/spike_battle.py
"""

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "server"))

from app.battle import Fighter, Mulberry32, seed_from_fight_id, simulate

FIXTURE_PATH = pathlib.Path(__file__).resolve().parents[1] / "ios/Mealee/Fixtures/battle_fixtures.json"

BALANCED = Fighter(
    name="Protein Pete", attack=68, defense=54, stamina=88, speed=62,
    focus=79, recovery_milli=8200, hp_max=188, crash_turn=None, first_strike=True,
)
SUGAR_RUSH = Fighter(
    name="Donut Dana", attack=31, defense=22, stamina=61, speed=91,
    focus=70, recovery_milli=4100, hp_max=161, crash_turn=6, first_strike=False,
)
TANK = Fighter(
    name="Broccoli Bo", attack=44, defense=97, stamina=95, speed=50,
    focus=85, recovery_milli=10000, hp_max=195, crash_turn=None, first_strike=False,
)

MATCHUPS = [
    ("quick-demo-001", BALANCED, SUGAR_RUSH),
    ("quick-demo-002", SUGAR_RUSH, TANK),
    ("nightly-2026-09-12-a", TANK, BALANCED),
]


# Produced by `node spikes/mulberry_reference.js`, which runs the canonical mulberry32
# unmodified. Regenerate with that script rather than by hand.
RNG_REFERENCE = {
    1: [2693262067, 11749833, 2265367787, 4213581821, 4159151403],
    0: [1144304738, 1416247, 958946056, 627933444, 2007157716],
    2967037554: [634114255, 3430785177, 1044617980, 2133622804, 2768123999],
    744262745: [723998645, 651310318, 82830691, 74561485, 305162176],
}


def check_rng_reference() -> bool:
    """If the generator drifts from the canonical implementation, every fixture below is
    meaningless, so this runs before anything else."""
    ok = True
    for seed, expected in RNG_REFERENCE.items():
        rng = Mulberry32(seed)
        got = [rng.next_u32() for _ in range(len(expected))]
        matched = got == expected
        ok = ok and matched
        print(f"  seed {seed:<12} {'PASS' if matched else 'FAIL'}  {got}")
    return ok


def main() -> int:
    print("Spike 3: battle simulation\n")
    print("RNG reference check")
    rng_ok = check_rng_reference()

    fixtures = []
    all_ok = rng_ok

    for fight_id, fighter_a, fighter_b in MATCHUPS:
        seed = seed_from_fight_id(fight_id)
        first = simulate(seed, fighter_a, fighter_b)
        second = simulate(seed, fighter_a, fighter_b)

        deterministic = first == second
        turn_count = first["turns"][-1]["turn"] if first["turns"] else 0
        within_limit = turn_count <= 20
        all_ok = all_ok and deterministic and within_limit

        print(f"\n{fight_id}  seed={seed}")
        print(f"  {fighter_a.name} ({fighter_a.hp_max} HP) vs {fighter_b.name} ({fighter_b.hp_max} HP)")
        for entry in first["turns"]:
            print(f"    t{entry['turn']:>2} {entry['actor']} {entry['action']:<8}"
                  f" dmg={entry['damage']:<4} a={entry['a_hp']:<4} b={entry['b_hp']:<4} {entry['note']}")
        winner_name = fighter_a.name if first["winner"] == "a" else fighter_b.name
        print(f"  winner: {winner_name}  ({len(first['turns'])} log entries, {turn_count} turns)")
        print(f"  {'PASS' if deterministic else 'FAIL'} identical on rerun"
              f" | {'PASS' if within_limit else 'FAIL'} finished within 20 turns")

        fixtures.append({
            "fight_id": fight_id,
            "seed": seed,
            "a": vars(fighter_a),
            "b": vars(fighter_b),
            "expected": first,
        })

    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(json.dumps(fixtures, indent=2) + "\n")
    print(f"\nwrote {FIXTURE_PATH.relative_to(pathlib.Path.cwd())}")
    print(f"\nSPIKE 3: {'PASS' if all_ok else 'FAIL'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
