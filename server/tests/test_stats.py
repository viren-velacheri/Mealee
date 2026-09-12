from app.stats import DayTotals, blend_with_yesterday, fighter_from_totals


def test_empty_day_is_weak_but_never_zero_hp():
    fighter = fighter_from_totals(DayTotals())
    assert fighter.attack == 0
    assert fighter.stamina == 0
    assert fighter.hp_max == 100
    assert fighter.speed == 50
    assert fighter.focus == 70
    assert fighter.crash_turn is None
    assert not fighter.first_strike


def test_targets_hit_gives_full_stats():
    fighter = fighter_from_totals(DayTotals(
        kcal=2000, protein_g=100, fiber_g=30, veg_g=400, added_sugar_g=0,
        caffeine_mg=200, water_ml=2500, sodium_mg=2300))
    assert fighter.attack == 100
    assert fighter.defense == 100
    assert fighter.stamina == 100
    assert fighter.hp_max == 200
    assert fighter.focus == 85
    assert fighter.recovery == 10
    assert fighter.first_strike


def test_overeating_costs_stamina_like_undereating():
    under = fighter_from_totals(DayTotals(kcal=1500))
    over = fighter_from_totals(DayTotals(kcal=2500))
    assert under.stamina == over.stamina == 75


def test_sugar_gives_speed_and_a_crash_turn():
    fighter = fighter_from_totals(DayTotals(added_sugar_g=41))
    assert fighter.speed == 91
    assert fighter.crash_turn == 6
    assert "crash on turn 6" in " ".join(fighter.reasons)


def test_sugar_crash_never_earlier_than_turn_three():
    assert fighter_from_totals(DayTotals(added_sugar_g=90)).crash_turn == 3


def test_too_much_caffeine_hurts_focus():
    assert fighter_from_totals(DayTotals(caffeine_mg=800)).focus == 65


def test_every_reason_names_the_input_and_the_stat():
    fighter = fighter_from_totals(DayTotals(protein_g=62))
    assert fighter.reasons[0] == "Protein 62 g: attack 68"


def test_no_meals_today_fights_at_a_fifth_of_yesterday():
    yesterday = fighter_from_totals(DayTotals(protein_g=100, kcal=2000))
    today = blend_with_yesterday(fighter_from_totals(DayTotals()), yesterday, has_meals_today=False)
    assert today.attack == 20
    assert today.hp_max == 120


def test_carry_over_is_eighty_twenty():
    yesterday = fighter_from_totals(DayTotals(protein_g=100))
    today = blend_with_yesterday(fighter_from_totals(DayTotals(protein_g=0)), yesterday, has_meals_today=True)
    assert today.attack == 20
