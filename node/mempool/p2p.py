"""P2P transport for the Zebend mempool: an inbound listener and outbound peers.

Transport only (Python moves bytes; every transaction is decided by Bend in admit.py):
  * handshake: version/verack both ways (relay flag 1, services 0: we serve no blocks),
    self-connection detection by nonce; ping -> pong; getaddr -> addr (known good peers);
    addr/addrv2 -> address book; getheaders/getblocks -> empty answers (as net.py does)
  * transactions: inv (MSG_TX = 1 for v1-v4, MSG_WTX = 5, ZIP 239, txid || auth digest for
    v5+) -> getdata for unknown ids (at most MAX_INFLIGHT per peer, retried from another
    announcer after DL_TIMEOUT s or a notfound); tx -> admission queue; getdata -> tx or
    notfound; mempool (BIP 35) -> inv of the whole mempool; admitted txs are announced by inv
    to every other peer (batched every RELAY_EVERY s); every CRAWL_EVERY s we send `mempool`
    to up to CRAWL_PEERS peers (Zebra's crawler does the same with MempoolTransactionIds)
  * per-peer rate limits (token buckets): messages, inv entries and tx bytes; a peer that keeps
    exceeding them is disconnected and banned for BAN_SECS
  * blocks: getdata for a block by hash (node.py's block cache for reorg re-admission); the
    block is checked by Bend (blockdelta) before use
"""
import collections, hashlib, random, socket, struct, sys, threading, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import net  # node/net.py: framing helpers, DNS seeds, addr parsing (read-only use)

MAGIC, PROTO = net.MAGIC, net.PROTO
MSG_TX, MSG_BLOCK, MSG_WTX = 1, 2, 5
UA = b"/Zebend-mempool:0.1/"
MAX_MSG = 2 * 1024 * 1024        # Zebra MAX_PROTOCOL_MESSAGE_LEN
MAX_INFLIGHT = 50                # tx getdata outstanding per peer
DL_TIMEOUT = 20
RELAY_EVERY = 0.5
CRAWL_EVERY = 75
CRAWL_PEERS = 3
BAN_SECS = 1800
# token buckets per peer: (rate per second, burst)
MSG_RATE = (50, 500)
INV_RATE = (500, 50_000)
TX_BYTES_RATE = (1_000_000, 8_000_000)
MAX_VIOLATIONS = 200


def netaddr(ip, port, services=0):
    raw = socket.inet_pton(socket.AF_INET6, ip) if ":" in ip else b"\0" * 10 + b"\xff\xff" + socket.inet_aton(ip)
    return struct.pack("<Q", services) + raw + struct.pack(">H", port)


def version_payload(ip, port, height, nonce, listen_port):
    return (struct.pack("<iQq", PROTO, 0, int(time.time())) + netaddr(ip, port) + netaddr("0.0.0.0", listen_port)
            + struct.pack("<Q", nonce) + net.varint(len(UA)) + UA + struct.pack("<i", height) + b"\x01")


def parse_inv(p):
    out = []
    n, i = net.read_cs(p, 0)
    for _ in range(min(n, 50_000)):
        typ = struct.unpack_from("<I", p, i)[0]
        k = 64 if typ == MSG_WTX else 32
        h = bytes(p[i + 4:i + 4 + k])
        if len(h) != k:
            raise ValueError("truncated inv")
        out.append((typ, h))
        i += 4 + k
    return out


def build_inv(entries):
    return net.varint(len(entries)) + b"".join(struct.pack("<I", t) + h for t, h in entries)


class Bucket:
    def __init__(self, rate, burst):
        self.rate, self.burst, self.v, self.t = rate, burst, burst, time.time()

    def take(self, n=1):
        now = time.time()
        self.v = min(self.burst, self.v + (now - self.t) * self.rate)
        self.t = now
        if self.v >= n:
            self.v -= n
            return True
        return False


