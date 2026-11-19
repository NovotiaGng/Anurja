"""Feature definitions shared by training, the API and (via the generated
Swift file) the iPhone app. Keep the ORDER of the lists below in sync with
`Anurja/MLEngine.swift`; `ml/train.py` writes them into GeneratedModel.swift
so the app and the server always agree."""

from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"

RISE_FEATURES = [
    "carbs",
    "glycemic_load",
    "fiber",
    "protein",
    "fat",
    "eaten_quickly",
    "eaten_slowly",
    "at_desk",
    "screen_on",
    "on_the_move",
    "walked_after",
    "lay_down_after",
    "sweet_drink",
    "sugar_spoons",
    "sleep_deficit",
    "stress",
    "morning",
]

ACTIVITY_FEATURES = [
    "glucose",
    "slope_per_5min",
    "hours_since_meal",
    "fasting",
    "steps_last_hour_k",
    "hour_sin",
    "hour_cos",
]

# Order matters: index == class id used by the Swift app.
ACTIVITY_CLASSES = ["in_range", "rising", "high", "low"]

FASTING_TARGET = (70, 130)
AFTER_MEAL_MAX = 180

# Raw values coming from the Swift enums.
DURATION_QUICK = {"quick", "Under 10 min"}
DURATION_LONG = {"longer", "Longer"}
CONTEXT_KEYS = {
    "At my desk": "at_desk",
    "Screen on": "screen_on",
    "On the move": "on_the_move",
    "Walked after": "walked_after",
    "Lay down after": "lay_down_after",
}
STRESS_LEVEL = {"Low": 0, "Medium": 1, "High": 2, "low": 0, "medium": 1, "high": 2}


@lru_cache(maxsize=1)
def foods() -> list[dict]:
    return json.loads((DATA / "foods.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def foods_by_id() -> dict[str, dict]:
    return {f["id"]: f for f in foods()}


GROUP_DEFAULT_FOOD = {
    "Rice & dal": "rice_dal",
    "Idli / dosa": "idli",
    "Roti & sabzi": "roti_sabzi",
    "Biryani": "veg_biryani",
    "Salad & curd": "salad_curd",
    "Something else": "khichdi",
}


def food_for(meal: dict) -> dict:
    by_id = foods_by_id()
    if meal.get("food_id") in by_id:
        return by_id[meal["food_id"]]
    return by_id[GROUP_DEFAULT_FOOD.get(meal.get("group") or "", "rice_dal")]


def rise_vector(meal: dict) -> list[float]:
    """meal: dict with food_id/group, servings, duration, contexts, drink,
    sugar_spoons, sleep_hours, stress, hour (0-23)."""
    food = food_for(meal)
    servings = float(meal.get("servings") or 1.0)
    carbs = meal.get("carbs_grams")
    carbs = float(carbs) if carbs else food["carbs"] * servings
    contexts = {CONTEXT_KEYS.get(c, c) for c in (meal.get("contexts") or [])}
    duration = meal.get("duration") or "medium"
    drink = meal.get("drink") or ""
    hour = float(meal.get("hour", 13))
    values = {
        "carbs": carbs,
        "glycemic_load": carbs * food["gi"] / 100.0,
        "fiber": food["fiber"] * servings,
        "protein": food["protein"] * servings,
        "fat": food["fat"] * servings,
        "eaten_quickly": 1.0 if duration in DURATION_QUICK else 0.0,
        "eaten_slowly": 1.0 if duration in DURATION_LONG else 0.0,
        "at_desk": float("at_desk" in contexts),
        "screen_on": float("screen_on" in contexts),
        "on_the_move": float("on_the_move" in contexts),
        "walked_after": float("walked_after" in contexts),
        "lay_down_after": float("lay_down_after" in contexts),
        "sweet_drink": 1.0 if drink in {"Juice / soft drink", "juice"} else 0.0,
        "sugar_spoons": float(meal.get("sugar_spoons") or 0),
        "sleep_deficit": max(0.0, 7.0 - float(meal.get("sleep_hours") or 7.0)),
        "stress": float(STRESS_LEVEL.get(meal.get("stress") or "Medium", 1)),
        "morning": 1.0 if 5 <= hour < 11 else 0.0,
    }
    return [values[name] for name in RISE_FEATURES]


def activity_vector(glucose: float, slope: float, minutes_since_meal: float | None,
                    steps_last_hour: float, hour: float) -> list[float]:
    minutes = 600.0 if minutes_since_meal is None else max(0.0, float(minutes_since_meal))
    fasting = 1.0 if minutes >= 240 else 0.0
    angle = 2 * math.pi * (hour % 24) / 24
    return [
        float(glucose),
        float(slope),
        min(minutes, 600.0) / 60.0,
        fasting,
        float(steps_last_hour) / 1000.0,
        math.sin(angle),
        math.cos(angle),
    ]


def activity_rule(glucose: float, slope: float, minutes_since_meal: float | None) -> str:
    """Clinical targets from the brief: fasting 70-130 mg/dL, after a meal
    under 180 mg/dL. Used to label synthetic training data."""
    fasting = minutes_since_meal is None or minutes_since_meal >= 240
    high_line = FASTING_TARGET[1] if fasting else AFTER_MEAL_MAX
    if glucose < 70 or (glucose < 85 and slope < -4):
        return "low"
    if glucose > high_line:
        return "high"
    if slope > 2 and glucose > (115 if fasting else 140):
        return "rising"
    return "in_range"


ACTIONS = {
    "high": [
        {"id": "brisk_walk", "title": "Brisk walk, 10–15 minutes", "detail": "Working muscles pull glucose out of your blood."},
        {"id": "stairs", "title": "Climb stairs for 5 minutes", "detail": "Short, strong bursts help bring it down."},
        {"id": "water", "title": "Drink a glass of water", "detail": "Staying hydrated helps your kidneys clear extra glucose."},
    ],
    "rising": [
        {"id": "light_walk", "title": "Light walk, 5–10 minutes", "detail": "A short walk now can flatten the rise."},
        {"id": "squats", "title": "10 slow squats", "detail": "Big leg muscles soak up glucose."},
        {"id": "water", "title": "Drink a glass of water", "detail": "Skip sweet drinks for now."},
    ],
    "low": [
        {"id": "fast_carbs", "title": "Eat 15 g of quick carbs", "detail": "Half a glass of juice, 3 glucose tablets or 1 tbsp sugar."},
        {"id": "rest", "title": "Sit down and rest", "detail": "Recheck in 15 minutes. Follow your care team's plan."},
    ],
    "in_range": [
        {"id": "keep_going", "title": "You're in your target range", "detail": "Keep doing what you're doing."},
    ],
}
