"""Consensus rules for the Zebend full node: driver for bin/rules (Bend) and the verifier hooks.

sync.py calls validate() for every window of blocks above the last checkpoint (mode "full"),
before the window is committed. Bend (fullnode/rules/rules.bend) re-parses each block and
decides every non-cryptographic rule; this module only

  * looks up what Bend needs and the block does not contain: the spent outputs (value,
    scriptPubKey, height, from-coinbase) from the UTXO store or from earlier transactions of
    the same window, the previous 11 block times, and the value pools before the window;
  * writes them to ctx.bin, runs bin/rules, and compares the printed verdict lines;
  * runs the per-transaction verifier hooks (hooks/README) and reports a hook whose component
    has not landed as SKIPPED (component pending), never as a pass.

Not done here (done by the store during the commit, see store.py): nullifier-set and UTXO
membership (a spent output must exist and be unspent; a nullifier must not be in the set) and
anchors.

ctx.bin layout (all integers u32 little-endian):
  6 x (lo, hi)  value pools before the window's first block: sprout, sapling, orchard,
                ironwood, lockbox, transparent (two's complement 64-bit)
  per block:    L | height | nt | nt x time | per spent transparent input in block order
                (coinbase input excluded): value lo | value hi | height | from-coinbase |
                script length | scriptPubKey bytes          (L = byte length after L)
"""
import json, os, re, struct, subprocess, time
from pathlib import Path

import headers
import store as S

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"
HOOKS = HERE / "hooks"
WORK = HERE / "work" / "rules"
HDR = 1487
POOL_NAMES = ["sprout", "sapling", "orchard", "ironwood", "lockbox", "transparent"]
HOOK_NAMES = ["transparent", "sapling", "orchard"]


class RuleFail(S.StateError):
    """A block violates a consensus rule (sync.py reports it like a state error: not committed)."""


# ------------------------------------------------------------------ inputs Bend needs

def _u64(v):
    return struct.pack("<Q", v & 0xFFFFFFFFFFFFFFFF)


def _prev_times(h, st, window_times):
    """Times of the up to 11 blocks before h: the window's own headers, else the block index,
    else the verified header files (raw header fields; Bend computes the median)."""
    out = []
    for x in range(max(0, h - 11), h):
        t = window_times.get(x)
        if t is None:
            r = None
            try:
                r = st.db.execute("SELECT time FROM blk WHERE height=?", (x,)).fetchone()
            except AttributeError:
                pass
            if r:
                t = r[0]
            elif 1 <= x <= headers.last_height():
                t = struct.unpack_from("<I", headers.header(x), 100)[0]
        if t is not None:
            out.append(t)
    return out


def build_ctx(blocks, st, pools):
    """ctx.bin bytes for the window. Raises RuleFail if a spent output is unknown."""
    made = {}  # (txid, vout) -> (value, script, height, cb): outputs created earlier in the window
    window_times = {b["height"]: b["time"] for b in blocks}
    out = b"".join(_u64(pools.get(n, 0)) for n in POOL_NAMES)
    for b in blocks:
        h = b["height"]
        times = _prev_times(h, st, window_times)
        rec = struct.pack("<II", h, len(times)) + b"".join(struct.pack("<I", t) for t in times)
        for t in b["txs"]:
            for (ptxid, vout, _seq) in t["ins"]:
                u = made.get((ptxid, vout)) or st.utxo(ptxid, vout)
                if u is None:
                    raise RuleFail(f"block {h} tx {t['txid']}: spends {ptxid}:{vout}, which is not an unspent output")
                value, script, ph, cb = u
                rec += struct.pack("<IIIII", value & 0xFFFFFFFF, value >> 32, ph, int(cb), len(script)) + bytes(script)
            for (k, value, script) in t["outs"]:
                made[(t["txid"], k)] = (value, script, h, t["cb"])
        out += struct.pack("<I", len(rec)) + rec
    return out


def window_bytes(blocks, raw_by_height):
    out = b""
    for b in blocks:
        h = b["height"]
        raw = raw_by_height[h]
        exp = headers.header(h) if 1 <= h <= headers.last_height() else raw[:HDR]
        out += struct.pack("<I", h) + exp + struct.pack("<I", len(raw)) + raw
    return out


