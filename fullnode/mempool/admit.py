"""Mempool admission: full validation of a transaction against the tip state, then policy.

Order for a batch of candidates (one consistent read snapshot of the tip state):
  1. Bend extraction (txcheck.extract: node/wire gate, txid, inputs, outputs, nullifiers,
     anchors) and the wtxid (txcheck.policy, no fee yet) -> rejection caches, duplicates.
  2. Lookups (Python, like store.py's during a block commit): every spent output is an unspent
     output of the chain state or of an earlier mempool tx (and not spent by one); no
     nullifier is in the chain's sets or spent in the mempool; not already mined; Ironwood
     anchors are roots of earlier blocks (follow's Bend-computed tree, like sync.py's
     anchor_checks); Orchard / Sapling / Sprout anchors SKIPPED (tree builders pending), as in
     the node itself.
     Assumed-state instance (state-tip): an output created before the start height comes from
     the lightwalletd oracle and is used only if Bend recomputes the creating tx's txid (as
     assumed.py does for blocks); such inputs are counted per tx (`oracle_ins`).
  3. bin/rules on the synthetic block at tip+1 (txcheck.rules): every non-crypto consensus rule
     (value balance / fee >= 0, expiry against tip+1, lock time against the next block's
     median-time-past, sizes, sigops, versions + branch id, coinbase maturity, ...).
  4. Policy (txcheck.policy, Bend): ZIP 317 unpaid actions + min fee rate, standardness.
  5. Verifier hooks (transparent, sapling, orchard) at height tip+1.
  6. Insert under the pool lock after re-checking conflicts against the pool as it is then
     (if the tip moved meanwhile, the batch is validated again).
"""
import hashlib, re, sqlite3, struct, subprocess, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import txcheck as X
from pool import Entry

POOLS = ["sprout", "sapling", "orchard", "ironwood"]
LWD = X.FN.parent / "follow/bin/follow-lwd"
FOLLOW_ROOTS = X.FN.parent / "follow/state/roots.txt"


def op_key(txid_display, vout):
    return bytes.fromhex(txid_display)[::-1] + struct.pack("<I", vout)


