"""api (Cloud Run の軽い方)。口は docs/api.yaml。本物にした口を router ごとに足す。

エラーはどれも {"error": {"code", "message"}} の形で返す (docs/api.yaml の Error)。
"""
import logging
import os

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

import broadcast
import cards
import friends
import likes
import match
import nearby
import notifications
import outfits
import routes_me
import saves
import same
import tryon

app = FastAPI(title="api")
# Web デモ (Firebase Hosting) と手元の flutter run からブラウザで呼ぶため
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get(
        "CORS_ORIGINS",
        "https://project-10522535-9db8-40c0-a68.web.app,https://project-10522535-9db8-40c0-a68.firebaseapp.com",
    ).split(","),
    allow_origin_regex=r"http://localhost:\d+",
    allow_methods=["*"],
    allow_headers=["authorization", "content-type", "x-admin-token"],
)


def error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status)


@app.middleware("http")
async def unexpected(request: Request, call_next):
    """想定外の失敗も Error の形で返す。例外の文には uid や path が入りうるので、ログには型の名前だけ。"""
    try:
        return await call_next(request)
    except Exception as e:
        logging.error("unhandled %s %s: %s", request.method, request.url.path.split("/")[2:3], type(e).__name__)
        return error(500, "internal", "処理に失敗しました。もう一度お試しください")


@app.exception_handler(HTTPException)  # starlette の物を受けると、口の無い道の 404 もこの形になる
def http_error(_: Request, e: HTTPException) -> JSONResponse:
    if isinstance(e.detail, dict):
        return JSONResponse({"error": e.detail}, status_code=e.status_code)
    if e.status_code == 404:
        return error(404, "not_found", "見つかりません")
    return error(e.status_code, "internal", str(e.detail))


@app.exception_handler(RequestValidationError)
def validation_error(_: Request, e: RequestValidationError) -> JSONResponse:
    return error(422, "validation", "入力の形が正しくありません")


for r in (routes_me, broadcast, nearby, outfits, cards, match, tryon, same, friends, notifications, likes, saves):
    app.include_router(r.router)
