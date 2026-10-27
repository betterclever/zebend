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
BEND_TIMEOUT = int(os.environ.get("ZEBEND_BEND_TIMEOUT", 900))  # s per blockdelta part (<= 8 MB / 400 blocks)
VERIFIER_RETRIES = 3   # a window whose verifier gave no verdict (timeout, crash) is retried, not failed


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class Fail(Exception):
    pass


def load_checkpoints():
    return {int(h): x for h, x in (l.split() for l in CHECKPOINTS.read_text().splitlines() if l.strip())}


# ------------------------------------------------------------------ spool

_SPOOL_INDEX = {}  # chunk path -> (size, [(height, offset, length)])


def _chunk_index(p):
    size = p.stat().st_size
    got = _SPOOL_INDEX.get(p)
    if got and got[0] == size:
        return got[1]
    recs = []
    with open(p, "rb") as f:
        off = 0
        while off + 8 <= size:
            f.seek(off)
            h, n = struct.unpack("<II", f.read(8))
            recs.append((h, off + 8, n))
            off += 8 + n
    _SPOOL_INDEX[p] = (size, recs)
    return recs


def spool_records(after, max_blocks, max_bytes):
    """Next contiguous blocks after height `after`, from complete spool chunks.
    Returns (records [(height, raw)], chunk files fully consumed by this window).
    Each chunk's record headers are indexed once; chunks entirely below the window are not
    read again (with --keep-spool the spool holds every chunk since genesis)."""
    files = sorted(SPOOL.glob("*.blk"), key=lambda p: int(p.stem))
    out, size, used, want = [], 0, [], after + 1
    for p in files:
        try:
            idx = _chunk_index(p)
        except FileNotFoundError:  # deleted after its window committed
            continue
        if not idx or idx[-1][0] < want:
            continue  # nothing at or above the window's start
        take = []
        whole, last = True, None
        for h, off, n in idx:
            if h == want and len(out) + len(take) < max_blocks and size < max_bytes:
                take.append((h, off, n))
                size += n
                want += 1
            elif h >= want:
                whole = False
            last = h
        if take:
            with open(p, "rb") as f:
                for h, off, n in take:
                    f.seek(off)
                    out.append((h, f.read(n)))
        if last is not None and last < want:
            used.append(p)  # everything in this chunk is at or below the window's end
        if not whole or len(out) >= max_blocks or size >= max_bytes:
            break
        if last is not None and last >= want:  # gap: wait for the downloader
            break
    return out, used


# ------------------------------------------------------------------ Bend extraction

def window_file(path, recs):
    last = headers.last_height()
    with open(path, "wb") as f:
        for h, raw in recs:
            exp = headers.header(h) if 1 <= h <= last else bytes(HDR)
            f.write(struct.pack("<I", h) + exp + struct.pack("<I", len(raw)) + raw)