def _signed(s):
    return int(s)


def parse_rules(text):
    """bin/rules lines -> {height: {"fails": [...], "fees": int, "sigops": int, "pools": {...}, "verdict": str}}."""
    res = {}
    for line in text.splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == "fail":
            res.setdefault(int(f[1]), {}).setdefault("fails", []).append(" ".join(f[2:]))
        elif f[0] == "fees":
            r = res.setdefault(int(f[1]), {})
            r["fees"], r["sigops"] = int(f[2]), int(f[4])
        elif f[0] == "pools":
            res.setdefault(int(f[1]), {})["pools"] = dict(zip(POOL_NAMES, map(_signed, f[2:8])))
        elif f[0] == "verdict":
            res.setdefault(int(f[1]), {})["verdict"] = f[2]
    return res


def run_rules(blocks, st, raw_by_height, pools, tag=None):
    WORK.mkdir(parents=True, exist_ok=True)
    tag = tag or f"{os.getpid()}_{blocks[0]['height']}"  # several node instances share work/
    wp, cp = WORK / f"win_{tag}.bin", WORK / f"ctx_{tag}.bin"
    wp.write_bytes(window_bytes(blocks, raw_by_height))
    cp.write_bytes(build_ctx(blocks, st, pools))
    for _ in range(3):  # empty output (a known rare Bend runtime issue) is rerun
        r = subprocess.run([str(BIN / "rules"), str(wp), str(cp)], capture_output=True, text=True)
        if r.stdout.strip():
            break
    res = parse_rules(r.stdout)
    missing = [b["height"] for b in blocks if "verdict" not in res.get(b["height"], {})]
    if missing:
        raise RuleFail(f"bin/rules gave no verdict for {missing[:3]}; stderr {r.stderr.strip()[-300:]!r}")
    wp.unlink(missing_ok=True)
    cp.unlink(missing_ok=True)
    return res


# ------------------------------------------------------------------ verifier hooks

def tx_slices(raw, sizes):
    """Raw bytes of each transaction, by the sizes Bend printed (blockdelta `size`)."""
    n = len(sizes)
    off = HDR + (1 if n < 0xfd else 3 if n <= 0xffff else 5)
    out = []
    for s in sizes:
        out.append(raw[off:off + s])
        off += s
    if off != len(raw):
        raise RuleFail("transaction sizes from Bend do not tile the block")
    return out


def follow_ctx(spent):
    """Spent outputs in follow's txx ctx layout: u32 len | amounts (i64 each) | u32 len | scripts
    (CompactSize-prefixed)."""
    amounts = b"".join(struct.pack("<q", v) for v, _ in spent)
    scripts = b""
    for _, s in spent:
        scripts += (bytes([len(s)]) if len(s) < 0xfd else b"\xfd" + struct.pack("<H", len(s))) + bytes(s)
    return struct.pack("<I", len(amounts)) + amounts + struct.pack("<I", len(scripts)) + scripts


def hook_jobs(blocks):
    """Which hook each transaction needs (coinbase transactions included where they carry
    shielded data: their Sapling/Orchard/Ironwood outputs and binding signatures)."""
    jobs = {n: [] for n in HOOK_NAMES}
    for b in blocks:
        for t in b["txs"]:
            if t["ins"]:
                jobs["transparent"].append((b["height"], t["i"]))
            if t["sap"] or t["js"]:
                jobs["sapling"].append((b["height"], t["i"]))
            if t["orch"] or t["iw"]:
                jobs["orchard"].append((b["height"], t["i"]))
    return jobs


