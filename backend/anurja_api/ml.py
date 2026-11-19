"""Model inference + per-person personalisation.

The global models come from ml/train.py. Personalisation is a shrunken
residual correction learned from the person's own logged meals: for every
meal we know the real rise from the sensor, so (actual - predicted) tells us
how this person reacts to that food compared with the population model."""

from __future__ import annotations

from collections import defaultdict
from functools import lru_cache
from pathlib import Path
from statistics import mean

import joblib
import numpy as np

from . import features as F

MODELS = Path(__file__).resolve().parent.parent / "models"
FOOD_SHRINK = 3.0
USER_SHRINK = 5.0


@lru_cache(maxsize=1)
def rise_model():
    return joblib.load(MODELS / "rise.joblib")


@lru_cache(maxsize=1)
def activity_model():
    return joblib.load(MODELS / "activity.joblib")


def band(rise: float) -> str:
    if rise < 30:
        return "gentle"
    if rise < 55:
        return "moderate"
    return "sharp"


def _food_key(meal: dict) -> str:
    return meal.get("food_id") or F.GROUP_DEFAULT_FOOD.get(meal.get("group") or "", "rice_dal")


class Personaliser:
    def __init__(self, meals: list[dict]):
        logged = [m for m in meals if m.get("rise") is not None]
        self.count = len(logged)
        self.food_adj: dict[str, float] = {}
        self.user_adj = 0.0
        if not logged:
            return
        preds = rise_model().predict(np.array([F.rise_vector(m) for m in logged]))
        residuals = defaultdict(list)
        for meal, pred in zip(logged, preds):
            residuals[_food_key(meal)].append(float(meal["rise"]) - float(pred))
        every = [r for rs in residuals.values() for r in rs]
        self.user_adj = sum(every) / (len(every) + USER_SHRINK)
        for key, rs in residuals.items():
            self.food_adj[key] = sum(rs) / (len(rs) + FOOD_SHRINK)

    def adjust(self, meal: dict, raw: float) -> float:
        key = _food_key(meal)
        return raw + self.food_adj.get(key, self.user_adj)


def predict_rise(meal: dict, history: list[dict] | None = None) -> dict:
    raw = float(rise_model().predict(np.array([F.rise_vector(meal)]))[0])
    person = Personaliser(history or [])
    value = max(0.0, person.adjust(meal, raw))
    return {
        "rise": round(value, 1),
        "population_rise": round(raw, 1),
        "band": band(value),
        "personalised_from": person.count,
    }


def recommend_activity(glucose: float, slope: float, minutes_since_meal: float | None,
                       steps_last_hour: float, hour: float) -> dict:
    x = np.array([F.activity_vector(glucose, slope, minutes_since_meal, steps_last_hour, hour)])
    probs = activity_model().predict_proba(x)[0]
    status = F.ACTIVITY_CLASSES[int(np.argmax(probs))]
    fasting = minutes_since_meal is None or minutes_since_meal >= 240
    target = {"low": F.FASTING_TARGET[0], "high": F.FASTING_TARGET[1] if fasting else F.AFTER_MEAL_MAX}
    return {
        "status": status,
        "probabilities": {c: round(float(p), 3) for c, p in zip(F.ACTIVITY_CLASSES, probs)},
        "fasting": fasting,
        "target_range": target,
        "actions": F.ACTIONS[status],
        "notify": status in ("high", "low"),
    }


TYPICAL = {"duration": "10–20 min", "contexts": [], "drink": "Water", "sugar_spoons": 0,
           "sleep_hours": 7, "stress": "Medium", "hour": 13, "servings": 1}


def what_helps(meals: list[dict], profile: dict | None) -> dict:
    allergies = {a.lower() for a in (profile or {}).get("allergies", [])}
    person = Personaliser(meals)
    safe = [f for f in F.foods() if not allergies.intersection(a.lower() for a in f["allergens"])]
    cand = [dict(TYPICAL, food_id=f["id"]) for f in safe]
    raw = rise_model().predict(np.array([F.rise_vector(m) for m in cand])) if cand else []
    ranked = sorted(
        ({"food_id": f["id"], "name": f["name"], "category": f["category"],
          "predicted_rise": round(max(0.0, person.adjust(m, float(r))), 1)}
         for f, m, r in zip(safe, cand, raw)),
        key=lambda x: x["predicted_rise"],
    )
    by_cat = defaultdict(list)
    for row in ranked:
        by_cat[row["category"]].append(row)

    snacks = by_cat.get("Snacks", [])
    snack = dict(snacks[0], reason="Keeps your glucose level steadier between meals") if snacks else None

    comparisons = []
    logged = defaultdict(list)
    for m in meals:
        if m.get("rise") is not None:
            logged[_food_key(m)].append(float(m["rise"]))
    foods = F.foods_by_id()
    for key, rises in sorted(logged.items(), key=lambda kv: -mean(kv[1])):
        food = foods.get(key)
        if not food:
            continue
        options = [r for r in by_cat.get(food["category"], []) if r["food_id"] != key]
        swap = options[0] if options else None
        avg = round(mean(rises), 1)
        comparisons.append({
            "food_id": key, "name": food["name"], "average_rise": avg, "count": len(rises),
            "swap": swap,
            "saving": round(avg - swap["predicted_rise"], 1) if swap else None,
        })

    habits = []
    for raw_ctx in F.CONTEXT_KEYS:
        with_c = [float(m["rise"]) for m in meals if m.get("rise") is not None and raw_ctx in (m.get("contexts") or [])]
        without = [float(m["rise"]) for m in meals if m.get("rise") is not None and raw_ctx not in (m.get("contexts") or [])]
        if with_c and without:
            habits.append({"context": raw_ctx, "with_average": round(mean(with_c), 1),
                           "without_average": round(mean(without), 1),
                           "delta": round(mean(with_c) - mean(without), 1)})
    habits.sort(key=lambda h: h["delta"])

    return {
        "glucose_friendly": [r for r in ranked if r["category"] not in ("Snacks", "Drinks", "Sweets", "Fruits")][:5],
        "snack": snack,
        "comparisons": comparisons[:6],
        "habits": habits,
        "personalised_from": person.count,
    }
