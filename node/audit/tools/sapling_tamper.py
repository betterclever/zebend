#!/usr/bin/env python3
"""Targeted tamper test of the sapling hook on real Testnet NU7 v5/v6 transactions with Sapling.

nu7_hooks.py flips a random byte in the last quarter of a tx; for a tx that also has an
Orchard/Ironwood bundle that byte is often in the Orchard part (not the sapling hook's job), so a
PASS there proves nothing. Here the Sapling part of the ZIP 225 layout is located and a byte is
flipped in: (a) a spend proof, (b) a spend-auth signature, (c) an output proof, (d) the binding
signature, (e) an output's encCiphertext (sighash-covered, not the txid... v5 txid covers it:
expected FAIL by txid), (f) valueBalance. Every tampered copy must FAIL.
usage: sapling_tamper.py CODE_DIR
"""
import json, re, struct, subprocess, sys
from collections import Counter
from pathlib import Path

CODE = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(CODE))
import rules, sync  # noqa

TN = Path("/Users/betterclever/projects/zecathon/zebend/zcash/consensus/nu7/data/testnet")
OUT = Path(__file__).resolve().parent.parent / "work" / "sapling_tamper"
OUT.mkdir(parents=True, exist_ok=True)
HDR = 1487
sys.path.insert(0, str(Path(__file__).resolve().parent))
from nu7_common import records, spent_of  # noqa


def cs(b, i):
    k = b[i]
    if k < 253:
        return k, i + 1
    if k == 253:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    return struct.unpack_from("<I", b, i + 1)[0], i + 5


def sapling_regions(tx):
    """Offsets of the Sapling fields of a v5/v6 tx (ZIP 225 layout; v6 keeps it before Orchard)."""
    i = 20
    n, i = cs(tx, i)
    for _ in range(n):
        i += 36
        l, i = cs(tx, i)
        i += l + 4
    n, i = cs(tx, i)
    for _ in range(n):
        i += 8
        l, i = cs(tx, i)
        i += l
    ns, i = cs(tx, i)
    sp = i
    i += 96 * ns
    no, i = cs(tx, i)
    op = i
    i += 756 * no
    r = {}
    if ns + no:
        r["valueBalance"] = i
        i += 8
    if ns:
        r["anchor"] = i
        i += 32
    if ns:
        r["spend proof"] = i
        i += 192 * ns
        r["spend-auth sig"] = i
        i += 64 * ns
    if no:
        r["output proof"] = i
        i += 192 * no
        r["output encCiphertext"] = op + 96
    if ns + no:
        r["binding sig"] = i
        i += 64
    if ns:
        r["spend rk"] = sp + 64
    return r


items = []
for chunk_from in range(4465026, 4542676, 1500):
    recs = [r for r in records(TN, chunk_from, chunk_from + 1500)]
    if not recs:
        continue
    wf = OUT / "win.bin"
    with open(wf, "wb") as f:
        for h, raw, _ in recs:
            f.write(struct.pack("<I", h) + raw[:HDR] + struct.pack("<I", len(raw)) + raw)
    out = subprocess.run([str(CODE / "bin/blockdelta"), str(wf)], capture_output=True, text=True, timeout=1800).stdout
    by_h = {h: (raw, crec) for h, raw, crec in recs}
    for b in sync.parse_delta(out):
        if "invalid" in b:
            continue
        for t in b["txs"]:
            if t["sap"] and t["v"] in (5, 6):
                raw, crec = by_h[b["height"]]
                txs = rules.tx_slices(raw, [x["size"] for x in b["txs"]])
                sp = spent_of(crec)
                k = sum(len(x["ins"]) for x in b["txs"][:t["i"]] if not x["cb"])
                items.append((b["height"], t["i"], t, txs[t["i"]], sp[k:k + len(t["ins"])]))
print(f"{len(items)} real Testnet NU7 txs with Sapling bundles")

bases, expect = [], {}
d = OUT / "items"
d.mkdir(exist_ok=True)
for p in d.glob("*"):
    p.unlink()
n = 0
for h, i, t, tx, spent in items:
    regs = sapling_regions(tx)
    variants = [("orig", None)] + [(k, off + 3) for k, off in regs.items()]
    for k, off in variants:
        b = bytearray(tx)
        if off is not None:
            if off >= len(b):
                continue
            b[off] ^= 0x04
        base = d / f"{n}"
        base.with_suffix(".tx").write_bytes(bytes(b))
        base.with_suffix(".ctx").write_bytes(rules.follow_ctx(spent))
        base.with_suffix(".json").write_text(json.dumps({"height": 4000000 + n, "txidx": 0, "txid": t["txid"],
                                                         "version": t["v"], "branch_id": t["br"]}))
        expect[4000000 + n] = (k, h, i, t["v"], t["sap"])
        bases.append(base)
        n += 1
lst = OUT / "list.txt"
lst.write_text("\n".join(map(str, bases)) + "\n")
r = subprocess.run([str(CODE / "hooks/sapling"), str(lst)], capture_output=True, text=True, timeout=3600)
got = {int(x): (v, rest) for x, _, v, rest in re.findall(r"^verdict (\d+) (\d+) (PASS|FAIL|SKIPPED) ?(.*)$", r.stdout, re.M)}
res = Counter()
bad = []
for key, (k, h, i, v, sap) in expect.items():
    verdict = got.get(key, ("MISSING", ""))
    want = "PASS" if k == "orig" else "FAIL"
    res[(k, verdict[0])] += 1
    if verdict[0] != want:
        bad.append((k, h, i, v, sap, verdict))
for k, c in sorted(res.items()):
    print(f"  {k[0]:22} {k[1]:8} {c}")
print("unexpected:", bad[:10])
print("RESULT", "PASS" if not bad else "FAIL")
