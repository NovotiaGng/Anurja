"""SQLite storage. One table per record kind; each row keeps the full JSON the
app sent plus the columns we query on. Set ANURJA_DB to choose the file."""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path

KINDS = ("meals", "insulin", "checkins", "sessions")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    profile TEXT NOT NULL,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS glucose (
    user_id TEXT NOT NULL,
    time TEXT NOT NULL,
    value REAL NOT NULL,
    PRIMARY KEY (user_id, time)
);
"""
for _kind in KINDS:
    _SCHEMA += f"""
CREATE TABLE IF NOT EXISTS {_kind} (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    date TEXT NOT NULL,
    body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_{_kind}_user ON {_kind}(user_id, date);
"""


class Database:
    def __init__(self, path: str | os.PathLike | None = None):
        default = Path(__file__).resolve().parent.parent / "anurja.db"
        self.path = str(path or os.environ.get("ANURJA_DB", default))
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self.path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    @contextmanager
    def tx(self):
        with self._lock:
            try:
                yield self._conn
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    # users -----------------------------------------------------------------
    def put_profile(self, user_id: str, profile: dict) -> None:
        with self.tx() as c:
            c.execute(
                "INSERT INTO users(id, profile) VALUES(?, ?) "
                "ON CONFLICT(id) DO UPDATE SET profile=excluded.profile, updated_at=CURRENT_TIMESTAMP",
                (user_id, json.dumps(profile)),
            )

    def get_profile(self, user_id: str) -> dict | None:
        with self.tx() as c:
            row = c.execute("SELECT profile FROM users WHERE id=?", (user_id,)).fetchone()
        return json.loads(row["profile"]) if row else None

    # records ---------------------------------------------------------------
    def upsert(self, kind: str, user_id: str, records: list[dict]) -> int:
        assert kind in KINDS
        with self.tx() as c:
            for r in records:
                c.execute(
                    f"INSERT INTO {kind}(id, user_id, date, body) VALUES(?, ?, ?, ?) "
                    "ON CONFLICT(id) DO UPDATE SET date=excluded.date, body=excluded.body",
                    (str(r["id"]), user_id, str(r.get("date", "")), json.dumps(r)),
                )
        return len(records)

    def list(self, kind: str, user_id: str, limit: int = 500) -> list[dict]:
        assert kind in KINDS
        with self.tx() as c:
            rows = c.execute(
                f"SELECT body FROM {kind} WHERE user_id=? ORDER BY date DESC LIMIT ?",
                (user_id, limit),
            ).fetchall()
        return [json.loads(r["body"]) for r in rows]

    def delete(self, kind: str, user_id: str, record_id: str) -> bool:
        assert kind in KINDS
        with self.tx() as c:
            cur = c.execute(f"DELETE FROM {kind} WHERE id=? AND user_id=?", (record_id, user_id))
        return cur.rowcount > 0

    # glucose ---------------------------------------------------------------
    def add_glucose(self, user_id: str, points: list[dict]) -> int:
        with self.tx() as c:
            c.executemany(
                "INSERT OR REPLACE INTO glucose(user_id, time, value) VALUES(?, ?, ?)",
                [(user_id, str(p["time"]), float(p["value"])) for p in points],
            )
        return len(points)

    def glucose(self, user_id: str, limit: int = 2000) -> list[dict]:
        with self.tx() as c:
            rows = c.execute(
                "SELECT time, value FROM glucose WHERE user_id=? ORDER BY time DESC LIMIT ?",
                (user_id, limit),
            ).fetchall()
        return [{"time": r["time"], "value": r["value"]} for r in reversed(rows)]
