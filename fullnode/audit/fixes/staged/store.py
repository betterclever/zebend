"""Chain state of the Zebend full node, on disk, without the blocks.

One SQLite database (WAL) plus append-only leaf logs. Every window of blocks is applied in
ONE SQLite transaction (UTXO changes, nullifiers, tx index, block index, anchors, undo data,
tip); the leaf logs are appended before that commit and truncated back to the lengths the
committed tip records on start-up, so a crash at any point leaves the last committed window.

Tables
  meta(k, v)                      tip, leaf-log lengths, value pools, tree frontiers
  blk(height, hash, prev, time, size, ntx, sapling_root, orchard_root, ironwood_root, pools)
  utxo(op = txid||vout, value, script, height, cb)       transparent unspent outputs
  addr(script, op)                 address index (getaddressutxos / getaddressbalance)
  nf(pool, nf, height)            nullifier sets: 0 Sprout, 1 Sapling, 2 Orchard, 3 Ironwood
  anchor(pool, root, height)      note commitment tree roots (valid anchors)
  tx(txid, height, idx)           transaction index (getrawtransaction refetches the block)
  undo(height, data)              per-block undo data for the last UNDO_DEPTH blocks (reorgs)

Leaf logs (leaves/<pool>.bin, 32 bytes per note commitment, in tree order, and
leaves/<pool>.blk: u32 height, u32 count per block that appends any): the input of the tree
builders. Sprout and Sapling trees are pending components; their leaves are kept so the
trees can be built later without downloading the chain again.
"""
import json, os, pickle, sqlite3, struct, time
from pathlib import Path

POOLS = ["sprout", "sapling", "orchard", "ironwood"]
UNDO_DEPTH = 600  # ZIP 218: nodes SHOULD support rollback of at least 600 blocks after NU7

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS blk(height INTEGER PRIMARY KEY, hash BLOB, prev BLOB, time INTEGER, size INTEGER,
  ntx INTEGER, bits TEXT, info TEXT);
