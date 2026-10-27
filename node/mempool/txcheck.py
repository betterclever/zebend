"""Bend I/O for mempool admission: every consensus and policy decision is a Bend program's.

A candidate transaction is checked as the only non-coinbase transaction of a synthetic block
at height tip+1 (the height it would be mined at), so the SAME Bend programs that validate
blocks decide it:

  * bin/blockdelta (node/bend/delta.bend): zcash/wire validator gate, txid, inputs,
    outputs, nullifiers, anchors, value balances, legacy sigops;
  * bin/rules (node/rules/rules.bend): every non-crypto consensus rule, tx-level ones
    reported as `fail <h> <rule> tx 1`; the per-block `fees` line is this tx's fee;
  * the verifier hooks node/hooks/{transparent,sapling,orchard} (scripts + ECDSA +
    sighash; Sapling Groth16 + RedJubjub; Orchard/Ironwood RedPallas + Halo 2);
  * mempool/bin/txpolicy (mempool/bend/txpolicy.bend): wtxid auth digest, ZIP 317, standardness.

The synthetic block: a header-shaped prefix (version 4, hashPrevBlock = tip, time = the
next block's median-time-past, as Zebra's mempool uses for lock times, bits = tip's), a
synthetic coinbase (v5, BIP34 height tip+1, one 0-value OP_TRUE output: 0 sigops), then the
candidate. Lines about the synthetic coinbase and header (`tx 0`, miner_fees,
issuance_required_outputs, mtp, header/merkle MISMATCH) are not about the candidate and are
ignored; which lines are attributed to the candidate is listed in TX_BLOCK_RULES below.
Python here only builds byte records and reads the printed lines.
"""
import json, os, re, struct, subprocess, threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent          # node/mempool
FN = HERE.parent                                 # fullnode
BIN_FN = FN / "bin"
BIN = HERE / "bin"
HOOKS = FN / "hooks"
WORK = HERE / "work"
HDR = 1487
HOOK_NAMES = ["transparent", "sapling", "orchard"]
# Mainnet upgrades: name, branch id, activation height (same table as rpc.py).
UPGRADES = [("Overwinter", "5ba81b19", 347500), ("Sapling", "76b809bb", 419200), ("Blossom", "2bb40e60", 653600),
            ("Heartwood", "f5b9230b", 903000), ("Canopy", "e9ff75a6", 1046400), ("NU5", "c2d6d0b4", 1687104),
            ("NU6", "c8e71055", 2726400), ("NU6.1", "4dec4df0", 3146400), ("NU6.2", "5437f330", 3364600),
            ("NU6.3", "37a5165b", 3428143), ("NU7", "77190ad9", 3543405)]
# Block-level rule lines of the synthetic block that can only come from the candidate (the
# synthetic coinbase has one null-prevout input, no shielded data, 0 sigops):
TX_BLOCK_RULES = {"duplicate_spend", "sigops", "coinbase_first", "wire"}
# Block-level lines about the synthetic coinbase/header, never about the candidate:
IGNORED_BLOCK_RULES = {"miner_fees", "issuance_required_outputs", "mtp", "coinbase_height",
                       "coinbase_expiry", "coinbase_script_length"}
BIG_POOL = 1 << 61  # pools when the state does not track them: the turnstile is SKIPPED


def branch_at(h):
    br = "00000000"
    for _, b, a in UPGRADES:
        if h >= a:
            br = b
    return br


def cs(n):
    if n < 0xfd:
        return bytes([n])
    return b"\xfd" + struct.pack("<H", n) if n <= 0xffff else b"\xfe" + struct.pack("<I", n)


def _scriptnum(n):
    out = b""
    while n:
        out += bytes([n & 0xff])
        n >>= 8
    if out and out[-1] & 0x80:
        out += b"\0"
    return out


