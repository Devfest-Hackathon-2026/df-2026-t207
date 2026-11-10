import io
import re
from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import notify
from auth import User, current_user
from main import app
from routes_me import JST, today_jst

A, B, C = "uid_alice", "uid_bob", "uid_carol"
JOB = "job_abcdef12"


@pytest.fixture
def c(db, blobs, monkeypatch):
    sent = []
    monkeypatch.setattr(notify, "notify", lambda db, uid, type_, text, **ref: sent.append((uid, type_, text, ref)))
    for uid, name in ((A, "さくら"), (B, "けんた"), (C, "みお")):
        db.document(f"users/{uid}").set({"displayName": name})
    client = TestClient(app)
    client.sent = sent
    yield client
    app.dependency_overrides.pop(current_user, None)


def as_user(uid, anonymous=False):
    app.dependency_overrides[current_user] = lambda: User(uid, anonymous)


def code_of(db, uid):
    from friends import me_fields

    return me_fields(db, uid)["friendCode"]


def send(c, db, frm, to, code=None):
    as_user(frm)
    return c.post("/v1/friends/requests", json={"friendCode": code or code_of(db, to)})


def befriend(c, db, a=A, b=B):
    rid = send(c, db, b, a).json()["requestId"]
    as_user(a)
    return c.post(f"/v1/friends/requests/{rid}/accept").json()["friendId"]


def no_uid(r):
    assert A not in r.text and B not in r.text and C not in r.text


def jpeg(size=(2000, 1200)):
    buf = io.BytesIO()
    exif = Image.Exif()
    exif[0x010F] = "SecretCam"  # Make
    Image.new("RGB", size, "red").save(buf, "JPEG", exif=exif)
    return buf.getvalue()


def test_me_fields_makes_code_once(db):
    from friends import me_fields

    f = me_fields(db, A)
    assert re.fullmatch(r"[A-HJ-NP-Z2-9]{8}", f["friendCode"])
    assert f["profileImage"] is None and f["profileCrop"] is None
    assert me_fields(db, A)["friendCode"] == f["friendCode"]
    assert db.document(f"friendCodes/{f['friendCode']}").get().to_dict()["uid"] == A


def test_request_by_code_notifies_and_lists(c, db):
    code = code_of(db, A)
    r = send(c, db, B, A, code=" " + code.lower()[:4] + " " + code.lower()[4:])
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "pending" and body["displayName"] == "さくら" and body["profileImage"] is None
    no_uid(r)
    assert c.sent == [(A, "friend_request", "けんたさんからフレンドの申請が届きました", {"requestId": body["requestId"]})]
    out = c.get("/v1/friends/requests").json()
    assert out["incoming"] == [] and [x["requestId"] for x in out["outgoing"]] == [body["requestId"]]
    as_user(A)
    r = c.get("/v1/friends/requests")
    no_uid(r)
    inc = r.json()["incoming"]
    assert [(x["requestId"], x["displayName"], x["profileImage"]) for x in inc] == [(body["requestId"], "けんた", None)]


def test_request_errors(c, db, monkeypatch):
    assert send(c, db, A, A).json()["error"]["code"] == "validation"
    r = send(c, db, A, B, code="ZZZZZZZZ")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"
    assert send(c, db, A, B).status_code == 201
    r = send(c, db, A, B)
    assert r.status_code == 409 and r.json()["error"]["code"] == "conflict"
    befriend(c, db, A, C)
    assert send(c, db, A, C).status_code == 409
    assert send(c, db, C, A).status_code == 409


def test_request_quota(c, db, monkeypatch):
    monkeypatch.setenv("QUOTA_FRIEND_REQUEST", "1")
    assert send(c, db, A, B).status_code == 201
    assert send(c, db, A, C).status_code == 429


def test_crossing_request_becomes_friends(c, db):
    send(c, db, A, B)
    c.sent.clear()
    r = send(c, db, B, A)
    assert r.status_code == 201 and r.json()["status"] == "accepted"
    assert c.sent == [(A, "friend_accepted", "けんたさんがフレンドの申請を承認しました", {})]
    assert [f["displayName"] for f in c.get("/v1/friends").json()["friends"]] == ["さくら"]
    assert c.get("/v1/friends/requests").json() == {"incoming": [], "outgoing": []}


