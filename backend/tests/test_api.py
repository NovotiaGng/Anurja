"""Run from backend/:  python -m pytest -q   (or: python -m tests.test_api)"""

import os
import tempfile

os.environ["ANURJA_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")

from fastapi.testclient import TestClient  # noqa: E402

from anurja_api.main import app  # noqa: E402

client = TestClient(app)
USER = "test-user"


def meal(i, food_id, rise, contexts=()):
    return {"id": f"m{i}", "date": f"2026-11-{10 + i:02d}T13:00:00Z", "food_id": food_id,
            "group": "Rice & dal", "servings": 1, "duration": "10–20 min", "contexts": list(contexts),
            "drink": "Water", "sugar_spoons": 0, "sleep_hours": 7, "stress": "Medium", "hour": 13,
            "rise": rise}


def test_health_and_foods():
    assert client.get("/health").json()["ok"]
    rows = client.get("/api/foods", params={"q": "dosa"}).json()
    assert any(r["id"] == "masala_dosa" for r in rows)


def test_sync_and_list():
    body = {
        "profile": {"name": "Asha", "age": 41, "allergies": ["peanut"], "takes_insulin": True},
        "meals": [meal(1, "rice_dal", 62), meal(2, "rice_dal", 58, ["Walked after"]), meal(3, "roti_sabzi", 30)],
        "insulin": [{"id": "i1", "date": "2026-11-11T12:40:00Z", "units": 4, "relation": "pre_meal"}],
        "glucose": [{"time": "2026-11-11T13:00:00Z", "value": 120}],
    }
    r = client.post(f"/api/users/{USER}/sync", json=body).json()
    assert r["saved"]["meals"] == 3 and r["saved"]["insulin"] == 1
    assert len(client.get(f"/api/users/{USER}/meals").json()) == 3
    assert client.get(f"/api/users/{USER}").json()["name"] == "Asha"


def test_predictions_and_personalisation():
    base = client.post("/api/ml/predict-rise", json={"meal": meal(9, "rice_dal", None)}).json()
    personal = client.post("/api/ml/predict-rise", json={"user_id": USER, "meal": meal(9, "rice_dal", None)}).json()
    assert base["band"] in {"gentle", "moderate", "sharp"}
    assert personal["personalised_from"] == 3


def test_activity_targets():
    high = client.post("/api/ml/recommend-activity", json={"glucose": 210, "minutes_since_meal": 60}).json()
    low = client.post("/api/ml/recommend-activity", json={"glucose": 62, "slope_per_5min": -2}).json()
    fine = client.post("/api/ml/recommend-activity", json={"glucose": 105, "minutes_since_meal": 300}).json()
    assert high["status"] == "high" and high["actions"][0]["id"] == "brisk_walk"
    assert low["status"] == "low" and low["actions"][0]["id"] == "fast_carbs"
    assert fine["status"] == "in_range" and fine["target_range"]["high"] == 130


def test_what_helps_respects_allergies():
    data = client.get(f"/api/users/{USER}/insights/what-helps").json()
    assert data["snack"]["food_id"] != "peanuts"
    assert data["comparisons"][0]["food_id"] == "rice_dal"


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