def synth_coinbase(height):
    """A v5 coinbase for `height` (bytes only; it is never relayed or mined)."""
    num = _scriptnum(height)
    sig = bytes([len(num)]) + num + b"\x00"  # BIP34 push + 1 byte (scriptSig length >= 2)
    return (struct.pack("<II", 0x80000005, 0x26A7270A) + struct.pack("<I", int(branch_at(height), 16))
            + struct.pack("<II", 0, height)
            + b"\x01" + bytes(32) + b"\xff\xff\xff\xff" + cs(len(sig)) + sig + b"\xff\xff\xff\xff"
            + b"\x01" + struct.pack("<q", 0) + b"\x01\x51"
            + b"\x00\x00" + b"\x00")


def synth_header(prev_display, time_, bits_hex):
    return (struct.pack("<i", 4) + bytes.fromhex(prev_display)[::-1] + bytes(64) + struct.pack("<I", time_)
            + struct.pack("<I", int(bits_hex, 16)) + bytes(32) + b"\xfd\x40\x05" + bytes(1344))


def synth_block(ctx, raw_tx):
    """ctx: {"height", "prev", "time", "bits"}; one block [coinbase, candidate]."""
    return (synth_header(ctx["prev"], ctx["time"], ctx["bits"]) + cs(2) + synth_coinbase(ctx["height"]) + raw_tx)


def window_bytes(recs):
    """blockdelta / rules window: u32 height | 1487-byte header | u32 len | block."""
    return b"".join(struct.pack("<I", h) + raw[:HDR] + struct.pack("<I", len(raw)) + raw for h, raw in recs)


_seq = [0]
_seq_lock = threading.Lock()


def tmp(name):
    WORK.mkdir(parents=True, exist_ok=True)
    with _seq_lock:
        _seq[0] += 1
        k = _seq[0]
    return WORK / f"{os.getpid()}_{k}_{name}"


def run(*args, timeout=120):
    """Run a Bend binary; an empty output (a known rare Bend runtime issue) is rerun. A run
    longer than `timeout` s is killed and reported as no output (the caller fails closed)."""
    r = None
    for _ in range(3):
        try:
            r = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return subprocess.CompletedProcess(args, -9, "", f"timeout after {timeout} s")
        if r.stdout.strip():
            break
    return r


# ------------------------------------------------------------------ blockdelta

def parse_delta(text):
    """bin/blockdelta lines -> block dicts (copied from node/sync.py parse_delta: moves fields only)."""
    pools = ["sprout", "sapling", "orchard", "ironwood"]
    blocks, b, t = [], None, None
    for line in text.splitlines():
        f = line.split()
        if not f:
            continue
        k = f[0]
        if k == "block":
            if len(f) > 2 and f[2] == "INVALID":
                blocks.append({"height": int(f[1]), "invalid": " ".join(f[2:]), "txs": []})
                b = None
                continue
            kv = dict(zip(f[4::2], f[5::2]))
            b = {"height": int(f[1]), "hash": f[2], "prev": f[3], "time": int(kv["time"]), "size": int(kv["size"]),
                 "ntx": int(kv["txs"]), "header": kv["header"], "merkle": kv["merkle"], "txs": []}
            blocks.append(b)
        elif k == "tx":
            kv = dict(zip(f[3::2], f[4::2]))
            t = {"i": int(f[1]), "txid": f[2], "v": int(kv["v"]), "ow": kv.get("ow") == "1", "grp": kv.get("grp"),
                 "br": kv.get("br"), "lock": int(kv.get("lock", 0)), "exp": int(kv.get("exp", 0)),
                 "size": int(kv["size"]), "sigops": int(kv["sigops"]) if "sigops" in kv else None,
                 "cb": False, "ins": [], "outs": [], "js": [], "sap": None, "orch": None, "iw": None,
                 "nfs": {p: [] for p in pools}, "anchors": {p: [] for p in pools}}
            b["txs"].append(t)
        elif k == "cb":
            t["cb"] = True
        elif k == "in":
            t["ins"].append((f[2], int(f[3]), int(f[4])))
        elif k == "out":
            t["outs"].append((int(f[1]), int(f[2]), bytes.fromhex(f[3]) if len(f) > 3 else b""))
        elif k == "js":
            t["js"].append({"vpub_old": int(f[1]), "vpub_new": int(f[2]), "anchor": f[3]})
            t["nfs"]["sprout"] += [f[4], f[5]]
            t["anchors"]["sprout"].append(f[3])
        elif k == "sap":
            t["sap"] = {"vb": int(f[1]), "nspends": int(f[2]), "noutputs": int(f[3])}
        elif k == "ss":
            t["anchors"]["sapling"].append(f[1])
            t["nfs"]["sapling"].append(f[2])
        elif k in ("orch", "iw"):
            pool = "orchard" if k == "orch" else "ironwood"
            t["orch" if k == "orch" else "iw"] = {"vb": int(f[1]), "anchor": f[2], "flags": f[3], "n": int(f[4])}
            t["anchors"][pool].append(f[2])
        elif k in ("oa", "ia"):
            t["nfs"]["orchard" if k == "oa" else "ironwood"].append(f[1])
        elif k == "end":
            b = t = None
    return blocks


