# 本物の api の土台 (S5) と匿名 ID (S1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仮の api の口を、本物の認証・回数の上限・Firestore で動く口に順に置き換える。最初に `GET/PATCH /v1/me`、`PUT /v1/publish` (匿名 ID の発行)、`POST /v1/nearby` (ID → カード) を本物にする。

**Architecture:** `server/api/main.py` の仮の口 (見本を返す) は残し、本物にした口だけを前に足す (FastAPI は先に登録した口が勝つ)。認証は firebase-admin の `verify_id_token`、データは firebase-admin の Firestore。テストは Firestore のエミュレータと、認証の依存の差し替えで行う。

**Tech Stack:** Python 3.12、FastAPI、firebase-admin、Firestore エミュレータ (`npx firebase-tools emulators:exec --only firestore`)、pytest

**Spec:** `docs/architecture.md` (3.2、3.3、4、5 節)、`docs/api.yaml`、`docs/tech-decisions.md` (1、3、7)

## Global Constraints

- 返すのは `docs/api.yaml` の形。食い違ったら `docs/api.yaml` が正しい
- 匿名 ID は 11 バイトの乱数の 16 進 (22 文字)。5 分の枠ごとに 1 つ、公開した時からその日の 24 時 (JST) までの分をまとめて発行
- サーバが受け付ける ID は、その ID の枠が終わってから 20 分以内
- 同じ人の着姿は見る人ごとに 1 日 1 回。記録は HMAC-SHA256(秘密, 見る人 uid + 見られる人 uid + 日付) だけを `viewLog/{日付}/v/{hmac}` に置く
- お互いさま: 見る人が今日公開していなければ `cards: []`、`viewerPublishing: false`
- `DEMO_UIDS` (環境変数、カンマ区切り) の見られる側は、日付・1 日 1 回・お互いさまの判定から外す。見る側が `DEMO_UIDS` でも同じく外す
- 見る側に返すのは使い捨ての `cardId` だけ。uid・匿名 ID・手持ちの服の id は返さない。カードは `cards/{cardId}` に置き、見てから 30 分で切れる
- ログに ID トークン・匿名 ID・素の uid を書かない
- 日付は JST (`Asia/Tokyo`) で区切る
- 回数の上限: 利用者ごと・1 日・口の種類ごと。既定は nearby 200、match 30、tryon 10 (環境変数 `QUOTA_<KIND>` で変えられる)。超えたら 429 `quota_exceeded`

## Review Focus

- ID の枠の境目 (枠が終わってちょうど 20 分) と、日付をまたぐ ID (23:55 の枠): 受け付けるか、どの日付の着姿を返すかが決まっていること
- 同じ ID の一覧に同じ人の ID が 2 つ以上 (5 分ずつ受け取った) 入っている時: カードは 1 枚
- 見る人自身の ID が一覧に入っている時: 自分のカードは返さない
- 公開を取り消した (private) 後に、前に受け取った ID が来た時: 返さない
- 発行の後に公開をし直した時: 前の ID は無効になり、新しい ID だけが通る

---

### Task 1: 認証と回数の上限 (S5)

**Files:**
- Create: `server/api/auth.py`、`server/api/test_auth.py`
- Modify: `server/api/requirements.txt` (firebase-admin を足す)

**Interfaces:**
- Produces: `async def current_user(authorization: str = Header("")) -> User` (FastAPI の依存)。`User` は `dataclass(uid: str, is_anonymous: bool)`。テストは `app.dependency_overrides[current_user]` で差し替える
- Produces: `def charge(db, uid: str, kind: str, today: date) -> None` (上限を超えたら `HTTPException(429)`)。`quotas/{uid}_{日付}` の `kind` を transaction で 1 足す

- [ ] **Step 1: テストを書く** — `test_missing_bearer_is_401`、`test_invalid_token_is_401` (`verify_id_token` が例外を投げる時)、`test_charge_allows_up_to_limit_then_429` (上限 2 で 3 回目が 429)、`test_charge_counts_per_day` (日付が変われば 0 から)
- [ ] **Step 2: 落ちるのを確かめる** — `npx firebase-tools emulators:exec --only firestore --project demo-test "python -m pytest -q server/api/test_auth.py"`
- [ ] **Step 3: 実装** — `firebase_admin.auth.verify_id_token(token)`。`is_anonymous` は `decoded["firebase"]["sign_in_provider"] == "anonymous"`
- [ ] **Step 4: 通るのを確かめる** (Step 2 と同じ)
- [ ] **Step 5: commit**