def run_blockdelta(recs, jobs, tag, ex=None):
    """Split the window into ~equal-byte parts, one blockdelta process each, in parallel
    (on the shared Bend executor `ex` when given)."""
    parts, cur, size = [], [], 0
    target = max(1, sum(len(r) for _, r in recs) // jobs + 1)
    for rec in recs:
        cur.append(rec)
        size += len(rec[1])
        if size >= min(target, 8 << 20) or len(cur) >= 400:
            parts.append(cur)
            cur, size = [], 0
    if cur:
        parts.append(cur)
    WORK.mkdir(exist_ok=True)

    def one(k):
        p = WORK / f"win_{os.getpid()}_{tag}_{k}.bin"
        window_file(p, parts[k])
        for _ in range(3):  # empty output (a known rare Bend runtime issue) or a hang is rerun
            try:
                r = subprocess.run([str(BIN / "blockdelta"), str(p)], capture_output=True, text=True,
                                   timeout=BEND_TIMEOUT)
            except subprocess.TimeoutExpired:
                r = subprocess.CompletedProcess([], -9, "", f"blockdelta timed out after {BEND_TIMEOUT} s")
                continue
            if r.stdout.strip():
                break
        p.unlink(missing_ok=True)
        return parse_delta(r.stdout), r.stderr

    if ex is None:
        with ThreadPoolExecutor(jobs) as ex1:
            outs = list(ex1.map(one, range(len(parts))))
    else:
        outs = list(ex.map(one, range(len(parts))))
    blocks = []
    for (got, err), part in zip(outs, parts):
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
            # gated: blockdelta's zcash/wire validator accepted this block (else it prints INVALID)
            b = {"height": int(f[1]), "gated": True, "hash": f[2], "prev": f[3], "time": int(kv["time"]), "bits": kv["bits"],
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


def _follow_roots():
    """Follow's committed Ironwood roots: {root: height} and follow's committed (height, hash).
    Only the first tip.json["roots_bytes"] bytes of roots.txt are committed (follow appends
    roots.txt before it replaces tip.json, and truncates the excess on restart), so a
    half-written line or a root of an abandoned window is never read. Re-read on every miss:
    a cache that is never invalidated kept roots of a branch follow had dropped (audit F3)."""
    fs = Path(os.environ.get("ZEBEND_FOLLOW_STATE", HERE.parent / "follow/state"))
    try:
        tip = json.loads((fs / "tip.json").read_text())
        with open(fs / "roots.txt", "rb") as f:
            data = f.read(int(tip["roots_bytes"]))
    except (OSError, ValueError, KeyError):
        return {}, None
    roots = {}
    for l in data.decode(errors="replace").splitlines():
        p = l.split()
        if len(p) == 3:
            roots.setdefault(p[2], int(p[0]))
    return roots, (int(tip["height"]), tip.get("hash"))


def anchor_checks(full, st, log, idx=None):
    """Each shielded bundle's anchor must be a tree root after a strictly earlier block.

    Ironwood: roots from a Bend-computed tree: the instance's snapshot
    (<state>/ironwood_roots.txt, a copy of node/follow/state/roots.txt) plus follow's committed live
    roots, re-read on a miss. An anchor that is not a known root fails only if follow has
    committed a block at or above h-1 ON THE SAME CHAIN as ours (its tip hash equals our
    verified header hash at that height); otherwise follow is behind or on another branch and
    the anchor is SKIPPED (reported). Orchard, Sapling, Sprout anchors: SKIPPED (tree builders
    pending) and reported as such."""
    p = st.dir / "ironwood_roots.txt"
    if not _ROOTS:
        if p.exists():
            for l in p.read_text().splitlines():
                q = l.split()
                if len(q) == 3:
                    _ROOTS.setdefault(q[2], int(q[0]))
        _ROOTS.update(_follow_roots()[0])  # genesis instance: no snapshot, follow's roots still apply
    skipped = {"orchard": 0, "sapling": 0, "sprout": 0}
    checked = 0
    for b in full:
        for t in b["txs"]:
            for a in t["anchors"]["ironwood"]:
                h = b["height"]
                if a not in _ROOTS or _ROOTS[a] >= h:
                    fresh, ftip = _follow_roots()
                    for r, rh in fresh.items():  # follow's committed view wins over the cache
                        _ROOTS[r] = rh
                    # same chain: follow's tip hash is our verified hash at that height (follow ahead of
                    # our verified headers: its chain is the one tiphdr is about to extend; trusted)
                    on_chain = ftip is not None and (idx is None or ftip[0] >= idx.n or idx.display(ftip[0]) == ftip[1])
                    if a not in _ROOTS or _ROOTS[a] >= h:
                        if ftip is None or ftip[0] < h - 1 or not on_chain:
                            k = "ironwood (follow behind or on another branch)"
                            skipped[k] = skipped.get(k, 0) + 1
                            continue
                        raise Fail(f"block {h} tx {t['txid']}: Ironwood anchor {a[:16]} is not a root of an earlier block "
                                   f"(follow committed tip {ftip[0]}, same chain)")
                checked += 1
            for pool in ("orchard", "sapling", "sprout"):
                skipped[pool] += len(set(t["anchors"][pool]))
    sk = ", ".join(f"{k} {v}" for k, v in skipped.items() if v)
    log(f"  anchors: Ironwood {checked}/{checked} PASS" + (f"; SKIPPED: {sk}" if sk else ""))


# ------------------------------------------------------------------ main loop

def prepare(after, args, last_cp, ex):
    """Read the next window after height `after` from the spool and run blockdelta on it.
    Runs in a background thread while the previous window's rules and state commit run."""
    recs, used = spool_records(after, args.window, args.window_mb << 20)
    if args.to is not None:
        recs = [r for r in recs if r[0] <= args.to]
    if recs and recs[0][0] <= last_cp < recs[-1][0]:
        recs = [r for r in recs if r[0] <= last_cp]  # never mix checkpointed and fully validated blocks
        used = []
    if not recs:
        return recs, used, [], 0.0
    tw = time.time()
    blocks = run_blockdelta(recs, args.jobs, recs[0][0], ex)
    return recs, used, blocks, time.time() - tw


_STOP = []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--to", type=int, default=None)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 8) - 2),
                    help="Bend processes at a time (blockdelta and bin/rules parts)")
    ap.add_argument("--window", type=int, default=2000, help="max blocks per committed window")
    ap.add_argument("--window-mb", type=int, default=96)
    ap.add_argument("--once", action="store_true", help="one window, then exit")
    ap.add_argument("--assumed-start", type=int, default=None,
                    help="fallback mode: start an EMPTY state at this height; spent outputs older than it come "
                         "from the lightwalletd oracle, checked by Bend txids (assumed.py). Not genesis-verified.")
    ap.add_argument("--keep-spool", action="store_true", help="do not delete consumed spool chunks (re-sync tests)")
    ap.add_argument("--commit-mb", type=int, default=1,
                    help="commit group size: windows are committed together, ONE transaction per group of about "
                         "this many MB of blocks (or 4M UTXO changes, or --commit-secs); a crash resumes at the "
                         "last committed group")
    ap.add_argument("--commit-secs", type=int, default=300, help="commit a group at least this often")
    ap.add_argument("--writer-cache-mb", type=int, default=2048, help="SQLite page cache of the writer process")
    ap.add_argument("--addr-index", choices=["defer", "keep"], default="defer",
                    help="defer: below the last checkpoint the RPC-only address index is not maintained; it is "
                         "rebuilt from the UTXO set before the first fully validated window")
    args = ap.parse_args()
    import signal  # SIGTERM/SIGINT: finish (or drop) the current window, then exit at a window boundary
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: (_STOP.append(1), log("stop requested: exiting after this window")))
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
    if args.addr_index == "defer" and st.addr_index and tip["height"] < last_cp:
        log("address index: deferred until the last checkpoint (emptied now, rebuilt from the UTXO set later)")
        st.defer_addr_index()
    log(f"sync: state tip {tip['height']}, last checkpoint {last_cp}, verified headers to {idx.n - 1}, "
        f"{args.jobs} Bend jobs")
    import rules  # the Bend consensus rules engine (bin/rules) + verifier hooks
    # Three overlapping stages: extraction of window k+1 (blockdelta), checks + rules + resolution
    # of window k (this thread), and the state writer process, which writes each resolved window
    # into the open transaction of the current commit group. A group (windows up to --commit-mb)
    # is ONE SQLite transaction; groups commit in order. Windows are resolved against the
    # committed state plus the overlays of the groups not committed yet (Store.pending).
    ex = ThreadPoolExecutor(args.jobs)    # blockdelta parts (extraction of the next window) run here
    # bin/rules parts get their own pool: they are on the critical path of the window being
    # checked and short (~0.2 s each since --gated), so they must not queue behind the next
    # window's blockdelta parts (measured: 2 s of a 4.3 s spam window was that wait).
    ex_rules = ThreadPoolExecutor(args.jobs)
    prep = ThreadPoolExecutor(1)          # extraction of the next window
    wr = S.Writer(STATE, cache_mb=args.writer_cache_mb)
    t0, done, nbytes, last_log = time.time(), 0, 0, 0
    nxt = None
    group = S.new_group()   # windows resolved since the last commit (sent to the writer)
    inflight = None         # the group whose commit the writer is finishing
    st.pending = [group]
    pools_cur = st.get("pools")  # value pools after the last resolved window (None: not tracked)
    audit_n = st.get("audit_disagreements", 0)
    t_commit = 0.0

    def finish():
        """Wait for the group in flight to be committed; then its spool chunks can go."""
        nonlocal inflight, t_commit
        if inflight is None:
            return
        g, inflight = inflight, None
        try:
            t_commit = wr.result()  # a StateError of the commit surfaces here (group not committed)
        finally:
            st.pending = [x for x in st.pending if x is not g]
        ctip = st.tip()["height"]
        for p in ([] if args.keep_spool else g["used"]):
            ix = _chunk_index(p)  # delete a chunk only once every block in it is committed
            if ix and ix[-1][0] <= ctip:
                p.unlink()
                _SPOOL_INDEX.pop(p, None)
        log(f"committed tip {ctip}: {g['n']} windows, {g['bytes'] / 1e6:.0f} MB in one transaction "
            f"(writer {t_commit:.1f} s)")

    def flush():
        """End the current group: commit it (asynchronously; at most one group in flight)."""
        nonlocal group, inflight
        if not group["n"]:
            return
        finish()
        wr.commit(group["last"], group["hash"], group["extra"])
        inflight, group = group, S.new_group()
        st.pending = [inflight, group]

    def drain():
        flush()
        finish()

    try:
        while not _STOP:
            if args.to is not None and tip["height"] >= args.to:
                break
            idx = headers.Index(HDRDIR / "hashes.bin")  # reopened: tiphdr.py extends (or, on a reorg, cuts) it
            if tip["height"] >= 0 and (tip["height"] >= idx.n or idx.display(tip["height"]) != tip["hash"]):
                if nxt is not None:  # the prepared window may belong to the abandoned branch
                    try:
                        nxt[1].result()
                    except Exception:
                        pass
                    nxt = None
                drain()
                h = min(tip["height"], idx.n - 1)
                while h >= 0:
                    r = st.rdb.execute("SELECT hash FROM blk WHERE height=?", (h,)).fetchone()
                    if r and r[0].hex() == idx.display(h):
                        break
                    h -= 1
                log(f"REORG: tip {tip['height']} is no longer on the verified header chain; rolling back to {h}")
                st.rollback_to(h)
                tip = st.tip()
                pools_cur = st.get("pools")
                for p in SPOOL.glob("*.blk"):  # blocks of the abandoned branch
                    p.unlink()
                continue
            if nxt is None or nxt[0] != tip["height"]:
                nxt = (tip["height"], prep.submit(prepare, tip["height"], args, last_cp, ex))
            tw = time.time()
            recs, used, blocks, t_bend = nxt[1].result()
            t_wait = time.time() - tw
            nxt = None
            if not recs:
                drain()
                if args.once:
                    break
                time.sleep(5)
                continue
            if not (args.to is not None and recs[-1][0] >= args.to) and not args.once:
                nxt = (recs[-1][0], prep.submit(prepare, recs[-1][0], args, last_cp, ex))  # overlap: next window
            tr = time.time()
            checkpoint_checks(blocks, idx, cps, tip)
            st.new_window()
            if assumed_mode:
                drain()  # prefill writes to the store: no group open
                while True:  # the oracle is a network service: wait for it, never exit the node
                    try:
                        n_or = assumed.prefill(blocks, st, log)
                        break
                    except ConnectionError as e:
                        log(f"  oracle unavailable ({e}); retrying in 60 s")
                        time.sleep(60)
                        if _STOP:
                            raise
                if n_or:
                    log(f"  {n_or} spent outputs from before the start height taken from the oracle (Bend-checked txids)")
            # every spent output of the window not created inside it: one sorted batch lookup,
            # shared by the rules engine (st.utxo) and the state resolution
            made = set()
            want = []
            for b in blocks:
                for t in b["txs"]:
                    for (ptxid, vout, _seq) in t["ins"]:
                        if (ptxid, vout) not in made:
                            want.append(S.op_key(ptxid, vout))
                    for (k, _v, _s) in t["outs"]:
                        made.add((t["txid"], k))
            st.prefetch(want)
            t_pre = time.time() - tr
            full = [b for b in blocks if b["height"] > last_cp]
            if full:
                if not st.addr_index:
                    drain()
                    ta = time.time()
                    st.build_addr_index()
                    log(f"  address index rebuilt from the UTXO set ({time.time() - ta:.0f} s)")
                anchor_checks(full, st, log, idx)
            raw = dict(recs)
            cp_part = [b for b in blocks if b["height"] <= last_cp]
            extra = {}
            if cp_part:
                # Checkpointed blocks: the rules run in audit mode. They decide nothing (the checkpoint
                # does) but track the value pools from genesis, and any disagreement with the
                # canonical chain is a bug in our rules: logged and counted, never hidden.
                extra = rules.validate(cp_part, st, raw, log, mode="audit", pools=pools_cur, jobs=args.jobs, ex=ex_rules)
                dis = extra["rules"]["disagreements"]
                if dis:
                    audit_n += len(dis)
                    extra["audit_disagreements"] = audit_n
                    log(f"  AUDIT: rules disagree with checkpointed blocks: {dis[:3]} (total {audit_n})")
            if full:
                for attempt in range(VERIFIER_RETRIES + 1):
                    try:
                        e2 = rules.validate(full, st, raw, log, mode="full", pools=extra.get("pools", pools_cur),
                                            jobs=args.jobs, ex=ex_rules)
                        break
                    except rules.VerifierError as e:  # no verdict is not a verdict: retry, then halt
                        if attempt == VERIFIER_RETRIES:
                            raise
                        log(f"  verifier error ({e}); retrying the window ({attempt + 1}/{VERIFIER_RETRIES})")
                        time.sleep(10 * (attempt + 1))
                rs = e2["rules"]
                log(f"  full validation {full[0]['height']}..{full[-1]['height']}: every consensus rule PASS "
                    f"(turnstile {rs['turnstile']}); hooks: {rs['hooks']}")
                extra.update(e2)
            for b in blocks:  # per-block pools go into the block index (rollback restores them)
                pb = extra.get("pools_by_height", {})
                if b["height"] in pb:
                    b["info"] = {"pools": pb[b["height"]]}
            extra.pop("pools_by_height", None)
            t_rules = time.time() - tr
            ta = time.time()
            ws = st.resolve_window(blocks)  # pass 1 (raises StateError on a missing input etc.)
            wbytes = sum(b["size"] for b in blocks)
            S.merge_window(group, ws, wbytes)
            group.setdefault("t0", time.time())
            group["used"] += used
            group["extra"].update(extra)
            wr.apply(ws)
            t_resolve = time.time() - ta
            if "pools" in extra:
                pools_cur = extra["pools"]
            tip = {"height": blocks[-1]["height"], "hash": blocks[-1]["hash"]}
            done += len(blocks)
            nbytes += wbytes
            if (group["bytes"] >= args.commit_mb << 20 or len(group["spent"]) + len(group["created"]) > 4_000_000
                    or time.time() - group["t0"] > args.commit_secs
                    or args.once or (args.to is not None and tip["height"] >= args.to)):
                flush()
            el = time.time() - t0
            if time.time() - last_log > 30 or args.once or args.to is not None:
                log(f"tip {tip['height']}  window {len(blocks)} blocks {wbytes / 1e6:.1f} MB in {time.time() - tw:.1f} s "
                    f"(waited for bend {t_wait:.1f} s [bend {t_bend:.1f} s, overlapped]; lookups {t_pre:.1f} s, "
                    f"rules {t_rules - t_pre:.1f} s; resolve {t_resolve:.1f} s)  avg {done / el:.1f} blocks/s "
                    f"{nbytes / el / 1e6:.2f} MB/s  rules parts {rules.STATS['parts']} reruns {rules.STATS['reruns']}")
                last_log = time.time()
            if args.once:
                break
        drain()
    finally:
        if nxt is not None:
            nxt[1].cancel()
        prep.shutdown(wait=True, cancel_futures=True)
        if inflight is not None:  # leaving on an error: let the group in flight finish committing
            try:
                finish()
            except Exception:
                pass
        wr.close()  # an open (uncommitted) group is rolled back
        ex.shutdown(wait=True)
        ex_rules.shutdown(wait=True)
    el = time.time() - t0
    if done:
        log(f"stopped at committed tip {st.tip()['height']}: {done} blocks {nbytes / 1e6:.1f} MB in {el:.0f} s, "
            f"{done / el:.1f} blocks/s {nbytes / el / 1e6:.2f} MB/s")
    st.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Fail, S.StateError) as e:  # rules.RuleFail is a StateError
        log(f"FAIL: {e}")
        log("  window NOT committed; state stays at the last committed tip")
        sys.exit(1)