def test_accept(c, db):
    rid = send(c, db, B, A).json()["requestId"]
    as_user(C)
    assert c.post(f"/v1/friends/requests/{rid}/accept").status_code == 404
    as_user(B)
    assert c.post(f"/v1/friends/requests/{rid}/accept").status_code == 404  # 送った側は承認できない
    c.sent.clear()
    as_user(A)
    r = c.post(f"/v1/friends/requests/{rid}/accept")
    assert r.status_code == 200
    f = r.json()
    no_uid(r)
    assert f["displayName"] == "けんた" and f["today"] is None and f["profileImage"] is None and f["since"]
    assert c.sent == [(B, "friend_accepted", "さくらさんがフレンドの申請を承認しました", {})]
    assert [x["friendId"] for x in c.get("/v1/friends").json()["friends"]] == [f["friendId"]]
    as_user(B)
    assert [x["displayName"] for x in c.get("/v1/friends").json()["friends"]] == ["さくら"]
    assert c.get("/v1/friends/requests").json() == {"incoming": [], "outgoing": []}


def test_decline_is_silent(c, db):
    rid = send(c, db, B, A).json()["requestId"]
    c.sent.clear()
    as_user(B)
    assert c.post(f"/v1/friends/requests/{rid}/decline").status_code == 404
    as_user(A)
    assert c.post(f"/v1/friends/requests/{rid}/decline").status_code == 204
    assert c.sent == [] and c.get("/v1/friends/requests").json()["incoming"] == []
    assert c.post(f"/v1/friends/requests/{rid}/accept").status_code == 404


def test_cancel_own_request(c, db):
    rid = send(c, db, B, A).json()["requestId"]
    as_user(A)
    assert c.delete(f"/v1/friends/requests/{rid}").status_code == 404
    as_user(B)
    assert c.delete(f"/v1/friends/requests/{rid}").status_code == 204
    as_user(A)
    assert c.get("/v1/friends/requests").json()["incoming"] == []


def test_unfriend_removes_both_sides(c, db):
    fid = befriend(c, db)
    as_user(C)
    assert c.delete(f"/v1/friends/{fid}").status_code == 404
    as_user(B)
    c.sent.clear()
    assert c.delete(f"/v1/friends/{fid}").status_code == 204
    assert c.get("/v1/friends").json()["friends"] == [] and c.sent == []
    as_user(A)
    assert c.get("/v1/friends").json()["friends"] == []


def seed_today(db, uid=A, visibility="nearby", day=None):
    db.document(f"users/{uid}/dailyOutfits/{day or today_jst()}").set({
        "visibility": visibility, "image": f"users/{uid}/jobs/{JOB}/outfit.png", "items": ["w_secret1"],
        "snapshot": [{"itemId": "w_secret1", "slot": "outer", "label": "ジャケット", "color": "紺", "memo": "古着",
                      "image": f"/v1/jobs/{JOB}/images/item-3"}],
        "itemNotes": ["靴は白"], "jobId": JOB})


def test_friend_today_only_when_public_today(c, db, blobs):
    fid = befriend(c, db)
    as_user(B)
    seed_today(db)
    r = c.get("/v1/friends")
    no_uid(r)
    assert "w_secret1" not in r.text and JOB not in r.text
    t = r.json()["friends"][0]["today"]
    assert t == {"date": today_jst(), "image": f"/v1/friends/{fid}/today/image",
                 "items": [{"slot": "outer", "label": "ジャケット", "color": "紺", "memo": "古着",
                            "image": f"/v1/friends/{fid}/today/items/0/image"}],
                 "itemNotes": ["靴は白"], "liked": False}
    blobs.d[f"users/{A}/jobs/{JOB}/outfit.png"] = b"outfit"
    blobs.d[f"users/{A}/jobs/{JOB}/item-3.png"] = b"item3"
    assert c.get(f"/v1/friends/{fid}/today/image").content == b"outfit"
    assert c.get(f"/v1/friends/{fid}/today/items/0/image").content == b"item3"
    assert c.get(f"/v1/friends/{fid}/today/items/1/image").status_code == 404
    as_user(C)
    assert c.get(f"/v1/friends/{fid}/today/image").status_code == 404
    as_user(B)
    seed_today(db, visibility="private")
    assert c.get("/v1/friends").json()["friends"][0]["today"] is None
    assert c.get(f"/v1/friends/{fid}/today/image").status_code == 404
    assert c.get(f"/v1/friends/{fid}/today/items/0/image").status_code == 404


def _friend_card(c, fid, **changes):
    body = {"date": today_jst(), "slot": "outer", "label": "ジャケット", "color": "紺"} | changes
    return c.post(f"/v1/friends/{fid}/today/items/0/card", json=body)


