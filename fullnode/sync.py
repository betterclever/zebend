#!/usr/bin/env python3
"""zebend fullnode sync: build the chain state from genesis, streaming, without keeping blocks.

Pipeline per window (blocks from the spool that download.py fills):
  1. bin/blockdelta (Bend) parses every block of every era: block hash, header == the
     verified header at that height, merkle root over the txids it computes (SHA-256d for
     v1-v4, ZIP 244 for v5/v6), and each transaction's state delta (inputs, outputs,
     Sprout/Sapling/Orchard/Ironwood nullifiers, note commitments, anchors, value balances).
  2. Checkpoint rules (every height): block hash == the Bend-verified header-chain hash at
     that height (state/hdr/hashes.bin, which equals all 14,444 Zebra checkpoints), header
     bytes == the verified header (Equihash, target, links verified in Bend), merkle MATCH.
  3. Full validation above the last checkpoint (rules.py): the Bend consensus rules engine
     and the per-tx verifier hooks (transparent, Sapling, Orchard/Ironwood); a hook whose
     component has not landed is reported SKIPPED (component pending), never PASS.
  4. State (store.py): UTXO set, nullifier sets, tx index, block index, leaf logs for the note
     commitment trees, undo data; one atomic commit per window. Then the spool chunk is deleted.

usage: sync.py [--to H] [--jobs N] [--window N] [--once]
"""
import argparse, json, os, re, struct, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers, store as S

BIN = HERE / "bin"
STATE = Path(os.environ.get("ZEBEND_STATE", HERE / "state"))  # instance state dir
HDRDIR = HERE / "state/hdr"  # Bend-verified header-hash index, shared by instances
SPOOL = Path(os.environ.get("ZEBEND_SPOOL", HERE / "spool"))
WORK = HERE / "work"
CHECKPOINTS = HERE / "checkpoints/main-checkpoints.txt"
HDR = 1487


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class Fail(Exception):
    pass


def load_checkpoints():
    return {int(h): x for h, x in (l.split() for l in CHECKPOINTS.read_text().splitlines() if l.strip())}


# ------------------------------------------------------------------ spool

def spool_records(after, max_blocks, max_bytes):
    """Next contiguous blocks after height `after`, from complete spool chunks.
    Returns (records [(height, raw)], chunk files fully consumed by this window)."""
    files = sorted(SPOOL.glob("*.blk"), key=lambda p: int(p.stem))
    out, size, used, want = [], 0, [], after + 1
    for p in files:
        data = p.read_bytes()
        i, last = 0, None
        whole = True
        while i < len(data):
            h, n = struct.unpack_from("<II", data, i)
            if h == want and len(out) < max_blocks and size < max_bytes:
                out.append((h, data[i + 8:i + 8 + n]))
                size += n
                want += 1
            elif h >= want:
                whole = False
            last = h
            i += 8 + n
        if last is not None and last < want:
            used.append(p)  # everything in this chunk is at or below the window's end
        if not whole or len(out) >= max_blocks or size >= max_bytes:
            break
        if last is not None and last >= want:  # gap: wait for the downloader
            break
    return out, used


# ------------------------------------------------------------------ Bend extraction

def window_file(path, recs):
    with open(path, "wb") as f:
        for h, raw in recs:
            exp = headers.header(h) if 1 <= h <= headers.last_height() else bytes(HDR)
            f.write(struct.pack("<I", h) + exp + struct.pack("<I", len(raw)) + raw)


