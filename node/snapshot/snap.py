"""Zebend state snapshots (assumeutxo-style): format, Bend digest, producer, consumer checks.

Python here moves bytes: it reads SQLite rows and leaf logs, writes length-prefixed records,
cuts files at record boundaries, runs Bend programs and compares what they print. Every hash
(the state digest, every Merkle node, every note commitment tree root) is computed in Bend:
  bin/snapdigest   SHA-256 Merkle trees over the sorted records + the final digest
  ../bin/sprout    Sprout tree (SHA256Compress, depth 29)       node/trees/sprout.bend
  bin/sapfront     Sapling tree (Pedersen, depth 32)            bend/sapfront.bend
  bin/sinfront     Orchard / Ironwood trees (Sinsemilla, d 32)  bend/sinfront.bend
See README.md for the format and the trust model.
"""
import json, os, shutil, sqlite3, struct, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
FULL = HERE.parent
sys.path.insert(0, str(FULL))
import store as S  # noqa: E402

BIN = HERE / "bin"
SNAPDIGEST = BIN / "snapdigest"
POOLS = S.POOLS                     # sprout, sapling, orchard, ironwood
TREE = {"sprout": (FULL / "bin/sprout", 29), "sapling": (BIN / "sapfront", 32),
        "orchard": (BIN / "sinfront", 32), "ironwood": (BIN / "sinfront", 32)}
# First height at which a pool can have notes (ZIP 205 Sapling, ZIP 252 NU5, NU6.3 Ironwood;
# the same heights rpc.py lists). Below it, a snapshot's frontier of that pool must be empty.
ACTIVATION = {"sprout": 0, "sapling": 419200, "orchard": 1687104, "ironwood": 3428143}
HEARTWOOD = 903000                  # from here on the header field at 68..100 is no longer
                                    # hashFinalSaplingRoot (ZIP 221 / ZIP 244 commitments)
CHUNK = 1 << 14                     # records per Bend leaf process (a power of two)
PART_MAX = 1 << 30                  # bytes per section part file (Bend's read_at takes a U32)
BLK_CONTEXT = 128                   # block-index rows kept below and at H
LEAF_BATCH = 1_000_000              # leaves per tree-tool run (its reader caps at 200 MB; bounds RSS)
CLONE_LEAVES = sys.platform == "darwin" and os.environ.get("ZEBEND_SNAP_CLONE_LEAVES", "1") != "0"
PTREE = os.environ.get("ZEBEND_SNAP_PTREE", "1") != "0"   # big trees: parallel segments (ptree.py)
PTREE_JOBS = int(os.environ.get("ZEBEND_SNAP_PTREE_JOBS", 14))
MAGIC = b"ZEBENDSNAP1\n"
VERSION = 1
SECTIONS = (["meta", "blk", "utxo"] + [f"nf.{p}" for p in POOLS] + ["frontier"]
            + [f"roots.{p}" for p in POOLS] + ["oracle_prevout"])
EXPORT_META = ["tip", "pools", "audit_disagreements", "assumed_state", "snapshot_sources"]


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class SnapError(Exception):
    pass


def cjson(v):
    """Canonical JSON bytes (sorted keys, no spaces): meta values in the snapshot."""
    return json.dumps(v, sort_keys=True, separators=(",", ":")).encode()


# ====================================================================== sections on disk

class SectionWriter:
    """Records (u32 LE length || payload) into part files <dir>/<name>.<k>.bin. Parts are cut
    only at multiples of CHUNK records, so every Bend chunk lies inside one part."""

    def __init__(self, d: Path, name: str):
        self.d, self.name = Path(d), name
        self.parts, self.count, self.f, self.cur_n, self.cur_b = [], 0, None, 0, 0
        self.last = None
        self._roll()

    def _roll(self):
        if self.f:
            self.f.close()
            self.parts.append({"count": self.cur_n, "bytes": self.cur_b})
        self.f = open(self.d / f"{self.name}.{len(self.parts)}.bin", "wb", buffering=8 << 20)
        self.cur_n = self.cur_b = 0

    def add(self, payload: bytes):
        self.f.write(struct.pack("<I", len(payload)))
        self.f.write(payload)
        self.cur_n += 1
        self.count += 1
        self.cur_b += 4 + len(payload)
        if self.cur_b >= PART_MAX and self.cur_n % CHUNK == 0:
            self._roll()

    def close(self):
        self.f.close()
        self.parts.append({"count": self.cur_n, "bytes": self.cur_b})
        self.f = None
        return {"name": self.name, "count": self.count, "bytes": sum(p["bytes"] for p in self.parts),
                "parts": self.parts}


