from fastapi.testclient import TestClient

from main import app

c = TestClient(app)


def test_without_token_is_401():
    r = c.get("/v1/wardrobe")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthenticated"


def test_unknown_path_is_404_in_error_shape():
    r = c.get("/v1/nope", headers={"Authorization": "Bearer x"})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "not_found"


def test_browser_preflight_from_web_demo_is_allowed():
    r = c.options(
        "/v1/me",
        headers={"Origin": "http://localhost:5000", "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "authorization"},
    )
    assert r.status_code == 200
    assert r.headers["access-control-allow-origin"] == "http://localhost:5000"


def test_unexpected_error_is_500_in_error_shape_and_log_has_no_detail(monkeypatch, caplog):
    import outfits
    from auth import User, current_user

    monkeypatch.setattr(outfits, "today_jst", lambda: (_ for _ in ()).throw(RuntimeError("users/secret_uid/x")))
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    try:
        r = c.get("/v1/outfits/today")
    finally:
        app.dependency_overrides.pop(current_user, None)
    assert r.status_code == 500 and r.json()["error"]["code"] == "internal"
    assert "secret_uid" not in caplog.text
