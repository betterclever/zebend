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
  7 x (lo, hi)  value pools before the window's first block: sprout, sapling, orchard,
                ironwood, lockbox, transparent, nsm (ZIP 237 NSM value balance; zero before
                NU7, seeded by bin/rules at 3,543,405) (two's complement 64-bit)
  per block:    L | height | nt | nt x time | per spent transparent input in block order
                (coinbase input excluded): value lo | value hi | height | from-coinbase |
                script length | scriptPubKey bytes          (L = byte length after L)
"""
import json, os, re, shutil, struct, subprocess, time
from pathlib import Path

import headers
import store as S

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"
HOOKS = HERE / "hooks"
# Per instance: the genesis (state/) and tip (state-tip/) syncs run from the same code dir and
# used to share work/rules/hooks/<name>/list.txt and the hooks' batch files (audit F2).
WORK = HERE / "work" / "rules" / Path(os.environ.get("ZEBEND_STATE", HERE / "state")).name
RULES_TIMEOUT = int(os.environ.get("ZEBEND_RULES_TIMEOUT", 900))   # s per bin/rules part (<= 8 MB)
HOOK_TIMEOUT = int(os.environ.get("ZEBEND_HOOK_TIMEOUT", 3600))    # s per hook call (one window)
HDR = 1487
POOL_NAMES = ["sprout", "sapling", "orchard", "ironwood", "lockbox", "transparent", "nsm"]
# rules.bend with NU7 (consensus/nu7) reads/prints 7 pools; ZEBEND_RULES_BIN lets the
# consensus/nu7 test harness run its own build.
RULES_BIN = Path(os.environ.get("ZEBEND_RULES_BIN", BIN / "rules"))
HOOK_NAMES = ["transparent", "sapling", "orchard"]


class RuleFail(S.StateError):
    """A block violates a consensus rule (sync.py reports it like a state error: not committed)."""


class VerifierError(RuleFail):
    """A verifier could not give a verdict (timeout, crash, empty output, missing verdict lines).
    Not a statement about the block: sync.py retries the window instead of halting on it."""


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
                r = getattr(st, "rdb", st.db).execute("SELECT time FROM blk WHERE height=?", (x,)).fetchone()
            except AttributeError:
                pass
            if r:
                t = r[0]
            elif 1 <= x <= headers.last_height():
                t = struct.unpack_from("<I", headers.header(x), 100)[0]
        if t is not None:
            out.append(t)
    return out


NU6, NU61, NU63_END = 2726400, 3146400, 4406400
NU7, NU7_FS_END, NSM_SEED = 3543405, 6132390, 36858445520  # ZIP 259, ZIP 214 rev. 3, ZIP 237


def predicted_delta(b, tin):
    """A GUESS of bin/rules' value-pool change for block b (sprout, sapling, orchard, ironwood,
    lockbox, transparent), used only to start the parts of a window in parallel. It decides
    nothing: run_rules accepts a part's output only if the pools it started from equal the pools
    bin/rules itself printed after the previous part's last block, and reruns the part otherwise."""
    spr = sum(j["vpub_old"] - j["vpub_new"] for t in b["txs"] for j in t["js"])
    sap = sum(t["sap"]["vb"] for t in b["txs"] if t["sap"])
    orch = sum(t["orch"]["vb"] for t in b["txs"] if t["orch"])
    iw = sum(t["iw"]["vb"] for t in b["txs"] if t["iw"])
    tout = sum(o[1] for t in b["txs"] for o in t["outs"])
    h = b["height"]
    # FS_DEFERRED / FS_CCF_H3: 12% of 156,250,000 before NU7, of 52,083,333 from NU7 (ZIP 218,
    # ZIP 214 rev. 3: the stream now ends at 6,132,390); 9,375,000 was a misprediction.
    dfr = (18750000 if NU6 <= h < min(NU63_END, NU7) else 6249999 if NU7 <= h < NU7_FS_END else 0) \
        - (7875000000000 if h == NU61 else 0)
    nsm = 0
    if h >= NU7:  # ZIP 235: floor(6 fees / 10); NSM reissuance (8,939,664 on) is not predicted
        fees = tin + sum(
            (t["sap"]["vb"] if t["sap"] else 0) + (t["orch"]["vb"] if t["orch"] else 0) + (t["iw"]["vb"] if t["iw"] else 0)
            - sum(j["vpub_old"] - j["vpub_new"] for j in t["js"]) - sum(o[1] for o in t["outs"])
            for t in b["txs"] if not t["cb"])
        nsm = fees // 10 * 6 + fees % 10 * 6 // 10 + (NSM_SEED if h == NU7 else 0)
    return [spr, -sap, -orch, -iw, dfr, tout - tin, nsm]


