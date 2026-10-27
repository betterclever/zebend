#!/usr/bin/env python3
"""ZIP 401 eviction and the rejection caches (policy), in-process, with real transactions.

  1. ZIP 401: the live mempool's txs are admitted into a test pool whose cost limit fits only
     LIMIT_TXS txs (cost = max(size, 10,000)); after every insertion the total cost must be
     <= the limit, each evicted tx must be in the RecentlyEvicted cache (re-submission rejected
     as cached, not re-validated), and over many random trials the eviction frequency of a tx
     must follow its eviction weight (cost + 40,000 if it pays less than the conventional fee).
  2. rejection caches: a tampered tx is rejected once by validation; the same bytes again are
     answered from the cache; a new block clears the tip-scoped caches (clear_tip_rejections).
usage: python3 tests/test_eviction.py [--state ../state-tip]
"""
import argparse, collections, json, random, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from admit import Admitter, ChainView
from pool import Pool, Entry

LIMIT_TXS = 3


def rpc(method, *params):
    req = urllib.request.Request("http://127.0.0.1:18234/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode())
    return json.load(urllib.request.urlopen(req, timeout=60))["result"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=str(HERE.parent.parent / "state-tip"))
    a = ap.parse_args()
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        print(f"  {'PASS' if ok else 'FAIL'}  {name} {detail}")

    view = ChainView(a.state)
    logs = []
    txids = [t for t in rpc("getrawmempool")]
    raws = [bytes.fromhex(rpc("getrawtransaction", t, 0)) for t in txids]
    small = [r for r in raws if len(r) <= 10_000]
    limit_txs = max(1, min(LIMIT_TXS, len(small) - 2))  # at least 2 evictions when >= 3 txs
    adm = Admitter(view, Pool(cost_limit=limit_txs * 10_000), logs.append)
    print(f"{len(raws)} live txs, {len(small)} with size <= 10,000 (cost 10,000 each); limit {limit_txs * 10_000}")
    over, evicted, admitted = 0, [], []
    for r in small:
        res = adm.admit([(r, "test")])[0]
        if res.status == "admitted":
            admitted.append(res.txid)
        elif res.reason and "evicted" in res.reason:
            evicted.append(res.txid)
        over += adm.pool.total_cost > adm.pool.cost_limit
        ev = [l for l in logs if "ZIP 401 eviction" in l]
    cached = adm.pool.chain.get("randomly evicted (ZIP 401)")
    n_ev = len(cached) if cached else 0
    check("total cost never above the limit after an insertion", over == 0,
          f"(final {adm.pool.total_cost} / {adm.pool.cost_limit}, {len(adm.pool.entries)} txs)")
    check("evictions happened and every evicted txid is in the RecentlyEvicted cache",
          n_ev > 0 and n_ev == len(small) - len(adm.pool.entries),
          f"{n_ev} evicted of {len(small)}")
    if cached and len(cached):
        victim = next(iter(cached.d))
        raw = next(r for r, t in zip(raws, txids) if t == victim)
        again = adm.admit([(raw, "test")])[0]
        check("re-submitting an evicted tx is answered from the cache", again.status == "rejected" and
              (again.reason or "").startswith("cached"), again.reason or "")
    # eviction weights: many trials on a synthetic pool (weights only; no validation involved)
    trials = 20000
    cnt = collections.Counter()
    for _ in range(trials):
        p = Pool(cost_limit=10**12)
        es = [Entry(txid=f"{i:064x}", auth="", raw=b"", v=4, size=s, fee=f, conv_fee=10_000, ins=[], outs=[], nfs={})
              for i, (s, f) in enumerate([(5_000, 20_000), (5_000, 1_000), (30_000, 50_000)])]
        for e in es:
            p.insert(e)
        p.cost_limit = p.total_cost + 10_000 - 1  # the new tx (cost 10,000) forces exactly one eviction
        before = set(p.entries)
        p.insert(Entry(txid="f" * 64, auth="", raw=b"", v=4, size=1, fee=10**6, conv_fee=10_000, ins=[], outs=[],
                       nfs={}))
        for t in (before | {"f" * 64}) - set(p.entries):
            cnt[t] += 1
    # weights: 10,000 ; 10,000 + 40,000 (low fee) ; 30,000 ; new tx 10,000  -> total 100,000
    exp = {f"{0:064x}": 0.10, f"{1:064x}": 0.50, f"{2:064x}": 0.30, "f" * 64: 0.10}
    got = {k: cnt[k] / trials for k in exp}
    ok = all(abs(got[k] - exp[k]) < 0.02 for k in exp)
    check("eviction frequency follows the ZIP 401 weights (cost + 40,000 low-fee penalty)", ok,
          " ".join(f"w={exp[k]:.2f}:got={got[k]:.3f}" for k in exp))
    # rejection caches
    adm.pool = Pool()
    bad = None
    for t, r in zip(txids, raws):  # a tampered signature: the tx still parses (txid / wtxid known)
        j = rpc("getrawtransaction", t, 1)
        if j["version"] >= 5 and not j["vin"]:
            bad = bytearray(r)
            bad[-1] ^= 1  # last bundle's binding signature
            break
        if j["vin"]:
            pt = bytes.fromhex(j["vin"][0]["txid"])[::-1] + j["vin"][0]["vout"].to_bytes(4, "little")
            i = r.find(pt)
            bad = bytearray(r)
            bad[i + 36 + 10] ^= 1  # a byte inside the first scriptSig's signature
            break
    first = adm.admit([(bytes(bad), "test")])[0]
    second = adm.admit([(bytes(bad), "test")])[0]
    check("a rejected tx is rejected again from the cache (no re-validation)",
          first.status == "rejected" and not (first.reason or "").startswith("cached")
          and second.status == "rejected" and (second.reason or "").startswith("cached"),
          f"1st: {first.reason}; 2nd: {second.reason}")
    mal = bytes(bad[:-7])
    m1, m2 = adm.admit([(mal, "test")])[0], adm.admit([(mal, "test")])[0]
    check("a malformed tx is answered from the cache the second time (keyed by its bytes' hash)",
          (m2.reason or "").startswith("cached"), f"1st: {m1.reason}; 2nd: {m2.reason}")
    adm.pool.clear_tip_rejections()
    third = adm.admit([(bytes(bad), "test")])[0]
    check("after a new block (tip-scoped caches cleared) it is validated again",
          not (third.reason or "").startswith("cached"), f"3rd: {third.reason}")
    n = sum(c["ok"] for c in checks)
    print(f"\nRESULT: {n}/{len(checks)} PASS")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "eviction.json").write_text(json.dumps(checks, indent=1))


if __name__ == "__main__":
    main()
