#!/usr/bin/env python3
"""NU7 rehearsal, part 1: the full node's per-tx verifier hooks on REAL post-NU7 transactions.

Mainnet has no NU7 transactions yet, and a relabelled mainnet block cannot carry signed
transactions across the activation (the ZIP 244 sighash commits to the branch id). Testnet's NU7
uses the same branch id 0x77190ad9 and the same circuits/parameters, so its real signed
transactions are the closest thing to the first mainnet NU7 blocks:
  * blocks: zcash/consensus/nu7/data/testnet/blocks.bin (P2P, links + Equihash checked in Bend),
    only heights >= 4,465,026 (Testnet NU7), where mainnet-height logic (>= 3,543,405) and
    Testnet agree on the era;
  * spent outputs: zcash/consensus/nu7/data/testnet/ctx.bin (per input: value, script; from the
    testnet lightwalletd, as fetched by zcash/consensus/nu7/testnet/fetch.py);
  * extraction: this code dir's bin/blockdelta (the node's), header compared to itself;
  * hooks: this code dir's hooks/{transparent,sapling,orchard}, exactly as rules.run_hooks
    calls them (same .tx/.ctx/.json files, same list file).
Every item must PASS. Then each PASS item is tampered (one signature/proof byte flipped, or a
spent amount changed) and must FAIL, so a PASS is not vacuous.
usage: nu7_hooks.py CODE_DIR [--max-blocks N] [--tamper N]
"""
import argparse, json, os, random, re, struct, subprocess, sys
from collections import Counter
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("code")
ap.add_argument("--max-blocks", type=int, default=400)
ap.add_argument("--tamper", type=int, default=40)
ap.add_argument("--from-height", type=int, default=4465026)
a = ap.parse_args()
CODE = Path(a.code).resolve()
sys.path.insert(0, str(CODE))
import rules, sync  # noqa: E402

TN = Path("/Users/betterclever/projects/zecathon/zebend/zcash/consensus/nu7/data/testnet")
OUT = Path(__file__).resolve().parent.parent / "work" / "nu7_hooks"
OUT.mkdir(parents=True, exist_ok=True)
HDR = 1487


def records():
    b, c = (TN / "blocks.bin").read_bytes(), (TN / "ctx.bin").read_bytes()
    i = j = 0
    while i < len(b):
        h = struct.unpack_from("<I", b, i)[0]
        L = struct.unpack_from("<I", b, i + 4 + HDR)[0]
        raw = b[i + 8 + HDR:i + 8 + HDR + L]
        i += 8 + HDR + L
        cl = struct.unpack_from("<I", c, j)[0]
        crec = c[j + 4:j + 4 + cl]
        j += 4 + cl
        yield h, raw, crec


def spent_of(crec):
    h, nt = struct.unpack_from("<II", crec, 0)
    k = 8 + 4 * nt
    out = []
    while k < len(crec):
        lo, hi, ph, cb, sl = struct.unpack_from("<IIIII", crec, k)
        k += 20
        out.append((lo | hi << 32, crec[k:k + sl]))
        k += sl
    return out


recs = [r for r in records() if r[0] >= a.from_height][: a.max_blocks]
wf = OUT / "win.bin"
with open(wf, "wb") as f:
    for h, raw, _ in recs:
        f.write(struct.pack("<I", h) + raw[:HDR] + struct.pack("<I", len(raw)) + raw)
r = subprocess.run([str(CODE / "bin/blockdelta"), str(wf)], capture_output=True, text=True, timeout=1800)
blocks = sync.parse_delta(r.stdout)
assert [b["height"] for b in blocks] == [h for h, _, _ in recs], "blockdelta did not return every block"
inv = [b["height"] for b in blocks if "invalid" in b]
print(f"blocks {recs[0][0]}..{recs[-1][0]}: {len(blocks)} parsed by blockdelta, {len(inv)} INVALID {inv[:5]}")
by_h = {h: (raw, crec) for h, raw, crec in recs}
stats = Counter()
for b in blocks:
    for t in b["txs"]:
        stats[f"v{t['v']} br={t['br']}"] += 1
