from datetime import date

import pytest
from fastapi import Depends, FastAPI, HTTPException
from fastapi.testclient import TestClient

import auth
from auth import User, charge, current_user

app = FastAPI()


@app.get("/who")
def who(user: User = Depends(current_user)):
    return {"uid": user.uid, "anon": user.is_anonymous}


c = TestClient(app)


def test_missing_bearer_is_401():
    r = c.get("/who")
    assert r.status_code == 401


def test_invalid_token_is_401(monkeypatch):
    def bad(token):
        raise ValueError("bad token")

    monkeypatch.setattr(auth, "_verify", bad)
    assert c.get("/who", headers={"Authorization": "Bearer x"}).status_code == 401


def test_valid_token_gives_user(monkeypatch):
    monkeypatch.setattr(auth, "_verify", lambda t: {"uid": "u1", "firebase": {"sign_in_provider": "anonymous"}})
    r = c.get("/who", headers={"Authorization": "Bearer x"})
    assert r.json() == {"uid": "u1", "anon": True}


def test_charge_allows_up_to_limit_then_429(db, monkeypatch):
    monkeypatch.setenv("QUOTA_MATCH", "2")
    today = date(2026, 11, 8)
    charge(db, "u1", "match", today)
    charge(db, "u1", "match", today)
    with pytest.raises(HTTPException) as e:
        charge(db, "u1", "match", today)
    assert e.value.status_code == 429


def test_charge_counts_per_day(db, monkeypatch):
    monkeypatch.setenv("QUOTA_MATCH", "1")
    charge(db, "u1", "match", date(2026, 11, 8))
    charge(db, "u1", "match", date(2026, 11, 9))  # 日付が替われば 0 から
