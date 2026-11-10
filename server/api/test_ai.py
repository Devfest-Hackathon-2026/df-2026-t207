"""ai._client の試験。本物の Gemini は呼ばない。"""
import sys
import threading
import time
import types
from concurrent.futures import ThreadPoolExecutor

import ai


def test_concurrent_first_calls_share_one_client(monkeypatch):
    """起動直後に same-items・登録が 4 本並べて呼ぶと Client が何個も作られ、捨てられた方が閉じて送りかけの要求が落ちた (2026-11-09)"""
    made = []

    class FakeClient:
        def __init__(self, **kw):
            time.sleep(0.05)  # 作るのに時間がかかる間に、ほかのスレッドが来る
            made.append(self)

    google = types.ModuleType("google")
    google.genai = types.SimpleNamespace(Client=FakeClient)
    monkeypatch.setitem(sys.modules, "google", google)
    ai._new_client.cache_clear()
    start = threading.Barrier(4)

    def call(_):
        start.wait()
        return ai._client()

    with ThreadPoolExecutor(4) as ex:
        got = list(ex.map(call, range(4)))
    ai._new_client.cache_clear()
    assert len(made) == 1
    assert all(c is made[0] for c in got)