def part_path(d, name, k):
    return Path(d) / f"{name}.{k}.bin"


def iter_records(path):
    """(offset, payload) of every record of a part file (moves bytes)."""
    with open(path, "rb") as f:
        buf = f.read()
    mv = memoryview(buf)
    i, n = 0, len(buf)
    while i < n:
        if i + 4 > n:
            raise SnapError(f"{path}: truncated record header at {i}")
        ln, = struct.unpack_from("<I", buf, i)
        if i + 4 + ln > n:
            raise SnapError(f"{path}: record at {i} runs past the end")
        yield i, mv[i + 4:i + 4 + ln]
        i += 4 + ln


def last_record(path):
    """Payload of the last record of a part file, with bounded memory (moves bytes)."""
    offs = record_offsets(path)
    with open(path, "rb") as f:
        f.seek(offs[-2] + 4)
        return f.read(offs[-1] - offs[-2] - 4)


def record_offsets(path):
    """Offsets of every record start in a part file, plus the end offset (moves bytes)."""
    from array import array
    offs = array("Q")
    with open(path, "rb") as f:
        buf = f.read()
    i, n = 0, len(buf)
    up = struct.unpack_from
    while i < n:
        offs.append(i)
        if i + 4 > n:
            raise SnapError(f"{path}: truncated record header at {i}")
        i += 4 + up("<I", buf, i)[0]
    if i != n:
        raise SnapError(f"{path}: last record runs past the end")
    offs.append(n)
    return offs


# ====================================================================== Bend digest

def _bend(args, tries=3):
    for _ in range(tries):  # an empty output (rare Bend runtime issue under load) is rerun
        r = subprocess.run([str(a) for a in args], capture_output=True, text=True)
        if r.stdout.strip():
            return r.stdout
    raise SnapError(f"Bend produced no output: {' '.join(map(str, args))[:200]} {r.stderr[-300:]}")


def _kv(out):
    d = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 2:
            d[f[0]] = f[1]
    return d


def section_root(d, sec, ex, work):
    """Bend: the section's Merkle root over its records, chunk by chunk in parallel, plus the
    strict-order check of every record against the one before it. Returns the root (hex)."""
    name = sec["name"]
    jobs, bounds = [], []
    for k, part in enumerate(sec["parts"]):
        p = part_path(d, name, k)
        if p.stat().st_size != part["bytes"]:
            raise SnapError(f"{p}: {p.stat().st_size} bytes, manifest says {part['bytes']}")
        offs = record_offsets(p)
        n = len(offs) - 1
        if n != part["count"]:
            raise SnapError(f"{p}: {n} records, manifest says {part['count']}")
        if k < len(sec["parts"]) - 1 and n % CHUNK:
            raise SnapError(f"{p}: a part that is not the last must hold whole chunks")
        for c in range(0, n, CHUNK):
            m = min(CHUNK, n - c)
            if c == 0:
                jobs.append((p, offs[0], offs[m] - offs[0], m, 0))
            else:  # context: the previous chunk's last record (order check across chunks)
                jobs.append((p, offs[c - 1], offs[c + m] - offs[c - 1], m, 1))
        if k > 0 and n:  # order across the part boundary: last record of part k-1, first of k
            bounds.append((part_path(d, name, k - 1), p))
    outs = list(ex.map(lambda j: _bend([SNAPDIGEST, "leaves", *j]), jobs))
    roots = []
    for j, out in zip(jobs, outs):
        kv = _kv(out)
        if kv.get("n") != str(j[3]) or kv.get("order") != "OK" or kv.get("exact") != "OK":
            raise SnapError(f"section {name}: Bend rejects the records at {j[0].name}+{j[1]}: "
                            f"n {kv.get('n')}/{j[3]} order {kv.get('order')} exact {kv.get('exact')}")
        roots.append(bytes.fromhex(kv["root"]))
    for a, b in bounds:
        last = last_record(a)   # not list(iter_records(a)): ~27M memoryviews of a 1 GiB nf part = GBs of RSS
        first = next(iter_records(b))[1].tobytes()
        tmp = work / f"bound_{name}.bin"
        tmp.write_bytes(struct.pack("<I", len(last)) + last + struct.pack("<I", len(first)) + first)
        kv = _kv(_bend([SNAPDIGEST, "leaves", tmp, 0, tmp.stat().st_size, 1, 1]))
        if kv.get("order") != "OK":
            raise SnapError(f"section {name}: records out of order across parts")
    nodes = work / f"nodes_{name}.bin"
    nodes.write_bytes(b"".join(roots))
    kv = _kv(_bend([SNAPDIGEST, "nodes", nodes, 0, len(roots) * 32, len(roots)]))
    return kv["root"]