def block_records(blocks, st):
    """Per block: the ctx.bin record (without the pools header) and the predicted pool delta.
    Raises RuleFail if a spent output is unknown."""
    made = {}  # (txid, vout) -> (value, script, height, cb): outputs created earlier in the window
    window_times = {b["height"]: b["time"] for b in blocks}
    recs, deltas = [], []
    for b in blocks:
        h = b["height"]
        times = _prev_times(h, st, window_times)
        rec = [struct.pack("<II", h, len(times)), b"".join(struct.pack("<I", t) for t in times)]
        tin = 0
        for t in b["txs"]:
            for (ptxid, vout, _seq) in t["ins"]:
                u = made.get((ptxid, vout)) or st.utxo(ptxid, vout)
                if u is None:
                    raise RuleFail(f"block {h} tx {t['txid']}: spends {ptxid}:{vout}, which is not an unspent output")
                value, script, ph, cb = u
                tin += value
                rec.append(struct.pack("<IIIII", value & 0xFFFFFFFF, value >> 32, ph, int(cb), len(script)))
                rec.append(bytes(script))
            for (k, value, script) in t["outs"]:
                made[(t["txid"], k)] = (value, script, h, t["cb"])
        rec = b"".join(rec)
        recs.append(struct.pack("<I", len(rec)) + rec)
        deltas.append(predicted_delta(b, tin))
    return recs, deltas


def build_ctx(blocks, st, pools):
    """ctx.bin bytes for a window. Raises RuleFail if a spent output is unknown."""
    recs, _ = block_records(blocks, st)
    return b"".join(_u64(pools.get(n, 0)) for n in POOL_NAMES) + b"".join(recs)


def window_bytes(blocks, raw_by_height):
    out = []
    last = headers.last_height()
    for b in blocks:
        h = b["height"]
        raw = raw_by_height[h]
        exp = headers.header(h) if 1 <= h <= last else raw[:HDR]
        out += [struct.pack("<I", h), exp, struct.pack("<I", len(raw)), raw]
    return b"".join(out)


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
            res.setdefault(int(f[1]), {})["pools"] = dict(zip(POOL_NAMES, map(_signed, f[2:2 + len(POOL_NAMES)])))
        elif f[0] == "verdict":
            res.setdefault(int(f[1]), {})["verdict"] = f[2]
    return res


def gated_flag(blocks):
    """bin/rules --gated skips node/wire's validator, which blockdelta already ran on the same
    bytes: sync.py passes rules only blocks that blockdelta's gate accepted (checkpoint_checks
    raises on `block <h> INVALID wire`). The wire gate was ~90% of bin/rules' time in the spam
    era (Jubjub/Pallas point decoding). Blocks that did not come from blockdelta are gated."""
    return ["--gated"] if blocks and all(b.get("gated") for b in blocks) else []