CREATE INDEX IF NOT EXISTS blk_hash ON blk(hash);
CREATE TABLE IF NOT EXISTS utxo(op BLOB PRIMARY KEY, value INTEGER, script BLOB, height INTEGER, cb INTEGER) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS addr(script BLOB, op BLOB, PRIMARY KEY(script, op)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS nf(pool INTEGER, nf BLOB, height INTEGER, PRIMARY KEY(pool, nf)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS anchor(pool INTEGER, root BLOB, height INTEGER, PRIMARY KEY(pool, root)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS tx(txid BLOB PRIMARY KEY, height INTEGER, idx INTEGER) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS undo(height INTEGER PRIMARY KEY, data BLOB);
"""


def op_key(txid_display, vout):
    return bytes.fromhex(txid_display)[::-1] + struct.pack("<I", vout)


class Store:
    def __init__(self, path: Path, readonly=False):
        self.dir = Path(path)
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.dir / "leaves").mkdir(exist_ok=True)
        uri = f"file:{self.dir / 'chain.sqlite'}" + ("?mode=ro" if readonly else "")
        self.db = sqlite3.connect(uri, uri=True, check_same_thread=False, isolation_level=None)
        self.rdb = self.db
        if not readonly:
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")      # every commit fsyncs the WAL
            self.db.execute("PRAGMA cache_size=-1048576")   # 1 GB page cache
            # Checkpoint (copy the WAL into the database file) after each commit (SQLite default
            # threshold). sync.py commits a group of windows per transaction in a separate writer
            # process, so the checkpoint runs off the critical path, and a large WAL (slow reads:
            # every page read searches the WAL index) never builds up. Durability does not depend
            # on it: every commit is fsynced in the WAL (synchronous=FULL).
            self.db.execute(f"PRAGMA wal_autocheckpoint={int(os.environ.get('ZEBEND_WAL_PAGES', 1000))}")
            self.db.execute("PRAGMA journal_size_limit=1073741824")
            self.db.execute("PRAGMA busy_timeout=600000")
            self.db.executescript(SCHEMA)
            # Reads (prevout lookups, meta) use their own connection, so they can run while a
            # window is being committed on self.db by sync.py's writer thread. They see the last
            # committed state; the windows resolved but not yet committed are in self.pending.
            self.rdb = sqlite3.connect(uri, uri=True, check_same_thread=False, isolation_level=None)
            self.rdb.execute("PRAGMA cache_size=-262144")
            self.rdb.execute("PRAGMA busy_timeout=600000")
            self.recover()
        self._pre = {}  # op -> UTXO row or None, looked up for the window being resolved
        self.pending = []  # overlays (new_group) of windows resolved but not committed, oldest first
        # The address index (addr) is only used by RPC. In the checkpointed region sync.py may
        # defer it (meta addr_deferred): it is then empty and rebuilt from utxo in one sorted
        # pass (build_addr_index) before the first fully validated window.
        self.addr_index = not self.get("addr_deferred", False)

    # ------------------------------------------------------------------ meta
    def get(self, k, default=None):
        r = self.rdb.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
        return json.loads(r[0]) if r else default

    def put(self, k, v):
        self.db.execute("INSERT OR REPLACE INTO meta VALUES(?,?)", (k, json.dumps(v)))

    def tip(self):
        return self.get("tip", {"height": -1, "hash": "00" * 32})

    # ------------------------------------------------------------------ leaf logs
    def leaf_paths(self, pool):
        return self.dir / "leaves" / f"{pool}.bin", self.dir / "leaves" / f"{pool}.blk"

    def leaf_lengths(self):
        out = {}
        for p in POOLS:
            a, b = self.leaf_paths(p)
            out[p] = [a.stat().st_size if a.exists() else 0, b.stat().st_size if b.exists() else 0]
        return out

    def recover(self):
        """Truncate the leaf logs back to what the committed tip recorded (crash consistency)."""
        want = self.get("leaf_lengths", {p: [0, 0] for p in POOLS})
        for p in POOLS:
            for path, n in zip(self.leaf_paths(p), want.get(p, [0, 0])):
                if not path.exists():
                    path.write_bytes(b"")
                if path.stat().st_size > n:
                    with open(path, "r+b") as f:
                        f.truncate(n)
                elif path.stat().st_size < n:
                    raise RuntimeError(f"leaf log {path} shorter than the committed tip records")

    # ------------------------------------------------------------------ prevout lookups
    def _overlay(self, k):
        """(found, row) from the windows resolved but not committed yet, newest first."""
        for w in reversed(list(self.pending)):
            if k in w["created"]:
                return True, w["created"][k]
            if k in w["spent"]:
                return True, None
        return False, None

    def prefetch(self, keys):
        """Look the UTXO rows for `keys` (op keys) up once, in sorted batches, into a per-window
        dict shared by the rules engine (st.utxo) and resolve_window. None = not an unspent output.
        Valid for one window (new_window() clears it)."""
        want = []
        for k in set(keys):
            if k in self._pre:
                continue
            found, r = self._overlay(k)
            if found:
                self._pre[k] = r
            else:
                want.append(k)
        want.sort()
        q = self.rdb.execute
        for i in range(0, len(want), 500):
            part = want[i:i + 500]
            for k in part:
                self._pre[k] = None
            for r in q(f"SELECT op, value, script, height, cb FROM utxo WHERE op IN ({','.join('?' * len(part))})", part):
                self._pre[r[0]] = r[1:]

    def new_window(self):
        self._pre.clear()

    def _lookup(self, k):
        if k in self._pre:
            return self._pre[k]
        found, r = self._overlay(k)
        if found:
            return r
        return self.rdb.execute("SELECT value, script, height, cb FROM utxo WHERE op=?", (k,)).fetchone()

    # ------------------------------------------------------------------ applying a window
    def apply_window(self, blocks, extra_meta=None):
        """blocks: list of dicts from sync.parse_delta (already checked). One transaction.
        Raises StateError on a missing input, a repeated nullifier or a BIP 30 overwrite (the
        transaction is rolled back)."""
        self.new_window()
        ws = self.resolve_window(blocks)
        self.write_window(ws, extra_meta)

    def resolve_window(self, blocks):
        """Pass 1, no writes: resolve every input in block and transaction order (exactly the
        sequential semantics: an input may spend an output of an earlier transaction of the
        window, never a later one) and collect the window's writes. Lookups see the committed
        state plus self.pending (overlays of windows resolved but not committed yet)."""
        leaf_bufs = {p: [bytearray(), bytearray()] for p in POOLS}
        want = []
        made = set()
        for b in blocks:
            for t in b["txs"]:
                for (ptxid, vout, _seq) in t["ins"]:
                    k = op_key(ptxid, vout)
                    if k not in made:
                        want.append(k)
                if b["height"]:
                    tk = bytes.fromhex(t["txid"])[::-1]
                    for (k_out, _v, _s) in t["outs"]:
                        k = tk + struct.pack("<I", k_out)
                        made.add(k)
                        want.append(k)  # BIP 30: must not already be an unspent output
        self.prefetch(want)
        pre = self._pre
        created = {}   # op -> row, created in this window and still unspent
        db_spent = {}  # op -> row, outputs of the state before the window, spent in it
        nf_seen = set()
        tx_rows, blk_rows, undo_rows, anchor_rows, nf_rows = {}, [], [], [], []
        for b in blocks:
            undo = {"spent": [], "created": [], "nf": [], "tx": [], "anchor": []}
            h = b["height"]
            for t in b["txs"]:
                tk = bytes.fromhex(t["txid"])[::-1]
                for (ptxid, vout, _seq) in t["ins"]:
                    k = op_key(ptxid, vout)
                    r = created.pop(k, None)
                    if r is None and k not in db_spent:
                        r = pre.get(k)
                        if r is not None:
                            db_spent[k] = r
                    if r is None:
                        raise StateError(f"block {h} tx {t['txid']}: input {ptxid}:{vout} is not an unspent output")
                    undo["spent"].append((k, *r))
                for (k_out, value, script) in t["outs"]:
                    if h == 0:
                        continue  # the genesis coinbase is not spendable (not in the UTXO set)
                    k = tk + struct.pack("<I", k_out)
                    if k in created or (pre.get(k) is not None and k not in db_spent):
                        # BIP 30: a duplicate txid overwriting an unspent output (never on Zcash
                        # mainnet; Zcash coinbases commit to the height from genesis).
                        raise StateError(f"block {h}: output {t['txid']}:{k_out} already unspent (BIP 30)")
                    created[k] = (value, script, h, int(t["cb"]))
                    undo["created"].append(k)
                for pool, nfs in t["nfs"].items():
                    pi = POOLS.index(pool)
                    for nf in nfs:
                        nb = bytes.fromhex(nf)
                        if (pi, nb) in nf_seen:
                            raise StateError(f"block {h} tx {t['txid']}: {pool} nullifier {nf} already spent")
                        nf_seen.add((pi, nb))
                        nf_rows.append((pi, nb, h, t["txid"]))
                        undo["nf"].append((pi, nb))
                tx_rows[tk] = (tk, h, t["i"])
                undo["tx"].append(tk)
            for pool, cms in b["leaves"].items():
                if cms:
                    leaf_bufs[pool][0] += b"".join(bytes.fromhex(c) for c in cms)  # wire order
                    leaf_bufs[pool][1] += struct.pack("<II", h, len(cms))
            for pool, root in b.get("roots", {}).items():
                anchor_rows.append((POOLS.index(pool), bytes.fromhex(root), h))
                undo["anchor"].append((POOLS.index(pool), bytes.fromhex(root)))
            blk_rows.append((h, bytes.fromhex(b["hash"]), bytes.fromhex(b["prev"]), b["time"], b["size"],
                             len(b["txs"]), b["bits"], json.dumps(b.get("info", {}))))
            undo_rows.append((h, pickle.dumps(undo)))
        return {"created": created, "spent": db_spent, "nf": nf_rows, "tx": tx_rows, "anchor": anchor_rows,
                "blk": blk_rows, "undo": undo_rows, "leaves": leaf_bufs, "first": blocks[0]["height"],
                "last": blocks[-1]["height"], "hash": blocks[-1]["hash"]}

    def write_rows(self, ws, group_first):
        """A resolved window's row writes, inside the open transaction (one sorted batch per
        table). Undo data, leaf logs and the tip are written by finish_commit."""
        db = self.db
        created, db_spent = ws["created"], ws["spent"]
        dels = sorted(db_spent)
        db.executemany("DELETE FROM utxo WHERE op=?", ((k,) for k in dels))
        ins = sorted(created.items())
        db.executemany("INSERT INTO utxo VALUES(?,?,?,?,?)", ((k, *r) for k, r in ins))
        if self.addr_index:
            db.executemany("DELETE FROM addr WHERE script=? AND op=?", sorted((db_spent[k][1], k) for k in dels))
            db.executemany("INSERT OR IGNORE INTO addr VALUES(?,?)", sorted((r[1], k) for k, r in ins))
        try:
            db.executemany("INSERT INTO nf VALUES(?,?,?)", sorted(r[:3] for r in ws["nf"]))
        except sqlite3.IntegrityError:
            for pi, nb, h, txid in ws["nf"]:
                if db.execute("SELECT height FROM nf WHERE pool=? AND nf=? AND height<?", (pi, nb, group_first)).fetchone():
                    raise StateError(f"block {h} tx {txid}: {POOLS[pi]} nullifier {nb.hex()} already spent")
            raise
        db.executemany("INSERT OR REPLACE INTO tx VALUES(?,?,?)", sorted(ws["tx"].values()))
        db.executemany("INSERT OR IGNORE INTO anchor VALUES(?,?,?)", ws["anchor"])
        db.executemany("INSERT OR REPLACE INTO blk VALUES(?,?,?,?,?,?,?,?)", ws["blk"])

    def finish_commit(self, last, last_hash, undo_rows, leaf_bufs, extra_meta=None):
        """Undo data of the last UNDO_DEPTH blocks, leaf logs (fsynced first), tip, COMMIT."""
        db = self.db
        db.executemany("INSERT OR REPLACE INTO undo VALUES(?,?)", [r for r in undo_rows if r[0] > last - UNDO_DEPTH])
        db.execute("DELETE FROM undo WHERE height <= ?", (last - UNDO_DEPTH,))
        # Leaf logs: appended (fsync) before the commit that records their new lengths.
        for p in POOLS:
            for path, buf in zip(self.leaf_paths(p), leaf_bufs[p]):
                if buf:
                    with open(path, "ab") as f:
                        f.write(buf)
                        f.flush()
                        os.fsync(f.fileno())
        self.put("leaf_lengths", self.leaf_lengths())
        self.put("tip", {"height": last, "hash": last_hash})
        for k, v in (extra_meta or {}).items():
            self.put(k, v)
        db.execute("COMMIT")

    def write_window(self, ws, extra_meta=None):
        """Pass 2 for one window: its writes in ONE transaction."""
        db = self.db
        db.execute("BEGIN IMMEDIATE")
        try:
            self.write_rows(ws, ws["first"])
            self.finish_commit(ws["last"], ws["hash"], ws["undo"], ws["leaves"], extra_meta)
        except BaseException:
            db.execute("ROLLBACK")
            self.recover()
            raise

    def wal_bytes(self):
        p = self.dir / "chain.sqlite-wal"
        return p.stat().st_size if p.exists() else 0

    def checkpoint(self):
        """Copy the WAL into the database file now (e.g. at a clean exit)."""
        return self.db.execute("PRAGMA wal_checkpoint(PASSIVE)").fetchone()

    # ------------------------------------------------------------------ reorgs
    def rollback_to(self, height):
        """Undo blocks above `height` (at most UNDO_DEPTH back), in one transaction."""
        tip = self.tip()["height"]
        db = self.db
        db.execute("BEGIN IMMEDIATE")
        try:
            for h in range(tip, height, -1):
                r = db.execute("SELECT data FROM undo WHERE height=?", (h,)).fetchone()
                if r is None:
                    raise StateError(f"no undo data for block {h} (deeper than {UNDO_DEPTH} blocks)")
                u = pickle.loads(r[0])
                for (k, value, script, hh, cb) in u["spent"]:
                    db.execute("INSERT INTO utxo VALUES(?,?,?,?,?)", (k, value, script, hh, cb))
                    if self.addr_index:
                        db.execute("INSERT OR IGNORE INTO addr VALUES(?,?)", (script, k))
                for k in u["created"]:
                    s = db.execute("SELECT script FROM utxo WHERE op=?", (k,)).fetchone()
                    db.execute("DELETE FROM utxo WHERE op=?", (k,))
                    if s and self.addr_index:
                        db.execute("DELETE FROM addr WHERE script=? AND op=?", (s[0], k))
                for pool, nf in u["nf"]:
                    db.execute("DELETE FROM nf WHERE pool=? AND nf=?", (pool, nf))
                for tk in u["tx"]:
                    db.execute("DELETE FROM tx WHERE txid=? AND height=?", (tk, h))
                for pool, root in u["anchor"]:
                    db.execute("DELETE FROM anchor WHERE pool=? AND root=? AND height=?", (pool, root, h))
                db.execute("DELETE FROM blk WHERE height=?", (h,))
                db.execute("DELETE FROM undo WHERE height=?", (h,))
            # leaf logs: cut every pool back to the blocks <= height
            lens = {}
            for p in POOLS:
                a, b = self.leaf_paths(p)
                idx = b.read_bytes()
                keep, nleaves = 0, 0
                for i in range(0, len(idx), 8):
                    hh, c = struct.unpack_from("<II", idx, i)
                    if hh > height:
                        break
                    keep, nleaves = i + 8, nleaves + c
                lens[p] = [nleaves * 32, keep]
            hb = db.execute("SELECT hash FROM blk WHERE height=?", (height,)).fetchone()
            self.put("leaf_lengths", lens)
            self.put("tip", {"height": height, "hash": hb[0].hex() if hb else "00" * 32})
            info = db.execute("SELECT info FROM blk WHERE height=?", (height,)).fetchone()
            pools = json.loads(info[0]).get("pools") if info and info[0] else None
            if pools is not None:
                self.put("pools", pools)  # value pools after `height` (bin/rules' per-block output)
            elif self.get("pools") is not None:
                raise StateError(f"no per-block pools recorded at {height}: cannot roll the pools back")
            db.execute("COMMIT")
        except BaseException:
            db.execute("ROLLBACK")
            self._pre.clear()
            raise
        self._pre.clear()
        self.recover()

    # ------------------------------------------------------------------ queries (sync + RPC)
    def utxo(self, txid_display, vout):
        return self._lookup(op_key(txid_display, vout))

    def defer_addr_index(self):
        """Empty the address index and stop maintaining it (checkpointed region only)."""
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute("DELETE FROM addr")
        self.put("addr_deferred", True)
        self.db.execute("COMMIT")
        self.addr_index = False

    def build_addr_index(self):
        """(Re)build the address index from the UTXO set, in one transaction."""
        self.db.execute("BEGIN IMMEDIATE")
        self.db.execute("DELETE FROM addr")
        self.db.execute("INSERT INTO addr SELECT script, op FROM utxo ORDER BY script, op")
        self.put("addr_deferred", False)
        self.db.execute("COMMIT")
        self.addr_index = True

    def has_anchor(self, pool, root_hex):
        return self.db.execute("SELECT height FROM anchor WHERE pool=? AND root=?",
                               (POOLS.index(pool), bytes.fromhex(root_hex))).fetchone() is not None

    def close(self):
        if self.rdb is not self.db:
            self.rdb.close()
        self.db.close()


class StateError(Exception):
    pass


# ---------------------------------------------------------------------- commit groups
def new_group():
    """Windows resolved since the last commit, committed together in ONE transaction. Only what
    lookups need is kept here: outputs created (rows) and outputs spent (keys) by the group."""
    return {"created": {}, "spent": set(), "nf": set(), "used": [], "extra": {}, "n": 0, "bytes": 0,
            "first": None, "last": None, "hash": None}


def merge_window(g, ws, nbytes):
    """Fold a resolved window into the group overlay (in block order)."""
    for pi, nb, h, txid in ws["nf"]:
        if (pi, nb) in g["nf"]:
            raise StateError(f"block {h} tx {txid}: {POOLS[pi]} nullifier {nb.hex()} already spent")
    g["nf"].update((pi, nb) for pi, nb, _h, _t in ws["nf"])
    gc = g["created"]
    for k in ws["spent"]:
        if k in gc:
            del gc[k]       # created and spent inside the group: never written
        else:
            g["spent"].add(k)
    gc.update(ws["created"])
    g["n"] += 1
    g["bytes"] += nbytes
    if g["first"] is None:
        g["first"] = ws["first"]
    g["last"], g["hash"] = ws["last"], ws["hash"]


# ---------------------------------------------------------------------- writer process
def _writer_main(path, inq, outq, cache_mb):
    st = Store(path)
    st.db.execute(f"PRAGMA cache_size=-{cache_mb * 1024}")
    open_, failed, first, busy = False, None, None, 0.0
    undo, leaves = [], {p: [bytearray(), bytearray()] for p in POOLS}
    while True:
        msg = inq.get()
        if msg is None:
            if open_:
                st.db.execute("ROLLBACK")
            break
        t = time.time()
        if msg[0] == "apply":
            ws = msg[1]
            if failed is not None:
                continue
            try:
                if not open_:
                    st.db.execute("BEGIN IMMEDIATE")
                    open_, first = True, ws["first"]
                st.write_rows(ws, first)
                undo = [r for r in undo + ws["undo"] if r[0] > ws["last"] - UNDO_DEPTH]
                for p in POOLS:
                    leaves[p][0] += ws["leaves"][p][0]
                    leaves[p][1] += ws["leaves"][p][1]
            except BaseException as e:
                failed = e
            busy += time.time() - t
        elif msg[0] == "commit":
            _, last, last_hash, extra = msg
            if failed is None:
                try:
                    st.finish_commit(last, last_hash, undo, leaves, extra)
                    outq.put(("ok", busy + time.time() - t))
                except BaseException as e:
                    failed = e
            if failed is not None:
                try:
                    st.db.execute("ROLLBACK")
                except sqlite3.Error:
                    pass
                st.recover()
                outq.put(("state", str(failed)) if isinstance(failed, StateError) else ("error", repr(failed)))
            open_, failed, first, busy = False, None, None, 0.0
            undo, leaves = [], {p: [bytearray(), bytearray()] for p in POOLS}
    st.close()


class Writer:
    """Commits groups of windows in a separate process, in order, ONE SQLite transaction per group.

    apply(ws) sends a resolved window (written into the open transaction as it arrives);
    commit(...) ends the group: undo data, leaf logs (fsynced), tip, COMMIT; result() waits
    for that commit. A separate process, not a thread: a thread running executemany next to a
    CPU-bound Python thread is starved by the GIL (measured: 600k deletes 4.9 s alone, 641 s
    next to a busy thread). The caller makes no other write to the store while a group is open."""

    def __init__(self, path, cache_mb=2048):
        import multiprocessing as mp
        ctx = mp.get_context("spawn")
        self.inq, self.outq = ctx.Queue(maxsize=4), ctx.Queue()
        self.proc = ctx.Process(target=_writer_main, args=(str(path), self.inq, self.outq, cache_mb), daemon=True)
        self.proc.start()

    def apply(self, ws):
        self.inq.put(("apply", ws))

    def commit(self, last, last_hash, extra):
        self.inq.put(("commit", last, last_hash, extra))

    def result(self):
        while True:
            try:
                kind, v = self.outq.get(timeout=5)
                break
            except Exception:
                if not self.proc.is_alive():
                    raise StateError("state writer process died; the group was not committed")
        if kind == "ok":
            return v
        if kind == "state":
            raise StateError(v)
        raise RuntimeError(f"state writer: {v}")

    def close(self):
        try:
            self.inq.put(None)
        except (OSError, ValueError):
            pass
        self.proc.join(timeout=600)