class Conn:
    def __init__(self, mgr, sock, ip, port, inbound):
        self.mgr, self.s, self.ip, self.port, self.inbound = mgr, sock, ip, port, inbound
        self.buf, self.pos = bytearray(), 0
        self.wlock = threading.Lock()
        self.ua, self.height, self.services, self.version = "?", 0, 0, 0
        self.ready = False
        self.alive = True
        self.t0 = time.time()
        self.known = collections.OrderedDict()   # inventory ids this peer has or was sent
        self.inflight = {}                       # txid -> time of our getdata
        self.inv_out = []                        # inv entries to announce (flushed by the manager)
        self.b_msg, self.b_inv, self.b_tx = Bucket(*MSG_RATE), Bucket(*INV_RATE), Bucket(*TX_BYTES_RATE)
        self.violations = 0
        self.counts = collections.Counter()
        self.last_recv = time.time()

    def know(self, h):
        self.known[h] = 1
        if len(self.known) > 100_000:
            self.known.popitem(last=False)

    def send(self, cmd, payload):
        with self.wlock:
            self.s.sendall(net.frame(cmd, payload))
        self.counts["sent " + cmd] += 1

    def recv(self):
        while True:
            b, i = self.buf, self.pos
            if len(b) - i >= 24:
                if b[i:i + 4] != MAGIC:
                    raise ConnectionError("bad magic")
                n = struct.unpack_from("<I", b, i + 16)[0]
                if n > MAX_MSG:
                    raise ConnectionError("oversized message")
                if len(b) - i >= 24 + n:
                    cmd = bytes(b[i + 4:i + 16]).rstrip(b"\0").decode(errors="replace")
                    p = bytes(b[i + 24:i + 24 + n])
                    if net.checksum(p) != bytes(b[i + 20:i + 24]):
                        raise ConnectionError("bad checksum")
                    self.pos = i + 24 + n
                    if self.pos > (1 << 20):
                        del b[:self.pos]
                        self.pos = 0
                    self.last_recv = time.time()
                    return cmd, p
            d = self.s.recv(1 << 20)
            if not d:
                raise ConnectionError("peer closed")
            b += d

    def handshake(self, height, nonce, listen_port, timeout=10):
        self.s.settimeout(timeout)
        if not self.inbound:
            self.send("version", version_payload(self.ip, self.port, height, nonce, listen_port))
        got_v = got_va = False
        deadline = time.time() + timeout
        while not (got_v and got_va):
            if time.time() > deadline:
                raise TimeoutError("handshake timeout")
            cmd, p = self.recv()
            if cmd == "version":
                if got_v:
                    raise ConnectionError("duplicate version")
                got_v = True
                self.version, self.services = struct.unpack_from("<iQ", p, 0)
                their_nonce = struct.unpack_from("<Q", p, 72)[0]
                if their_nonce == nonce:
                    raise ConnectionError("connected to ourselves")
                n, i = net.read_cs(p, 80)
                self.ua = bytes(p[i:i + n]).decode(errors="replace")[:80]
                self.height = struct.unpack_from("<i", p, i + n)[0]
                if self.inbound:
                    self.send("version", version_payload(self.ip, self.port, height, nonce, listen_port))
                self.send("verack", b"")
            elif cmd == "verack":
                got_va = True
        self.ready = True
        self.s.settimeout(2)

    def close(self):
        self.alive = False
        try:
            self.s.close()
        except OSError:
            pass


