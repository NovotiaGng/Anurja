"""Train Anurja's two models and export them.

    python -m ml.train            (run from the backend/ folder)

1. Meal rise model  - MLPRegressor that predicts the glucose rise (mg/dL)
   after a meal from food nutrients + eating context.
2. Activity model   - MLPClassifier that maps the current glucose state to
   in_range / rising / high / low, which drives the activity suggestion.

Both are trained on synthetic data shaped by published glycaemic-load
physiology and the target ranges in the brief (fasting 70-130 mg/dL, after a
meal < 180 mg/dL). The app personalises on top of them with each person's own
logged meals (see anurja_api/ml.py and Anurja/MLEngine.swift).

Outputs
- models/rise.joblib, models/activity.joblib     (used by the API)
- models/report.json                            (holdout metrics)
- ../Anurja1/Anurja/GeneratedModel.swift         (weights for on-device inference)
- ../Anurja1/Anurja/FoodLibraryData.swift        (food library for the app)
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import joblib
import numpy as np
from sklearn.linear_model import Ridge
from sklearn.metrics import accuracy_score, mean_absolute_error
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from anurja_api import features as F

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "models"
SWIFT_DIR = ROOT.parent / "Anurja1" / "Anurja"
RNG = np.random.default_rng(7)

CONTEXTS = list(F.CONTEXT_KEYS.keys())
DRINKS = ["Tea", "Coffee", "Juice / soft drink", "Water", None]


# --------------------------------------------------------------------------
# Synthetic data
# --------------------------------------------------------------------------

def true_rise(meal: dict) -> float:
    v = dict(zip(F.RISE_FEATURES, F.rise_vector(meal)))
    base = 8 + 1.15 * v["glycemic_load"] + 0.12 * v["carbs"]
    base -= 1.2 * v["fiber"] + 0.35 * v["protein"] + 0.25 * v["fat"]
    mult = 1.0
    mult *= 1.15 if v["eaten_quickly"] else 1.0
    mult *= 0.92 if v["eaten_slowly"] else 1.0
    mult *= 0.72 if v["walked_after"] else 1.0
    mult *= 1.15 if v["lay_down_after"] else 1.0
    mult *= 1.05 if v["at_desk"] else 1.0
    mult *= 1.06 if v["screen_on"] else 1.0
    mult *= 1.03 if v["on_the_move"] else 1.0
    add = 16 * v["sweet_drink"] + 5 * v["sugar_spoons"] + 3.5 * v["sleep_deficit"]
    add += 4.5 * v["stress"] + 6 * v["morning"]
    return max(3.0, base) * mult + add


def synth_meals(n: int) -> tuple[np.ndarray, np.ndarray]:
    foods = F.foods()
    X, y = [], []
    for _ in range(n):
        food = foods[RNG.integers(len(foods))]
        contexts = [c for c in CONTEXTS if RNG.random() < 0.25]
        meal = {
            "food_id": food["id"],
            "servings": float(RNG.choice([0.5, 1, 1, 1, 1.5, 2])),
            "duration": str(RNG.choice(["Under 10 min", "10–20 min", "Longer"])),
            "contexts": contexts,
            "drink": DRINKS[RNG.integers(len(DRINKS))],
            "sugar_spoons": int(RNG.choice([0, 0, 0, 1, 2, 3])),
            "sleep_hours": float(np.clip(RNG.normal(6.8, 1.1), 3, 10)),
            "stress": str(RNG.choice(["Low", "Medium", "High"])),
            "hour": int(RNG.integers(6, 23)),
        }
        rise = true_rise(meal) + RNG.normal(0, 7)
        X.append(F.rise_vector(meal))
        y.append(float(np.clip(rise, 3, 160)))
    return np.array(X), np.array(y)


def synth_states(n: int) -> tuple[np.ndarray, np.ndarray]:
    X, y = [], []
    for _ in range(n):
        minutes = None if RNG.random() < 0.3 else float(RNG.uniform(0, 400))
        glucose = float(np.clip(RNG.normal(135, 45), 45, 320))
        slope = float(RNG.normal(0, 4))
        steps = float(max(0, RNG.normal(800, 900)))
        hour = float(RNG.uniform(0, 24))
        label = F.activity_rule(glucose, slope, minutes)
        if RNG.random() < 0.02:  # a little label noise near real-world ambiguity
            label = F.ACTIVITY_CLASSES[RNG.integers(len(F.ACTIVITY_CLASSES))]
        X.append(F.activity_vector(glucose, slope, minutes, steps, hour))
        y.append(F.ACTIVITY_CLASSES.index(label))
    return np.array(X), np.array(y)


# --------------------------------------------------------------------------
# Training
# --------------------------------------------------------------------------

def train_rise():
    X, y = synth_meals(16000)
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=1)
    ridge = Pipeline([("scale", StandardScaler()), ("model", Ridge(alpha=1.0))]).fit(Xtr, ytr)
    mlp = Pipeline([
        ("scale", StandardScaler()),
        ("model", MLPRegressor(hidden_layer_sizes=(24,), activation="relu", alpha=1e-3,
                               max_iter=1500, early_stopping=True, random_state=3)),
    ]).fit(Xtr, ytr)
    report = {
        "ridge_mae": round(float(mean_absolute_error(yte, ridge.predict(Xte))), 2),
        "mlp_mae": round(float(mean_absolute_error(yte, mlp.predict(Xte))), 2),
        "noise_floor_mae": round(7 * math.sqrt(2 / math.pi), 2),
        "samples": len(X),
    }
    return mlp, report


def train_activity():
    X, y = synth_states(20000)
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=1, stratify=y)
    mlp = Pipeline([
        ("scale", StandardScaler()),
        ("model", MLPClassifier(hidden_layer_sizes=(16,), activation="relu", alpha=1e-4,
                                max_iter=1500, early_stopping=True, random_state=3)),
    ]).fit(Xtr, ytr)
    report = {
        "accuracy": round(float(accuracy_score(yte, mlp.predict(Xte))), 4),
        "samples": len(X),
        "classes": F.ACTIVITY_CLASSES,
    }
    return mlp, report


# --------------------------------------------------------------------------
# Swift export
# --------------------------------------------------------------------------

def swift_array(values) -> str:
    flat = np.asarray(values, dtype=float)
    if flat.ndim == 1:
        return "[" + ", ".join(f"{v:.6f}" for v in flat) + "]"
    rows = ",\n            ".join(swift_array(row) for row in flat)
    return "[\n            " + rows + "\n        ]"


def swift_net(prefix: str, pipe: Pipeline) -> str:
    scale, model = pipe.named_steps["scale"], pipe.named_steps["model"]
    return f"""
    static let {prefix} = DenseNetwork(
        mean: {swift_array(scale.mean_)},
        scale: {swift_array(scale.scale_)},
        hiddenWeights: {swift_array(model.coefs_[0])},
        hiddenBias: {swift_array(model.intercepts_[0])},
        outputWeights: {swift_array(model.coefs_[1])},
        outputBias: {swift_array(model.intercepts_[1])}
    )
