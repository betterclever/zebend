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
import json, os, pickle, sqlite3, struct
from pathlib import Path

POOLS = ["sprout", "sapling", "orchard", "ironwood"]
UNDO_DEPTH = 200

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
        if not readonly:
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=FULL")
            self.db.execute("PRAGMA cache_size=-262144")  # 256 MB page cache
            self.db.executescript(SCHEMA)
            self.recover()

    # ------------------------------------------------------------------ meta
    def get(self, k, default=None):
        r = self.db.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
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

    # ------------------------------------------------------------------ applying a window
    def apply_window(self, blocks, extra_meta=None):
        """blocks: list of dicts from sync.parse_delta (already checked). One transaction.

        Returns per-block lists of resolved prevouts (for the rules engine) is done earlier by
        resolve(); here we only mutate. Raises StateError on a missing input or a repeated
        nullifier (the transaction is rolled back)."""
        db = self.db
        leaf_bufs = {p: [bytearray(), bytearray()] for p in POOLS}
        db.execute("BEGIN IMMEDIATE")
        try:
            for b in blocks:
                undo = {"spent": [], "created": [], "nf": [], "tx": [], "anchor": []}
                h = b["height"]
                for t in b["txs"]:
                    for (ptxid, vout, _seq) in t["ins"]:
                        k = op_key(ptxid, vout)
                        r = db.execute("SELECT value, script, height, cb FROM utxo WHERE op=?", (k,)).fetchone()
                        if r is None:
                            raise StateError(f"block {h} tx {t['txid']}: input {ptxid}:{vout} is not an unspent output")
                        db.execute("DELETE FROM utxo WHERE op=?", (k,))
                        db.execute("DELETE FROM addr WHERE script=? AND op=?", (r[1], k))
                        undo["spent"].append((k, *r))
                    for (k_out, value, script) in t["outs"]:
                        k = op_key(t["txid"], k_out)
                        if h == 0:
                            continue  # the genesis coinbase is not spendable (not in the UTXO set)
                        try:
                            db.execute("INSERT INTO utxo VALUES(?,?,?,?,?)", (k, value, script, h, int(t["cb"])))
                        except sqlite3.IntegrityError:
                            # BIP 30: a duplicate txid overwriting an unspent output (never on Zcash
                            # mainnet; Zcash coinbases commit to the height from genesis).
                            raise StateError(f"block {h}: output {t['txid']}:{k_out} already unspent (BIP 30)")
                        db.execute("INSERT OR IGNORE INTO addr VALUES(?,?)", (script, k))
                        undo["created"].append(k)
                    for pool, nfs in t["nfs"].items():
                        for nf in nfs:
                            try:
                                db.execute("INSERT INTO nf VALUES(?,?,?)", (POOLS.index(pool), bytes.fromhex(nf), h))
                            except sqlite3.IntegrityError:
                                raise StateError(f"block {h} tx {t['txid']}: {pool} nullifier {nf} already spent")
                            undo["nf"].append((POOLS.index(pool), bytes.fromhex(nf)))
                    tk = bytes.fromhex(t["txid"])[::-1]
                    db.execute("INSERT OR REPLACE INTO tx VALUES(?,?,?)", (tk, h, t["i"]))
                    undo["tx"].append(tk)
                for pool, cms in b["leaves"].items():
                    if cms:
                        leaf_bufs[pool][0] += b"".join(bytes.fromhex(c) for c in cms)  # wire order
                        leaf_bufs[pool][1] += struct.pack("<II", h, len(cms))
                for pool, root in b.get("roots", {}).items():
                    db.execute("INSERT OR IGNORE INTO anchor VALUES(?,?,?)", (POOLS.index(pool), bytes.fromhex(root), h))
                    undo["anchor"].append((POOLS.index(pool), bytes.fromhex(root)))
                db.execute("INSERT OR REPLACE INTO blk VALUES(?,?,?,?,?,?,?,?)",
                           (h, bytes.fromhex(b["hash"]), bytes.fromhex(b["prev"]), b["time"], b["size"], len(b["txs"]),
                            b["bits"], json.dumps(b.get("info", {}))))
                db.execute("INSERT OR REPLACE INTO undo VALUES(?,?)", (h, pickle.dumps(undo)))
            last = blocks[-1]
            db.execute("DELETE FROM undo WHERE height <= ?", (last["height"] - UNDO_DEPTH,))
            # Leaf logs: appended (fsync) before the commit that records their new lengths.
            lengths = self.leaf_lengths()
            for p in POOLS:
                for path, buf in zip(self.leaf_paths(p), leaf_bufs[p]):
                    if buf:
                        with open(path, "ab") as f:
                            f.write(buf)
                            f.flush()
                            os.fsync(f.fileno())
            self.put("leaf_lengths", self.leaf_lengths())
            self.put("tip", {"height": last["height"], "hash": last["hash"]})
            for k, v in (extra_meta or {}).items():
                self.put(k, v)
            db.execute("COMMIT")
        except BaseException:
            db.execute("ROLLBACK")
            self.recover()
            raise

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
                    db.execute("INSERT OR IGNORE INTO addr VALUES(?,?)", (script, k))
                for k in u["created"]:
                    s = db.execute("SELECT script FROM utxo WHERE op=?", (k,)).fetchone()
                    db.execute("DELETE FROM utxo WHERE op=?", (k,))
                    if s:
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
            raise
        self.recover()

    # ------------------------------------------------------------------ queries (sync + RPC)
    def utxo(self, txid_display, vout):
        return self.db.execute("SELECT value, script, height, cb FROM utxo WHERE op=?",
                               (op_key(txid_display, vout),)).fetchone()

    def has_anchor(self, pool, root_hex):
        return self.db.execute("SELECT height FROM anchor WHERE pool=? AND root=?",
                               (POOLS.index(pool), bytes.fromhex(root_hex))).fetchone() is not None

    def close(self):
        self.db.close()


class StateError(Exception):
    pass
