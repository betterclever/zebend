#!/usr/bin/env python3
"""Verifier hook `transparent` for fullnode (fullnode/hooks/README): every transparent input of
every listed transaction, by the Bend binary transparent/tv (scripts incl. P2SH, multisig and
CHECKLOCKTIMEVERIFY, ECDSA on secp256k1, legacy / ZIP 143 / ZIP 243 / ZIP 244 sighashes).

usage: hook.py <list file>   (each line: a base path P with P.tx, P.ctx (follow layout), P.json)
prints exactly one line per item:
    verdict <height> <txidx> PASS
    verdict <height> <txidx> FAIL <reason>

To wire it in: make fullnode/hooks/transparent an executable that runs this file, e.g.
    #!/bin/sh
    exec python3 /Users/betterclever/projects/zecathon/bend-zcash/transparent/hook.py "$@"

This script only moves bytes: it re-frames each (tx, spent outputs, height) into tv's ZTV1
record (flags 513 = P2SH | CHECKLOCKTIMEVERIFY, mainnet consensus at every height), runs tv on
chunks in parallel and maps its per-input verdict string to PASS / FAIL. Every decision is tv's.
"""
import json, os, struct, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
TV = HERE / "tv"
FLAGS = 513
CHUNK = 200          # records per tv process
JOBS = int(os.environ.get("TV_JOBS", "12"))


def cs(b, i):
    k = b[i]
    if k < 253:
        return k, i + 1
    if k == 253:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    if k == 254:
        return struct.unpack_from("<I", b, i + 1)[0], i + 5
    return struct.unpack_from("<Q", b, i + 1)[0], i + 9


def prevs_of(ctx):
    """follow ctx (u32 len | amounts | u32 len | CompactSize-prefixed scripts) -> per input
    (amount i64 LE bytes, script bytes)."""
    (alen,) = struct.unpack_from("<I", ctx, 0)
    amounts = ctx[4:4 + alen]
    (slen,) = struct.unpack_from("<I", ctx, 4 + alen)
    sb = ctx[8 + alen:8 + alen + slen]
    scripts, i = [], 0
    while i < len(sb):
        n, j = cs(sb, i)
        scripts.append(sb[j:j + n])
        i = j + n
    if len(amounts) != 8 * len(scripts):
        raise ValueError(f"ctx: {len(amounts) // 8} amounts but {len(scripts)} scripts")
    return [(amounts[8 * k:8 * k + 8], s) for k, s in enumerate(scripts)]


def record(tx, height, prevs):
    r = struct.pack("<III", height, FLAGS, len(tx)) + tx + struct.pack("<I", len(prevs))
    for a, s in prevs:
        r += a + struct.pack("<I", len(s)) + s
    return r


def run_chunk(items):
    """items: [(height, txidx, record bytes)] -> {(height, txidx): verdict line}"""
    with tempfile.NamedTemporaryFile(suffix=".ztv", delete=False) as f:
        f.write(b"ZTV1" + struct.pack("<I", len(items)) + b"".join(r for _, _, r in items))
        path = f.name
    try:
        out = ""
        for _ in range(3):  # an empty output (rare Bend runtime issue) is rerun
            p = subprocess.run([str(TV), path], capture_output=True, text=True)
            out = p.stdout
            if out.strip():
                break
    finally:
        os.unlink(path)
    got = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "r":
            got[int(parts[1])] = parts[2]
    res = {}
    for k, (h, i, _) in enumerate(items):
        v = got.get(k)
        if v is None:
            res[(h, i)] = f"verdict {h} {i} FAIL tv produced no verdict"
        elif v == "INVALID":
            res[(h, i)] = f"verdict {h} {i} FAIL malformed transaction or input/prevout count mismatch"
        elif set(v) == {"1"}:
            res[(h, i)] = f"verdict {h} {i} PASS"
        else:
            bad = [str(n) for n, c in enumerate(v) if c != "1"]
            res[(h, i)] = f"verdict {h} {i} FAIL transparent input(s) {','.join(bad)} of {len(v)} invalid"
    return res


def main():
    bases = [l.strip() for l in open(sys.argv[1]) if l.strip()]
    items, early = [], []
    for b in bases:
        base = Path(b)
        info = json.loads(base.with_suffix(".json").read_text())
        h, i = int(info["height"]), int(info["txidx"])
        try:
            prevs = prevs_of(base.with_suffix(".ctx").read_bytes())
        except (ValueError, struct.error) as e:
            early.append(f"verdict {h} {i} FAIL bad spent-output context: {e}")
            continue
        if not prevs:
            early.append(f"verdict {h} {i} FAIL no transparent inputs routed to the transparent hook")
            continue
        items.append((h, i, record(base.with_suffix(".tx").read_bytes(), h, prevs)))
    chunks = [items[k:k + CHUNK] for k in range(0, len(items), CHUNK)]
    res = {}
    with ThreadPoolExecutor(JOBS) as ex:
        for r in ex.map(run_chunk, chunks):
            res.update(r)
    for line in early:
        print(line)
    for h, i, _ in items:
        print(res[(h, i)])


if __name__ == "__main__":
    main()
