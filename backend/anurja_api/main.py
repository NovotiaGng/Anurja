"""Anurja API.

    uvicorn anurja_api.main:app --host 0.0.0.0 --port 8000   (from backend/)

Interactive docs at http://localhost:8000/docs
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from . import features as F
from . import ml
from .db import KINDS, Database

app = FastAPI(title="Anurja API", version="1.0")
_db: Database | None = None


def db() -> Database:
    global _db
    if _db is None:
        _db = Database()
    return _db


class Profile(BaseModel):
    model_config = {"extra": "allow"}
    name: str = ""
    age: Optional[int] = None
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    allergies: list[str] = []
    takes_insulin: bool = False
    medicines: list[dict[str, Any]] = []


class SyncBody(BaseModel):
    profile: Optional[Profile] = None
    meals: list[dict[str, Any]] = []
    insulin: list[dict[str, Any]] = []
    checkins: list[dict[str, Any]] = []
    sessions: list[dict[str, Any]] = []
    glucose: list[dict[str, Any]] = []


class RiseRequest(BaseModel):
    user_id: Optional[str] = None
    meal: dict[str, Any]


class ActivityRequest(BaseModel):
    glucose: float = Field(..., ge=20, le=600)
    slope_per_5min: float = 0
    minutes_since_meal: Optional[float] = None
    steps_last_hour: float = 0
    hour: float = Field(12, ge=0, lt=24)


@app.get("/health")
def health():
    return {"ok": True, "models": [p.name for p in ml.MODELS.glob("*.joblib")]}


@app.get("/api/foods")
def foods(q: str = "", category: str = "", limit: int = Query(100, le=500)):
    items = F.foods()
    if category:
        items = [f for f in items if f["category"].lower() == category.lower()]
    if q:
        ql = q.lower()
        items = [f for f in items if ql in f["name"].lower() or any(ql in k for k in f["keywords"])]
    return items[:limit]


@app.put("/api/users/{user_id}")
def put_profile(user_id: str, profile: Profile, store: Database = Depends(db)):
    store.put_profile(user_id, profile.model_dump())
    return {"ok": True}


@app.get("/api/users/{user_id}")
def get_profile(user_id: str, store: Database = Depends(db)):
    profile = store.get_profile(user_id)
    if profile is None:
        raise HTTPException(404, "Unknown user")
    return profile


@app.post("/api/users/{user_id}/sync")
def sync(user_id: str, body: SyncBody, store: Database = Depends(db)):
    if body.profile is not None:
        store.put_profile(user_id, body.profile.model_dump())
    saved = {kind: store.upsert(kind, user_id, getattr(body, kind)) for kind in KINDS}
    saved["glucose"] = store.add_glucose(user_id, body.glucose)
    return {"ok": True, "saved": saved}


@app.get("/api/users/{user_id}/{kind}")
def list_records(user_id: str, kind: str, store: Database = Depends(db)):
    if kind == "glucose":
        return store.glucose(user_id)
    if kind not in KINDS:
        raise HTTPException(404, "Unknown record kind")
    return store.list(kind, user_id)


@app.delete("/api/users/{user_id}/{kind}/{record_id}")
def delete_record(user_id: str, kind: str, record_id: str, store: Database = Depends(db)):
    if kind not in KINDS:
        raise HTTPException(404, "Unknown record kind")
    if not store.delete(kind, user_id, record_id):
        raise HTTPException(404, "Not found")
    return {"ok": True}


@app.post("/api/ml/predict-rise")
def predict_rise(req: RiseRequest, store: Database = Depends(db)):
    history = store.list("meals", req.user_id) if req.user_id else []
    return ml.predict_rise(req.meal, history)


@app.post("/api/ml/recommend-activity")
def recommend_activity(req: ActivityRequest):
    return ml.recommend_activity(req.glucose, req.slope_per_5min, req.minutes_since_meal,
                                 req.steps_last_hour, req.hour)


@app.get("/api/users/{user_id}/insights/what-helps")
def what_helps(user_id: str, store: Database = Depends(db)):
    return ml.what_helps(store.list("meals", user_id), store.get_profile(user_id))