def manifest_bytes(height, hash_hex, secs):
    """The bytes the final digest is the SHA-256 of (Bend): binds the height, the block hash and
    every section's name, record count and Merkle root, in the fixed section order."""
    b = bytearray(b"zebend-snapshot-v1\x00")
    b += struct.pack("<I", height) + bytes.fromhex(hash_hex)[::-1]
    b += struct.pack("<B", len(secs))
    for s in secs:
        nm = s["name"].encode()
        b += struct.pack("<B", len(nm)) + nm + struct.pack("<Q", s["count"]) + bytes.fromhex(s["root"])
    return bytes(b)


def digest_dir(d, man, jobs=16, work=None):
    """Bend-compute every section root and the state digest of the sections in directory d.
    Fills man['sections'][*]['root'] and returns the digest (hex)."""
    work = Path(work or d)
    with ThreadPoolExecutor(jobs) as ex:
        for s in man["sections"]:
            s["root"] = section_root(d, s, ex, work)
    mb = manifest_bytes(man["height"], man["hash"], man["sections"])
    mp = work / "manifest.bin"
    mp.write_bytes(mb)
    return _kv(_bend([SNAPDIGEST, "hash", mp, 0, len(mb)]))["hash"]


# ====================================================================== tree frontiers

def levels_text(levels):
    return "".join((l or "-") + "\n" for l in levels)


def run_tree(pool, levels_in, leaves: bytes, counts, work):
    """Push `leaves` (32 bytes each) in groups of `counts` onto the frontier `levels_in` with the
    pool's Bend tree program, in batches. Returns (roots after each group, levels out, empty root).
    A group of 0 leaves gives the root of the frontier as it stands."""
    tool, depth = TREE[pool]
    lv = list(levels_in)
    roots, empty = [], None
    i, off = 0, 0
    while True:
        j, n = i, 0
        while j < len(counts) and (n + counts[j] <= LEAF_BATCH or j == i):
            n += counts[j]
            j += 1
        fin, lf, cf, fout = (work / f"t_{pool}_{x}" for x in ("in.txt", "leaves.bin", "counts.bin", "out.txt"))
        fin.write_text(levels_text(lv))
        lf.write_bytes(leaves[off * 32:(off + n) * 32])
        cf.write_bytes(b"".join(struct.pack("<I", c) for c in counts[i:j]))
        out = _bend([tool, fin, lf, cf, fout])
        got = [l.split() for l in out.splitlines() if l.startswith("root ")]
        if len(got) != j - i:
            raise SnapError(f"{pool} tree: {len(got)} roots for {j - i} groups")
        roots += [g[3] for g in got]
        empty = _kv(out).get("empty_root")
        lv = [l.strip() if l.strip() != "-" else None for l in fout.read_text().splitlines()][:depth]
        if len(lv) != depth:
            raise SnapError(f"{pool} tree: frontier has {len(lv)} levels, expected {depth}")
        off += n
        i = j
        if i >= len(counts):
            break
    return roots, lv, empty


