"""The verified mempool set and its rejection caches (data structure only; no validation here).

Mirrors Zebra main 1e03ee7 zebrad/src/components/mempool/storage.rs (+ storage/verified_set.rs,
storage/eviction_list.rs, zebra-chain transaction/unmined.rs), all POLICY, not consensus:

  * ZIP 401 size limit: cost = max(size, 10,000); eviction weight = cost + 40,000 when the fee
    is below the ZIP 317 conventional fee; while the total cost exceeds tx_cost_limit
    (default 80,000,000) a random transaction is evicted with probability proportional to its
    eviction weight (the new transaction is a candidate too), with its dependents.
  * rejection caches: exact (by wtxid; authorizing-data / consensus / policy failures; cleared
    every new block), same-effects-tip (by txid; spend conflicts, missing inputs; cleared every
    new block), same-effects-chain (by txid; expired, duplicate spend, mined, randomly evicted;
    each list <= 40,000 entries and entries older than eviction_memory_time (1 h) dropped,
    cleared on a reorg).
"""
import collections, random, threading, time

MAX_EVICTION_MEMORY_ENTRIES = 40_000
COST_THRESHOLD = 10_000
LOW_FEE_PENALTY = 40_000


class Entry:
    __slots__ = ("txid", "auth", "raw", "v", "size", "fee", "conv_fee", "conv_actions", "unpaid", "time",
                 "height", "ins", "outs", "nfs", "exp", "lock", "deps", "source", "hooks", "spent", "oracle_ins",
                 "sigops", "txd")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))

    @property
    def cost(self):
        return max(self.size, COST_THRESHOLD)

    @property
    def weight(self):
        return self.cost + (LOW_FEE_PENALTY if self.fee < self.conv_fee else 0)

    @property
    def wtxid(self):
        """ZIP 239 inventory id: txid (internal order) || auth digest for v5+, else txid."""
        tid = bytes.fromhex(self.txid)[::-1]
        return tid + bytes.fromhex(self.auth) if self.v >= 5 else tid


class EvictionList:
    """txid -> time, at most `cap` entries, entries older than `age` seconds dropped."""

    def __init__(self, cap=MAX_EVICTION_MEMORY_ENTRIES, age=3600):
        self.d, self.cap, self.age = collections.OrderedDict(), cap, age

    def _prune(self):
        now = time.time()
        while self.d and (len(self.d) > self.cap or now - next(iter(self.d.values())) > self.age):
            self.d.popitem(last=False)

    def add(self, k):
        self.d.pop(k, None)
        self.d[k] = time.time()
        self._prune()

    def __contains__(self, k):
        self._prune()
        return k in self.d

    def __len__(self):
        return len(self.d)


