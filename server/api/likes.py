"""いいね (PUT/DELETE /v1/likes/cards/{cardId}、/v1/likes/friends/{friendId})。tasks の M9。

- いいねは持ち主のその日のコーデ (users/{owner}/dailyOutfits/{day}) の likeCount に数える。同じ見る人・同じ出所 (card / friend) からは 1 つ。
  取り消すと減る。出所ごとに分けるのは、カードのいいねで FriendPost.liked が立つと、すれ違いの相手がどのフレンドか分かるため
- 誰がいいねしたかは top-level の likes/{hash} にだけ置く (users/{owner} の下は持ち主がアプリで読めるため)
- 通知は同じ見る人・出所・コーデにつき 1 日 1 回 (付けて外してを繰り返してプッシュを送り続けられないように)
- カードの持ち主には「近くの人から」とだけ通知し、誰からかは出さない。フレンドには名前を出す
- 匿名 (Web デモ) はカードにだけ付けられる
"""
import hashlib
from datetime import datetime

from fastapi import APIRouter, Depends, Response
from google.cloud import firestore

import friends
from auth import User, charge, charge_user, current_user, google_uid
from cards import load_card, not_found
from notify import notify_once
from routes_me import JST, get_db, today_jst

router = APIRouter()


def _like_ref(db, source: str, viewer: str, outfit_path: str):
    return db.document("likes/" + hashlib.sha256(f"{source}|{viewer}|{outfit_path}".encode()).hexdigest())


def liked(db, viewer: str, owner: str, day: str) -> bool:
    """viewer が owner の day のコーデにフレンドとしていいねしているか (FriendPost.liked)。カードからのいいねは見ない。"""
    return _like_ref(db, "friend", viewer, f"users/{owner}/dailyOutfits/{day}").get().exists


def set_like(db, source: str, viewer: str, outfit_path: str, on: bool) -> bool:
    """いいねを付ける / 外す。数が変わった時だけ True。"""
    like, outfit = _like_ref(db, source, viewer, outfit_path), db.document(outfit_path)

    @firestore.transactional
    def run(tx) -> bool:
        if like.get(transaction=tx).exists == on:
            return False
        if on:
            tx.set(like, {"at": firestore.SERVER_TIMESTAMP})
        else:
            tx.delete(like)
        tx.update(outfit, {"likeCount": firestore.Increment(1 if on else -1)})
        return True

    return run(db.transaction())


@router.put("/v1/likes/cards/{cardId}", status_code=204)
def like_card(cardId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    now = datetime.now(JST)
    card = load_card(db, cardId, user.uid, now)
    charge_user(db, user, "like", now.date())
    if set_like(db, "card", user.uid, card["outfitRef"], True):
        notify_once(db, f"like|card|{user.uid}|{card['outfitRef']}", card["owner"], "like", "近くの人からいいねが付きました")
    return Response(status_code=204)


@router.delete("/v1/likes/cards/{cardId}", status_code=204)
def unlike_card(cardId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    card = load_card(db, cardId, user.uid, datetime.now(JST))
    set_like(db, "card", user.uid, card["outfitRef"], False)
    return Response(status_code=204)


def _friend_outfit(db, uid: str, friend_id: str) -> tuple[str, str]:
    """フレンドの今日の公開コーデの path と持ち主。フレンドでないか公開していなければ 404。"""
    owner = friends.friend_owner(db, uid, friend_id)
    if not friends._today(db, owner):
        raise not_found()
    return owner, f"users/{owner}/dailyOutfits/{today_jst()}"


@router.put("/v1/likes/friends/{friendId}", status_code=204)
def like_friend(friendId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    uid = google_uid(user)
    owner, path = _friend_outfit(db, uid, friendId)
    charge(db, uid, "like", datetime.now(JST).date())
    if set_like(db, "friend", uid, path, True):
        name = (db.document(f"users/{uid}").get().to_dict() or {}).get("displayName") or "フレンド"
        notify_once(db, f"like|friend|{uid}|{path}", owner, "like", f"{name}さんからいいねが付きました")
    return Response(status_code=204)


@router.delete("/v1/likes/friends/{friendId}", status_code=204)
def unlike_friend(friendId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    uid = google_uid(user)
    owner = friends.friend_owner(db, uid, friendId)
    set_like(db, "friend", uid, f"users/{owner}/dailyOutfits/{today_jst()}", False)
    return Response(status_code=204)
