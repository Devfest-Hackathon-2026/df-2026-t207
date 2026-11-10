"""すれ違い検証 (jp.wojak.blepoc) の CSV から秒数を出す。標準ライブラリだけ。

使い方:
  python analyze.py summary  <csv>...                     各ファイルの件数・失敗・端末の対応
  python analyze.py open     <受信側の csv>               画面を開いてから最初の受信までの秒数
  python analyze.py latency  <発信側の csv> <受信側の csv> [--offset-ms N]
                                                          発信側が新しい ID を出してから、受信側が最初に受け取るまでの秒数
  python analyze.py gaps     <受信側の csv> [--sender <発信側の csv>] [--gap 30]
                                                          受信が途切れた区間 (画面オフでの発信の継続の試験)

--offset-ms: 受信側の時計 - 発信側の時計 (ミリ秒)。README の「時計のずれ」の手順で測る。
"""
import argparse
import csv
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime


def load(path):
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["t"] = int(r["time_ms"])
    rows.sort(key=lambda r: r["t"])
    return rows


def hhmmss(ms):
    return datetime.fromtimestamp(ms / 1000).strftime("%H:%M:%S")


def stats(label, xs):
    if not xs:
        print(f"  {label}: データなし")
        return
    xs = sorted(xs)
    p90 = xs[min(len(xs) - 1, int(round(0.9 * (len(xs) - 1))))]
    print(f"  {label}: n={len(xs)}  中央値 {statistics.median(xs):.2f} 秒  平均 {statistics.mean(xs):.2f}"
          f"  90% {p90:.2f}  最小 {xs[0]:.2f}  最大 {xs[-1]:.2f}")


def cmd_summary(paths):
    for p in paths:
        rows = load(p)
        labels = sorted({r["label"] for r in rows})
        print(f"== {p}  ラベル {labels}  {hhmmss(rows[0]['t'])}〜{hhmmss(rows[-1]['t'])}  {len(rows)} 行")
        for ev, n in sorted(Counter(r["event"] for r in rows).items()):
            print(f"  {ev:14s} {n}")
        for r in rows:
            if r["event"] in ("caps", "svc_create") and r["detail"]:
                print(f"  対応: {r['detail']}")
                break
        for r in rows:
            if r["event"].endswith("_fail"):
                print(f"  失敗 {hhmmss(r['t'])} {r['event']} {r['method']} {r['detail']}")


def cmd_open(path):
    """ui_open から、次の ui_close までの最初の rx の秒数。方式と受信のモードで分ける"""
    rows = load(path)
    groups = defaultdict(list)
    missed = 0
    deferred = 0
    opened = None
    for r in rows:
        if r["event"] == "ui_open":
            opened = r
        elif r["event"] == "ui_close":
            if opened is not None:
                missed += 1
            opened = None
        elif r["event"] == "rx_deferred" and opened is not None:
            # 30 秒 5 回の制限で張り直しが後回しになった回は、前のスキャンが続いていて測り方が違うので数えない
            deferred += 1
            opened = None
        elif r["event"] == "rx" and opened is not None:
            sec = (r["t"] - opened["t"]) / 1000
            groups[(r["method"], r["rx_mode"])].append(sec)
            opened = None
    print(f"== {path}: 画面を開いてから最初の受信まで")
    for (m, mode), xs in sorted(groups.items()):
        stats(f"{m} {mode}", xs)
    print(f"  開いて閉じるまでに 1 件も来なかった回数: {missed}")
    print(f"  スキャンの回数の制限で張り直しが後回しになり、数えなかった回数: {deferred}")


def sender_ids(rows):
    """発信側の id_rotate → (時刻, ID, 方式)。tx_start が後に来たらその時刻にする (発信が実際に始まった時刻)"""
    out = []
    for r in rows:
        if r["event"] == "id_rotate" and r["tx_id"]:
            out.append({"t": r["t"], "id": r["tx_id"], "method": r["method"], "start": None})
        elif r["event"] == "tx_start" and out and out[-1]["start"] is None and r["tx_id"] == out[-1]["id"]:
            out[-1]["start"] = r["t"]
    return out


def cmd_latency(sender_path, receiver_path, offset_ms):
    srows, rrows = load(sender_path), load(receiver_path)
    first = {}
    for r in rrows:
        if r["event"] == "rx" and r["rx_id"] not in first:
            first[r["rx_id"]] = r
    groups = defaultdict(list)
    print(f"== 発信 {sender_path} → 受信 {receiver_path}  (offset {offset_ms} ms)")
    for s in sender_ids(srows):
        t0 = s["start"] or s["t"]
        r = first.get(s["id"])
        if r is None:
            print(f"  {hhmmss(t0)} {s['id'][:8]}  受け取っていない")
            continue
        sec = (r["t"] - offset_ms - t0) / 1000
        state = f"画面{'on' if r['screen_on'] == '1' else 'off'}・{'前面' if r['app_fg'] == '1' else '裏'}・{r['rx_mode']}"
        print(f"  {hhmmss(t0)} {s['id'][:8]}  {sec:7.2f} 秒  RSSI {r['rssi'] or '-'}  受信側 {state}")
        groups[(s["method"], state)].append(sec)
    print("  まとめ:")
    for k, xs in sorted(groups.items()):
        stats(f"{k[0]} {k[1]}", xs)


def cmd_gaps(path, sender_path, gap_s):
    rows = load(path)
    ids = None
    if sender_path:
        ids = {s["id"] for s in sender_ids(load(sender_path))}
    rx = [r for r in rows if r["event"] == "rx" and (ids is None or r["rx_id"] in ids)]
    if not rx:
        print("受信が 1 件も無い")
        return
    print(f"== {path}: {hhmmss(rx[0]['t'])}〜{hhmmss(rx[-1]['t'])} に {len(rx)} 件"
          f" ({(rx[-1]['t'] - rx[0]['t']) / 60000:.1f} 分)。{gap_s} 秒を超える途切れ:")
    n = 0
    for a, b in zip(rx, rx[1:]):
        d = (b["t"] - a["t"]) / 1000
        if d > gap_s:
            n += 1
            print(f"  {hhmmss(a['t'])} → {hhmmss(b['t'])}  {d:.0f} 秒")
    print(f"  途切れ {n} 回。最後の受信 {hhmmss(rx[-1]['t'])}")
    rssi = [int(r["rssi"]) for r in rx if r["rssi"]]
    if rssi:
        print(f"  RSSI 中央値 {statistics.median(rssi):.0f} dBm (最小 {min(rssi)} / 最大 {max(rssi)})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("summary"); a.add_argument("csv", nargs="+")
    a = sub.add_parser("open"); a.add_argument("csv")
    a = sub.add_parser("latency"); a.add_argument("sender"); a.add_argument("receiver")
    a.add_argument("--offset-ms", type=int, default=0)
    a = sub.add_parser("gaps"); a.add_argument("csv"); a.add_argument("--sender"); a.add_argument("--gap", type=float, default=30)
    args = ap.parse_args()
    if args.cmd == "summary":
        cmd_summary(args.csv)
    elif args.cmd == "open":
        cmd_open(args.csv)
    elif args.cmd == "latency":
        cmd_latency(args.sender, args.receiver, args.offset_ms)
    else:
        cmd_gaps(args.csv, args.sender, args.gap)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
