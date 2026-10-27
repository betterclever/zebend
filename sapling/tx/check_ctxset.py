#!/usr/bin/env python3
"""Bend tx_main vs the oracle on a ctxset file (txs with full spent-output context):
txid, sighash and every per-signature RedJubjub verdict, plus the Groth16 verdict of every
proof (Bend, sapling/groth16). Usage: check_ctxset.py TXS.bin EXPECTED.txt"""
import pathlib, subprocess, sys
here = pathlib.Path(__file__).resolve().parent
HEAVY = str(here.parent.parent / "heavy.sh")
VK = here.parent / "groth16/data"
txs, exp = sys.argv[1], sys.argv[2]
recs = txs + ".recs"
out = subprocess.run([HEAVY, str(here / "tx_main"), txs, recs], capture_output=True, text=True).stdout
got = {int(l.split()[0]): l.split() for l in out.split("\n") if l and l[0].isdigit()}
rows = [l.split() for l in open(exp) if l.strip() and not l.startswith("#")]
c = dict(n=0, txid=0, sighash=0, verdicts=0, sigs=0, sigs_eq=0)
bad = []
for r in rows:
    i = int(r[0]); want_v = r[7] if len(r) > 7 else ""
    p = got.get(i)
    c["n"] += 1
    if p is None:
        bad.append(("missing", i)); continue
    v = p[10] if len(p) > 10 else ""
    c["txid"] += p[2] == r[3]
    c["sighash"] += p[3] == r[4]
    c["verdicts"] += v == want_v
    c["sigs"] += len(want_v)
    c["sigs_eq"] += sum(a == b for a, b in zip(v, want_v)) if len(v) == len(want_v) else 0
    if p[2] != r[3] or p[3] != r[4] or v != want_v:
        bad.append((i, p[2] == r[3], p[3] == r[4], v, want_v))
print(f"txs {c['n']}: txid {c['txid']}/{c['n']}, sighash {c['sighash']}/{c['n']}, all-verdicts-equal {c['verdicts']}/{c['n']}; signatures equal {c['sigs_eq']}/{c['sigs']}")
print([l for l in out.split("\n") if l.startswith("TOTAL")])
g = subprocess.run([HEAVY, str(here / "g16_raw"), str(VK / "vk_spend.bin"), str(VK / "vk_output.bin"), str(VK / "vk_sprout.bin"), recs], capture_output=True, text=True).stdout
d = next((l.split()[1] for l in g.split("\n") if l.startswith("verdicts ")), "")
print(f"Groth16 proofs (Bend): {len(d)} records, valid {d.count('1')}; {[l for l in g.split(chr(10)) if l.startswith('n ')]}")
for b in bad[:10]:
    print("  BAD", b)
