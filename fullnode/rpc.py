#!/usr/bin/env python3
"""zcashd-compatible JSON-RPC for the Zebend full node (a subset for lightwalletd and wallets).

The node keeps no blocks. Methods that need block or transaction bytes (getblock verbosity 0
and 2, getrawtransaction) fetch the block from a P2P peer by its verified hash and run it
through Bend (`bin/blockdelta`: header == verified header, merkle root over Bend-computed
txids) before serving anything from it. Everything else is answered from the state
(state/chain.sqlite: block index, UTXO set, address index, tx index, pools, trees) and the
verified headers.

Methods: getinfo, getblockchaininfo, getbestblockhash, getblockcount, getblockhash,
getblockheader, getblock (0/1/2), getrawtransaction (0/1), sendrawtransaction (relay over
P2P), z_gettreestate, getaddressutxos, getaddressbalance, getaddresstxids (UTXO-only, see
README), getpeerinfo, getnetworkinfo, getmininginfo, getdifficulty, help.

usage: rpc.py [--port 8232] [--bind 127.0.0.1]
"""
import argparse, os, base64, hashlib, json, struct, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers, net, store as S, sync

STATE = Path(os.environ.get("ZEBEND_STATE", HERE / "state"))  # instance state dir
HDRDIR = HERE / "state/hdr"  # Bend-verified header-hash index, shared by instances
BIN = HERE / "bin"
HDR = 1487
VERSION = 6020050  # reported as a zcashd-style version number (lightwalletd checks a minimum)
SUBVERSION = "/Zebend-fullnode:0.1/"

# Network upgrades (mainnet): name, branch id, activation height.
UPGRADES = [("Overwinter", "5ba81b19", 347500), ("Sapling", "76b809bb", 419200), ("Blossom", "2bb40e60", 653600),
            ("Heartwood", "f5b9230b", 903000), ("Canopy", "e9ff75a6", 1046400), ("NU5", "c2d6d0b4", 1687104),
            ("NU6", "c8e71055", 2726400), ("NU6.1", "4dec4df0", 3146400), ("NU6.2", "5437f330", 3364600), ("NU6.3", "37a5165b", 3428143),
            ("NU7", "77190ad9", 3543405)]  # Zebra main 1e03ee75 (2026-10-23)