"""


def export_swift(rise: Pipeline, activity: Pipeline, report: dict) -> None:
    names = lambda xs: "[" + ", ".join(f'"{x}"' for x in xs) + "]"
    body = f"""// GENERATED by backend/ml/train.py — do not edit by hand.
// Re-run `python -m ml.train` in backend/ after changing the data or features.
// Holdout report: {json.dumps(report)}

import Foundation

enum GeneratedModels {{
    static let riseFeatures: [String] = {names(F.RISE_FEATURES)}
    static let activityFeatures: [String] = {names(F.ACTIVITY_FEATURES)}
    static let activityClasses: [String] = {names(F.ACTIVITY_CLASSES)}
    static let riseMAE: Double = {report["rise"]["mlp_mae"]}
    static let activityAccuracy: Double = {report["activity"]["accuracy"]}
{swift_net("rise", rise)}{swift_net("activity", activity)}}}
"""
    (SWIFT_DIR / "GeneratedModel.swift").write_text(body, encoding="utf-8")


def swift_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def export_food_library() -> None:
    rows = []
    for f in F.foods():
        rows.append(
            "        FoodItem("
            f"id: {swift_string(f['id'])}, name: {swift_string(f['name'])}, "
            f"category: {swift_string(f['category'])}, serving: {swift_string(f['serving'])}, "
            f"carbs: {f['carbs']}, fiber: {f['fiber']}, protein: {f['protein']}, fat: {f['fat']}, "
            f"kcal: {f['kcal']}, gi: {f['gi']}, group: {swift_string(f['group'])}, "
            f"allergens: [{', '.join(swift_string(a) for a in f['allergens'])}], "
            f"keywords: [{', '.join(swift_string(k) for k in f['keywords'])}])"
        )
    body = (
        "// GENERATED by backend/ml/train.py from backend/data/foods.json — do not edit by hand.\n"
        "// Nutrient values are approximate per serving (IFCT / USDA FoodData Central / international GI tables).\n\n"
        "import Foundation\n\n"
        "extension FoodLibrary {\n"
        "    static let all: [FoodItem] = [\n" + ",\n".join(rows) + "\n    ]\n}\n"
    )
    (SWIFT_DIR / "FoodLibraryData.swift").write_text(body, encoding="utf-8")


def main() -> None:
    MODELS.mkdir(exist_ok=True)
    rise, rise_report = train_rise()
    activity, activity_report = train_activity()
    report = {"rise": rise_report, "activity": activity_report}
    joblib.dump(rise, MODELS / "rise.joblib")
    joblib.dump(activity, MODELS / "activity.joblib")
    (MODELS / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if SWIFT_DIR.exists():
        export_swift(rise, activity, report)
        export_food_library()
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