def test_friend_card_matches_snapshot_with_only_viewers_wardrobe(c, db, blobs, monkeypatch):
    import ai

    fid = befriend(c, db)
    seed_today(db)
    blobs.put(f"users/{A}/jobs/{JOB}/outfit.png", b"outfit")
    blobs.put(f"users/{A}/jobs/{JOB}/item-3.png", b"friend item")
    blobs.put(f"users/{B}/photo.jpg", b"my photo")
    for uid, wid in ((A, "w_theirs"), (B, "w_mine")):
        db.document(f"users/{uid}/wardrobeItems/{wid}").set({
            "slot": "top", "label": "Tシャツ", "color": "白",
            "image": f"users/{uid}/shirt.png", "createdAt": datetime.now(JST)})
        blobs.put(f"users/{uid}/shirt.png", wid.encode())
    seen = []
    monkeypatch.delenv("AI_DISABLED", raising=False)
    monkeypatch.setattr(ai, "ask_match", lambda item, image, candidates: seen.append((item, image, candidates)) or
                        {"combos": [{"wardrobeItemIds": ["w_mine"], "reason": "合う"}], "missing": None, "similarOwned": None})
    monkeypatch.setattr(ai, "make_tryon", lambda photo, images: b"tryon")
    as_user(B)
    r = _friend_card(c, fid)
    assert r.status_code == 200
    no_uid(r)
    assert "w_secret1" not in r.text and JOB not in r.text
    card = r.json()
    assert len(card["items"]) == 1
    cid, item_id = card["cardId"], card["items"][0]["cardItemId"]
    assert c.get(card["items"][0]["image"]).content == b"friend item"
    result = c.post("/v1/match", json={"cardId": cid, "cardItemId": item_id})
    assert result.status_code == 200
    assert seen[0][1] == b"friend item"
    assert [candidate[0] for candidate in seen[0][2]] == ["w_mine"]
    assert c.post("/v1/tryon", json={"cardId": cid, "cardItemId": item_id, "wardrobeItemIds": ["w_mine"]}).status_code == 200
    assert (db.document(f"users/{A}/dailyOutfits/{today_jst()}").get().to_dict()).get("viewCount") is None
    as_user(C)
    assert c.get(card["image"]).status_code == 404
    assert _friend_card(c, fid).status_code == 404


@pytest.mark.parametrize("change", ["unfriend", "private", "item", "image", "day"])
def test_friend_card_expires_when_access_or_outfit_changes(c, db, blobs, change):
    from cards import load_card
    from fastapi import HTTPException

    fid = befriend(c, db)
    seed_today(db)
    as_user(B)
    card = _friend_card(c, fid).json()
    ref = db.document(f"users/{A}/dailyOutfits/{today_jst()}")
    if change == "unfriend":
        db.document(f"friendships/{fid}").delete()
    elif change == "private":
        ref.update({"visibility": "private"})
    elif change == "item":
        ref.update({"snapshot": []})
    elif change == "image":
        ref.update({"image": "different.png"})
    if change == "day":
        with pytest.raises(HTTPException) as error:
            load_card(db, card["cardId"], B, datetime.now(JST) + timedelta(days=1))
        assert error.value.status_code == 410
    else:
        assert c.get(card["image"]).status_code == 410
        assert c.post("/v1/match", json={"cardId": card["cardId"], "cardItemId": "a"}).status_code == 410


def test_friend_card_rejects_stale_selection_and_unpublished_outfit(c, db):
    fid = befriend(c, db)
    seed_today(db)
    as_user(B)
    assert _friend_card(c, fid, label="別の服").status_code == 409
    assert _friend_card(c, fid, date="2000-01-01").status_code == 409
    seed_today(db, visibility="private")
    assert _friend_card(c, fid).status_code == 404
    as_user(B, anonymous=True)
    assert _friend_card(c, fid).status_code == 403


def test_past_day_is_not_shown(c, db, blobs):
    befriend(c, db)
    yesterday = (date.fromisoformat(today_jst()) - timedelta(days=1)).isoformat()
    seed_today(db, day=yesterday)
    as_user(B)
    assert c.get("/v1/friends").json()["friends"][0]["today"] is None