def frontier_ok(levels, size):
    """Structure: level i holds a node exactly when bit i of the tree size is set."""
    return all((levels[i] is not None) == bool((size >> i) & 1) for i in range(len(levels))) and \
        size < (1 << len(levels))


def enc_frontier(pool, fr):
    """frontier record: pool u8 | known u8 | depth u8 | size u64 | root 32 | per level 0 or 1||node."""
    depth = TREE[pool][1]
    if fr is None:
        return struct.pack("<BBB", POOLS.index(pool), 0, depth)
    b = bytearray(struct.pack("<BBBQ", POOLS.index(pool), 1, depth, fr["size"]) + bytes.fromhex(fr["root"]))
    for l in fr["levels"]:
        b += b"\x00" if l is None else b"\x01" + bytes.fromhex(l)
    return bytes(b)


def dec_frontier(rec):
    pid, known, depth = struct.unpack_from("<BBB", rec, 0)
    pool = POOLS[pid]
    if depth != TREE[pool][1]:
        raise SnapError(f"frontier {pool}: depth {depth}")
    if not known:
        if len(rec) != 3:
            raise SnapError(f"frontier {pool}: trailing bytes")
        return pool, None
    size, = struct.unpack_from("<Q", rec, 3)
    root = rec[11:43].hex()
    lv, i = [], 43
    for _ in range(depth):
        if rec[i] == 0:
            lv.append(None)
            i += 1
        elif rec[i] == 1:
            lv.append(rec[i + 1:i + 33].hex())
            i += 33
        else:
            raise SnapError(f"frontier {pool}: bad level tag")
    if i != len(rec):
        raise SnapError(f"frontier {pool}: trailing bytes")
    return pool, {"size": size, "root": root, "levels": lv}


# ====================================================================== producer

def open_ro(state_dir):
    db = sqlite3.connect(f"file:{Path(state_dir) / 'chain.sqlite'}?mode=ro", uri=True, isolation_level=None,
                         check_same_thread=False)
    db.execute("PRAGMA busy_timeout=600000")
    return db


def _meta(db):
    return {k: json.loads(v) for k, v in db.execute("SELECT k, v FROM meta WHERE k NOT LIKE 'pools@%'")}


class LeafFile:
    """Leaves read lazily from a leaf log, from byte offset `start` (one batch in memory at a time:
    the Sapling and Orchard logs are GBs at the checkpoint)."""

    def __init__(self, path, start=0):
        self.path, self.start = path, start

    def __getitem__(self, sl):
        with open(self.path, "rb") as f:
            f.seek(self.start + sl.start)
            return f.read(sl.stop - sl.start)


def leaf_blocks(state_dir, pool, lens):
    """(lazy leaves, [(height, count)]) of a store's leaf log, cut at the committed lengths."""
    a, b = (Path(state_dir) / "leaves" / f"{pool}{x}" for x in (".bin", ".blk"))
    with open(b, "rb") as f:
        ix = f.read(lens[1])
    if a.stat().st_size < lens[0] or len(ix) != lens[1]:
        raise SnapError(f"leaf log {pool} shorter than the committed lengths")
    blocks = [struct.unpack_from("<II", ix, i) for i in range(0, len(ix), 8)]
    if sum(c for _, c in blocks) * 32 != lens[0]:
        raise SnapError(f"leaf log {pool}: counts and leaves disagree")
    return LeafFile(a), blocks


