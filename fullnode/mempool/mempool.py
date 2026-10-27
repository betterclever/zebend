#!/usr/bin/env python3
"""Zebend mempool: a separate process next to a fullnode instance (reads its state read-only).

  * P2P (p2p.py): listens on --port (default 8233) and keeps --peers outbound peers;
    transactions in and out (inv / getdata / tx / notfound / mempool), getaddr, ping.
  * Admission (admit.py): full validation against the tip state with the node's own Bend
    programs (blockdelta, bin/rules, hooks) + Bend policy (txpolicy: ZIP 317, standardness).
  * Lifecycle: polls the instance's tip (SQLite, read-only); after every new block removes
    mined, conflicting, expired and no-longer-valid txs (bin/rules again at the new tip+1) and
    clears the tip-scoped rejection caches; on a reorg re-admits the transactions of the
    disconnected blocks (kept in a cache of recent blocks fetched by hash over P2P and checked
    by Bend blockdelta: hash == the state's block hash, merkle MATCH).
  * RPC (--rpc-port, default 18234): getrawmempool [verbose], getmempoolinfo,
    getrawtransaction (mempool txs; anything else is forwarded), sendrawtransaction (admits,
    then relays), getpeerinfo, getmempoolstats; every other method is forwarded to the node's
    rpc.py (--rpc-backend), so lightwalletd can use this port as its zcashd.

usage: ZEBEND_STATE=../state-tip python3 mempool.py [--port 8233] [--rpc-port 18234]
       [--rpc-backend http://127.0.0.1:18233] [--peers 8] [--connect HOST:PORT ...]
"""
import argparse, collections, hashlib, json, os, queue, struct, sys, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import txcheck as X
from admit import Admitter, ChainView, Result
from pool import Pool
from p2p import P2P, MSG_TX, MSG_WTX