def test_profile_image(c, db, blobs):
    from friends import me_fields

    as_user(A)
    r = c.put("/v1/me/profile-image", files={"image": ("p.jpg", jpeg(), "image/jpeg")}, data={"crop": '{"x":0.1}'})
    assert r.status_code == 204
    im = Image.open(io.BytesIO(blobs.d[f"users/{A}/profile.jpg"]))
    assert im.format == "JPEG" and max(im.size) == 1024 and not im.getexif()
    assert me_fields(db, A) | {"friendCode": ""} == {"friendCode": "", "profileImage": "/v1/me/profile-image",
                                                     "profileCrop": '{"x":0.1}'}
    assert c.get("/v1/me/profile-image").content == blobs.d[f"users/{A}/profile.jpg"]

    rid = send(c, db, A, B).json()["requestId"]
    as_user(B)
    assert c.get("/v1/friends/requests").json()["incoming"][0]["profileImage"] is None  # 承認の前は出さない
    fid = c.post(f"/v1/friends/requests/{rid}/accept").json()["friendId"]
    f = c.get("/v1/friends").json()["friends"][0]
    assert f["profileImage"] == f"/v1/friends/{fid}/profile-image" and f["profileCrop"] == '{"x":0.1}'
    assert c.get(f"/v1/friends/{fid}/profile-image").content == blobs.d[f"users/{A}/profile.jpg"]
    assert c.get("/v1/me/profile-image").status_code == 404
    as_user(C)
    assert c.get(f"/v1/friends/{fid}/profile-image").status_code == 404

    as_user(A)
    assert c.delete("/v1/me/profile-image").status_code == 204
    assert f"users/{A}/profile.jpg" not in blobs.d and me_fields(db, A)["profileImage"] is None
    as_user(B)
    assert c.get("/v1/friends").json()["friends"][0]["profileImage"] is None


def test_profile_image_rejects_non_image(c, blobs):
    as_user(A)
    r = c.put("/v1/me/profile-image", files={"image": ("p.jpg", b"not an image", "image/jpeg")})
    assert r.status_code == 400 and r.json()["error"]["code"] == "validation"


@pytest.mark.parametrize("method,path", [
    ("get", "/v1/friends"), ("delete", "/v1/friends/f_x"), ("get", "/v1/friends/f_x/today/image"),
    ("get", "/v1/friends/f_x/today/items/0/image"), ("get", "/v1/friends/f_x/profile-image"),
    ("get", "/v1/friends/requests"), ("post", "/v1/friends/requests"), ("post", "/v1/friends/requests/r_x/accept"),
    ("post", "/v1/friends/requests/r_x/decline"), ("delete", "/v1/friends/requests/r_x"),
    ("get", "/v1/me/profile-image"), ("delete", "/v1/me/profile-image")])
def test_anonymous_is_403(c, method, path):
    as_user("anon1", anonymous=True)
    kw = {"json": {"friendCode": "ABCDEFGH"}} if method == "post" and path.endswith("requests") else {}
    assert getattr(c, method)(path, **kw).status_code == 403


def test_anonymous_put_profile_image_is_403(c):
    as_user("anon1", anonymous=True)
    assert c.put("/v1/me/profile-image", files={"image": ("p.jpg", jpeg((10, 10)), "image/jpeg")}).status_code == 403


def test_profile_image_without_crop_keeps_previous_crop(c, db, blobs):
    """画像だけを替える時は、前に決めた表示範囲を残す"""
    from friends import me_fields

    as_user(A)
    c.put("/v1/me/profile-image", files={"image": ("p.jpg", jpeg(), "image/jpeg")}, data={"crop": '{"x":0.1}'})
    c.put("/v1/me/profile-image", files={"image": ("p.jpg", jpeg(), "image/jpeg")})
    assert me_fields(db, A)["profileCrop"] == '{"x":0.1}'


def test_racing_accepts_make_one_friendship(c, db):
    """同時の相互申請 (両方の申請が残った) を両方が承認しても関係は 1 件。片方の解除で両方から消える。"""
    now = datetime.now(JST)
    db.document("friendRequests/r_ab").set({"from": A, "to": B, "createdAt": now})
    db.document("friendRequests/r_ba").set({"from": B, "to": A, "createdAt": now})
    as_user(A)
    f1 = c.post("/v1/friends/requests/r_ba/accept").json()
    c.sent.clear()
    as_user(B)
    f2 = c.post("/v1/friends/requests/r_ab/accept").json()
    assert f1["friendId"] == f2["friendId"] and f1["since"] == f2["since"] and c.sent == []
    assert len(list(db.collection("friendships").stream())) == 1
    assert c.delete(f"/v1/friends/{f2['friendId']}").status_code == 204
    as_user(A)
    assert c.get("/v1/friends").json()["friends"] == []


def test_friend_id_does_not_contain_uid(c, db):
    fid = befriend(c, db)
    assert re.fullmatch(r"f_[0-9a-f]{22}", fid) and A not in fid and B not in fid


def test_profile_image_rejects_huge_pixel_count(c, blobs):
    buf = io.BytesIO()
    Image.new("1", (6400, 6400)).save(buf, "PNG")  # ファイルは小さいが、展開すると 4,096 万画素
    as_user(A)
    r = c.put("/v1/me/profile-image", files={"image": ("p.png", buf.getvalue(), "image/png")})
    assert r.status_code == 400 and not blobs.d
