#!/usr/bin/env python3
"""Item 5: our RPC (rpc.py, read-only queries) vs a public reference (Blockchair's zcashd-format
raw API), at the tip and at a few chosen heights; getaddressutxos/getaddressbalance for busy
transparent addresses. Prints every field that differs; a field we do not serve is listed as
MISSING (not as a match).
usage: rpc_spotcheck.py [--port 18233]"""
import argparse, json, time, urllib.request
from collections import Counter

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=18233)
ap.add_argument("--heights", default="")
a = ap.parse_args()


def rpc(method, *params):
    req = urllib.request.Request(f"http://127.0.0.1:{a.port}/", json.dumps({"jsonrpc": "1.0", "id": 1, "method": method,
                                                                            "params": list(params)}).encode(),
                                 {"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=120))
    if d.get("error"):
        raise RuntimeError(f"{method}{params}: {d['error']}")
    return d["result"]


def bc(path):
    for _ in range(4):
        try:
            d = json.load(urllib.request.urlopen(f"https://api.blockchair.com/zcash/{path}", timeout=60))
            time.sleep(2.5)  # stay under the free rate limit
            return d["data"]
        except OSError as e:
            err = e
            time.sleep(10)
    raise err


diffs = Counter()
report = []


def cmp(where, ours, ref, fields):
    for f in fields:
        if f not in ref:
            continue
        if f not in ours:
            diffs[f"MISSING {f}"] += 1
            report.append(f"{where}: {f} MISSING in ours (ref {str(ref[f])[:80]})")
        elif ours[f] != ref[f]:
            diffs[f"DIFF {f}"] += 1
            report.append(f"{where}: {f} ours {str(ours[f])[:90]} != ref {str(ref[f])[:90]}")


tip = rpc("getblockcount")
heights = [int(x) for x in a.heights.split(",") if x] or [tip - 3, tip - 30, 3532500, 3530569, 3522890, 3522461]
FIELDS = ["hash", "size", "height", "version", "merkleroot", "blockcommitments", "authdataroot", "finalsaplingroot",
          "finalorchardroot", "finalironwoodroot", "chainhistoryroot", "time", "nonce", "solution", "bits", "difficulty",
          "chainwork", "anchor", "previousblockhash", "nextblockhash", "tx", "trees", "chainSupply", "valuePools"]
for h in heights:
    ref = bc(f"raw/block/{h}")[str(h)]["decoded_raw_block"]
    ours = rpc("getblock", str(h), 1)
    ref.pop("confirmations", None)
    cmp(f"getblock {h}", ours, ref, FIELDS)
    extra = sorted(set(ref) - set(ours) - {"confirmations"})
    if extra:
        report.append(f"getblock {h}: reference fields we do not return: {extra}")
    raw_ref = bc(f"raw/block/{h}")[str(h)]["raw_block"]
    raw_ours = rpc("getblock", str(h), 0)
    if raw_ours != raw_ref:
        diffs["DIFF getblock verbosity 0"] += 1
        report.append(f"getblock {h} 0: raw bytes differ")
    for txid in ref["tx"][:2] + ref["tx"][-1:]:
        rt = bc(f"raw/transaction/{txid}")[txid]
        ot = rpc("getrawtransaction", txid, 1)
        if ot.get("hex") != rt["raw_transaction"]:
            diffs["DIFF getrawtransaction hex"] += 1
            report.append(f"getrawtransaction {txid}: hex differs")
        dref = rt["decoded_raw_transaction"]
        cmp(f"getrawtransaction {txid[:12]}", ot, dref,
            ["txid", "authdigest", "size", "overwintered", "version", "versiongroupid", "locktime", "expiryheight",
             "vin", "vout", "valueBalance", "valueBalanceZat", "vShieldedSpend", "vShieldedOutput", "orchard", "ironwood",
             "blockhash", "height", "confirmations", "time", "blocktime"])

# chain-level
ci = rpc("getblockchaininfo")
ref_tip = bc(f"raw/block/{ci['blocks']}")[str(ci["blocks"])]["decoded_raw_block"]
ours_pools = {p["id"]: p.get("chainValueZat") for p in ci.get("valuePools", [])}
ref_pools = {p["id"]: p.get("chainValueZat") for p in ref_tip.get("valuePools", [])}
for k in sorted(set(ours_pools) | set(ref_pools)):
    if ours_pools.get(k) != ref_pools.get(k):
        diffs[f"DIFF valuePool {k}"] += 1
        report.append(f"getblockchaininfo valuePools {k}: ours {ours_pools.get(k)} ref (block {ci['blocks']}) {ref_pools.get(k)}")
for f in ("chainwork", "estimatedheight", "headers"):
    report.append(f"getblockchaininfo {f}: ours {ci.get(f)}" + (f", ref chainwork {ref_tip.get('chainwork')}" if f == "chainwork" else ""))
try:
    ts = rpc("z_gettreestate", str(ci["blocks"]))
    report.append(f"z_gettreestate: {str(ts)[:200]}")
except Exception as e:
    report.append(f"z_gettreestate: {e}")

# busy transparent addresses: the most frequent output addresses of the last 20 blocks (ours)
addrs = Counter()
for h in range(tip - 20, tip + 1):
    b = rpc("getblock", str(h), 2)
    for t in b["tx"]:
        for o in t.get("vout", []):
            for ad in o.get("scriptPubKey", {}).get("addresses", []) or []:
                addrs[ad] += 1
for ad, n in addrs.most_common(4):
    ours_u = rpc("getaddressutxos", {"addresses": [ad]})
    ours_b = rpc("getaddressbalance", {"addresses": [ad]})
    ref = bc(f"dashboards/address/{ad}?limit=100,100")[ad]
    rb = ref["address"]["balance"]
    ref_utxo = {(u["transaction_hash"], u["index"]) for u in ref.get("utxo", [])}
    our_utxo = {(u["txid"], u["outputIndex"]) for u in ours_u}
    n_ref = ref["address"].get("unspent_output_count")
    ok_bal = ours_b.get("balance") == rb
    report.append(f"address {ad} ({n} outputs in the last 20 blocks): balance ours {ours_b.get('balance')} ref {rb} "
                  f"{'MATCH' if ok_bal else 'DIFF'}; utxos ours {len(our_utxo)} ref {n_ref} (ref list shows "
                  f"{len(ref_utxo)}): ref-listed missing in ours {len(ref_utxo - our_utxo)}")
    if not ok_bal:
        diffs["DIFF address balance"] += 1
print("\n".join(report))
print("\nSUMMARY", dict(diffs) or "no differences")
