#!/usr/bin/env python3
"""Real-chain test of the Sprout-capable sapling hook (consensus/gaps/sprout/hook.py).

usage: test_hook.py OUTDIR [MAX]
Items: every v4 transaction with Sprout JoinSplits in sapling/data/sig_raw.bin (real mainnet
txs, 419,200..3.5M) plus those in the tip-era blocks in ../data/blocks/*.hex (3,522,155..3,523,680).
For each real tx three tampered copies (no txid in P.json, so the stage that rejects is visible):
  sig   flip a bit of joinSplitSig's S half      -> FAIL joinsplitsig
  proof flip a bit of the first JoinSplit's proof (A's x) -> FAIL groth16 (decode or pairing)
  pk    flip a bit of joinSplitPubKey            -> FAIL (sighash/h_sig change: ed25519 and proof)
Python here only locates byte offsets to tamper and selects txs (verdicts are the hook's)."""
import json, pathlib, struct, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
MAX = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9


def cs(b, i):
    x = b[i]
    if x < 0xfd: return x, i + 1
    if x == 0xfd: return struct.unpack_from('<H', b, i + 1)[0], i + 3
    if x == 0xfe: return struct.unpack_from('<I', b, i + 1)[0], i + 5
    return struct.unpack_from('<Q', b, i + 1)[0], i + 9


def v4_js(b):
    """(nj, jp, ns, no, end) for a v4 tx."""
    i = 8
    n, i = cs(b, i)
    for _ in range(n):
        i += 36; l, i = cs(b, i); i += l + 4
    n, i = cs(b, i)
    for _ in range(n):
        i += 8; l, i = cs(b, i); i += l
    i += 8 + 8
    ns, i = cs(b, i); i += 384 * ns
    no, i = cs(b, i); i += 948 * no
    nj, i = cs(b, i)
    jp = i
    end = jp + 1698 * nj + (96 if nj else 0) + (64 if ns + no else 0)
    return nj, jp, ns, no, end


def tx_len(b, i):
    """length of the tx at offset i of a block (v4 only parsed; v5/v6 via their sizes is not
    needed: we stop at the first v5 tx after which only... ) -> parse generically below."""
    raise NotImplementedError


items = []  # (height, txid_display or None, bytes, tag)
with open(ROOT / "sapling/data/sig_raw.bin", "rb") as f:
    while True:
        hdr = f.read(40)
        if len(hdr) < 40: break
        h, = struct.unpack_from("<I", hdr, 0); txid = hdr[4:36]; n, = struct.unpack_from("<I", hdr, 36)
        b = f.read(n)
        if b[:4] == b"\x04\x00\x00\x80" and v4_js(b)[0] > 0:
            items.append((h, txid[::-1].hex(), b, "real"))
# tip-era blocks: transactions sliced with blockdelta's sizes (bin/blockdelta, Bend)
blk = HERE.parent / "data/blocks"
win = HERE.parent / "work/tip_js_win.bin"
recs = []
for p in sorted(blk.glob("*.hex")):
    raw = bytes.fromhex(p.read_text().strip()); h = int(p.stem)
    recs.append((h, raw))
with open(win, "wb") as f:
    for h, raw in recs:
        f.write(struct.pack("<I", h) + raw[:1487] + struct.pack("<I", len(raw)) + raw)
out = subprocess.run([str(ROOT / "fullnode/bin/blockdelta"), str(win)], capture_output=True, text=True).stdout
sys.path.insert(0, str(ROOT / "fullnode"))
import sync, rules  # read-only imports: parse_delta / tx_slices
blocks = sync.parse_delta(out)
rawby = dict(recs)
for b in blocks:
    txs = rules.tx_slices(rawby[b["height"]], [t["size"] for t in b["txs"]])
    for t in b["txs"]:
        if t["js"]:
            items.append((b["height"], t["txid"], txs[t["i"]], "tip"))