def extract(raws, ctx):
    """Run blockdelta on one synthetic block per candidate. Returns per candidate either the
    candidate's tx dict (from Bend) or {"invalid": reason}."""
    recs = [(ctx["height"], synth_block(ctx, r)) for r in raws]
    p = tmp("delta.bin")
    p.write_bytes(window_bytes(recs))
    r = run(BIN_FN / "blockdelta", p)
    p.unlink(missing_ok=True)
    blocks = parse_delta(r.stdout)
    if len(blocks) != len(raws):
        raise RuntimeError(f"blockdelta returned {len(blocks)} blocks for {len(raws)} records: {r.stderr[-300:]!r}")
    out = []
    for b, raw in zip(blocks, raws):
        if "invalid" in b:
            out.append({"invalid": "malformed transaction (zcash/wire validator: " + b["invalid"] + ")"})
        elif len(b["txs"]) != 2 or b["txs"][1]["size"] != len(raw):
            out.append({"invalid": "transaction does not parse as exactly one transaction"})
        else:
            out.append(b["txs"][1])
    return out


# ------------------------------------------------------------------ txpolicy (Bend)

def policy(items):
    """items: [(raw, fee or None, sigops, spent scripts or None)] -> per item dict from
    mempool/bin/txpolicy (spent scripts: one scriptPubKey per transparent input, in order)."""
    p = tmp("policy.bin")
    with open(p, "wb") as f:
        for it in items:
            raw, fee, sigops = it[:3]
            scripts = it[3] if len(it) > 3 else None
            blk = bytes(140) + b"\xfd\x40\x05" + bytes(1344) + b"\x01" + raw
            blob = b"".join(struct.pack("<I", len(sc)) + bytes(sc) for sc in scripts) if scripts is not None else b""
            fz = (fee or 0) & 0xFFFFFFFFFFFFFFFF
            flags = int(fee is not None) | (2 if scripts is not None else 0)
            f.write(struct.pack("<IIIIII", len(blk), fz & 0xFFFFFFFF, fz >> 32, flags, sigops or 0, len(blob))
                    + blk + blob)
    r = run(BIN / "txpolicy", p)
    p.unlink(missing_ok=True)
    res = [dict() for _ in items]
    for line in r.stdout.splitlines():
        f = line.split()
        if len(f) < 3:
            continue
        k = int(f[1])
        if k >= len(res):
            continue
        if f[0] == "tx" and f[2] == "INVALID":
            res[k]["invalid"] = True
        elif f[0] == "tx":
            kv = dict(zip(f[2::2], f[3::2]))
            res[k].update({"v": int(kv["v"]), "txid": kv["txid"], "auth": kv["auth"], "size": int(kv["size"]),
                           "actions": int(kv["actions"]), "conv_actions": int(kv["conv_actions"]),
                           "conv_fee": int(kv["conv_fee"])})
        elif f[0] == "zip317":
            res[k]["zip317"] = {"unpaid": int(f[3]), "min_fee": int(f[5]), "verdict": f[6],
                                "reason": " ".join(f[7:])}
        elif f[0] == "std":
            res[k]["std"] = {"verdict": f[2], "reason": " ".join(f[3:])}
    for k, d in enumerate(res):
        if not d:
            raise RuntimeError(f"txpolicy gave no line for record {k}: {r.stderr[-300:]!r}")
    return res