def export(state_dir, out_dir, height=None, external=None, jobs=16, db=None, log=log, on_txn=None):
    """Write the sections of a store's state at its committed tip into out_dir and Bend-digest
    them. Every SQLite read is inside ONE read transaction (a consistent state at one committed
    tip even while the store's writer keeps committing: WAL readers see a fixed snapshot); the
    transaction ends once the rows are written, before the (long) tree builds. Leaf logs are
    append-only and read up to the lengths that tip records, so they need no lock.

    external: {pool: {"height", "size", "levels", "roots": [(h, root)], "source"}} frontiers for
    pools whose leaf log does not start at genesis (the oracle-assisted instance).
    on_txn(H): called once the read transaction holds the state (confirm.py signals sync.py).
    Returns the manifest (with 'digest')."""
    t0 = time.time()
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    own = db is None
    db = db or open_ro(state_dir)
    timing, secs = {}, {}
    pk = struct.pack
    db.execute("BEGIN")
    try:
        meta = _meta(db)       # the first read pins the transaction's snapshot
        tip = meta["tip"]
        H = tip["height"]
        if height is not None and H != height:
            raise SnapError(f"store tip is {H}, not the requested height {height}")
        if on_txn:
            on_txn(H)
        assumed = meta.get("assumed_state") is not None
        lens = meta.get("leaf_lengths", {p: [0, 0] for p in POOLS})
        leaf_src = state_dir
        if CLONE_LEAVES and (Path(state_dir) / "leaves").is_dir():
            # APFS clones (cp -c: instant, copy-on-write) of the append-only leaf logs, taken while
            # the read transaction holds the tip: the trees never open the live store's files
            leaf_src = out_dir / "leafclone"
            (leaf_src / "leaves").mkdir(parents=True, exist_ok=True)
            for f in sorted((Path(state_dir) / "leaves").iterdir()):
                subprocess.run(["cp", "-c", str(f), str(leaf_src / "leaves" / f.name)], check=True)
        base = meta.get("snapshot_frontier") or {}
        sources = dict(meta.get("snapshot_sources") or {})
        plans, fronts, roots = {}, {}, {}
        for p in POOLS:
            old = [(h, r.hex()) for h, r in db.execute("SELECT height, root FROM anchor WHERE pool=? ORDER BY height",
                                                       (POOLS.index(p),))]
            if p in base and base[p] is not None:
                plans[p] = ((base[p]["levels"], base[p]["size"]), old, None)
                sources.setdefault(p, "snapshot")
            elif external and p in external:
                e = external[p]
                plans[p] = ((e["levels"], e["size"]), list(e["roots"]), e["height"])
                sources[p] = e["source"]
            elif not assumed:
                plans[p] = (([None] * TREE[p][1], 0), old, None)
                sources[p] = "leaf log from genesis (genesis-verified blocks), tree in Bend"
            else:
                fronts[p], roots[p] = None, []
                sources[p] = "unknown: this instance's leaf log does not start at genesis"
        t = time.time()
        w = SectionWriter(out_dir, "meta")
        mrec = []
        for k in EXPORT_META:
            v = sources if k == "snapshot_sources" else meta.get(k)
            if v is not None:
                mrec.append(k.encode() + b"\x00" + cjson(v))
        for r in sorted(mrec):
            w.add(r)
        secs["meta"] = w.close()
        w = SectionWriter(out_dir, "blk")
        for r in db.execute("SELECT height, hash, prev, time, size, ntx, bits, info FROM blk WHERE height > ? AND "
                            "height <= ? ORDER BY height", (H - BLK_CONTEXT, H)):
            bits = (r[6] or "").encode()
            w.add(pk(">I", r[0]) + r[1] + r[2] + pk("<III", r[3], r[4], r[5])
                  + pk("<B", len(bits)) + bits + (r[7] or "").encode())
        secs["blk"] = w.close()
        w = SectionWriter(out_dir, "utxo")
        for op, value, script, h, cb in db.execute("SELECT op, value, script, height, cb FROM utxo ORDER BY op"):
            w.add(op + pk("<qIB", value, h, cb) + script)
        secs["utxo"] = w.close()
        for i, p in enumerate(POOLS):
            w = SectionWriter(out_dir, f"nf.{p}")
            for nf, h in db.execute("SELECT nf, height FROM nf WHERE pool=? ORDER BY nf", (i,)):
                w.add(nf + pk("<I", h))
            secs[f"nf.{p}"] = w.close()
        w = SectionWriter(out_dir, "oracle_prevout")
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='oracle_prevout'").fetchone():
            for op, h in db.execute("SELECT op, height FROM oracle_prevout ORDER BY op"):
                w.add(op + pk("<I", h))
        secs["oracle_prevout"] = w.close()
        timing["records"] = round(time.time() - t, 1)
    finally:
        db.execute("COMMIT")
        if own:
            db.close()
    # --- frontiers + root histories: Bend tree programs over the leaf logs (outside the txn)
    t = time.time()

    def tree_for(p):
        (levels0, size0), old, ext_h = plans[p]
        lv, blocks = leaf_blocks(leaf_src, p, lens[p])
        if ext_h is not None:
            skip = sum(c for h, c in blocks if h <= ext_h)
            blocks = [(h, c) for h, c in blocks if h > ext_h]
            lv = LeafFile(lv.path, skip * 32)
        counts = [c for _, c in blocks] or [0]
        if PTREE and p != "sprout" and ext_h is None and size0 == 0 and sum(counts) > 2 * LEAF_BATCH:
            import ptree   # segments in parallel Bend processes, continuity-checked (ptree.py)
            rts, lv_out, empty, ptree_stats[p] = ptree.build(p, lv, blocks, out_dir, pex, log)
        else:
            rts, lv_out, empty = run_tree(p, levels0, lv, counts, out_dir)
        size = size0 + sum(c for _, c in blocks)
        if not frontier_ok(lv_out, size):
            raise SnapError(f"{p}: Bend frontier does not match the tree size {size}")
        new = [(h, r) for (h, c), r in zip(blocks, rts) if c]
        root = rts[-1] if blocks else rts[0]
        return p, {"size": size, "root": root, "levels": lv_out}, old + new, sum(c for _, c in blocks)

    pushed, ptree_stats = {}, {}
    with ThreadPoolExecutor(4) as tex, ThreadPoolExecutor(PTREE_JOBS) as pex:
        for p, fr, rs, n in tex.map(tree_for, list(plans)):
            fronts[p], roots[p], pushed[p] = fr, rs, n
    if ptree_stats:
        timing["ptree"] = ptree_stats
    if leaf_src != state_dir:
        shutil.rmtree(leaf_src, ignore_errors=True)
    w = SectionWriter(out_dir, "frontier")
    for p in POOLS:
        w.add(enc_frontier(p, fronts[p]))
    secs["frontier"] = w.close()
    for p in POOLS:
        w = SectionWriter(out_dir, f"roots.{p}")
        for h, r in sorted(set((h, r) for h, r in roots[p] if h <= H)):
            w.add(pk(">I", h) + bytes.fromhex(r))
        secs[f"roots.{p}"] = w.close()
    timing["trees"] = round(time.time() - t, 1)
    timing["leaves_pushed"] = pushed
    man = {"version": VERSION, "chain": "main", "height": H, "hash": tip["hash"],
           "sections": [secs[n] for n in SECTIONS], "provenance": provenance(meta), "sources": sources}
    t = time.time()
    man["digest"] = digest_dir(out_dir, man, jobs)
    timing["digest"] = round(time.time() - t, 1)
    timing["total"] = round(time.time() - t0, 1)
    man["timing_export"] = timing
    (out_dir / "manifest.json").write_text(json.dumps(man, indent=1))
    return man


