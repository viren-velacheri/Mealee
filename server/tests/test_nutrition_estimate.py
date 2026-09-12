from app.nutrition_estimate import agree, parse


def _paneer(kcal=321.0, protein=25.0, fiber=0.0, sodium=18.0, caffeine=0.0, veg=False):
    return {"kcal": kcal, "protein_g": protein, "fiber_g": fiber,
            "sodium_mg": sodium, "caffeine_mg": caffeine, "is_vegetable": veg}


def test_close_answers_are_averaged():
    agreed = agree(_paneer(kcal=321, protein=25), _paneer(kcal=330, protein=23))
    assert agreed is not None
    assert agreed["kcal"] == 325.5
    assert agreed["protein_g"] == 24.0
    assert agreed["is_vegetable"] is False


def test_a_model_inventing_a_different_food_is_rejected():
    # One says paneer, the other answers as if asked about lettuce.
    assert agree(_paneer(kcal=321, protein=25), _paneer(kcal=15, protein=1)) is None


def test_small_absolute_gaps_survive_even_when_relatively_huge():
    # 0.2g vs 0.6g of fiber is a 3x relative gap and nutritionally identical.
    assert agree(_paneer(fiber=0.2), _paneer(fiber=0.6)) is not None


def test_disagreement_about_being_a_vegetable_is_rejected():
    assert agree(_paneer(veg=True), _paneer(veg=False)) is None


def test_one_model_not_knowing_the_food_rejects_the_pair():
    assert agree({}, _paneer()) is None
    assert agree(_paneer(), {}) is None


def test_missing_or_non_numeric_fields_are_rejected():
    broken = _paneer()
    broken["protein_g"] = "twenty five"
    assert agree(_paneer(), broken) is None
    missing = _paneer()
    del missing["kcal"]
    assert agree(_paneer(), missing) is None


def test_negative_values_are_rejected():
    assert agree(_paneer(), _paneer(sodium=-5)) is None


def test_parse_digs_json_out_of_prose_and_fences():
    assert parse('```json\n{"kcal": 100}\n```') == {"kcal": 100}
    assert parse('Sure! {"kcal": 100} hope that helps') == {"kcal": 100}
    assert parse("no idea") == {}
    assert parse("{}") == {}
    assert parse("[1,2]") == {}


def test_marginal_disagreement_is_resolved_against_the_player():
    # Real case: asked about paneer, the two models returned 395 and 18 mg of sodium
    # while agreeing exactly on calories and protein. Sodium only costs recovery, so the
    # food survives and takes the worse number rather than being thrown away.
    agreed = agree(_paneer(sodium=395), _paneer(sodium=18))
    assert agreed is not None
    assert agreed["sodium_mg"] == 395.0
    assert agreed["kcal"] == 321.0


def test_marginal_bonuses_take_the_smaller_value():
    assert agree(_paneer(fiber=0.0), _paneer(fiber=9.0))["fiber_g"] == 0.0
    assert agree(_paneer(caffeine=0.0), _paneer(caffeine=80.0))["caffeine_mg"] == 0.0


def test_headline_disagreement_still_drops_the_food():
    assert agree(_paneer(kcal=265), _paneer(kcal=60)) is None
    assert agree(_paneer(protein=18), _paneer(protein=2)) is None