# ------------------------------------------------------------------ bin/rules (Bend)

def _u64(v):
    return struct.pack("<Q", v & 0xFFFFFFFFFFFFFFFF)


POOLS6 = ["sprout", "sapling", "orchard", "ironwood", "lockbox", "transparent"]
POOLS7 = POOLS6 + ["nsm"]  # NU7 build of bin/rules (ZIP 237 NSM value balance)
_FMT = {"key": None, "names": None}
_FMT_LOCK = threading.Lock()


def rules_pool_names():
    """The value-pool header bin/rules expects (6 before its NU7 build, 7 with it). The node's
    bin/rules can be rebuilt while we run, so this is re-probed whenever the binary changes: a
    coinbase-only synthetic block is run with each layout, and the layout for which bin/rules
    prints a verdict and a `pools` line with exactly as many values as it was given is used."""
    st = (BIN_FN / "rules").stat()
    key = (st.st_mtime_ns, st.st_size)
    with _FMT_LOCK:
        if _FMT["key"] == key:
            return _FMT["names"]
        h = 3_500_000
        ctx = {"height": h, "prev": "00" * 32, "time": 1_790_000_000, "bits": "1c00ffff"}
        blk = synth_header(ctx["prev"], ctx["time"], ctx["bits"]) + cs(1) + synth_coinbase(h)
        found = None
        for names in (POOLS7, POOLS6):
            wp, cp = tmp("probe_win.bin"), tmp("probe_ctx.bin")
            wp.write_bytes(window_bytes([(h, blk)]))
            rec = struct.pack("<II", h, 0)
            cp.write_bytes(b"".join(_u64(BIG_POOL) for _ in names) + struct.pack("<I", len(rec)) + rec)
            r = run(BIN_FN / "rules", wp, cp, timeout=30)
            wp.unlink(missing_ok=True)
            cp.unlink(missing_ok=True)
            lines = [l.split() for l in r.stdout.splitlines()]
            pools = [l for l in lines if l and l[0] == "pools"]
            if any(l and l[0] == "verdict" for l in lines) and pools and len(pools[0]) - 2 == len(names):
                found = names
                break
        if found is None:
            raise RuntimeError("bin/rules: could not determine its ctx layout (6 or 7 value pools)")
        _FMT.update(key=key, names=found)
        return found


def rules_ctx(height, times, spent, pools):
    """ctx.bin for one synthetic block; spent: [(value, script, height, cb)] in input order."""
    rec = [struct.pack("<II", height, len(times)), b"".join(struct.pack("<I", t) for t in times)]
    for value, script, ph, cb in spent:
        rec.append(struct.pack("<IIIII", value & 0xFFFFFFFF, (value >> 32) & 0xFFFFFFFF, ph, int(cb), len(script)))
        rec.append(bytes(script))
    rec = b"".join(rec)
    return b"".join(_u64(pools.get(n, BIG_POOL)) for n in rules_pool_names()) + struct.pack("<I", len(rec)) + rec