def provenance(meta):
    if meta.get("assumed_state") is not None:
        return ("ORACLE-ASSISTED, NOT genesis-verified: state started empty at "
                f"{meta['assumed_state'].get('start')}; older spent outputs from the lightwalletd oracle")
    if meta.get("snapshot"):
        return f"imported from a snapshot at {meta['snapshot'].get('height')} ({meta['snapshot'].get('status')})"
    return "genesis-verified: every block from genesis checked by this node (checkpoint sync + Bend)"


# ====================================================================== external frontier (zebend follow)

FOLLOW = FULL.parent / "node/follow/state"


def follow_ironwood(h, snaps=None):
    d = Path(snaps or FOLLOW / "snapshots") / str(h)
    if not (d / "frontier.txt").exists():
        raise SnapError(f"zebend follow has no committed snapshot at {h} (has {sorted(p.name for p in (FOLLOW / 'snapshots').iterdir())[-3:]})")
    tipj = json.loads((d / "tip.json").read_text())
    if tipj["height"] != h:
        raise SnapError("follow snapshot height mismatch")
    with open(FOLLOW / "roots.txt", "rb") as f:
        roots_txt = f.read(tipj["roots_bytes"]).decode()
    roots = []   # roots.txt: "height <block index in its window> root", one line per block that appends
    for l in roots_txt.splitlines():
        hh, _, r = l.split()
        if ACTIVATION["ironwood"] <= int(hh) <= h:
            roots.append((int(hh), r))
    levels = [l.strip() if l.strip() != "-" else None for l in (d / "frontier.txt").read_text().splitlines()][:32]
    # tree size = number of Ironwood note commitments = number of Ironwood nullifiers (one each
    # per action) = follow's nf.bin length / 32 at that snapshot
    return {"height": h, "size": tipj["nf_bytes"] // 32, "levels": levels, "roots": roots,
            "source": "zebend follow's committed snapshot at H (Ironwood tree in Bend from NU6.3 activation; "
                      "follow cross-checks its roots with the chain's GetTreeState, an oracle)"}