### Task 2: 自分の状態 (`GET/PATCH /v1/me`)

**Files:**
- Create: `server/api/routes_me.py`、`server/api/test_me.py`
- Modify: `server/api/main.py` (本物の口を仮の口より先に登録する)

**Interfaces:**
- Consumes: `current_user`
- Produces: Firestore `users/{uid}` (`displayName`、`hasPhoto`)、`users/{uid}/dailyOutfits/{日付}` (`visibility`、`until`)。`viewCountToday` は `users/{uid}/dailyOutfits/{日付}.viewCount`

- [ ] **Step 1: テストを書く** — `test_me_new_user_defaults` (`displayName == ""`、`publishing.visibility == "private"`、`viewCountToday == 0`)、`test_patch_me_sets_name`、`test_patch_me_rejects_empty_and_over_20` (422)
- [ ] **Step 2: 落ちるのを確かめる**
- [ ] **Step 3: 実装** — 応答の形は `docs/api.yaml` の `Me`
- [ ] **Step 4: 通るのを確かめる** — 仮の口のテスト (`test_main.py`) も全部通ること
- [ ] **Step 5: commit**

### Task 3: 公開と匿名 ID の発行 (`PUT /v1/publish`)

**Files:**
- Create: `server/api/broadcast.py`、`server/api/test_broadcast.py`

**Interfaces:**
- Produces: `def issue_ids(db, uid: str, now: datetime) -> list[dict]` (`[{"slotStart": iso, "id": hex22}]`、now の枠から 24 時まで)。`broadcastIds/{id}` に `{uid, slotStart, slotEnd, date, epoch}` を書く。`users/{uid}/dailyOutfits/{日付}.epoch` を 1 足し、古い epoch の ID は以後無効
- Produces: `def unpublish(db, uid: str, today: date) -> None`

- [ ] **Step 1: テストを書く** — `test_issue_ids_covers_until_midnight` (23:52 に公開 → 23:50 と 23:55 の 2 枠)、`test_ids_are_22_hex_and_unique`、`test_publish_without_today_outfit_is_409` (`no_outfit_today`)、`test_republish_invalidates_old_ids`、`test_private_returns_no_ids`
- [ ] **Step 2〜5:** 落ちる → 実装 → 通る → commit

### Task 4: ID → カード (`POST /v1/nearby`)

**Files:**
- Create: `server/api/nearby.py`、`server/api/test_nearby.py`

**Interfaces:**
- Consumes: `broadcastIds/{id}`、`users/{uid}/dailyOutfits/{日付}`、`blocks/{viewer}_{owner}`
- Produces: `def resolve(db, viewer: str, sightings: list[dict], now: datetime, demo_uids: set[str], secret: bytes) -> dict` (`{"cards": [...], "viewerPublishing": bool}`)。カードごとに `cards/{cardId}` に `{owner, outfitDate, expiresAt, items: {cardItemId: wardrobeItemId}}` を書く

- [ ] **Step 1: テストを書く** — `test_returns_card_for_published_owner`、`test_viewer_not_publishing_gets_empty`、`test_same_owner_twice_today_is_hidden`、`test_two_ids_of_same_owner_make_one_card`、`test_own_id_is_ignored`、`test_id_older_than_20min_after_slot_is_ignored`、`test_unpublished_owner_is_hidden`、`test_blocked_owner_is_hidden`、`test_demo_owner_ignores_once_per_day_and_date`、`test_card_has_no_uid_or_item_ids` (応答の JSON に uid・匿名 ID・`w_` で始まる id が含まれない)
- [ ] **Step 2〜5:** 落ちる → 実装 → 通る → commit。並びは `lastSeenAt` の新しい順、同じなら rssi の強い順。`viewCount` を 1 足す

### Task 5: 配備とレビュー

- [ ] `server/api/Dockerfile` に新しいファイルを入れる。Cloud Run のサービスアカウントに `roles/datastore.user` があることを確かめる (無ければ白井さんに聞く)
- [ ] 環境変数: `VIEWLOG_SECRET` (Secret Manager か、配備の時に渡す)、`DEMO_UIDS`
- [ ] ponytail のレビュー → 普通のコードレビュー → 直す → 配備 → URL で `/v1/me` を本物のトークンで確かめる