LOGS = HERE / "logs"


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class Node:
    def __init__(self, a):
        self.a = a
        self.view = ChainView(a.state)
        self.pool = Pool(cost_limit=a.cost_limit, eviction_age=a.eviction_age)
        self.adm = Admitter(self.view, self.pool, log, jobs=a.jobs)
        self.p2p = P2P(self, port=a.port, bind=a.bind, outbound=a.peers, log=log, book=a.data / "peers.txt",
                       connect=a.connect, listen=not a.no_listen, seeds=not a.no_seeds, per_ip=a.per_ip)
        self.q = queue.Queue()
        self.queued = {}            # sha256(raw) -> time, while queued or being validated
        self.recent = collections.OrderedDict()  # txid -> time: recently seen, answered by admission
        self.tip = self.view.tip()
        self.tip_event = threading.Event()
        self.cache_event = threading.Event()
        self.chain_lock = threading.Lock()   # admission batches vs tip handling
        self.blocks = collections.OrderedDict()  # height -> {"hash", "txs": [raw], "txids": [...]}
        a.data.mkdir(parents=True, exist_ok=True)
        LOGS.mkdir(exist_ok=True)
        self.journal = open(a.journal, "a", buffering=1)
        self.counts = collections.Counter()
        self.started = time.time()

    # ------------------------------------------------------------ hooks for p2p.py
    def tip_height(self):
        return self.tip["height"]

    def wants(self, txid, auth):
        if txid in self.pool.entries or txid in self.recent:
            return False
        return self.pool.rejection(txid, (txid, auth)) is None

    def lookup(self, h):
        return self.pool.by_wtxid(h)

    def inventory(self):
        return [(MSG_WTX if e.v >= 5 else MSG_TX, e.wtxid) for e in self.pool.snapshot()]

    def block_announced(self):
        self.tip_event.set()

    def submit(self, raw, source, conn=None, wait=False):
        k = hashlib.sha256(raw).digest()
        if k in self.queued and not wait:
            return None
        self.queued[k] = time.time()
        ev = threading.Event() if wait else None
        box = []
        self.q.put((raw, source, conn, ev, box, k))
        if wait:
            ev.wait(300)
            return box[0] if box else None
        return None

    # ------------------------------------------------------------ journal
    def record(self, d):
        d["t"] = round(time.time(), 1)
        self.journal.write(json.dumps(d) + "\n")

    # ------------------------------------------------------------ admission worker
    def worker(self):
        while True:
            items = [self.q.get()]
            t_end = time.time() + 0.3
            while len(items) < 64:
                try:
                    items.append(self.q.get(timeout=max(0, t_end - time.time())))
                except queue.Empty:
                    break
            with self.chain_lock:
                self.process(items)

    def process(self, items):
        """Admit a batch (caller holds chain_lock), then journal, log and relay the results.
        items: (raw, source, conn, event, box, key)."""
        t0 = time.time()
        try:
            res = self.adm.admit([(it[0], it[1]) for it in items])
        except Exception as e:  # a Bend/runtime failure: nothing admitted, logged
            log(f"admit: batch of {len(items)} failed: {e.__class__.__name__}: {e}")
            res = [None] * len(items)
        dt = time.time() - t0
        for it, r in zip(items, res):
            raw, source, conn, ev, box, k = it
            self.queued.pop(k, None)
            if r is not None:
                if r.txid:
                    self.recent[r.txid] = time.time()
                    while len(self.recent) > 20000:
                        self.recent.popitem(last=False)
                    self.p2p.done(r.txid)
                self.counts[r.status] += 1
                ann = self.p2p.announced_auth.get(r.txid) if r.txid else None
                if ann and r.wtxid:
                    self.counts["wtxid: Bend auth digest == peer's MSG_WTX inv" if ann == r.wtxid
                                else "wtxid: Bend auth digest != peer's MSG_WTX inv"] += 1
                d = r.as_dict()
                d["secs"] = round(dt, 2)
                d["tip"] = self.tip["height"]
                if r.status != "duplicate" or source.startswith("rpc"):
                    self.record(d)
                if r.status == "admitted":
                    n = self.p2p.relay(r.entry, conn)
                    log(f"admitted {r.txid} v{r.entry.v} {r.entry.size} B fee {r.entry.fee} from {source}; "
                        f"inv to {n} peers; mempool {len(self.pool.entries)} txs")
                elif r.status == "rejected" and not (r.reason or "").startswith("cached"):
                    log(f"rejected {r.txid} from {source}: {r.reason}")
            if ev is not None:
                box.append(r)
                ev.set()

    # ------------------------------------------------------------ tip follower
    def fetch_block(self, h):
        """Raw block at height h of the state's chain, from P2P, checked by Bend blockdelta."""
        hd, hp = self.view.blk_hash(h), self.view.blk_hash(h - 1)
        if not hd or not hp:
            return None
        raw = None
        if self.a.block_dir and (Path(self.a.block_dir) / f"{h}.bin").exists():
            raw = (Path(self.a.block_dir) / f"{h}.bin").read_bytes()  # tests: checked by Bend like P2P blocks
        if raw is None:
            raw = self.p2p.fetch_block(bytes.fromhex(hd)[::-1], bytes.fromhex(hp)[::-1], h)
        if raw is None:
            return None
        p = X.tmp("blk.bin")
        p.write_bytes(X.window_bytes([(h, raw)]))
        b = X.parse_delta(X.run(X.BIN_FN / "blockdelta", p).stdout)
        p.unlink(missing_ok=True)
        if not b or "invalid" in b[0] or b[0]["hash"] != hd or b[0]["merkle"] != "MATCH":
            log(f"block {h} from P2P failed the Bend check; not cached")
            return None
        b = b[0]
        n = len(b["txs"])
        off = X.HDR + len(X.cs(n))
        txs = []
        for t in b["txs"]:
            txs.append(raw[off:off + t["size"]])
            off += t["size"]
        return {"hash": hd, "txs": [r for r, t in zip(txs, b["txs"]) if not t["cb"]],
                "txids": [t["txid"] for t in b["txs"] if not t["cb"]]}

    def fill_cache(self):
        tip = self.view.tip()["height"]
        for h in range(max(0, tip - self.a.cache_blocks + 1), tip + 1):
            hd = self.view.blk_hash(h)
            with self.chain_lock:
                if h in self.blocks and self.blocks[h]["hash"] == hd:
                    continue
            b = self.fetch_block(h)
            if b:
                with self.chain_lock:
                    if self.view.blk_hash(h) == b["hash"]:
                        self.blocks[h] = b
        with self.chain_lock:
            for h in list(self.blocks):
                if h <= tip - self.a.cache_blocks:
                    del self.blocks[h]
            self.blocks = collections.OrderedDict(sorted(self.blocks.items()))

    def on_tip(self, new):
        old = self.tip
        readmit = []
        with self.chain_lock:
            gone = [h for h in self.blocks if h > new["height"] or self.view.blk_hash(h) != self.blocks[h]["hash"]]
            if gone or new["height"] < old["height"]:
                log(f"REORG: tip {old['height']} -> {new['height']}; {len(gone)} cached blocks disconnected "
                    f"({gone[:1]}..{gone[-1:]})")
                self.record({"event": "reorg", "old": old, "new": new, "disconnected": gone})
                self.pool.clear_chain_rejections()
                for h in gone:
                    b = self.blocks.pop(h)
                    readmit += [(raw, txid, h) for raw, txid in zip(b["txs"], b["txids"])]
            self.tip = new
            self.pool.clear_tip_rejections()
            self.recent.clear()  # txs rejected for missing inputs etc. may be valid now
            if readmit:
                # zcashd-style: the disconnected blocks' txs first (oldest block first, block order, so
                # parents come before children), validated against the new tip; then the re-check
                self.process([(raw, f"reorg (block {h})", None, None, [], hashlib.sha256(raw).digest())
                              for raw, txid, h in readmit])
            removed, ctx = self.adm.recheck()
            for reason, ids in removed.items():
                for txid in ids:
                    d = {"event": "removed", "txid": txid, "reason": reason, "tip": new["height"]}
                    if reason == "mined":
                        d["height"] = self.view.tx_height(txid)
                    self.record(d)
            self.counts["removed mined"] += len(removed.get("mined", []))
        log(f"tip {new['height']} ({new['hash'][:16]}): mempool {len(self.pool.entries)} txs "
            f"{self.pool.total_bytes} B, removed {sum(len(v) for v in removed.values())}")
        self.cache_event.set()

    def cacher(self):
        """Keep the last --cache-blocks blocks of the state's chain (for reorg re-admission)."""
        while True:
            self.cache_event.wait(30)
            self.cache_event.clear()
            try:
                n0 = len(self.blocks)
                self.fill_cache()
                if len(self.blocks) != n0:
                    log(f"block cache: {len(self.blocks)} blocks {list(self.blocks)[:1]}..{list(self.blocks)[-1:]}")
            except Exception as e:
                log(f"block cache: {e.__class__.__name__}: {e}")

    def follower(self):
        while True:
            self.tip_event.wait(self.a.poll)
            self.tip_event.clear()
            try:
                new = self.view.tip()
                if new["hash"] != self.tip["hash"]:
                    self.on_tip(new)
            except Exception as e:
                log(f"tip follower: {e.__class__.__name__}: {e}")
                time.sleep(2)

    def stats_loop(self):
        while True:
            time.sleep(60)
            s = self.stats()
            (self.a.data / "stats.json").write_text(json.dumps(s, indent=1))
            log(f"stats: mempool {s['size']} txs {s['bytes']} B; peers {s['peers']}; counts {dict(self.counts)}")

    def stats(self):
        P = self.pool
        return {"tip": self.tip["height"], "size": len(P.entries), "bytes": P.total_bytes, "cost": P.total_cost,
                "cost_limit": P.cost_limit, "rejected_cached": P.rejected_count(), "counts": dict(self.counts),
                "pool": dict(P.stats), "p2p": dict(self.p2p.stats), "peers": len(self.p2p.peer_info()),
                "anchors": self.adm.anchor_stats, "oracle": self.adm.oracle.stats if self.adm.oracle else None,
                "uptime": int(time.time() - self.started), "queued": self.q.qsize(),
                "block_cache": list(self.blocks),
                "relayed": {"txs": len(self.p2p.relayed),
                            "served_getdata": sum(1 for r in self.p2p.relayed.values() if r["getdata"]),
                            "inv_back": sum(1 for r in self.p2p.relayed.values() if r["inv_back"])}}

    # ------------------------------------------------------------ RPC
    def rpc_getrawmempool(self, verbose=False):
        es = self.pool.snapshot()
        if not verbose:
            return [e.txid for e in es]
        out = {}
        for e in es:
            desc = self._descendants(e.txid)
            out[e.txid] = {"size": e.size, "fee": e.fee / 1e8, "modifiedfee": e.fee / 1e8, "time": e.time,
                           "height": e.height, "startingpriority": 0, "currentpriority": 0,
                           "descendantcount": len(desc), "descendantsize": sum(d.size for d in desc),
                           "descendantfees": sum(d.fee for d in desc), "depends": sorted(e.deps or [])}
        return out

    def _descendants(self, txid):
        out, todo, seen = [], [txid], set()
        while todo:
            t = todo.pop()
            if t in seen or t not in self.pool.entries:
                continue
            seen.add(t)
            out.append(self.pool.entries[t])
            todo += list(self.pool.children.get(t, ()))
        return out

    def rpc_getmempoolinfo(self):
        P = self.pool
        return {"size": len(P.entries), "bytes": P.total_bytes, "usage": P.total_bytes, "maxmempool": P.cost_limit,
                "cost": P.total_cost, "fullyNotified": True}

    def rpc_getrawtransaction(self, txid, verbose=0, *rest):
        e = self.pool.get(txid)
        if e is None:
            return self.forward("getrawtransaction", [txid, verbose, *rest])
        if not int(verbose or 0):
            return e.raw.hex()
        t = e.txd
        vin = [{"txid": p, "vout": n, "sequence": q} for (p, n, q) in t["ins"]]
        vout = [{"value": v / 1e8, "valueZat": v, "n": k, "scriptPubKey": {"hex": s.hex()}} for (k, v, s) in t["outs"]]
        j = {"hex": e.raw.hex(), "txid": e.txid, "version": e.v, "overwintered": t["ow"], "locktime": t["lock"],
             "expiryheight": t["exp"], "vin": vin, "vout": vout, "size": e.size,
             "vjoinsplit": [{"vpub_old": x["vpub_old"] / 1e8, "vpub_new": x["vpub_new"] / 1e8} for x in t["js"]]}
        if t["ow"]:
            j["versiongroupid"] = t["grp"]
        if t["sap"]:
            j["valueBalanceZat"], j["valueBalance"] = t["sap"]["vb"], t["sap"]["vb"] / 1e8
        for key, pool in (("orch", "orchard"), ("iw", "ironwood")):  # as rpc.py's _tx_json
            if t[key]:
                j[pool] = {"valueBalanceZat": t[key]["vb"], "valueBalance": t[key]["vb"] / 1e8,
                           "anchor": t[key]["anchor"], "actions": t[key]["n"]}
        if e.v >= 5:
            j["authdigest"] = e.auth
        return j  # no "height"/"blockhash": a mempool tx (zcashd's format; lightwalletd reads height 0)

    def rpc_getmempooltx(self, txid, verbose=0):
        """getrawtransaction for mempool txs only (no forwarding: rpc.py calls this)."""
        if self.pool.get(txid) is None:
            raise RpcError(-5, "No such mempool or blockchain transaction")
        return self.rpc_getrawtransaction(txid, verbose)

    def rpc_sendrawtransaction(self, hexstr, *_):
        try:
            raw = bytes.fromhex(hexstr)
        except ValueError:
            raise RpcError(-22, "TX decode failed")
        r = self.submit(raw, "rpc", wait=True)
        if r is None:
            raise RpcError(-1, "admission did not finish")
        if r.status == "admitted":
            return r.txid
        if r.status == "duplicate":
            e = self.pool.get(r.txid)
            if e:
                self.p2p.relay(e)
            return r.txid
        reason = r.reason or ""
        if "mined" in reason:
            raise RpcError(-27, "transaction already in block chain")
        if "missing input" in reason:
            raise RpcError(-25, reason)
        if "malformed" in reason:
            raise RpcError(-22, "TX decode failed: " + reason)
        raise RpcError(-26, reason)

    def rpc_getpeerinfo(self):
        return self.p2p.peer_info()

    def rpc_getrelaystats(self, n=1000):
        """Per relayed tx: when, to how many peers, who fetched it from us (getdata, seconds after
        our inv) and who announced it to us afterwards (inv, seconds, whether we had sent them an inv)."""
        with self.p2p.lock:
            items = list(self.p2p.relayed.items())[-int(n):]
        return {t: {k: v for k, v in r.items()} for t, r in items}

    def rpc_getmempoolstats(self):
        return self.stats()

    def forward(self, method, params):
        req = urllib.request.Request(self.a.rpc_backend, data=json.dumps(
            {"jsonrpc": "1.0", "id": 1, "method": method, "params": params}).encode(),
            headers={"Content-Type": "application/json"})
        try:
            r = json.load(urllib.request.urlopen(req, timeout=120))
        except Exception as e:
            raise RpcError(-1, f"backend rpc unavailable: {e}")
        if r.get("error"):
            raise RpcError(r["error"].get("code", -1), r["error"].get("message", "error"))
        return r["result"]