def _run_part(blocks, ctx, raw_by_height, tag):
    WORK.mkdir(parents=True, exist_ok=True)
    wp, cp = WORK / f"win_{tag}.bin", WORK / f"ctx_{tag}.bin"
    wp.write_bytes(window_bytes(blocks, raw_by_height))
    cp.write_bytes(ctx)
    r = None
    for _ in range(3):  # empty output (a known rare Bend runtime issue) or a hang is rerun
        try:
            r = subprocess.run([str(RULES_BIN), str(wp), str(cp)] + gated_flag(blocks), capture_output=True, text=True,
                               timeout=RULES_TIMEOUT)
        except subprocess.TimeoutExpired:
            r = subprocess.CompletedProcess([], -9, "", f"bin/rules timed out after {RULES_TIMEOUT} s")
            continue
        if r.stdout.strip():
            break
    res = parse_rules(r.stdout)
    missing = [b["height"] for b in blocks if "verdict" not in res.get(b["height"], {})]
    if missing:
        raise VerifierError(f"bin/rules gave no verdict for {missing[:3]}; stderr {r.stderr.strip()[-300:]!r}")
    wp.unlink(missing_ok=True)
    cp.unlink(missing_ok=True)
    return res


STATS = {"parts": 0, "reruns": 0}


def split_parts(blocks, jobs, max_bytes=8 << 20):
    """Contiguous parts (lists of indexes into blocks) of about equal bytes."""
    total = sum(b["size"] for b in blocks)
    target = max(1, min(max_bytes, total // max(1, jobs) + 1))
    parts, cur, size = [], [], 0
    for i, b in enumerate(blocks):
        cur.append(i)
        size += b["size"]
        if size >= target:
            parts.append(cur)
            cur, size = [], 0
    if cur:
        parts.append(cur)
    return parts


def run_rules(blocks, st, raw_by_height, pools, tag=None, jobs=1, ex=None):
    """bin/rules over the window, split into parts that run in parallel.

    bin/rules carries exactly one value from block to block: the value pools (every other input
    of a block is in the block and its own ctx record). Part k starts from pools predicted by
    predicted_delta(); its output is used only if that start equals the pools bin/rules printed
    after part k-1's last block, so every verdict is the one a single sequential run over the
    window prints. A mispredicted part is rerun from the printed pools (STATS["reruns"])."""
    tag = tag or f"{os.getpid()}_{blocks[0]['height']}"  # several node instances share work/
    recs, deltas = block_records(blocks, st)
    parts = split_parts(blocks, jobs) if jobs > 1 else [list(range(len(blocks)))]
    starts, p = [], [pools.get(n, 0) for n in POOL_NAMES]
    for part in parts:
        starts.append(dict(zip(POOL_NAMES, p)))
        for i in part:
            p = [a + d for a, d in zip(p, deltas[i])]

    def one(k, start):
        ctx = b"".join(_u64(start[n]) for n in POOL_NAMES) + b"".join(recs[i] for i in parts[k])
        return _run_part([blocks[i] for i in parts[k]], ctx, raw_by_height, f"{tag}_{k}")

    if ex is not None and len(parts) > 1:
        outs = list(ex.map(one, range(len(parts)), starts))
    else:
        outs = [one(k, starts[k]) for k in range(len(parts))]
    res = {}
    for k, part in enumerate(parts):
        if k > 0:
            actual = outs[k - 1][blocks[parts[k - 1][-1]]["height"]]["pools"]
            if actual != starts[k]:
                STATS["reruns"] += 1
                outs[k] = one(k, actual)
        res.update(outs[k])
    STATS["parts"] += len(parts)
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
    """Run each hook on its transactions. Returns {hook: {"pass": n, "skipped": n[, "skipped_reasons":
    {reason: n}]}}; raises RuleFail on a FAIL or on a missing verdict from a hook that exists.
    A hook may answer SKIPPED <reason> for an item it cannot check: counted as skipped, never
    as passed."""
    jobs = hook_jobs(blocks)
    summary = {}
    by_h = {b["height"]: b for b in blocks}
    # outputs created in this window (an input may spend one: it is not in the store yet), and
    # each block's tx slices once (was: a scan of the whole window per such input, and a copy of
    # the block per item)
    made = {(t["txid"], k): (v, sc) for b in blocks for t in b["txs"] for (k, v, sc) in t["outs"]}
    slices = {}
    for name, items in jobs.items():
        exe = HOOKS / name
        if not items:
            summary[name] = {"pass": 0, "skipped": 0}
            continue
        if not (exe.exists() and os.access(exe, os.X_OK)):
            summary[name] = {"pass": 0, "skipped": len(items)}
            continue
        d = WORK / "hooks" / name
        shutil.rmtree(d, ignore_errors=True)  # last window's files (they were never deleted: 2.2 GB)
        d.mkdir(parents=True, exist_ok=True)
        lst = []
        for h, i in items:
            b = by_h[h]
            if h not in slices:
                slices[h] = tx_slices(raw_by_height[h], [t["size"] for t in b["txs"]])
            txs = slices[h]
            t = b["txs"][i]
            spent = []
            for (ptxid, vout, _seq) in t["ins"]:
                u = made.get((ptxid, vout)) or st.utxo(ptxid, vout)
                if u is None:  # block_records raised already; never index None
                    raise RuleFail(f"block {h} tx {t['txid']}: spends {ptxid}:{vout}, which is not an unspent output")
                spent.append((u[0], u[1]))
            base = d / f"{h}_{i}"
            base.with_suffix(".tx").write_bytes(txs[i])
            base.with_suffix(".ctx").write_bytes(follow_ctx(spent))
            base.with_suffix(".json").write_text(json.dumps({"height": h, "txidx": i, "txid": t["txid"],
                                                             "version": t["v"], "branch_id": t["br"]}))
            lst.append(str(base))
        (d / "list.txt").write_text("\n".join(lst) + "\n")
        try:
            r = subprocess.run([str(exe), str(d / "list.txt")], capture_output=True, text=True, timeout=HOOK_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise VerifierError(f"hook {name}: timed out after {HOOK_TIMEOUT} s on {len(items)} tx")
        got = {(int(a), int(b)): (v, rest) for a, b, v, rest in
               re.findall(r"^verdict (\d+) (\d+) (PASS|FAIL|SKIPPED) ?(.*)$", r.stdout, re.M)}
        bad = [(k, v) for k, v in got.items() if v[0] == "FAIL"]
        if bad:
            raise RuleFail(f"hook {name}: {bad[:3]}")
        miss = [k for k in items if k not in got]
        if miss:
            raise VerifierError(f"hook {name}: no verdict for {miss[:3]} (exit {r.returncode}: {r.stderr.strip()[-200:]!r})")
        # SKIPPED <reason>: the hook could not check this item (e.g. a construction it does not
        # implement). Counted as skipped, never as passed; the window is not rejected for it.
        skipped = [(k, v[1]) for k, v in got.items() if v[0] == "SKIPPED" and k in set(items)]
        reasons = {}
        for _, why in skipped:
            reasons[why or "no reason given"] = reasons.get(why or "no reason given", 0) + 1
        summary[name] = {"pass": len(items) - len(skipped), "skipped": len(skipped)}
        if reasons:
            summary[name]["skipped_reasons"] = reasons
    return summary


# ------------------------------------------------------------------ entry point

def validate(blocks, st, raw_by_height, log, mode="full", pools=None, jobs=1, ex=None):
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
    res = run_rules(blocks, st, raw_by_height, prev or {}, jobs=jobs, ex=ex)
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
                       "hooks": {k: _hook_status(v) for k, v in hooks.items()},
                       "disagreements": fails[:20] if mode == "audit" else []}}
    if known:
        extra["pools"] = res[last]["pools"]
        extra["pools_by_height"] = {b["height"]: res[b["height"]]["pools"] for b in blocks}
    for name, v in hooks.items():
        if v["skipped"]:
            why = v.get("skipped_reasons") or {"component pending": v["skipped"]}
            log(f"  {name}: SKIPPED for {v['skipped']} tx ({', '.join(f'{r}: {n}' for r, n in why.items())}); "
                f"PASS {v['pass']}")
    return extra


def _hook_status(v):
    """PASS only if every item passed; a hook that is absent or skipped items says so."""
    if not v["skipped"]:
        return f"PASS {v}"
    if not v["pass"] and "skipped_reasons" not in v:
        return f"SKIPPED (component pending) {v}"
    return f"PASS {v['pass']}, SKIPPED {v['skipped']} {v}"
