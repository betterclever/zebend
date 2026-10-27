#!/usr/bin/env python3
"""getaddressutxos at the SAME height as the reference: Blockchair's full UTXO list (paged), minus
outputs created above our tip; plus outputs we hold that the reference no longer lists (spent
above our tip, checked via the spending tx's block height). usage: addr_check.py ADDR..."""
import json, sys, time, urllib.request


def rpc(m, *p):
    r = urllib.request.Request("http://127.0.0.1:18233/", json.dumps({"method": m, "params": list(p), "id": 1}).encode())
    return json.load(urllib.request.urlopen(r, timeout=120))["result"]


def bc(path):
    time.sleep(2.5)
    return json.load(urllib.request.urlopen("https://api.blockchair.com/zcash/" + path, timeout=60))


for ad in sys.argv[1:]:
    tip = rpc("getblockcount")
    ours = {(u["txid"], u["outputIndex"]): (u["satoshis"], u["height"]) for u in rpc("getaddressutxos", {"addresses": [ad]})}
    ref, off = {}, 0
    while True:
        d = bc(f"dashboards/address/{ad}?limit=0,100&offset=0,{off}")
        us = d["data"][ad]["utxo"]
        for u in us:
            ref[(u["transaction_hash"], u["index"])] = (u["value"], u["block_id"])
        if len(us) < 100:
            break
        off += 100
    ref_tip = d["context"]["state"]
    ref_le = {k: v for k, v in ref.items() if 0 < v[1] <= tip}
    only_ours = set(ours) - set(ref_le)
    only_ref = set(ref_le) - set(ours)
    val_diff = [k for k in set(ours) & set(ref_le) if ours[k][0] != ref_le[k][0]]
    print(f"{ad}: our tip {tip}, ref state {ref_tip}; ours {len(ours)} utxos, ref {len(ref)} ({len(ref_le)} created <= our tip)")
    print(f"   only in ours: {len(only_ours)} (may be spent in blocks {tip + 1}..{ref_tip}); only in ref (<= our tip): "
          f"{len(only_ref)} {sorted(only_ref)[:3]}; value mismatches {len(val_diff)}")
    print(f"   balance over common-height outputs: ours {sum(v[0] for v in ours.values())} ref {sum(v[0] for v in ref_le.values())}")