# ====================================================================== container (zstd)

def pack(sec_dir, man, out_file, level=3, threads=0):
    """MAGIC | u32 manifest length | manifest JSON | ONE zstd stream of every part, in order."""
    t = time.time()
    hdr = json.dumps({k: v for k, v in man.items() if k != "timing_export"}).encode()
    with open(out_file, "wb") as f:
        f.write(MAGIC + struct.pack("<I", len(hdr)) + hdr)
        f.flush()
        z = subprocess.Popen(["zstd", f"-{level}", f"-T{threads}", "-q", "-c"], stdin=subprocess.PIPE, stdout=f)
        for s in man["sections"]:
            for k in range(len(s["parts"])):
                with open(part_path(sec_dir, s["name"], k), "rb") as g:
                    shutil.copyfileobj(g, z.stdin, 16 << 20)
        z.stdin.close()
        if z.wait():
            raise SnapError("zstd failed")
    return time.time() - t


def read_header(snap_file):
    with open(snap_file, "rb") as f:
        if f.read(len(MAGIC)) != MAGIC:
            raise SnapError("not a zebend snapshot")
        n, = struct.unpack("<I", f.read(4))
        man = json.loads(f.read(n))
        return man, len(MAGIC) + 4 + n


def unpack(snap_file, out_dir):
    """Decompress the parts into out_dir, cut by the manifest's byte lengths (moves bytes).
    The manifest is untrusted: the digest Bend recomputes over these files is what counts."""
    man, off = read_header(snap_file)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = [s["name"] for s in man["sections"]]
    if names != SECTIONS:
        raise SnapError(f"sections {names} != {SECTIONS}")
    with open(snap_file, "rb") as f:
        f.seek(off)
        z = subprocess.Popen(["zstd", "-d", "-q", "-c"], stdin=f, stdout=subprocess.PIPE)
        for s in man["sections"]:
            for k, part in enumerate(s["parts"]):
                left = part["bytes"]
                with open(part_path(out_dir, s["name"], k), "wb") as g:
                    while left:
                        b = z.stdout.read(min(left, 16 << 20))
                        if not b:
                            raise SnapError("snapshot stream ends early")
                        g.write(b)
                        left -= len(b)
        if z.stdout.read(1):
            raise SnapError("trailing data after the last section")
        z.stdout.close()
        if z.wait():
            raise SnapError("zstd -d failed (corrupt snapshot)")
    return man


# ====================================================================== reading sections

def records(d, sec):
    for k in range(len(sec["parts"])):
        for _off, rec in iter_records(part_path(d, sec["name"], k)):
            yield rec.tobytes()


def sec_by_name(man):
    return {s["name"]: s for s in man["sections"]}