class ChainView:
    """Read-only view of a node instance's state (the same SQLite file sync.py writes)."""

    def __init__(self, state_dir):
        self.dir = Path(state_dir)
        self.db = sqlite3.connect(f"file:{self.dir / 'chain.sqlite'}?mode=ro", uri=True, check_same_thread=False,
                                  isolation_level=None)
        self.db.execute("PRAGMA busy_timeout=10000")
        self.lock = threading.RLock()
        self.in_read = False

    def q1(self, sql, args=()):
        with self.lock:
            return self.db.execute(sql, args).fetchone()

    def qa(self, sql, args=()):
        with self.lock:
            return self.db.execute(sql, args).fetchall()

    def meta(self, k, default=None):
        import json
        r = self.q1("SELECT v FROM meta WHERE k=?", (k,))
        return json.loads(r[0]) if r else default

    def begin(self):
        """Start a read snapshot (WAL: a consistent view until end())."""
        self.lock.acquire()
        self.db.execute("BEGIN")
        self.db.execute("SELECT 1 FROM meta LIMIT 1").fetchone()  # the snapshot starts at the first read

    def end(self):
        try:
            self.db.execute("COMMIT")
        finally:
            self.lock.release()

    def tip(self):
        return self.meta("tip", {"height": -1, "hash": "00" * 32})

    def context(self):
        """What a synthetic block at tip+1 needs: prev hash, bits, the 11 previous times, MTP."""
        tip = self.tip()
        h = tip["height"]
        rows = self.qa("SELECT height, time, bits, hash FROM blk WHERE height BETWEEN ? AND ? ORDER BY height",
                       (h - 10, h))
        times = [r[1] for r in rows]
        bits = rows[-1][2] if rows else "1d00ffff"
        mtp = sorted(times)[len(times) // 2] if times else 0
        pools = self.meta("pools")
        return {"height": h + 1, "tip": h, "prev": tip["hash"], "bits": bits, "times": times, "time": mtp,
                "pools": pools, "assumed": self.meta("assumed_state")}

    def utxo(self, op):
        return self.q1("SELECT value, script, height, cb FROM utxo WHERE op=?", (op,))

    def has_nf(self, pool, nf_hex):
        return self.q1("SELECT 1 FROM nf WHERE pool=? AND nf=?", (POOLS.index(pool), bytes.fromhex(nf_hex))) is not None

    def tx_height(self, txid):
        r = self.q1("SELECT height FROM tx WHERE txid=?", (bytes.fromhex(txid)[::-1],))
        return r[0] if r else None

    def oracle_used(self, op):
        try:
            return self.q1("SELECT 1 FROM oracle_prevout WHERE op=?", (op,)) is not None
        except sqlite3.OperationalError:
            return False

    def blk_hash(self, h):
        r = self.q1("SELECT hash FROM blk WHERE height=?", (h,))
        return r[0].hex() if r else None


class Oracle:
    """Pre-start-height outputs for the assumed-state instance: lightwalletd (follow-lwd rawtx),
    used only if Bend (blockdelta) recomputes the txid the input names. LABELLED oracle data."""

    def __init__(self, log):
        self.cache, self.log, self.lock = {}, log, threading.Lock()
        self.stats = {"fetched": 0, "bend_ok": 0, "bend_bad": 0}

    def outputs(self, txid):
        with self.lock:
            if txid in self.cache:
                return self.cache[txid]
        rev = bytes.fromhex(txid)[::-1].hex()
        try:
            out = subprocess.run([str(LWD), "rawtx", rev], capture_output=True, text=True, timeout=30).stdout
        except subprocess.TimeoutExpired:
            return None
        m = re.search(r"^rawtx ([0-9a-f]{64}) height (\d+) hex ([0-9a-f]+)$", out, re.M)
        if not m:
            return None
        raw = bytes.fromhex(m.group(3))
        self.stats["fetched"] += 1
        blk = bytes(140) + b"\xfd\x40\x05" + bytes(1344) + b"\x01" + raw
        p = X.tmp("oracle.bin")
        p.write_bytes(X.window_bytes([(0, blk)]))
        b = X.parse_delta(X.run(X.BIN_FN / "blockdelta", p).stdout)
        p.unlink(missing_ok=True)
        if not b or "invalid" in b[0] or len(b[0]["txs"]) != 1 or b[0]["txs"][0]["txid"] != txid:
            self.stats["bend_bad"] += 1
            self.log(f"oracle: tx {txid} NOT accepted (Bend txid mismatch or invalid)")
            res = None
        else:
            self.stats["bend_ok"] += 1
            t = b[0]["txs"][0]
            res = (int(m.group(2)), {k: (v, s) for k, v, s in t["outs"]}, t["cb"])
        with self.lock:
            if len(self.cache) > 20000:
                self.cache.clear()
            self.cache[txid] = res
        return res


class Roots:
    """Ironwood note commitment tree roots (Bend-computed by follow/bin/frontier), root -> first height."""

    def __init__(self, state_dir):
        self.roots, self.last_load, self.top = {}, 0, -1
        self._load(Path(state_dir) / "ironwood_roots.txt")
        self.refresh()

    def _load(self, p):
        try:
            for l in p.read_text().splitlines():
                f = l.split()
                if len(f) == 3:
                    h = int(f[0])
                    self.roots.setdefault(f[2], h)
                    self.top = max(self.top, h)
        except OSError:
            pass

    def refresh(self, force=False):
        if force or time.time() - self.last_load > 20:
            self._load(FOLLOW_ROOTS)
            self.last_load = time.time()

    def check(self, anchor, next_height):
        """For an Ironwood anchor of a tx for block next_height (= state tip + 1):
        'PASS' (a root after a block <= the state's tip), 'LATER' (a root of a block above the
        state's tip: the state is behind), 'UNKNOWN' (not a root of any block follow has computed,
        and follow has computed every block <= the state's tip: invalid, or a root of a block above
        the tip that follow has not reached yet) or 'SKIPPED ...' (follow is behind the state's tip,
        as sync.py's anchor_checks reports it)."""
        if anchor not in self.roots:
            self.refresh(force=time.time() - self.last_load > 3)
        if anchor in self.roots:
            return "PASS" if self.roots[anchor] < next_height else "LATER"
        if self.top < next_height - 1:
            return "SKIPPED (Ironwood roots not computed to the tip yet)"
        return "UNKNOWN"


class Result:
    __slots__ = ("txid", "wtxid", "status", "reason", "entry", "raw", "source", "scope")

    def __init__(self, raw, source):
        self.raw, self.source = raw, source
        self.txid = self.wtxid = self.reason = self.entry = self.scope = None
        self.status = "pending"

    def as_dict(self):
        e = self.entry
        return {"txid": self.txid, "status": self.status, "reason": self.reason, "scope": self.scope,
                "source": self.source, "size": len(self.raw),
                "fee": e.fee if e else None, "v": e.v if e else None,
                "hooks": e.hooks if e else None, "oracle_ins": e.oracle_ins if e else None}


class Admitter:
    def __init__(self, view, pool, log, jobs=6):
        self.view, self.pool, self.log = view, pool, log
        self.oracle = Oracle(log) if view.meta("assumed_state") else None
        self.roots = Roots(view.dir)
        self.ex = ThreadPoolExecutor(jobs)
        self.anchor_stats = {"ironwood_pass": 0, "skipped": {}}

    # -------------------------------------------------------------- spent-output lookup
    def _spent(self, ptx, n, ctx, batch_created):
        """(value, script, height, cb, source) or (None, reason)."""
        k = (ptx, n)
        if k in self.pool.created:
            v, s = self.pool.created[k]
            return (v, s, ctx["height"], False, "mempool")
        if k in batch_created:
            v, s = batch_created[k]
            return (v, s, ctx["height"], False, "mempool")
        op = op_key(ptx, n)
        u = self.view.utxo(op)
        if u is not None:
            return (u[0], bytes(u[1]), u[2], bool(u[3]), "chain")
        if self.oracle is None or ptx in self.pool.entries:
            return (None, "missing")
        if self.view.tx_height(ptx) is not None or self.view.oracle_used(op):
            return (None, "spent")  # created (or oracle-filled) at/after the start height and no longer unspent
        o = self.oracle.outputs(ptx)
        if o is None:
            return (None, "missing")
        h, outs, cb = o
        start = (ctx.get("assumed") or {}).get("start", 0)
        if h >= start:
            return (None, "behind")  # created after the state's start height: the state has not synced it yet
        if n not in outs:
            return (None, "missing")
        return (outs[n][0], outs[n][1], h, cb, "oracle")

    # -------------------------------------------------------------- admission
    def admit(self, items):
        """items: [(raw bytes, source)]. Returns [Result] in order (validated against one tip)."""
        for _attempt in range(3):
            res, tip_seen = self._admit_once(items)
            if res is not None:
                return res
            self.log(f"admit: tip moved during validation (was {tip_seen}); validating the batch again")
        return [self._fail(Result(r, s), "tip", "tip kept moving during validation; retry later") for r, s in items]

    def _fail(self, r, scope, reason):
        r.status, r.scope, r.reason = "rejected", scope, reason
        return r

    def _admit_once(self, items):
        P = self.pool
        results = [Result(raw, src) for raw, src in items]
        self.view.begin()
        try:
            ctx = self.view.context()
            raws = [r.raw for r in results]
            f_ex = self.ex.submit(X.extract, raws, ctx)
            f_pol = self.ex.submit(X.policy, [(raw, None, 0) for raw in raws])
            ex, pol0 = f_ex.result(), f_pol.result()
            batch_created, batch_spent, batch_nf, seen = {}, {}, {}, set()
            live = []  # (result, txdict, spent rows, policy0)
            for r, t, p0 in zip(results, ex, pol0):
                hk = hashlib.sha256(r.raw).hexdigest()
                if hk in P.exact:  # malformed before: keyed by the bytes' hash (no txid)
                    r.txid = hk
                    r.status, r.scope, r.reason = "rejected", "exact-tip", "cached: " + P.exact[hk]
                    continue
                if "invalid" in t or p0.get("invalid"):
                    r.txid = hashlib.sha256(r.raw).hexdigest()  # no txid: keyed by the bytes' hash
                    self._fail(r, "exact", "consensus: " + t.get("invalid", "malformed (txpolicy gate)"))
                    P.reject("exact", r.txid, r.reason, wkey=r.txid)
                    continue
                r.txid = t["txid"]
                r.wtxid = p0["auth"] if p0["v"] >= 5 else None
                wkey = (r.txid, r.wtxid)
                if r.txid in P.entries or r.txid in seen:
                    r.status, r.reason = "duplicate", "already in the mempool"
                    continue
                cached = P.rejection(r.txid, wkey)
                if cached:
                    r.status, r.scope, r.reason = "rejected", cached[0], "cached: " + cached[1]
                    continue
                if t["cb"]:
                    self._fail(r, "exact", "consensus: coinbase transaction (not allowed in the mempool)")
                    P.reject("exact", r.txid, r.reason, wkey=wkey)
                    continue
                if self.view.tx_height(r.txid) is not None:
                    self._fail(r, "chain", "mined: transaction is in the best chain")
                    P.reject("chain", r.txid, r.reason)
                    continue
                spent, bad, oracle_ins = [], None, 0
                for (ptx, n, _seq) in t["ins"]:
                    k = (ptx, n)
                    if k in P.spent_by or k in batch_spent:
                        bad = ("tip", f"spend conflict: {ptx}:{n} is spent by mempool tx "
                                      f"{P.spent_by.get(k) or batch_spent.get(k)}")
                        break
                    s = self._spent(ptx, n, ctx, batch_created)
                    if s[0] is None:
                        bad = ("tip", f"missing input: {ptx}:{n} is not an unspent output of the chain or the mempool"
                               + {"spent": " (spent in the chain)", "behind": " (mined above this state's tip: "
                                  "the state is behind the network)"}.get(s[1], ""))
                        break
                    oracle_ins += s[4] == "oracle"
                    spent.append(s)
                if bad is None:
                    for pool_name, nfs in t["nfs"].items():
                        for nf in nfs:
                            if self.view.has_nf(pool_name, nf):
                                bad = ("chain", f"duplicate spend: {pool_name} nullifier {nf[:16]} is in the chain")
                            elif (pool_name, nf) in P.nf_by or (pool_name, nf) in batch_nf:
                                bad = ("tip", f"spend conflict: {pool_name} nullifier {nf[:16]} is spent in the mempool")
                            if bad:
                                break
                        if bad:
                            break
                if bad is None:
                    for a in t["anchors"]["ironwood"]:
                        v = self.roots.check(a, ctx["height"])
                        if v == "LATER":
                            bad = ("tip", "Ironwood anchor is a root of a block above this state's tip (the state "
                                          "is behind the network); retried after the next block")
                            break
                        if v == "UNKNOWN":
                            # invalid, or a root of a block above the state's tip not computed yet: a
                            # tip-scoped rejection (validated again after the next block)
                            bad = ("tip", "Ironwood anchor is not a root of any block up to this state's tip "
                                          "(invalid, or of a newer block); retried after the next block")
                            break
                        if v == "PASS":
                            self.anchor_stats["ironwood_pass"] += 1
                        else:
                            self.anchor_stats["skipped"][v] = self.anchor_stats["skipped"].get(v, 0) + 1
                    for pool_name in ("orchard", "sapling", "sprout"):
                        if t["anchors"][pool_name]:
                            k = f"{pool_name} SKIPPED (tree builder pending)"
                            self.anchor_stats["skipped"][k] = self.anchor_stats["skipped"].get(k, 0) + 1
                if bad:
                    self._fail(r, bad[0], bad[1])
                    P.reject("chain" if bad[0] == "chain" else bad[0], r.txid, bad[1], wkey=wkey)
                    continue
                seen.add(r.txid)
                for (ptx, n, _seq) in t["ins"]:
                    batch_spent[(ptx, n)] = r.txid
                for (k, v, s) in t["outs"]:
                    batch_created[(r.txid, k)] = (v, s)
                for pool_name, nfs in t["nfs"].items():
                    for nf in nfs:
                        batch_nf[(pool_name, nf)] = r.txid
                live.append((r, t, spent, oracle_ins))
        finally:
            self.view.end()
        pools_known = ctx["pools"] is not None
        # 3. consensus rules (bin/rules), one process per candidate, in parallel
        rr = list(self.ex.map(lambda x: X.rules(x[0].raw, ctx, [s[:4] for s in x[2]], pools_known), live))
        live2 = []
        for (r, t, spent, oi), ru in zip(live, rr):
            if ru["fails"]:
                self._fail(r, "exact", "consensus: " + "; ".join(ru["fails"]))
                P.reject("exact", r.txid, r.reason, wkey=(r.txid, r.wtxid))
            elif ru["fee"] is None or ru["fee"] < 0:
                self._fail(r, "exact", f"consensus: no fee from bin/rules ({ru['fee']})")
                P.reject("exact", r.txid, r.reason, wkey=(r.txid, r.wtxid))
            else:
                live2.append((r, t, spent, oi, ru))
        # 4. policy (Bend): ZIP 317 + standardness, with the fee and sigops bin/rules printed
        pol = X.policy([(r.raw, ru["fee"], ru["sigops"], [x[1] for x in sp]) for r, t, sp, oi, ru in live2]) \
            if live2 else []
        live3 = []
        for (r, t, spent, oi, ru), p in zip(live2, pol):
            z, s = p.get("zip317", {}), p.get("std", {})
            if z.get("verdict") != "PASS":
                self._fail(r, "exact", f"policy (ZIP 317): {z.get('reason') or 'no verdict'} "
                                       f"(fee {ru['fee']}, conventional {p['conv_fee']}, unpaid actions {z.get('unpaid')})")
                P.reject("exact", r.txid, r.reason, wkey=(r.txid, r.wtxid))
            elif s.get("verdict") != "PASS":
                self._fail(r, "exact", f"policy (non-standard): {s.get('reason') or 'no verdict'}")
                P.reject("exact", r.txid, r.reason, wkey=(r.txid, r.wtxid))
            else:
                live3.append((r, t, spent, oi, ru, p))
        # 5. verifier hooks
        hk = X.run_hooks([(i, r.raw, t, [(s[0], s[1]) for s in spent]) for i, (r, t, spent, oi, ru, p)
                          in enumerate(live3)], ctx["height"]) if live3 else {}
        ok = []
        for i, (r, t, spent, oi, ru, p) in enumerate(live3):
            h = hk.get(i, {})
            fails = {k: v for k, v in h.items() if v.startswith("FAIL")}
            if fails:
                self._fail(r, "exact", "consensus (hook): " + "; ".join(f"{k} {v}" for k, v in fails.items()))
                P.reject("exact", r.txid, r.reason, wkey=(r.txid, r.wtxid))
                continue
            e = Entry(txid=r.txid, auth=p["auth"], raw=r.raw, v=t["v"], size=len(r.raw), fee=ru["fee"],
                      conv_fee=p["conv_fee"], conv_actions=p["conv_actions"], unpaid=p["zip317"]["unpaid"],
                      time=int(time.time()), height=ctx["tip"], ins=[(a, b) for a, b, _ in t["ins"]],
                      outs=t["outs"], nfs={k: list(v) for k, v in t["nfs"].items() if v}, exp=t["exp"],
                      lock=t["lock"], source=r.source, hooks=h, spent=spent, oracle_ins=oi, sigops=ru["sigops"],
                      txd=t)
            r.entry = e
            ok.append(r)
        # 6. insert (conflicts against the pool as it is now; the tip must not have moved)
        with P.lock:
            if self.view.tip()["hash"] != ctx["prev"]:
                return None, ctx["tip"]
            for r in ok:
                e = r.entry
                bad = None
                for k in e.ins:
                    if k in P.spent_by:
                        bad = f"spend conflict: {k[0]}:{k[1]} is spent by mempool tx {P.spent_by[k]}"
                        break
                for i, k in enumerate(e.ins):
                    if bad:
                        break
                    if e.spent[i][4] == "mempool" and k not in P.created:
                        bad = f"missing input: mempool parent {k[0]} was not admitted"
                for pool_name, nfs in e.nfs.items():
                    for nf in nfs:
                        if not bad and (pool_name, nf) in P.nf_by:
                            bad = f"spend conflict: {pool_name} nullifier {nf[:16]} is spent in the mempool"
                if bad:
                    self._fail(r, "tip", bad)
                    P.reject("tip", r.txid, bad)
                    r.entry = None
                    continue
                e.deps = {k[0] for k in e.ins if k[0] in P.entries}
                inserted, evicted = P.insert(e)
                if inserted:
                    r.status, r.reason = "admitted", None
                else:
                    self._fail(r, "chain", "randomly evicted (ZIP 401) on insertion")
                if evicted:
                    self.log(f"ZIP 401 eviction: {len(evicted)} tx evicted (total cost limit {P.cost_limit})")
        return results, ctx["tip"]

    # -------------------------------------------------------------- re-checks after a new block
    def recheck(self, log_prefix="recheck"):
        """Remove mined, conflicting, expired or no-longer-valid txs (in insertion order: a removed
        parent removes its dependents). Then re-run bin/rules for every remaining tx at the new
        tip+1. Returns {reason: [txids]}."""
        P = self.pool
        removed = {}

        def drop(txid, scope, reason):
            if reason == "mined":
                # Zebra clear_mined_dependencies: a child of a mined tx stays (its input is now a chain output)
                for e in P.remove(txid, dependents=False):
                    removed.setdefault(reason, []).append(e.txid)
                    P.reject("chain", e.txid, reason)
                for c in P.entries.values():
                    if c.deps:
                        c.deps.discard(txid)
                return
            for e in P.remove(txid):
                removed.setdefault(reason if e.txid == txid else "dependent of a removed tx", []).append(e.txid)
                P.reject(scope if e.txid == txid else "tip", e.txid, reason if e.txid == txid else
                         f"dependent of removed tx {txid}")

        self.view.begin()
        try:
            ctx = self.view.context()
            with P.lock:
                for e in list(P.entries.values()):
                    if e.txid not in P.entries:
                        continue
                    if self.view.tx_height(e.txid) is not None:
                        drop(e.txid, "chain", "mined")
                        continue
                    if e.exp and ctx["tip"] >= e.exp:
                        drop(e.txid, "chain", "expired (tip >= nExpiryHeight)")
                        continue
                    bad = None
                    for i, (ptx, n) in enumerate(e.ins):
                        if ptx in P.entries:  # (after a reorg: a re-admitted parent)
                            P.children[ptx].add(e.txid)
                            e.deps = (e.deps or set()) | {ptx}
                            continue
                        u = self.view.utxo(op_key(ptx, n))
                        if u is None:
                            if self.oracle is not None and self.view.tx_height(ptx) is None and \
                                    not self.view.oracle_used(op_key(ptx, n)):
                                continue  # still a pre-start output (oracle), not spent in the chain since
                            bad = f"input {ptx}:{n} spent in the chain (duplicate spend)"
                            break
                    if not bad:
                        for pool_name, nfs in e.nfs.items():
                            if any(self.view.has_nf(pool_name, nf) for nf in nfs):
                                bad = f"{pool_name} nullifier revealed in the chain (duplicate spend)"
                                break
                    if bad:
                        drop(e.txid, "chain", "duplicate spend: " + bad)
                        continue
                    # after a reorg: an Ironwood anchor that is the root after a disconnected block
                    # is not a root of an earlier block of this chain any more
                    for a in (e.txd or {}).get("anchors", {}).get("ironwood", []):
                        v = self.roots.check(a, ctx["height"])
                        if v in ("LATER", "UNKNOWN"):
                            drop(e.txid, "tip", "Ironwood anchor is not a root of a block up to the new tip (reorg)")
                            break
                remaining = list(P.entries.values())
        finally:
            self.view.end()
        # consensus re-check at the new tip+1 (expiry, lock time, branch id at an upgrade, ...)
        def rr(e):
            spent = []
            for i, (ptx, n) in enumerate(e.ins):
                s = e.spent[i][:4]
                if ptx in P.entries or s[2] > ctx["tip"]:
                    s = (s[0], s[1], ctx["height"], s[3])
                spent.append(s)
            return X.rules(e.raw, ctx, spent, ctx["pools"] is not None)
        outs = list(self.ex.map(rr, remaining))
        with P.lock:
            for e, ru in zip(remaining, outs):
                if ru["fails"] and e.txid in P.entries:
                    drop(e.txid, "chain", "no longer valid at the new tip: " + "; ".join(ru["fails"]))
        if removed:
            self.log(f"{log_prefix}: removed " + ", ".join(f"{len(v)} {k}" for k, v in removed.items()))
        return removed, ctx