class RpcError(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code, self.msg = code, msg


def make_handler(node):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                req = json.loads(body)
            except ValueError:
                return self._send({"result": None, "error": {"code": -32700, "message": "Parse error"}, "id": None})
            reqs = req if isinstance(req, list) else [req]
            outs = [self._one(r) for r in reqs]
            self._send(outs if isinstance(req, list) else outs[0])

        def _one(self, r):
            rid, m, params = r.get("id"), r.get("method"), r.get("params") or []
            f = getattr(node, f"rpc_{m}", None)
            try:
                res = f(*params) if f else node.forward(m, params)
                return {"result": res, "error": None, "id": rid}
            except RpcError as e:
                return {"result": None, "error": {"code": e.code, "message": e.msg}, "id": rid}
            except (TypeError, ValueError, IndexError) as e:
                return {"result": None, "error": {"code": -8, "message": f"{e.__class__.__name__}: {e}"}, "id": rid}

        def _send(self, obj):
            data = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=os.environ.get("ZEBEND_STATE", str(HERE.parent / "state-tip")))
    ap.add_argument("--data", default=str(HERE / "state"), help="mempool's own files (peers, stats)")
    ap.add_argument("--journal", default=None, help="jsonl of admission results and lifecycle events")
    ap.add_argument("--port", type=int, default=8233)
    ap.add_argument("--bind", default="::")
    ap.add_argument("--no-listen", action="store_true")
    ap.add_argument("--peers", type=int, default=8, help="outbound peers to keep")
    ap.add_argument("--no-seeds", action="store_true", help="only --connect peers (tests)")
    ap.add_argument("--connect", action="append", default=[], help="HOST:PORT, kept connected")
    ap.add_argument("--per-ip", type=int, default=1, help="inbound connections per IP (loopback exempt)")
    ap.add_argument("--rpc-port", type=int, default=18234)
    ap.add_argument("--rpc-bind", default="127.0.0.1")
    ap.add_argument("--rpc-backend", default="http://127.0.0.1:18233/")
    ap.add_argument("--cost-limit", type=int, default=80_000_000, help="ZIP 401 mempooltxcostlimit")
    ap.add_argument("--eviction-age", type=int, default=3600, help="ZIP 401 eviction memory, seconds")
    ap.add_argument("--cache-blocks", type=int, default=12, help="recent blocks kept for reorg re-admission")
    ap.add_argument("--poll", type=float, default=2.0, help="tip poll interval, seconds")
    ap.add_argument("--block-dir", default=None, help="tests: raw blocks <height>.bin to fill the block cache "
                    "from before asking peers (each is checked by Bend blockdelta against the state's hash)")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    a.data = Path(a.data)
    a.journal = a.journal or str(LOGS / "journal.jsonl")
    node = Node(a)
    t = node.view.tip()
    log(f"zebend mempool: state {a.state} tip {t['height']} {t['hash'][:16]}; assumed-state "
        f"{'YES (oracle prevouts, labelled)' if node.adm.oracle else 'no'}; cost limit {a.cost_limit}")
    for target in (node.worker, node.follower, node.stats_loop, node.cacher):
        threading.Thread(target=target, daemon=True).start()
    node.p2p.start()
    srv = ThreadingHTTPServer((a.rpc_bind, a.rpc_port), make_handler(node))
    log(f"rpc on {a.rpc_bind}:{a.rpc_port} (other methods forwarded to {a.rpc_backend})")
    srv.serve_forever()


if __name__ == "__main__":
    main()
