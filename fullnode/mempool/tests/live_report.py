#!/usr/bin/env python3
"""Report of a live mainnet run of the mempool, from its journal (logs/journal.jsonl), its log and
its RPC (getmempoolstats), plus the state (read-only) for "mined later".

  * distinct transactions received (P2P / RPC), admitted vs rejected, rejection reasons
    (a tx rejected for a tip-scoped reason, e.g. a missing input while the state lags the
    network, can be admitted later: counted once, as admitted)
  * of the admitted ones: mined in a later block (journal "removed: mined" events, or found in
    the state's tx index), still in the mempool, removed for another reason
  * relay: txs announced to peers, peers that fetched one from us (getdata), peers that later
    announced back to us a tx we had announced
usage: python3 tests/live_report.py [--journal logs/journal.jsonl] [--log logs/mempool.log]
"""
import argparse, collections, json, re, sqlite3, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MP = HERE.parent


def category(reason):
    r = reason or ""
    if r.startswith("cached: "):
        r = r[8:]
    if r.startswith("missing input"):
        return "missing input (the state is behind the network)" if "behind" in r else (
            "missing input (spent in the chain)" if "spent in the chain" in r else "missing input")
    if r.startswith("Ironwood anchor is a root of a block above"):
        return "Ironwood anchor newer than the state's tip (the state is behind)"
    if r.startswith("Ironwood anchor is not a root of any block"):
        return "Ironwood anchor unknown at this state's tip (invalid, or newer)"
    if r.startswith("spend conflict"):
        return "spend conflict with a mempool tx"
    if r.startswith("consensus (hook)"):
        return "consensus (hook): " + " ".join(r.split(":", 1)[1].split()[:2])
    if r.startswith("consensus: malformed"):
        return "consensus: malformed (wire validator)"
    if r.startswith("consensus"):
        return "consensus: " + ", ".join(sorted({x.split()[0] for x in r.split(":", 1)[1].split(";")}))
    if r.startswith("policy"):
        return r.split(" (fee")[0]
    return r.split(":")[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--journal", default=str(MP / "logs/journal.jsonl"))
    ap.add_argument("--log", default=str(MP / "logs/mempool.log"))
    ap.add_argument("--state", default=str(MP.parent / "state-tip"))
    ap.add_argument("--rpc", type=int, default=18234)
    a = ap.parse_args()
    J = [json.loads(l) for l in open(a.journal)]
    t0, t1 = J[0]["t"], J[-1]["t"]
    seen = collections.OrderedDict()  # txid -> list of results
    events = []
    for j in J:
        if "status" in j:
            if j["status"] == "duplicate" or not j.get("txid"):
                continue
            seen.setdefault(j["txid"], []).append(j)
        else:
            events.append(j)
    admitted = {t for t, rs in seen.items() if any(r["status"] == "admitted" for r in rs)}
    rejected = {t: rs[-1] for t, rs in seen.items() if t not in admitted}
    later = {t for t, rs in seen.items() if t in admitted and rs[0]["status"] == "rejected"}
    cats = collections.Counter(category(r["reason"]) for r in rejected.values())
    srcs = collections.Counter(("rpc" if r["source"] == "rpc" else r["source"].split()[0]) for rs in seen.values()
                               for r in rs[:1])
    mined_ev = {e["txid"]: e.get("height") for e in events if e.get("event") == "removed" and e.get("reason") == "mined"}
    other_rm = collections.Counter(e["reason"].split(":")[0] for e in events
                                   if e.get("event") == "removed" and e.get("reason") != "mined" and e["txid"] in admitted)
    db = sqlite3.connect(f"file:{Path(a.state) / 'chain.sqlite'}?mode=ro", uri=True)
    mined_state = {}
    for t in admitted:
        r = db.execute("SELECT height FROM tx WHERE txid=?", (bytes.fromhex(t)[::-1],)).fetchone()
        if r:
            mined_state[t] = r[0]
    tip = json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])["height"]
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{a.rpc}/", data=json.dumps(
            {"jsonrpc": "1.0", "id": 1, "method": "getmempoolstats", "params": []}).encode())
        stats = json.load(urllib.request.urlopen(req, timeout=30))["result"]
        req = urllib.request.Request(f"http://127.0.0.1:{a.rpc}/", data=json.dumps(
            {"jsonrpc": "1.0", "id": 1, "method": "getrawmempool", "params": []}).encode())
        inpool = set(json.load(urllib.request.urlopen(req, timeout=30))["result"])
    except Exception:
        stats, inpool = None, set()
    mined = set(mined_ev) | set(mined_state)
    adm_mined = admitted & mined
    adm_in = (admitted - mined) & inpool
    rej_mined = {t for t in rejected if db.execute("SELECT 1 FROM tx WHERE txid=?", (bytes.fromhex(t)[::-1],)).fetchone()}
    rej_mined_cats = collections.Counter(category(rejected[t]["reason"]) for t in rej_mined)
    log = open(a.log).read()
    inbound = re.findall(r"inbound peer (\S+):\d+ (\S+)", log)
    inbound_net = [x for x in inbound if not x[0].startswith(("127.", "::1"))]
    out = {
        "window": {"from": t0, "to": t1, "hours": round((t1 - t0) / 3600, 2), "state_tip_now": tip},
        "received_distinct_txs": len(seen), "first_source": dict(srcs),
        "admitted": len(admitted), "admitted_after_an_earlier_tip_scoped_rejection": len(later),
        "rejected": len(rejected), "rejected_by_reason": dict(cats.most_common()),
        "admitted_then_mined": len(adm_mined), "admitted_still_in_mempool": len(adm_in),
        "admitted_removed_other": dict(other_rm),
        "admitted_unaccounted": len(admitted - mined - inpool - {e["txid"] for e in events if e.get("event") == "removed"}),
        "rejected_but_mined_later": len(rej_mined), "rejected_but_mined_later_by_reason": dict(rej_mined_cats),
        "mined_heights": [min(mined_state.values() or [0]), max(mined_state.values() or [0])],
        "inbound_connections_from_internet": len(inbound_net), "inbound_local": len(inbound) - len(inbound_net),
    }
    if stats:
        out["relay"] = stats["relayed"]
        out["p2p"] = stats["p2p"]
        out["counts"] = stats["counts"]
        out["anchors"] = stats["anchors"]
        out["oracle"] = stats["oracle"]
    print(json.dumps(out, indent=1))
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "live.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
