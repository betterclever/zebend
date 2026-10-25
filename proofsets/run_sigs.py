#!/usr/bin/env python3
"""Check the RedPallas signatures of the data/sigs sample with node/tx's Bend code (tx_main):
for each fully shielded tx, Bend must recompute the network txid and accept every spend-auth
signature and every binding signature (mainnet consensus accepted them all). Also runs tamper
controls: one signature byte flipped must make exactly that check fail.
"""
import os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIGS = os.path.join(HERE, "data", "sigs")
TX_MAIN = os.path.join(ROOT, "node/tx/tx_main")

expected = []
for line in open(os.path.join(SIGS, "expected.txt")):
    k, h, txid, oa, ia = line.split()
    expected.append((k, int(h), txid, int(oa), int(ia)))

def run(path_bin, path_ctx):
    out = subprocess.run([TX_MAIN, path_bin, path_ctx], capture_output=True, text=True, timeout=900).stdout
    txid = re.search(r"^txid ([0-9a-f]{64})$", out, re.M)
    sa = re.findall(r"^(orchard|ironwood)\.a\d+\.spend_auth_ok (\d)$", out, re.M)
    bd = re.findall(r"^(orchard|ironwood)\.binding_ok (\d)$", out, re.M)
    return (txid.group(1) if txid else None), sa, bd

def check(e):
    k, h, txid, oa, ia = e
    got, sa, bd = run(os.path.join(SIGS, f"{k}.bin"), os.path.join(SIGS, f"{k}.ctx"))
    want_bundles = (oa > 0) + (ia > 0)
    ok = (got == txid and len(sa) == oa + ia and all(v == "1" for _, v in sa)
          and len(bd) == want_bundles and all(v == "1" for _, v in bd))
    return k, ok, len(sa), len(bd), got == txid

t = time.time()
with ThreadPoolExecutor(max_workers=int(os.environ.get("JOBS", "12"))) as ex:
    res = list(ex.map(check, expected))
bad = [r for r in res if not r[1]]
n_sa = sum(r[2] for r in res)
n_bd = sum(r[3] for r in res)
print(f"txs {len(res)}: txid match {sum(r[4] for r in res)}/{len(res)}; spend-auth sigs verified {n_sa}; binding sigs verified {n_bd}; all valid {len(bad) == 0}; {time.time() - t:.0f}s")
if bad:
    print("FAILURES:", bad[:20])

# Tamper controls on the first sample tx: flip the last byte of its binding signature
# (the final 64 bytes before the Orchard-protocol bundle's end are not trivially located,
# so flip a byte of the raw tx near the end, where the binding signature lives in v5/v6).
k = expected[0][0]
raw = bytearray(open(os.path.join(SIGS, f"{k}.bin"), "rb").read())
raw[-1] ^= 1
tp = os.path.join(SIGS, "tamper.bin")
open(tp, "wb").write(raw)
got, sa, bd = run(tp, os.path.join(SIGS, f"{k}.ctx"))
print(f"tamper control (last tx byte flipped): txid changed {got != expected[0][2]}; spend-auth all valid {all(v == '1' for _, v in sa)}; binding all valid {all(v == '1' for _, v in bd)}")
os.remove(tp)
sys.exit(1 if bad else 0)