def run_hooks(blocks, st, raw_by_height, log):
    """Run each hook on its transactions. Returns {hook: {"pass": n, "skipped": n}}; raises
    RuleFail on a FAIL or on a missing verdict from a hook that exists."""
    jobs = hook_jobs(blocks)
    summary = {}
    made = {}
    by_h = {b["height"]: b for b in blocks}
    for name, items in jobs.items():
        exe = HOOKS / name
        if not items:
            summary[name] = {"pass": 0, "skipped": 0}
            continue
        if not (exe.exists() and os.access(exe, os.X_OK)):
            summary[name] = {"pass": 0, "skipped": len(items)}
            continue
        d = WORK / "hooks" / name
        d.mkdir(parents=True, exist_ok=True)
        lst = []
        for h, i in items:
            b = by_h[h]
            txs = tx_slices(raw_by_height[h], [t["size"] for t in b["txs"]])
            t = b["txs"][i]
            spent = []
            for (ptxid, vout, _seq) in t["ins"]:
                u = made.get((ptxid, vout)) or st.utxo(ptxid, vout)
                if u is None:
                    # an earlier tx of the same block: look it up in the window
                    for bb in blocks:
                        for tt in bb["txs"]:
                            if tt["txid"] == ptxid:
                                o = tt["outs"][vout]
                                u = (o[1], o[2], bb["height"], tt["cb"])
                spent.append((u[0], u[1]))
            base = d / f"{h}_{i}"
            base.with_suffix(".tx").write_bytes(txs[i])
            base.with_suffix(".ctx").write_bytes(follow_ctx(spent))
            base.with_suffix(".json").write_text(json.dumps({"height": h, "txidx": i, "txid": t["txid"],
                                                             "version": t["v"], "branch_id": t["br"]}))
            lst.append(str(base))
        (d / "list.txt").write_text("\n".join(lst) + "\n")
        r = subprocess.run([str(exe), str(d / "list.txt")], capture_output=True, text=True)
        got = {(int(a), int(b)): (v, rest) for a, b, v, rest in
               re.findall(r"^verdict (\d+) (\d+) (PASS|FAIL) ?(.*)$", r.stdout, re.M)}
        bad = [(k, v) for k, v in got.items() if v[0] != "PASS"]
        if bad:
            raise RuleFail(f"hook {name}: {bad[:3]}")
        miss = [k for k in items if k not in got]
        if miss:
            raise RuleFail(f"hook {name}: no verdict for {miss[:3]} (exit {r.returncode}: {r.stderr.strip()[-200:]!r})")
        summary[name] = {"pass": len(items), "skipped": 0}
    return summary


# ------------------------------------------------------------------ entry point

def validate(blocks, st, raw_by_height, log, mode="full", pools=None):
    """Decide every non-crypto rule for `blocks` (in height order, a contiguous window).

    mode "full": raise RuleFail on any violated rule or hook FAIL.
    mode "audit": for checkpointed blocks (tracks pools from genesis); returns the
    disagreements instead of raising and runs no hooks.
    Returns extra meta for the window's atomic commit: {"pools": {...}, "pools@<h>": {...},
    "rules": {...}} (no pools if they were not tracked from genesis: turnstile is then SKIPPED).
    """
    t0 = time.time()
    prev = st.get("pools") if pools is None else pools  # pools: carried from an earlier call in the same window
    known = prev is not None
    res = run_rules(blocks, st, raw_by_height, prev or {})
    fails, skipped_turnstile = [], 0
    for b in blocks:
        r = res[b["height"]]
        fs = r.get("fails", [])
        if not known:
            skipped_turnstile += sum(1 for x in fs if x.startswith("turnstile_"))
            fs = [x for x in fs if not x.startswith("turnstile_")]
        if fs:
            fails.append((b["height"], fs))
    hooks = {}
    if mode == "full":
        if fails:
            h, fs = fails[0]
            raise RuleFail(f"block {h}: consensus rule violated: {'; '.join(fs)}")
        hooks = run_hooks(blocks, st, raw_by_height, log)
    last = blocks[-1]["height"]
    extra = {"rules": {"last": last, "mode": mode, "blocks": len(blocks), "secs": round(time.time() - t0, 2),
                       "turnstile": "checked" if known else "SKIPPED (pools not tracked from genesis)",
                       "hooks": {k: ("SKIPPED (component pending)" if v["skipped"] else "PASS") + f" {v}"
                                 for k, v in hooks.items()},
                       "disagreements": fails[:20] if mode == "audit" else []}}
    if known:
        extra["pools"] = res[last]["pools"]
        extra["pools_by_height"] = {b["height"]: res[b["height"]]["pools"] for b in blocks}
    for name, v in hooks.items():
        if v["skipped"]:
            log(f"  {name}: SKIPPED (component pending) for {v['skipped']} tx")
    return extra
