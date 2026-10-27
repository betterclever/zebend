#!/usr/bin/env python3
"""Test bin/rules on real mainnet blocks and on tampered copies.

usage: test_rules.py [--tamper] [H ...]     (default: every block in ../bend/data)

Spent outputs come from the real chain: lightwalletd GetTransaction (node/follow/bin/follow-lwd
rawtx), parsed here for value/script (TEST DATA path only; the node takes them from its UTXO
store). Each block is its own window (the sample is not contiguous), so value pools are not
known and the turnstile is reported SKIPPED by rules.validate; the tamper test for the
turnstile gives bin/rules explicit pools instead.
"""
import json, re, struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
FN = HERE.parent
sys.path.insert(0, str(FN))
import headers, rules, sync

DATA = FN / "bend/data"
LWD = FN.parent / "node/follow/bin/follow-lwd"
CACHE = HERE / "data/prevtx.json"


def cs(b, i):
    x = b[i]
    if x < 0xfd:
        return x, i + 1
    if x == 0xfd:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    return struct.unpack_from("<I", b, i + 1)[0], i + 5


def tx_info(raw):
    """(is_coinbase, [(value, script)]) of a raw tx (test data only)."""
    ver = struct.unpack_from("<I", raw, 0)[0] & 0x7fffffff
    i = 4 if ver <= 2 else 8 if ver <= 4 else 20
    nin, i = cs(raw, i)
    cb = nin == 1 and raw[i:i + 32] == bytes(32) and raw[i + 32:i + 36] == b"\xff" * 4
    for _ in range(nin):
        i += 36
        sl, i = cs(raw, i)
        i += sl + 4
    nout, i = cs(raw, i)
    outs = []
    for _ in range(nout):
        v = struct.unpack_from("<q", raw, i)[0]
        sl, j = cs(raw, i + 8)
        outs.append((v, raw[j:j + sl]))
        i = j + sl
    return cb, outs


class TestStore:
    """The parts of store.Store that rules.validate uses, backed by the real chain."""

    def __init__(self):
        self.cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}

    def fetch(self, txids):
        need = sorted({t for t in txids if t not in self.cache})
        for k in range(0, len(need), 200):
            rev = lambda x: bytes.fromhex(x)[::-1].hex()  # follow-lwd takes internal byte order
            out = subprocess.run([str(LWD), "rawtx", *map(rev, need[k:k + 200])], capture_output=True, text=True).stdout
            for m in re.finditer(r"^rawtx ([0-9a-f]{64}) height (\d+) hex ([0-9a-f]+)$", out, re.M):
                self.cache[rev(m.group(1))] = [int(m.group(2)), m.group(3)]
        CACHE.parent.mkdir(exist_ok=True)
        CACHE.write_text(json.dumps(self.cache))

    def utxo(self, txid, vout):
        if txid not in self.cache:
            return None
        h, hx = self.cache[txid]
        cb, outs = tx_info(bytes.fromhex(hx))
        v, s = outs[vout]
        return (v, s, h, int(cb))

    def get(self, k, default=None):
        return default


def delta(raw_by_h):
    w = HERE / "data/w.bin"
    w.parent.mkdir(exist_ok=True)
    sync.window_file(w, sorted(raw_by_h.items()))
    out = subprocess.run([str(FN / "bin/blockdelta"), str(w)], capture_output=True, text=True).stdout
    return sync.parse_delta(out)


def check_block(st, h, raw, log=lambda *a: None):
    blocks = delta({h: raw})
    st.fetch([p for t in blocks[0]["txs"] for (p, _, _) in t["ins"]])
    t = time.time()
    res = rules.run_rules(blocks, st, {h: raw}, {}, tag=str(h))
    return blocks, res[h], time.time() - t


def main():
    hs = [int(a) for a in sys.argv[1:] if a.isdigit()] or sorted(int(p.stem) for p in DATA.glob("*.bin"))
    st = TestStore()
    ok = bad = 0
    tot = 0.0
    for h in hs:
        raw = (DATA / f"{h}.bin").read_bytes()
        blocks, r, secs = check_block(st, h, raw)
        tot += secs
        fs = [f for f in r.get("fails", []) if not f.startswith("turnstile_")]
        ntx = len(blocks[0]["txs"])
        nin = sum(len(t["ins"]) for t in blocks[0]["txs"])
        if r["verdict"] == "VALID" or not fs:
            ok += 1
            print(f"{h:>8}  txs {ntx:>4} inputs {nin:>5}  fees {r['fees']:>12}  sigops {r['sigops']:>5}  "
                  f"all rules PASS (turnstile skipped: no pools)  {secs * 1000:.0f} ms")
        else:
            bad += 1
            print(f"{h:>8}  FAIL {fs}")
    print(f"real blocks: {ok}/{len(hs)} pass every rule; bin/rules {tot:.2f} s total")


if __name__ == "__main__":
    main()