class Pool:
    def __init__(self, cost_limit=80_000_000, eviction_age=3600):
        self.lock = threading.RLock()
        self.cost_limit, self.eviction_age = cost_limit, eviction_age
        self.entries = collections.OrderedDict()  # txid -> Entry, insertion (topological) order
        self.created = {}   # (txid, vout) -> (value, script) of mempool outputs
        self.spent_by = {}  # (txid, vout) -> spending mempool txid
        self.nf_by = {}     # (pool, nf hex) -> mempool txid
        self.children = collections.defaultdict(set)  # txid -> mempool txids spending its outputs
        self.exact = {}         # wtxid key (bytes) -> reason            (tip)
        self.effects_tip = {}   # txid -> reason                         (tip)
        self.chain = {}         # reason -> EvictionList of txids        (chain)
        self.total_cost = 0
        self.total_bytes = 0
        self.stats = collections.Counter()

    # ------------------------------------------------------------ rejections
    def rejection(self, txid, wkey=None):
        with self.lock:
            if wkey is not None and wkey in self.exact:
                return "exact-tip", self.exact[wkey]
            if txid in self.effects_tip:
                return "effects-tip", self.effects_tip[txid]
            for reason, lst in self.chain.items():
                if txid in lst:
                    return "effects-chain", reason
        return None

    def reject(self, scope, txid, reason, wkey=None):
        with self.lock:
            if scope == "exact":
                self.exact[wkey if wkey is not None else txid] = reason
                if len(self.exact) > MAX_EVICTION_MEMORY_ENTRIES:
                    self.exact.clear()
            elif scope == "tip":
                self.effects_tip[txid] = reason
                if len(self.effects_tip) > MAX_EVICTION_MEMORY_ENTRIES:
                    self.effects_tip.clear()
            else:
                key = reason.split(":")[0]
                self.chain.setdefault(key, EvictionList(age=self.eviction_age)).add(txid)
            self.stats[f"rejected {scope}: {reason.split(':')[0]}"] += 1

    def clear_tip_rejections(self):
        with self.lock:
            self.exact.clear()
            self.effects_tip.clear()

    def clear_chain_rejections(self):
        with self.lock:
            self.chain.clear()

    def rejected_count(self):
        with self.lock:
            return len(self.exact) + len(self.effects_tip) + sum(len(v) for v in self.chain.values())

    # ------------------------------------------------------------ the verified set
    def __contains__(self, txid):
        return txid in self.entries

    def get(self, txid):
        return self.entries.get(txid)

    def by_wtxid(self, key):
        """Entry for an inventory id (32-byte txid or 64-byte wtxid, internal order)."""
        e = self.entries.get(key[:32][::-1].hex())
        if e is None:
            return None
        if len(key) == 64 and (e.v < 5 or bytes.fromhex(e.auth) != key[32:]):
            return None
        return e

    def insert(self, e):
        """Insert a validated entry (its inputs/nullifiers were checked against this pool under
        the same lock). Returns (inserted: bool, evicted txids)."""
        with self.lock:
            self.entries[e.txid] = e
            for i, (ptx, n) in enumerate(e.ins):
                self.spent_by[(ptx, n)] = e.txid
                if ptx in self.entries:
                    self.children[ptx].add(e.txid)
            for (k, v, s) in e.outs:
                self.created[(e.txid, k)] = (v, s)
            for pool, nfs in e.nfs.items():
                for nf in nfs:
                    self.nf_by[(pool, nf)] = e.txid
            self.total_cost += e.cost
            self.total_bytes += e.size
            evicted = []
            # ZIP 401: evict until the total cost is within the limit (the new tx is a candidate).
            while self.total_cost > self.cost_limit and self.entries:
                ids = list(self.entries)
                victim = random.choices(ids, weights=[self.entries[i].weight for i in ids])[0]
                for r in self.remove(victim):
                    evicted.append(r.txid)
                    self.reject("chain", r.txid, "randomly evicted (ZIP 401)")
            self.stats["inserted"] += 1
            return e.txid in self.entries, evicted

    def remove(self, txid, dependents=True):
        """Remove txid (and every mempool tx spending its outputs). Returns removed entries."""
        out = []
        with self.lock:
            todo = [txid]
            while todo:
                t = todo.pop()
                e = self.entries.pop(t, None)
                if e is None:
                    continue
                out.append(e)
                for (ptx, n) in e.ins:
                    if self.spent_by.get((ptx, n)) == t:
                        del self.spent_by[(ptx, n)]
                    self.children.get(ptx, set()).discard(t)
                for (k, _v, _s) in e.outs:
                    self.created.pop((t, k), None)
                for pool, nfs in e.nfs.items():
                    for nf in nfs:
                        if self.nf_by.get((pool, nf)) == t:
                            del self.nf_by[(pool, nf)]
                self.total_cost -= e.cost
                self.total_bytes -= e.size
                kids = self.children.pop(t, set())
                if dependents:
                    todo += list(kids)
        return out

    def snapshot(self):
        with self.lock:
            return list(self.entries.values())