class RpcError(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code, self.msg = code, msg


def b58encode(b):
    """Base58Check display of an address (presentation only)."""
    A = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    b = b + hashlib.sha256(hashlib.sha256(b).digest()).digest()[:4]
    n, s = int.from_bytes(b, "big"), ""
    while n:
        n, r = divmod(n, 58)
        s = A[r] + s
    return "1" * (len(b) - len(b.lstrip(b"\0"))) + s


def b58decode(s):
    A = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    n = 0
    for c in s:
        n = n * 58 + A.index(c)
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    b = b"\0" * (len(s) - len(s.lstrip("1"))) + b
    if hashlib.sha256(hashlib.sha256(b[:-4]).digest()).digest()[:4] != b[-4:]:
        raise RpcError(-5, f"Invalid address {s}")
    return b[:-4]


def addr_script(a):
    """t-address -> scriptPubKey (mainnet t1 = P2PKH 1cb8, t3 = P2SH 1cbd)."""
    raw = b58decode(a)
    if raw[:2] == b"\x1c\xb8" and len(raw) == 22:
        return b"\x76\xa9\x14" + raw[2:] + b"\x88\xac"
    if raw[:2] == b"\x1c\xbd" and len(raw) == 22:
        return b"\xa9\x14" + raw[2:] + b"\x87"
    raise RpcError(-5, f"Invalid address {a}")


def script_addr(s):
    if len(s) == 25 and s[:3] == b"\x76\xa9\x14" and s[23:] == b"\x88\xac":
        return b58encode(b"\x1c\xb8" + s[3:23])
    if len(s) == 23 and s[:2] == b"\xa9\x14" and s[22:] == b"\x87":
        return b58encode(b"\x1c\xbd" + s[2:22])
    return None


def bits_difficulty(bits_hex):
    bits = int(bits_hex, 16)
    target = (bits & 0xFFFFFF) << (8 * ((bits >> 24) - 3))
    pow_limit = 0x0007FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    return pow_limit / target if target else 0.0


class BlockSource:
    """Fetch a block from P2P by its verified hash, then let Bend check it before use."""

    def __init__(self, idx):
        self.idx, self.lock, self.peer, self.cache = idx, threading.Lock(), None, {}

    def _peer(self):
        if self.peer is None:
            for ip in net.dns_candidates():
                try:
                    self.peer = net.Peer(ip, timeout=6)
                    self.peer.s.settimeout(2)
                    break
                except Exception:
                    continue
        if self.peer is None:
            raise RpcError(-1, "no P2P peer available to fetch the block")
        return self.peer

    def _from_spool(self, height):
        """A block still in the download spool (not yet consumed); Bend checks it like any other."""
        try:
            chunks = sorted((int(p.stem) for p in sync.SPOOL.glob("*.blk")), reverse=True)
        except OSError:
            return None
        for c in chunks:
            if c <= height:
                try:
                    d = (sync.SPOOL / f"{c}.blk").read_bytes()
                except OSError:
                    return None
                i = 0
                while i < len(d):
                    h, n = struct.unpack_from("<II", d, i)
                    if h == height:
                        return d[i + 8:i + 8 + n]
                    i += 8 + n
                return None
        return None

    def get(self, height):
        """(raw block, parsed Bend delta) for a block at or below the verified headers."""
        if height in self.cache:
            return self.cache[height]
        want = self.idx.internal(height)
        raw = self._from_spool(height)
        with self.lock:
            for attempt in range(0 if raw else 3):
                try:
                    p = self._peer()
                    p.s.sendall(net.frame("getdata", net.varint(1) + struct.pack("<I", 2) + want))
                    t = time.time()
                    while time.time() - t < 20:
                        try:
                            c, b = p.recv()
                        except (TimeoutError, OSError) as e:
                            if isinstance(e, ConnectionError):
                                raise
                            continue
                        if c == "block" and b[4:36] == self.idx.internal(height - 1):
                            raw = b
                            break
                        if c == "notfound":
                            raise ConnectionError("notfound")
                    if raw:
                        break
                    raise TimeoutError("block not delivered")
                except (OSError, ConnectionError, TimeoutError):
                    if self.peer:
                        self.peer.close()
                    self.peer = None
        if raw is None:
            raise RpcError(-1, f"could not fetch block {height} from peers")
        blocks = sync.run_blockdelta([(height, raw)], 1, f"rpc{height}")
        b = blocks[0]
        ok = b.get("merkle") == "MATCH" and b.get("hash") == self.idx.display(height) and (height == 0 or b.get("header") == "MATCH")
        if not ok:
            raise RpcError(-1, f"block {height} from peer failed Bend verification")
        if len(self.cache) > 32:
            self.cache.pop(next(iter(self.cache)))
        self.cache[height] = (raw, b)
        return raw, b


class Node:
    def __init__(self):
        self.st = S.Store(STATE, readonly=True)  # sync.py is the only writer
        self.idx = headers.Index(HDRDIR / "hashes.bin")
        self.src = BlockSource(self.idx)
        self.lock = threading.Lock()
        self.started = time.time()

    # ---------------------------------------------------------------- helpers
    def q(self, sql, args=()):
        with self.lock:
            return self.st.db.execute(sql, args).fetchall()

    def tip(self):
        with self.lock:
            return self.st.tip()

    def height_of(self, h_or_hash):
        if isinstance(h_or_hash, int) or (isinstance(h_or_hash, str) and h_or_hash.isdigit()):
            h = int(h_or_hash)
            if not 0 <= h <= self.tip()["height"]:
                raise RpcError(-8, "Block height out of range")
            return h
        r = self.q("SELECT height FROM blk WHERE hash=?", (bytes.fromhex(h_or_hash),))
        if not r:
            raise RpcError(-5, "Block not found")
        return r[0][0]

    def header(self, h):
        if h == 0:
            raw, _ = self.src.get(0)
            return raw[:HDR]
        return headers.header(h)

    def branch_at(self, h):
        br = "00000000"
        for _, b, a in UPGRADES:
            if h >= a:
                br = b
        return br

    def pools(self):
        with self.lock:
            return self.st.get("pools")

    def tree_sizes(self):
        with self.lock:
            return self.st.get("leaf_lengths", {})

    # ---------------------------------------------------------------- methods
    def getblockcount(self):
        return self.tip()["height"]

    def getbestblockhash(self):
        return self.tip()["hash"]

    def getblockhash(self, h):
        h = int(h)
        if not 0 <= h <= self.tip()["height"]:
            raise RpcError(-8, "Block height out of range")
        return self.q("SELECT hash FROM blk WHERE height=?", (h,))[0][0].hex()

    def getdifficulty(self):
        return bits_difficulty(self.q("SELECT bits FROM blk WHERE height=?", (self.tip()["height"],))[0][0])

    def getinfo(self):
        t = self.tip()
        return {"version": VERSION, "build": "zebend-0.1", "subversion": SUBVERSION, "protocolversion": net.PROTO,
                "blocks": t["height"], "timeoffset": 0, "connections": 1, "proxy": "", "difficulty": self.getdifficulty(),
                "testnet": False, "paytxfee": 0, "relayfee": 0.000001, "errors": ""}

    def getblockchaininfo(self):
        t = self.tip()
        h = t["height"]
        best = self.q("SELECT time, bits FROM blk WHERE height=?", (h,))[0]
        ups = {}
        for name, br, act in UPGRADES:
            ups[br] = {"name": name, "activationheight": act, "status": "active" if h >= act else "pending", "info": ""}
        pools = self.pools()
        vp = []
        for p in ("sprout", "sapling", "orchard", "ironwood"):
            e = {"id": p, "monitored": pools is not None}
            if pools and p in pools:
                e["chainValue"], e["chainValueZat"] = pools[p] / 1e8, pools[p]
            vp.append(e)
        return {"chain": "main", "blocks": h, "initial_block_download_complete": h >= self.idx.n - 1,
                "headers": max(h, self.idx.n - 1), "bestblockhash": t["hash"], "difficulty": bits_difficulty(best[1]),
                "verificationprogress": min(1.0, h / max(1, self.idx.n - 1)), "chainwork": "0" * 64,
                "pruned": True, "size_on_disk": sum(p.stat().st_size for p in STATE.rglob("*") if p.is_file()),
                "estimatedheight": self.idx.n - 1, "commitments": 0, "valuePools": vp, "softforks": [],
                "upgrades": ups, "consensus": {"chaintip": self.branch_at(h), "nextblock": self.branch_at(h + 1)}}

    def _hdr_json(self, h):
        raw = self.header(h)
        r = self.q("SELECT hash, size, ntx, time, bits FROM blk WHERE height=?", (h,))[0]
        nxt = self.q("SELECT hash FROM blk WHERE height=?", (h + 1,))
        tip = self.tip()["height"]
        ver, = struct.unpack_from("<i", raw, 0)
        j = {"hash": r[0].hex(), "confirmations": tip - h + 1, "height": h, "version": ver,
             "merkleroot": raw[36:68][::-1].hex(), "finalsaplingroot": raw[68:100][::-1].hex(),
             "time": struct.unpack_from("<I", raw, 100)[0], "nonce": raw[108:140][::-1].hex(),
             "solution": raw[143:HDR].hex(), "bits": raw[104:108][::-1].hex(),
             "difficulty": bits_difficulty(raw[104:108][::-1].hex()), "chainwork": "0" * 64,
             "previousblockhash": raw[4:36][::-1].hex()}
        if h >= 1687104:
            j["blockcommitments"] = j.pop("finalsaplingroot")
        if h == 0:
            del j["previousblockhash"]
        if nxt:
            j["nextblockhash"] = nxt[0][0].hex()
        return j, raw

    def getblockheader(self, hsh, verbose=True):
        h = self.height_of(hsh)
        j, raw = self._hdr_json(h)
        return j if verbose else raw.hex()

    def getblock(self, hsh, verbosity=1):
        h = self.height_of(hsh)
        verbosity = int(verbosity)
        raw, b = self.src.get(h)
        if verbosity == 0:
            return raw.hex()
        j, _ = self._hdr_json(h)
        j["size"] = len(raw)
        sizes = self.tree_sizes()
        if verbosity == 1:
            j["tx"] = [t["txid"] for t in b["txs"]]
        else:
            j["tx"] = [self._tx_json(t, raw, b, h) for t in b["txs"]]
        j["trees"] = {}
        return j

    def _tx_slices(self, raw, b):
        off = HDR + (1 if len(b["txs"]) < 0xfd else 3 if len(b["txs"]) <= 0xffff else 5)
        out = []
        for t in b["txs"]:
            out.append(raw[off:off + t["size"]])
            off += t["size"]
        return out

    def _tx_json(self, t, raw, b, h):
        sl = self._tx_slices(raw, b)[t["i"]]
        vin = []
        if t["cb"]:
            vin.append({"coinbase": t["cbscript"], "sequence": 4294967295})
        for (ptx, n, seq) in t["ins"]:
            vin.append({"txid": ptx, "vout": n, "sequence": seq})
        vout = []
        for (k, v, s) in t["outs"]:
            o = {"value": v / 1e8, "valueZat": v, "n": k, "scriptPubKey": {"hex": s.hex()}}
            a = script_addr(s)
            if a:
                o["scriptPubKey"]["addresses"] = [a]
            vout.append(o)
        j = {"hex": sl.hex(), "txid": t["txid"], "version": t["v"], "overwintered": t["ow"], "locktime": t["lock"],
             "expiryheight": t["exp"], "vin": vin, "vout": vout, "height": h, "size": t["size"],
             "vjoinsplit": [{"vpub_old": j_["vpub_old"] / 1e8, "vpub_new": j_["vpub_new"] / 1e8} for j_ in t["js"]]}
        if t["ow"]:
            j["versiongroupid"] = t["grp"]
        if t["sap"]:
            j["valueBalanceZat"] = t["sap"]["vb"]
            j["valueBalance"] = t["sap"]["vb"] / 1e8
        for key, pool in (("orch", "orchard"), ("iw", "ironwood")):
            if t[key]:
                j[pool] = {"valueBalanceZat": t[key]["vb"], "valueBalance": t[key]["vb"] / 1e8,
                           "anchor": t[key]["anchor"], "actions": t[key]["n"]}
        return j

    def getrawtransaction(self, txid, verbose=0):
        r = self.q("SELECT height, idx FROM tx WHERE txid=?", (bytes.fromhex(txid)[::-1],))
        if not r:
            raise RpcError(-5, "No such mempool or blockchain transaction")
        h, i = r[0]
        raw, b = self.src.get(h)
        t = b["txs"][i]
        if t["txid"] != txid:
            raise RpcError(-1, "tx index inconsistent with the block")
        if not int(verbose):
            return self._tx_slices(raw, b)[i].hex()
        j = self._tx_json(t, raw, b, h)
        tip = self.tip()["height"]
        j.update({"blockhash": b["hash"], "confirmations": tip - h + 1, "time": b["time"], "blocktime": b["time"]})
        return j

    def sendrawtransaction(self, hexstr, *_):
        raw = bytes.fromhex(hexstr)
        # txid and well-formedness from Bend: wrap the tx as the only tx of a dummy block record
        # (blockdelta's wire validator + txid code); the dummy header/merkle lines are ignored.
        dummy = bytes(140) + b"\xfd\x40\x05" + bytes(1344) + b"\x01" + raw
        tmp = HERE / "work" / f"sendraw_{threading.get_ident()}.bin"
        tmp.parent.mkdir(exist_ok=True)
        tmp.write_bytes(struct.pack("<I", 0) + bytes(HDR) + struct.pack("<I", len(dummy)) + dummy)
        out = subprocess.run([str(BIN / "blockdelta"), str(tmp)], capture_output=True).stdout.decode()
        tmp.unlink(missing_ok=True)
        b = sync.parse_delta(out)
        if not b or "invalid" in b[0] or not b[0]["txs"]:
            raise RpcError(-22, "TX decode failed (rejected by the Bend wire validator)")
        txid = b[0]["txs"][0]["txid"]
        sent = relay_tx(raw)
        if not sent:
            raise RpcError(-1, "no peer accepted the connection to relay the transaction")
        return txid

    def z_gettreestate(self, hsh):
        h = self.height_of(hsh)
        r = self.q("SELECT hash, time FROM blk WHERE height=?", (h,))[0]
        res = {"hash": r[0].hex(), "height": h, "time": r[1]}
        # Tree states need the note commitment tree frontiers. Sapling (Pedersen hash) and Sprout
        # trees are pending components; Orchard/Ironwood frontiers come from the tree builder.
        for pool in ("sprout", "sapling", "orchard"):
            res[pool] = {"commitments": {"finalState": ""}, "skipped": "tree builder pending"}
        return res

    def _addresses(self, arg):
        if isinstance(arg, dict):
            arg = arg.get("addresses", [])
        if isinstance(arg, str):
            arg = [arg]
        return arg

    def getaddressutxos(self, arg, *_):
        if self.q("SELECT v FROM meta WHERE k='addr_deferred' AND v='true'"):
            raise RpcError(-1, "address index deferred until the sync passes the last checkpoint (store.py)")
        out = []
        tip = self.tip()["height"]
        for a in self._addresses(arg):
            s = addr_script(a)
            for (op,) in self.q("SELECT op FROM addr WHERE script=?", (s,)):
                v, sc, h, cb = self.q("SELECT value, script, height, cb FROM utxo WHERE op=?", (op,))[0]
                out.append({"address": a, "txid": op[:32][::-1].hex(), "outputIndex": struct.unpack("<I", op[32:])[0],
                            "script": sc.hex(), "satoshis": v, "height": h})
        return out

    def getaddressbalance(self, arg, *_):
        bal = sum(u["satoshis"] for u in self.getaddressutxos(arg))
        return {"balance": bal, "received": None, "note": "received is not tracked (UTXO-only index)"}

    def getaddresstxids(self, arg, *_):
        return sorted({u["txid"] for u in self.getaddressutxos(arg)})

    def getpeerinfo(self):
        return []

    def getnetworkinfo(self):
        return {"version": VERSION, "subversion": SUBVERSION, "protocolversion": net.PROTO, "connections": 1,
                "relayfee": 0.000001, "localservices": "0000000000000000"}

    def getmininginfo(self):
        return {"blocks": self.tip()["height"], "difficulty": self.getdifficulty(), "chain": "main", "testnet": False}

    def help(self, *_):
        return "\n".join(sorted(m for m in dir(self) if not m.startswith("_") and callable(getattr(self, m))
                                and m not in ("q", "tip", "height_of", "header", "branch_at", "pools", "tree_sizes")))


def relay_tx(raw):
    """Announce-free relay: send the `tx` message directly to a few peers."""
    sent = 0
    for ip in net.dns_candidates()[:12]:
        try:
            p = net.Peer(ip, timeout=6)
            p.s.sendall(net.frame("tx", raw))
            time.sleep(0.5)
            p.close()
            sent += 1
        except Exception:
            continue
        if sent >= 4:
            break
    return sent


def make_handler(node):
    methods = {m: getattr(node, m) for m in dir(node) if not m.startswith("_") and callable(getattr(node, m))}

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                req = json.loads(body)
            except ValueError:
                return self._send(400, {"result": None, "error": {"code": -32700, "message": "Parse error"}, "id": None})
            reqs = req if isinstance(req, list) else [req]
            outs = [self._one(r) for r in reqs]
            self._send(200, outs if isinstance(req, list) else outs[0])

        def _one(self, r):
            rid, m, params = r.get("id"), r.get("method"), r.get("params") or []
            if m not in methods or m in ("q", "tip", "height_of", "header", "branch_at", "pools", "tree_sizes"):
                return {"result": None, "error": {"code": -32601, "message": "Method not found"}, "id": rid}
            try:
                return {"result": methods[m](*params), "error": None, "id": rid}
            except RpcError as e:
                return {"result": None, "error": {"code": e.code, "message": e.msg}, "id": rid}
            except (TypeError, ValueError, IndexError) as e:
                return {"result": None, "error": {"code": -8, "message": f"{e.__class__.__name__}: {e}"}, "id": rid}

        def _send(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8232)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    node = Node()
    srv = ThreadingHTTPServer((a.bind, a.port), make_handler(node))
    print(f"zebend rpc on {a.bind}:{a.port}, tip {node.tip()['height']}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