def rules(raw, ctx, spent, pools_known):
    """bin/rules on the synthetic block [coinbase, raw]. Returns {"fails": [rule...] attributed
    to the candidate, "ignored": [...], "fee": int, "sigops": int, "turnstile": str}."""
    blk = synth_block(ctx, raw)
    wp, cp = tmp("rwin.bin"), tmp("rctx.bin")
    wp.write_bytes(window_bytes([(ctx["height"], blk)]))
    cp.write_bytes(rules_ctx(ctx["height"], ctx["times"], spent, ctx["pools"] or {}))
    r = run(BIN_FN / "rules", wp, cp)
    wp.unlink(missing_ok=True)
    cp.unlink(missing_ok=True)
    out = {"fails": [], "ignored": [], "fee": None, "sigops": None, "verdict": None,
           "turnstile": "checked" if pools_known else "SKIPPED (pools not tracked in this state)"}
    for line in r.stdout.splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == "fail":
            rule = f[2]
            tagged = len(f) >= 5 and f[3] == "tx"
            if tagged:
                (out["fails"] if f[4] == "1" else out["ignored"]).append(" ".join(f[2:]))
            elif rule in TX_BLOCK_RULES or (rule.startswith("turnstile_") and pools_known):
                out["fails"].append(rule)
            else:
                out["ignored"].append(rule)
        elif f[0] == "fees":
            out["fee"], out["sigops"] = int(f[2]), int(f[4])
        elif f[0] == "verdict":
            out["verdict"] = f[2]
        elif f[0] == "skip":
            out["ignored"].append(" ".join(f[2:]))
    if out["verdict"] is None:
        raise RuntimeError(f"bin/rules gave no verdict: {r.stderr.strip()[-300:]!r}")
    return out


# ------------------------------------------------------------------ verifier hooks

def follow_ctx(spent):
    amounts = b"".join(struct.pack("<q", v) for v, _ in spent)
    scripts = b"".join(cs(len(s)) + bytes(s) for _, s in spent)
    return struct.pack("<I", len(amounts)) + amounts + struct.pack("<I", len(scripts)) + scripts


def hook_names(t):
    out = []
    if t["ins"]:
        out.append("transparent")
    if t["sap"] or t["js"]:
        out.append("sapling")
    if t["orch"] or t["iw"]:
        out.append("orchard")
    return out


def run_hooks(items, height):
    """items: [(key, raw, txdict, spent [(value, script)])]. Every hook a tx needs runs on it.
    Returns {key: {"hooks": {name: "PASS" | "FAIL ..." | "SKIPPED (component pending)"}}}."""
    res = {k: {} for k, _, _, _ in items}
    for name in HOOK_NAMES:
        mine = [(k, raw, t, sp) for k, raw, t, sp in items if name in hook_names(t)]
        if not mine:
            continue
        exe = HOOKS / name
        if not (exe.exists() and os.access(exe, os.X_OK)):
            for k, *_ in mine:
                res[k][name] = "SKIPPED (component pending)"
            continue
        d = tmp(f"hooks_{name}")
        d.mkdir(parents=True, exist_ok=True)
        lst = []
        for idx, (k, raw, t, sp) in enumerate(mine):
            base = d / f"{height}_{idx + 1}"
            base.with_suffix(".tx").write_bytes(raw)
            base.with_suffix(".ctx").write_bytes(follow_ctx(sp))
            base.with_suffix(".json").write_text(json.dumps({"height": height, "txidx": idx + 1, "txid": t["txid"],
                                                             "version": t["v"], "branch_id": t["br"]}))
            lst.append(str(base))
        (d / "list.txt").write_text("\n".join(lst) + "\n")
        r = subprocess.run([str(exe), str(d / "list.txt")], capture_output=True, text=True)
        got = {int(i): (v, rest) for _h, i, v, rest in
               re.findall(r"^verdict (\d+) (\d+) (PASS|FAIL) ?(.*)$", r.stdout, re.M)}
        for idx, (k, *_rest) in enumerate(mine):
            v = got.get(idx + 1)
            res[k][name] = ("PASS" if v[0] == "PASS" else f"FAIL {v[1]}") if v else \
                f"FAIL no verdict (exit {r.returncode}: {r.stderr.strip()[-120:]!r})"
        for p in d.iterdir():
            p.unlink()
        d.rmdir()
    return res