print("tx versions/branches:", dict(stats))

jobs = rules.hook_jobs([b for b in blocks if "invalid" not in b])
items = {}  # (name, h, i) -> base path
for name, its in jobs.items():
    d = OUT / name
    d.mkdir(exist_ok=True)
    for p in d.glob("*"):
        p.unlink()
    for h, i in its:
        b = next(x for x in blocks if x["height"] == h)
        raw, crec = by_h[h]
        txs = rules.tx_slices(raw, [t["size"] for t in b["txs"]])
        sp = spent_of(crec)
        k = sum(len(t["ins"]) for t in b["txs"][:i] if not t["cb"])
        t = b["txs"][i]
        mine = sp[k:k + len(t["ins"])]
        assert len(mine) == len(t["ins"])
        base = d / f"{h}_{i}"
        base.with_suffix(".tx").write_bytes(txs[i])
        base.with_suffix(".ctx").write_bytes(rules.follow_ctx(mine))
        base.with_suffix(".json").write_text(json.dumps({"height": h, "txidx": i, "txid": t["txid"], "version": t["v"],
                                                         "branch_id": t["br"]}))
        items[(name, h, i)] = base


def run_hook(name, bases, tag):
    lst = OUT / name / f"list_{tag}.txt"
    lst.write_text("\n".join(map(str, bases)) + "\n")
    r = subprocess.run([str(CODE / "hooks" / name), str(lst)], capture_output=True, text=True, timeout=3600)
    got = {(int(x), int(y)): (v, rest) for x, y, v, rest in
           re.findall(r"^verdict (\d+) (\d+) (PASS|FAIL|SKIPPED) ?(.*)$", r.stdout, re.M)}
    return got, r


ok_all = True
passed = {}
for name in ("transparent", "sapling", "orchard"):
    bases = [v for k, v in items.items() if k[0] == name]
    if not bases:
        print(f"{name}: no items")
        continue
    got, r = run_hook(name, bases, "real")
    c = Counter(v[0] for v in got.values())
    miss = len(bases) - len(got)
    bad = [(k, v) for k, v in got.items() if v[0] != "PASS"]
    print(f"{name}: {len(bases)} real NU7 tx: {dict(c)}, missing {miss}" + (f"; e.g. {bad[:3]}" if bad else ""))
    ok_all &= not bad and not miss
    passed[name] = [b for b in bases if got.get(tuple(map(int, b.name.split("_"))), ("",))[0] == "PASS"]

# tamper: a PASS must not be vacuous
rnd = random.Random(7)
for name, bases in passed.items():
    sample = rnd.sample(bases, min(a.tamper, len(bases)))
    tb = []
    for b in sample:
        tx = bytearray(b.with_suffix(".tx").read_bytes())
        ctx = b.with_suffix(".ctx").read_bytes()
        nb = b.with_name(b.name + "_t")
        if name == "transparent":
            # change the first spent amount by 1 zat: every v5 sighash commits to all amounts
            amt = struct.unpack_from("<q", ctx, 4)[0]
            ctx = ctx[:4] + struct.pack("<q", amt + 1) + ctx[12:]
        else:
            # flip one byte in the last 25% of the tx (proofs / signatures live there)
            pos = rnd.randrange(len(tx) * 3 // 4, len(tx))
            tx[pos] ^= 0x01
        nb.with_suffix(".tx").write_bytes(bytes(tx))
        nb.with_suffix(".ctx").write_bytes(ctx)
        nb.with_suffix(".json").write_text(b.with_suffix(".json").read_text())
        tb.append(nb)
    got, r = run_hook(name, tb, "tamper")
    c = Counter(v[0] for v in got.values())
    why = Counter(" ".join(v[1].split()[:2]) for v in got.values() if v[0] == "FAIL")
    print(f"{name}: {len(tb)} tampered copies: {dict(c)} (every one must FAIL); reasons {dict(why)}")
    ok_all &= c.get("FAIL", 0) == len(tb)
print("RESULT", "PASS" if ok_all else "FAIL")