class P2P:
    def __init__(self, node, port=8233, bind="::", outbound=8, log=print, book=None, connect=(), listen=True,
                 max_inbound=64, per_ip=1, seeds=True):
        self.node, self.port, self.bind, self.n_out, self.log = node, port, bind, outbound, log
        self.book_path = Path(book) if book else None
        self.connect, self.listen, self.max_inbound, self.per_ip, self.seeds = list(connect), listen, max_inbound, per_ip, seeds
        self.lock = threading.RLock()
        self.conns = {}             # id -> Conn
        self.connecting = set()
        self.nonce = random.getrandbits(64)
        self.book = collections.OrderedDict()
        self.backoff = {}           # ip -> (fails, until)
        self.banned = {}            # ip -> until
        self.pending = {}           # txid -> {"conn", "t", "ann": [(conn, typ, h)]}
        self.block_wait = {}        # prev hash (internal) -> [Event, raw]
        self.stats = collections.Counter()
        self.relayed = {}           # txid -> {"t", "to": n peers, "source", "getdata": [(ip, dt)], "inv_back": [(ip, dt)]}
        self.announced_auth = {}    # txid -> auth digest from a peer's MSG_WTX inv (cross-check of Bend's)
        self.stop = False
        for ip in self._load_book():
            self.book[ip] = 1

    # ------------------------------------------------------------ address book
    def _load_book(self):
        out = []
        for p in ([self.book_path] if self.book_path else []) + [HERE.parent / "state-tip/peers.txt"]:
            try:
                out += [net.norm(l) for l in p.read_text().splitlines() if l.strip()]
            except OSError:
                pass
        return out

    def save_book(self):
        if not self.book_path:
            return
        with self.lock:
            good = [c.ip for c in self.conns.values() if not c.inbound and c.ready]
            ips = list(dict.fromkeys(good + list(self.book)))[:3000]
        self.book_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.book_path.with_suffix(".new")
        tmp.write_text("\n".join(ips) + "\n")
        tmp.replace(self.book_path)

    # ------------------------------------------------------------ lifecycle
    def start(self):
        if self.listen:
            threading.Thread(target=self._listen, daemon=True).start()
        threading.Thread(target=self._maintain, daemon=True).start()
        threading.Thread(target=self._tick, daemon=True).start()

    def _listen(self):
        fam = socket.AF_INET6 if ":" in self.bind else socket.AF_INET
        srv = socket.socket(fam, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if fam == socket.AF_INET6:
            try:
                srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        srv.bind((self.bind, self.port))
        srv.listen(64)
        self.log(f"p2p: listening on [{self.bind}]:{self.port}")
        while not self.stop:
            try:
                s, addr = srv.accept()
            except OSError:
                continue
            ip = net.norm(addr[0])
            with self.lock:
                n_in = sum(1 for c in self.conns.values() if c.inbound)
                same = sum(1 for c in self.conns.values() if c.ip == ip)
                loop = ip in ("127.0.0.1", "::1")
                refuse = (n_in >= self.max_inbound or self.banned.get(ip, 0) > time.time()
                          or (same >= self.per_ip and not loop))
            if refuse:
                self.stats["inbound refused"] += 1
                s.close()
                continue
            threading.Thread(target=self._run_conn, args=(s, ip, addr[1], True), daemon=True).start()

    def _maintain(self):
        last_dns, last_save = 0, time.time()
        while not self.stop:
            with self.lock:
                n_out = sum(1 for c in self.conns.values() if not c.inbound) + len(self.connecting)
                busy = {c.ip for c in self.conns.values()} | set(self.connecting)
            for hp in self.connect:  # manual peers (host:port), always kept
                ip, port = hp.rsplit(":", 1)
                key = f"{ip}:{port}"
                with self.lock:
                    up = any(f"{c.ip}:{c.port}" == key for c in self.conns.values()) or key in self.connecting
                    if not up and self.backoff.get(key, (0, 0))[1] <= time.time():
                        self.connecting.add(key)
                        threading.Thread(target=self._dial, args=(ip.strip("[]"), int(port), key), daemon=True).start()
            if self.seeds and n_out < self.n_out:
                if time.time() - last_dns > 600 or len(self.book) < 20:
                    for ip in net.dns_candidates():
                        self.book.setdefault(ip, 1)
                    last_dns = time.time()
                now = time.time()
                with self.lock:
                    cands = [ip for ip in self.book if ip not in busy and self.backoff.get(ip, (0, 0))[1] <= now
                             and self.banned.get(ip, 0) <= now]
                random.shuffle(cands)
                for ip in cands[:min(3, self.n_out - n_out)]:
                    with self.lock:
                        self.connecting.add(ip)
                    threading.Thread(target=self._dial, args=(ip, 8233, ip), daemon=True).start()
            if time.time() - last_save > 300:
                try:
                    self.save_book()
                except OSError:
                    pass
                last_save = time.time()
            time.sleep(2)

    def _fail(self, key):
        with self.lock:
            f, _ = self.backoff.get(key, (0, 0))
            self.backoff[key] = (f + 1, time.time() + min(3600, 60 * 2 ** f))

    def _dial(self, ip, port, key):
        try:
            s = socket.create_connection((ip, port), timeout=8)
        except OSError:
            with self.lock:
                self.connecting.discard(key)
            self._fail(key)
            self.stats["dial failed"] += 1
            return
        with self.lock:
            self.connecting.discard(key)
        self._run_conn(s, ip, port, False, key)

    def _run_conn(self, s, ip, port, inbound, key=None):
        c = Conn(self, s, ip, port, inbound)
        try:
            c.handshake(self.node.tip_height(), self.nonce, self.port)
        except Exception as e:
            self.stats[f"handshake failed ({'in' if inbound else 'out'})"] += 1
            c.close()
            if key:
                self._fail(key)
            return
        with self.lock:
            cid = id(c)
            self.conns[cid] = c
            if key:
                self.backoff[key] = (0, 0)
        self.stats["handshakes in" if inbound else "handshakes out"] += 1
        self.log(f"p2p: {'inbound' if inbound else 'outbound'} peer {ip}:{port} {c.ua} height {c.height}")
        reason = "closed"
        try:
            c.send("getaddr", b"")
            c.send("mempool", b"")  # BIP 35: the peer answers with inv of its mempool
            while c.alive and not self.stop:
                try:
                    cmd, p = c.recv()
                except (socket.timeout, TimeoutError):
                    if time.time() - c.last_recv > 600:
                        raise TimeoutError("idle 10 min")
                    continue
                c.counts[cmd] += 1
                if not c.b_msg.take():
                    c.violations += 1
                    self.stats["rate-limited messages"] += 1
                    if c.violations > MAX_VIOLATIONS:
                        raise ConnectionError("rate limit exceeded")
                    continue
                self._on_msg(c, cmd, p)
        except Exception as e:
            reason = f"{e.__class__.__name__}: {str(e)[:40]}"
            if "rate limit" in reason:
                self.banned[ip] = time.time() + BAN_SECS
        finally:
            c.close()
            with self.lock:
                self.conns.pop(id(c), None)
                for txid, d in list(self.pending.items()):
                    if d["conn"] is c:
                        self._retry(txid)
            if not inbound and key and time.time() - c.t0 < 60:
                self._fail(key)
            self.log(f"p2p: peer {ip}:{port} gone after {time.time() - c.t0:.0f} s ({reason})")

    # ------------------------------------------------------------ messages
    def _on_msg(self, c, cmd, p):
        if cmd == "ping":
            c.send("pong", p)
        elif cmd in ("addr", "addrv2"):
            for ip in net.parse_addr(cmd, p)[:1000]:
                self.book.setdefault(net.norm(ip), 1)
            while len(self.book) > 5000:
                self.book.popitem(last=False)
        elif cmd == "getaddr":
            c.send("addr", self._addr_payload())
        elif cmd == "getheaders":
            c.send("headers", b"\0")
        elif cmd == "getblocks":
            c.send("inv", b"\0")
        elif cmd == "inv":
            self._on_inv(c, p)
        elif cmd == "getdata":
            self._on_getdata(c, p)
        elif cmd == "notfound":
            for typ, h in parse_inv(p):
                if typ == MSG_BLOCK:
                    for w in list(self.block_wait.values()):
                        if w[2] == h:
                            w[0].set()
                if typ in (MSG_TX, MSG_WTX):
                    txid = h[:32][::-1].hex()
                    with self.lock:
                        d = self.pending.get(txid)
                        if d and d["conn"] is c:
                            c.inflight.pop(txid, None)
                            self._retry(txid)
        elif cmd == "tx":
            if not c.b_tx.take(len(p)):
                c.violations += 10
                self.stats["rate-limited tx bytes"] += 1
                return
            self.stats["tx received"] += 1
            self.node.submit(p, f"p2p {c.ip}", c)
        elif cmd == "mempool":
            ents = self.node.inventory()
            for k in range(0, len(ents), 1000):
                c.send("inv", build_inv(ents[k:k + 1000]))
            for _t, h in ents:
                c.know(h)
        elif cmd == "block":
            w = self.block_wait.get(p[4:36])
            if w:
                w[1] = p
                w[0].set()

    def _addr_payload(self):
        with self.lock:
            good = [c.ip for c in self.conns.values() if not c.inbound and c.ready]
            rest = [ip for ip in list(self.book)[:500] if ip not in good]
        random.shuffle(rest)
        ips = (good + rest)[:50]
        now = int(time.time())
        out = []
        for ip in ips:
            try:
                out.append(struct.pack("<I", now - random.randint(0, 3600)) + netaddr(ip, 8233, 1))
            except OSError:
                continue
        return net.varint(len(out)) + b"".join(out)

    def _on_inv(self, c, p):
        ents = parse_inv(p)
        if not c.b_inv.take(len(ents)):
            c.violations += 1
            self.stats["rate-limited inv entries"] += len(ents)
            return
        want = []
        now = time.time()
        with self.lock:
            for typ, h in ents:
                if typ not in (MSG_TX, MSG_WTX):
                    if typ == MSG_BLOCK:
                        self.node.block_announced()
                    continue
                c.know(h)
                txid = h[:32][::-1].hex()
                self.stats["tx inv received"] += 1
                r = self.relayed.get(txid)
                if r is not None and c.ip != r["source"]:
                    r["inv_back"].append((c.ip, round(now - r["t"], 2), c.ip in r.get("to_peers", ())))
                auth = h[32:].hex() if typ == MSG_WTX else None
                if auth:
                    self.announced_auth[txid] = auth
                    if len(self.announced_auth) > 50000:
                        self.announced_auth.pop(next(iter(self.announced_auth)))
                if not self.node.wants(txid, auth):
                    continue
                d = self.pending.get(txid)
                if d is not None:
                    d["ann"].append((c, typ, h))
                    continue
                if len(c.inflight) >= MAX_INFLIGHT:
                    self.pending[txid] = {"conn": None, "t": 0, "ann": [(c, typ, h)]}
                    continue
                self.pending[txid] = {"conn": c, "t": now, "ann": [], "typ": typ, "h": h}
                c.inflight[txid] = now
                want.append((typ, h))
        if want:
            self.stats["tx getdata sent"] += len(want)
            c.send("getdata", build_inv(want))

    def _retry(self, txid):
        """Caller holds the lock: ask the next announcer for txid, or forget it."""
        d = self.pending.get(txid)
        if d is None:
            return
        if d["conn"] is not None:
            d["conn"].inflight.pop(txid, None)
        while d["ann"]:
            c, typ, h = d["ann"].pop(0)
            if c.alive and len(c.inflight) < MAX_INFLIGHT:
                d.update(conn=c, t=time.time(), typ=typ, h=h)
                c.inflight[txid] = d["t"]
                try:
                    c.send("getdata", build_inv([(typ, h)]))
                    self.stats["tx getdata retried"] += 1
                    return
                except OSError:
                    continue
        del self.pending[txid]

    def done(self, txid):
        """Admission finished for txid (any outcome): stop tracking its download."""
        with self.lock:
            d = self.pending.pop(txid, None)
            if d and d["conn"] is not None:
                d["conn"].inflight.pop(txid, None)

    def _on_getdata(self, c, p):
        found, missing = [], []
        for typ, h in parse_inv(p):
            if typ in (MSG_TX, MSG_WTX):
                e = self.node.lookup(h)
                if e is not None:
                    found.append(e)
                    r = self.relayed.get(e.txid)
                    if r is not None:
                        r["getdata"].append((c.ip, round(time.time() - r["t"], 2)))
                    continue
            missing.append((typ, h))
        for e in found:
            c.send("tx", e.raw)
            self.stats["tx served"] += 1
        if missing:
            c.send("notfound", build_inv(missing))

    # ------------------------------------------------------------ relay
    def relay(self, e, source=None):
        h = e.wtxid
        typ = MSG_WTX if e.v >= 5 else MSG_TX
        n, to = 0, []
        with self.lock:
            for c in self.conns.values():
                if c is source or not c.ready or h in c.known:
                    continue
                c.inv_out.append((typ, h))
                c.know(h)
                n += 1
                to.append(c.ip)
            self.relayed[e.txid] = {"t": time.time(), "to": n, "to_peers": to, "source": source.ip if source else "rpc",
                                    "getdata": [], "inv_back": []}
            if len(self.relayed) > 20000:
                for k in list(self.relayed)[:5000]:
                    del self.relayed[k]
        self.stats["tx relayed (inv queued)"] += n
        return n

    def _tick(self):
        last_crawl = 0
        while not self.stop:
            time.sleep(RELAY_EVERY)
            with self.lock:
                conns = list(self.conns.values())
            for c in conns:
                if c.inv_out:
                    ents, c.inv_out = c.inv_out[:1000], c.inv_out[1000:]
                    try:
                        c.send("inv", build_inv(ents))
                    except OSError:
                        c.close()
            now = time.time()
            with self.lock:
                for txid, d in list(self.pending.items()):
                    if d["conn"] is None:
                        if d["ann"]:
                            self._retry(txid)
                        else:
                            del self.pending[txid]
                    elif now - d["t"] > DL_TIMEOUT:
                        self.stats["tx download timeouts"] += 1
                        self._retry(txid)
            if now - last_crawl > CRAWL_EVERY:
                last_crawl = now
                ready = [c for c in conns if c.ready and not c.inbound]
                for c in random.sample(ready, min(CRAWL_PEERS, len(ready))):
                    try:
                        c.send("mempool", b"")
                    except OSError:
                        pass

    # ------------------------------------------------------------ blocks (for the reorg cache)
    def fetch_block(self, hash_internal, prev_internal, height, timeout=10):
        with self.lock:
            peers = [c for c in self.conns.values() if c.ready and not c.inbound and c.services & 1
                     and c.height + 100 >= height]  # version start height: a synced peer keeps up
        random.shuffle(peers)
        for c in peers[:4]:
            ev = threading.Event()
            self.block_wait[prev_internal] = [ev, None, hash_internal]
            try:
                c.send("getdata", build_inv([(MSG_BLOCK, hash_internal)]))
            except OSError:
                continue
            got = ev.wait(timeout)
            raw = self.block_wait.pop(prev_internal, [None, None])[1]
            self.stats["block fetched" if raw else ("block notfound" if got else "block timeout")] += 1
            if raw:
                return raw
        if not peers:
            self.stats["block fetch: no peer at that height"] += 1
        return None

    def peer_info(self):
        with self.lock:
            return [{"addr": f"{c.ip}:{c.port}", "inbound": c.inbound, "subver": c.ua, "startingheight": c.height,
                     "conntime": int(c.t0), "version": c.version, "services": c.services, "inflight": len(c.inflight),
                     "violations": c.violations,
                     "counts": {k: v for k, v in c.counts.items() if k in ("tx", "inv", "getdata", "sent inv", "sent tx")}}
                    for c in self.conns.values() if c.ready]