def run_blockdelta(recs, jobs, tag):
    """Split the window into ~equal-byte parts, one blockdelta process each, in parallel."""
    parts, cur, size = [], [], 0
    target = max(1, sum(len(r) for _, r in recs) // jobs + 1)
    for rec in recs:
        cur.append(rec)
        size += len(rec[1])
        if size >= min(target, 24 << 20) or len(cur) >= 400:
            parts.append(cur)
            cur, size = [], 0
    if cur:
        parts.append(cur)
    WORK.mkdir(exist_ok=True)

    def one(k):
        p = WORK / f"win_{os.getpid()}_{tag}_{k}.bin"
        window_file(p, parts[k])
        for _ in range(3):  # empty output (a known rare Bend runtime issue) is rerun
            r = subprocess.run([str(BIN / "blockdelta"), str(p)], capture_output=True, text=True)
            if r.stdout.strip():
                break
        p.unlink(missing_ok=True)
        return r.stdout, r.stderr

    with ThreadPoolExecutor(jobs) as ex:
        outs = list(ex.map(one, range(len(parts))))
    blocks = []
    for (out, err), part in zip(outs, parts):
        got = parse_delta(out)
        if [b["height"] for b in got] != [h for h, _ in part]:
            raise Fail(f"blockdelta on {part[0][0]}..{part[-1][0]} returned blocks "
                       f"{[b['height'] for b in got][:3]}...; stderr {err.strip()[-300:]!r}")
        blocks += got
    return blocks


def parse_delta(text):
    """Bend's printed lines -> dicts. Only moves fields; computes nothing."""
    blocks, b, t = [], None, None
    for line in text.splitlines():
        f = line.split()
        if not f:
            continue
        k = f[0]
        if k == "block":
            if len(f) > 2 and f[2] == "INVALID":
                blocks.append({"height": int(f[1]), "invalid": " ".join(f[2:]), "txs": [], "leaves": {}})
                b = None
                continue
            kv = dict(zip(f[4::2], f[5::2]))
            b = {"height": int(f[1]), "hash": f[2], "prev": f[3], "time": int(kv["time"]), "bits": kv["bits"],
                 "size": int(kv["size"]), "ntx": int(kv["txs"]), "header": kv["header"], "merkle": kv["merkle"],
                 "txs": [], "leaves": {p: [] for p in S.POOLS}}
            blocks.append(b)
        elif k == "tx":
            kv = dict(zip(f[3::2], f[4::2]))
            t = {"i": int(f[1]), "txid": f[2], "v": int(kv["v"]), "ow": kv.get("ow") == "1", "grp": kv.get("grp"),
                 "br": kv.get("br"), "lock": int(kv.get("lock", 0)), "exp": int(kv.get("exp", 0)),
                 "size": int(kv["size"]), "sigops": int(kv["sigops"]) if "sigops" in kv else None,
                 "cb": False, "cbscript": None, "ins": [], "outs": [], "js": [], "sap": None,
                 "orch": None, "iw": None, "nfs": {p: [] for p in S.POOLS}, "anchors": {p: [] for p in S.POOLS}}
            b["txs"].append(t)
        elif k == "sigops":
            t["sigops"] = int(f[1])
        elif k == "cb":
            t["cb"], t["cbscript"] = True, (f[1] if len(f) > 2 else "")
        elif k == "in":
            t["ins"].append((f[2], int(f[3]), int(f[4])))
        elif k == "out":
            t["outs"].append((int(f[1]), int(f[2]), bytes.fromhex(f[3]) if len(f) > 3 else b""))
        elif k == "js":
            t["js"].append({"vpub_old": int(f[1]), "vpub_new": int(f[2]), "anchor": f[3]})
            t["nfs"]["sprout"] += [f[4], f[5]]
            t["anchors"]["sprout"].append(f[3])
            b["leaves"]["sprout"] += [f[6], f[7]]
        elif k == "sap":
            t["sap"] = {"vb": int(f[1]), "nspends": int(f[2]), "noutputs": int(f[3])}
        elif k == "ss":
            t["anchors"]["sapling"].append(f[1])
            t["nfs"]["sapling"].append(f[2])
        elif k == "so":
            b["leaves"]["sapling"].append(f[1])
        elif k in ("orch", "iw"):
            pool = "orchard" if k == "orch" else "ironwood"
            t["orch" if k == "orch" else "iw"] = {"vb": int(f[1]), "anchor": f[2], "flags": f[3], "n": int(f[4])}
            t["anchors"][pool].append(f[2])
        elif k in ("oa", "ia"):
            pool = "orchard" if k == "oa" else "ironwood"
            t["nfs"][pool].append(f[1])
            b["leaves"][pool].append(f[2])
        elif k == "end":
            b = t = None
    return blocks


# ------------------------------------------------------------------ checkpoint rules

def checkpoint_checks(blocks, idx, cps, tip):
    """The rules every block passes, below and above the last checkpoint."""
    prev = tip["hash"]
    for b in blocks:
        h = b["height"]
        if "invalid" in b:
            raise Fail(f"block {h}: {b['invalid']}")
        if h == 0:
            ok_hdr = b["hash"] == cps[0]  # genesis: no verified-header file entry; its hash is checkpoint 0
        else:
            ok_hdr = b["header"] == "MATCH"
        if not ok_hdr:
            raise Fail(f"block {h}: header is not the verified header at this height")
        if b["hash"] != idx.display(h):
            raise Fail(f"block {h}: hash {b['hash']} != verified chain hash {idx.display(h)}")
        if h in cps and cps[h] != b["hash"]:
            raise Fail(f"block {h}: checkpoint mismatch")
        if b["merkle"] != "MATCH":
            raise Fail(f"block {h}: merkle root MISMATCH")
        if h > 0 and b["prev"] != prev:
            raise Fail(f"block {h}: does not link to the tip {prev}")
        if len(b["txs"]) != b["ntx"] or not b["txs"] or not b["txs"][0]["cb"]:
            raise Fail(f"block {h}: transaction list incomplete or first tx is not a coinbase")
        prev = b["hash"]


# ------------------------------------------------------------------ anchors

_ROOTS = {}


def anchor_checks(full, st, log):
    """Each shielded bundle's anchor must be a tree root after a strictly earlier block.

    Ironwood: roots from a Bend-computed tree. Until this node's own Orchard/Ironwood tree
    builder runs, the root set is a snapshot of follow's Bend-computed Ironwood roots
    (<state>/ironwood_roots.txt, copied from follow/state/roots.txt: every root since
    activation, computed by follow/bin/frontier and cross-checked with the chain). Orchard,
    Sapling, Sprout anchors: SKIPPED (tree builders pending) and reported as such."""
    p = st.dir / "ironwood_roots.txt"
    if not _ROOTS and p.exists():
        for l in p.read_text().splitlines():
            h, _, r = l.split()
            _ROOTS.setdefault(r, int(h))
    skipped = {"orchard": 0, "sapling": 0, "sprout": 0}
    checked = 0
    for b in full:
        for t in b["txs"]:
            for a in t["anchors"]["ironwood"]:
                if not _ROOTS:
                    skipped.setdefault("ironwood", 0)
                    skipped["ironwood"] += 1
                    continue
                if a not in _ROOTS:  # refresh from follow's live Bend-computed roots (read-only)
                    fr = HERE.parent / "follow/state/roots.txt"
                    for l in fr.read_text().splitlines():
                        hh, _, r = l.split()
                        _ROOTS.setdefault(r, int(hh))
                    ftip = max(_ROOTS.values())
                    if a not in _ROOTS and ftip < b["height"] - 1:
                        skipped.setdefault("ironwood (roots not computed yet)", 0)
                        skipped["ironwood (roots not computed yet)"] += 1
                        continue
                if a not in _ROOTS or _ROOTS[a] >= b["height"]:
                    raise Fail(f"block {b['height']} tx {t['txid']}: Ironwood anchor {a[:16]} is not a root of an earlier block")
                checked += 1
            for pool in ("orchard", "sapling", "sprout"):
                skipped[pool] += len(set(t["anchors"][pool]))
    log(f"  anchors: Ironwood {checked}/{checked} PASS; SKIPPED (tree builder pending): "
        + ", ".join(f"{k} {v}" for k, v in skipped.items() if v))


# ------------------------------------------------------------------ main loop

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--to", type=int, default=None)
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--window", type=int, default=2000, help="max blocks per committed window")
    ap.add_argument("--window-mb", type=int, default=96)
    ap.add_argument("--once", action="store_true", help="one window, then exit")
    ap.add_argument("--assumed-start", type=int, default=None,
                    help="fallback mode: start an EMPTY state at this height; spent outputs older than it come "
                         "from the lightwalletd oracle, checked by Bend txids (assumed.py). Not genesis-verified.")
    ap.add_argument("--keep-spool", action="store_true", help="do not delete consumed spool chunks (re-sync tests)")
    args = ap.parse_args()
    st = S.Store(STATE)
    cps = load_checkpoints()
    last_cp = max(cps)
    hfile = HDRDIR / "hashes.bin"
    idx = headers.Index(hfile)
    tip = st.tip()
    if args.assumed_start is not None and tip["height"] < 0:
        a = args.assumed_start
        st.db.execute("BEGIN IMMEDIATE")
        st.put("tip", {"height": a - 1, "hash": idx.display(a - 1)})
        st.put("assumed_state", {"start": a, "note": "state starts empty at this height; older spent outputs "
                                 "from the lightwalletd oracle (Bend-checked txids); NOT genesis-verified"})
        st.db.execute("COMMIT")
        tip = st.tip()
    if tip["height"] < 0 and st.get("pools") is None and args.assumed_start is None:
        st.db.execute("BEGIN IMMEDIATE")  # genesis: every value pool starts at zero (tracked by bin/rules)
        st.put("pools", {n: 0 for n in ("sprout", "sapling", "orchard", "ironwood", "lockbox", "transparent")})
        st.db.execute("COMMIT")
    assumed_mode = st.get("assumed_state") is not None
    if assumed_mode:
        import assumed
        log(f"ASSUMED-STATE MODE from {st.get('assumed_state')['start']}: not genesis-verified")
    log(f"sync: state tip {tip['height']}, last checkpoint {last_cp}, verified headers to {idx.n - 1}")
    t0, done, nbytes, last_log = time.time(), 0, 0, 0
    while True:
        if args.to is not None and tip["height"] >= args.to:
            break
        idx = headers.Index(HDRDIR / "hashes.bin")  # reopened: tiphdr.py extends (or, on a reorg, cuts) it
        if tip["height"] >= 0 and (tip["height"] >= idx.n or idx.display(tip["height"]) != tip["hash"]):
            h = min(tip["height"], idx.n - 1)
            while h >= 0:
                r = st.db.execute("SELECT hash FROM blk WHERE height=?", (h,)).fetchone()
                if r and r[0].hex() == idx.display(h):
                    break
                h -= 1
            log(f"REORG: tip {tip['height']} is no longer on the verified header chain; rolling back to {h}")
            st.rollback_to(h)
            tip = st.tip()
            for p in SPOOL.glob("*.blk"):  # blocks of the abandoned branch
                p.unlink()
            continue
        recs, used = spool_records(tip["height"], args.window, args.window_mb << 20)
        if args.to is not None:
            recs = [r for r in recs if r[0] <= args.to]
        if recs and recs[0][0] <= last_cp < recs[-1][0]:
            recs = [r for r in recs if r[0] <= last_cp]  # never mix checkpointed and fully validated blocks
            used = []
        if not recs:
            if args.once:
                break
            time.sleep(5)
            continue
        tw = time.time()
        blocks = run_blockdelta(recs, args.jobs, recs[0][0])
        t_bend = time.time() - tw
        checkpoint_checks(blocks, idx, cps, tip)
        if assumed_mode:
            n_or = assumed.prefill(blocks, st, log)
            if n_or:
                log(f"  {n_or} spent outputs from before the start height taken from the oracle (Bend-checked txids)")
        full = [b for b in blocks if b["height"] > last_cp]
        if full:
            anchor_checks(full, st, log)
        import rules  # the Bend consensus rules engine (bin/rules) + verifier hooks
        raw = dict(recs)
        cp_part = [b for b in blocks if b["height"] <= last_cp]
        extra = {}
        if cp_part:
            # Checkpointed blocks: the rules run in audit mode. They decide nothing (the checkpoint
            # does) but track the value pools from genesis, and any disagreement with the
            # canonical chain is a bug in our rules: logged and counted, never hidden.
            extra = rules.validate(cp_part, st, raw, log, mode="audit")
            dis = extra["rules"]["disagreements"]
            if dis:
                n = st.get("audit_disagreements", 0) + len(dis)
                extra["audit_disagreements"] = n
                log(f"  AUDIT: rules disagree with checkpointed blocks: {dis[:3]} (total {n})")
        if full:
            e2 = rules.validate(full, st, raw, log, mode="full", pools=extra.get("pools", st.get("pools")))
            rs = e2["rules"]
            log(f"  full validation {full[0]['height']}..{full[-1]['height']}: every consensus rule PASS "
                f"(turnstile {rs['turnstile']}); hooks: {rs['hooks']}")
            extra.update(e2)
        for b in blocks:  # per-block pools go into the block index (rollback restores them)
            pb = extra.get("pools_by_height", {})
            if b["height"] in pb:
                b["info"] = {"pools": pb[b["height"]]}
        extra.pop("pools_by_height", None)
        ta = time.time()
        st.apply_window(blocks, extra_meta=extra)
        t_apply = time.time() - ta
        tip = st.tip()
        for p in ([] if args.keep_spool else used):
            if int(p.stem) <= tip["height"]:
                last_in = tip["height"]
                # delete a chunk only once every block in it is committed
                data_last = None
                with open(p, "rb") as f:
                    d = f.read()
                i = 0
                while i < len(d):
                    hh, n = struct.unpack_from("<II", d, i)
                    data_last = hh
                    i += 8 + n
                if data_last is not None and data_last <= last_in:
                    p.unlink()
        done += len(blocks)
        nbytes += sum(b["size"] for b in blocks)
        el = time.time() - t0
        if time.time() - last_log > 30 or args.once:
            log(f"tip {tip['height']}  window {len(blocks)} blocks {sum(b['size'] for b in blocks) / 1e6:.1f} MB "
                f"(bend {t_bend:.1f} s, state {t_apply:.1f} s)  avg {done / el:.1f} blocks/s {nbytes / el / 1e6:.2f} MB/s")
            last_log = time.time()
        if args.once:
            break
    st.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Fail, S.StateError) as e:  # rules.RuleFail is a StateError
        log(f"FAIL: {e}")
        log("  window NOT committed; state stays at the last committed tip")
        sys.exit(1)
