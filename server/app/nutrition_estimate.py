"""Last-resort nutrition for a food neither the catalog nor USDA could supply.

Two text models are asked the same question independently and only the figures they
agree on are kept. A single model's answer is never trusted. Disagreement on calories or
protein drops the food entirely; on a marginal nutrient it is resolved against the
player instead. Anything returned here is labelled an
estimate all the way to the phone, so it is never mistaken for measured USDA data.
"""
import json
import logging

import httpx

from app.config import (GROK_API_KEY, GROK_BASE_URL, GROK_MODEL, IFM_API_KEY, IFM_BASE_URL,
                        IFM_TEXT_MODEL, NUTRITION_ESTIMATE_TIMEOUT_S)

log = logging.getLogger("mealee.nutrition")

# kcal and protein drive stamina and attack, so a disagreement there means the models
# are not describing the same food and the answer is thrown away. The rest move stats
# only at the margin, so a disagreement is resolved against the player rather than
# discarding an otherwise solid answer: least fiber, least caffeine, most sodium.
HEADLINE = ("kcal", "protein_g")
MARGINAL = {"fiber_g": min, "caffeine_mg": min, "sodium_mg": max}
FIELDS = HEADLINE + tuple(MARGINAL)

# Two models rarely land on the same decimal, so agreement is a band, not equality.
# A quarter either way is tight enough to catch a hallucination and loose enough to
# survive honest rounding.
TOLERANCE = 0.25
# Below this, relative distance is meaningless: 0.1g and 0.4g of fiber are both "none".
ABSOLUTE_FLOOR = {"kcal": 15.0, "protein_g": 1.0, "fiber_g": 1.0,
                  "sodium_mg": 25.0, "caffeine_mg": 5.0}

PROMPT = (
    "Give the nutrition of 100 g of {food}. Reply with only compact JSON, no prose, "
    'using exactly these keys: {{"kcal": number, "protein_g": number, "fiber_g": number, '
    '"sodium_mg": number, "caffeine_mg": number, "is_vegetable": true or false}}. '
    "If you do not know this food, reply exactly {{}}."
)


def enabled() -> bool:
    """Both models are required: one alone cannot be checked against anything."""
    return bool(IFM_API_KEY) and bool(GROK_API_KEY)


def agree(first: dict, second: dict) -> dict | None:
    """The figures both models support, or None if they do not describe the same food."""
    if not first or not second:
        return None

    agreed: dict = {}
    for field in FIELDS:
        left, right = first.get(field), second.get(field)
        if not isinstance(left, (int, float)) or not isinstance(right, (int, float)):
            return None
        left, right = float(left), float(right)
        if left < 0 or right < 0:
            return None
        gap = abs(left - right)
        close = gap <= ABSOLUTE_FLOOR[field] or gap <= TOLERANCE * max(left, right)
        if close:
            agreed[field] = round((left + right) / 2, 1)
        elif field in HEADLINE:
            log.info("estimate rejected: %s %.1f vs %.1f", field, left, right)
            return None
        else:
            agreed[field] = round(MARGINAL[field](left, right), 1)
            log.info("estimate split on %s (%.1f vs %.1f), took %.1f",
                     field, left, right, agreed[field])

    if bool(first.get("is_vegetable")) != bool(second.get("is_vegetable")):
        return None
    agreed["is_vegetable"] = bool(first.get("is_vegetable"))
    return agreed


def parse(content: str) -> dict:
    """Models like to wrap JSON in prose or a fence; take the outermost object."""
    text = content.strip()
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return {}
    try:
        parsed = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


async def _ask(client: httpx.AsyncClient, base_url: str, key: str, model: str, food: str) -> dict:
    response = await client.post(
        f"{base_url}/chat/completions",
        headers={"Authorization": f"Bearer {key}"},
        # These models often think out loud in content before the JSON, and a short
        # budget truncates them mid-thought. parse() digs the object out of the prose.
        json={"model": model, "max_tokens": 900, "temperature": 0,
              "messages": [{"role": "user", "content": PROMPT.format(food=food)}]},
    )
    response.raise_for_status()
    return parse(response.json()["choices"][0]["message"]["content"])


async def estimate(food: str) -> dict | None:
    """Ask both models and return only what they agree on. None on any doubt."""
    if not enabled():
        return None
    try:
        async with httpx.AsyncClient(timeout=NUTRITION_ESTIMATE_TIMEOUT_S) as client:
            ifm = await _ask(client, IFM_BASE_URL, IFM_API_KEY, IFM_TEXT_MODEL, food)
            grok = await _ask(client, GROK_BASE_URL, GROK_API_KEY, GROK_MODEL, food)
    except (httpx.HTTPError, KeyError, IndexError, ValueError) as error:
        log.info("nutrition estimate unavailable: %s", error)
        return None
    return agree(ifm, grok)
