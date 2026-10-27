#!/usr/bin/env python3
"""For each UTXO the reference lists (created <= our tip) that we do not hold: is it spent per the
reference itself, or is its block not on the checkpointed chain (reference block hash/coinbase
differs from ours)? usage: addr_explain.py ADDR..."""
import json, sqlite3, sys, time, urllib.request
ST = "/Users/betterclever/projects/zecathon/bend-zcash/fullnode/state/chain.sqlite"


def rpc(m, *p):
    r = urllib.request.Request("http://127.0.0.1:18233/", json.dumps({"method": m, "params": list(p), "id": 1}).encode())
    return json.load(urllib.request.urlopen(r, timeout=120))["result"]


def bc(path):
    time.sleep(2.2)
    return json.load(urllib.request.urlopen("https://api.blockchair.com/zcash/" + path, timeout=60))


db = sqlite3.connect(f"file:{ST}?mode=ro", uri=True)
for ad in sys.argv[1:]:
    tip = rpc("getblockcount")
    ours = {(u["txid"], u["outputIndex"]) for u in rpc("getaddressutxos", {"addresses": [ad]})}
    ref, off = {}, 0
    while True:
        us = bc(f"dashboards/address/{ad}?limit=0,100&offset=0,{off}")["data"][ad]["utxo"]
        ref.update({(u["transaction_hash"], u["index"]): u["block_id"] for u in us})
        if len(us) < 100:
            break
        off += 100
    miss = [k for k, b in ref.items() if 0 < b <= tip and k not in ours]
    why = {}
    for tx, n in miss:
        t = bc(f"dashboards/transaction/{tx}")["data"][tx]
        o = [x for x in t["outputs"] if x["index"] == n][0]
        ours_tx = db.execute("SELECT height FROM tx WHERE txid=?", (bytes.fromhex(tx)[::-1],)).fetchone()
        bid = t["transaction"]["block_id"]
        if o.get("is_spent"):
            w = "reference itself says spent (stale UTXO list)"
        elif ours_tx is None:
            ob = rpc("getblock", str(bid), 1)
            w = f"tx not on our (checkpointed) chain: ref block {bid}, our block {ob['hash'][:16]} coinbase {ob['tx'][0][:12]}"
            w = "tx not on the checkpointed chain (reference indexes an orphan block)"
        else:
            w = f"UNEXPLAINED: we know tx at height {ours_tx[0]}, output unspent per reference"
        why.setdefault(w, []).append(f"{tx[:12]}:{n}@{bid}")
    print(f"{ad}: our tip {tip}; reference-listed utxos <= tip missing in ours: {len(miss)}")
    for w, l in why.items():
        print(f"   {len(l):3}  {w}  e.g. {l[:3]}")