items = items[:MAX]
lst, expect = [], {}
k = 0
def put(h, txid, tx, kind):
    global k
    P = OUT / f"{h}_{k}"
    P.with_suffix(".tx").write_bytes(tx); P.with_suffix(".ctx").write_bytes(struct.pack("<II", 0, 0))
    meta = {"height": h, "txidx": k, "version": 4}
    if txid: meta["txid"] = txid
    P.with_suffix(".json").write_text(json.dumps(meta))
    lst.append(str(P)); expect[(h, k)] = kind; k += 1
for h, txid, tx, src in items:
    put(h, txid, tx, "PASS:" + src)
    nj, jp, ns, no, end = v4_js(tx)
    kp = jp + 1698 * nj
    t = bytearray(tx); t[kp + 32 + 40] ^= 0x01; put(h, None, bytes(t), "FAIL:sig")
    t = bytearray(tx); t[jp + 304 + 5] ^= 0x10; put(h, None, bytes(t), "FAIL:proof")
    t = bytearray(tx); t[kp + 3] ^= 0x04; put(h, None, bytes(t), "FAIL:pk")
(OUT / "list.txt").write_text("\n".join(lst) + "\n")
import os
r = subprocess.run([sys.executable, str(HERE / "hook.py"), str(OUT / "list.txt")], capture_output=True, text=True, env=dict(os.environ, HOOK_DEBUG="1"))
got = {}
for l in r.stdout.splitlines():
    f = l.split()
    if f and f[0] == "verdict":
        got[(int(f[1]), int(f[2]))] = " ".join(f[3:])
from collections import Counter
c = Counter(); bad = []
for key, kind in expect.items():
    v = got.get(key, "MISSING")
    exp, what = kind.split(":")
    ok = v.startswith(exp)
    if ok and exp == "FAIL":
        ok = {"sig": "joinsplitsig", "proof": "", "pk": ""}[what] in v  # a proof tamper also breaks the binding sig and joinSplitSig (the sighash covers JoinSplits): its own digit is checked in the stage lines
    c[(kind, ok, v.split()[1] if v.startswith("FAIL") and len(v.split()) > 1 else v.split()[0])] += 1
    if not ok: bad.append((key, kind, v))
print(f"{len(items)} real txs with JoinSplits ({sum(1 for i in items if i[3]=='real')} from sapling/data/sig_raw.bin, "
      f"{sum(1 for i in items if i[3]=='tip')} from tip blocks), {sum(v4_js(i[2])[0] for i in items)} JoinSplits; {len(expect)} items")
for key in sorted(c): print("  ", key, c[key])
print("unexpected:", len(bad), bad[:5])
# per-stage: every real JoinSplit proof must be 1; the tampered JoinSplit proof must be 0 or 2
dbg = {}
for l in r.stdout.splitlines():
    f = l.split()
    if f and f[0] == "debug":
        dbg[(int(f[1]), int(f[2]))] = dict(x.split("=") for x in f[3:])
st = Counter()
for key, kind in expect.items():
    d = dbg.get(key)
    if d is None: st[(kind, "no-debug")] += 1; continue
    ns, no, nj = int(d["ns"]), int(d["no"]), int(d["nj"])
    js = d["groth16"][ns + no:]
    if kind.startswith("PASS"):
        st[(kind, "js proofs all 1" if js == "1" * nj else "js proofs " + js)] += 1
        st[(kind, "jsig " + d["jsig"])] += 1
    elif kind == "FAIL:proof":
        st[(kind, "tampered js proof " + js[:1] + (" rest ok" if js[1:] == "1" * (nj - 1) else " rest " + js[1:]))] += 1
    elif kind == "FAIL:sig":
        st[(kind, "jsig " + d["jsig"] + (", proofs ok" if js == "1" * nj else ", proofs " + js))] += 1
    else:
        st[(kind, "jsig " + d["jsig"] + ", js proofs " + ("all 1" if js == "1" * nj else "not all 1"))] += 1
for key in sorted(st): print("  stage", key, st[key])
if r.stderr.strip(): print("stderr:", r.stderr[-500:])
