"""Block transport for the Zebend full node: download blocks fast from many mainnet peers.

Transport only: frames P2P messages (the wire protocol's 4-byte checksum uses hashlib) and asks
peers for blocks by hash. It parses no block: a block is identified only by the 32 bytes of its
hashPrevBlock field (to place it at a height) and written to the spool as raw bytes. Bend
(`bin/blockdelta`) later checks each block's header is byte-identical to the verified header at
that height and that its transactions hash to the header's merkle root.

How peers serve blocks (Zebra main, zebrad/src/components/inbound.rs and
zebra-network/src/{constants.rs,peer/connection.rs}), and what this module does about it:
  * one inbound connection per IP (DEFAULT_MAX_CONNS_PER_IP = 1) and at most one inbound
    connection per second per node (MIN_INBOUND_PEER_CONNECTION_INTERVAL): we keep exactly one
    long-lived connection per peer IP, never a second, and back off exponentially (60 s x 2^k,
    <= 1 h) after a refused handshake or a lost connection;
  * a getdata is served sequentially, at most 16 blocks / 1 MB (GETDATA_MAX_BLOCK_COUNT,
    GETDATA_SENT_BYTES_LIMIT), one request at a time per connection; a response that takes more
    than 5 s (MAX_INBOUND_RESPONSE_TIME) or hits a loaded inbound service makes Zebra drop the
    connection with some probability: requests are sized per peer from its measured
    seconds-per-block so one response takes ~2 s, and a few are pipelined (queued in TCP) so the
    peer is never idle waiting for our next request;
  * peers are scored by measured bytes/s; work is pulled by whichever peer is ready (fast peers
    take more), and peers far slower than the median are evicted when others are waiting.
"""
import collections, hashlib, random, socket, struct, threading, time
from pathlib import Path

MAGIC = bytes.fromhex("24e92764")
PROTO = 170190
# Zebra's mainnet initial peers (zebra-network/src/config.rs) + the ones follow used.
SEEDS = ["dnsseed.str4d.xyz", "dnsseed.z.cash", "mainnet.seeder.shieldedinfra.net", "mainnet.seeder.zfnd.org",
         "seeder.zec.rocks", "mainnet.is.yolo.money"]
KNOWN = ["136.115.98.175", "34.80.219.125", "54.39.196.12", "38.190.136.76"]
MSG_BLOCK = 2
NODE_NETWORK = 1


def checksum(p):
    return hashlib.sha256(hashlib.sha256(p).digest()).digest()[:4]


def frame(cmd, p):
    return MAGIC + cmd.encode().ljust(12, b"\0") + struct.pack("<I", len(p)) + checksum(p) + p


def varint(n):
    if n < 0xfd:
        return bytes([n])
    return b"\xfd" + struct.pack("<H", n) if n <= 0xffff else b"\xfe" + struct.pack("<I", n)


def read_cs(b, i):
    x = b[i]
    if x < 0xfd:
        return x, i + 1
    if x == 0xfd:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    if x == 0xfe:
        return struct.unpack_from("<I", b, i + 1)[0], i + 5
    return struct.unpack_from("<Q", b, i + 1)[0], i + 9


def netaddr(ip, port):
    raw = socket.inet_pton(socket.AF_INET6, ip) if ":" in ip else b"\0" * 10 + b"\xff\xff" + socket.inet_aton(ip)
    return struct.pack("<Q", 0) + raw + struct.pack(">H", port)


def version_msg(ip, height=0):
    ua = b"/Zebend-fullnode:0.1/"
    return (struct.pack("<iQq", PROTO, 0, int(time.time())) + netaddr(ip, 8233) + netaddr("0.0.0.0", 0)
            + struct.pack("<Q", random.getrandbits(64)) + bytes([len(ua)]) + ua + struct.pack("<i", height) + b"\0")


def norm(ip):
    """One spelling per node: an IPv4-mapped IPv6 address is the IPv4 address."""
    ip = ip.strip()
    return ip[7:] if ip.lower().startswith("::ffff:") and "." in ip else ip


class Peer:
    def __init__(self, ip, timeout=8):
        self.ip = ip
        self.s = socket.create_connection((ip, 8233), timeout=timeout)
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
        self.buf, self.pos = bytearray(), 0
        self.last_cmds = []
        self.user_agent, self.height, self.services = "?", 0, 0
        self.addrs = []
        self.s.sendall(frame("version", version_msg(ip)))
        got_v = got_va = False
        deadline = time.time() + timeout
        while not (got_v and got_va):
            if time.time() > deadline:
                raise TimeoutError("handshake timeout")
            cmd, p = self.recv()
            if cmd == "version":
                got_v = True
                self.services = struct.unpack_from("<Q", p, 4)[0]
                n, i = read_cs(p, 80)
                self.user_agent = bytes(p[i:i + n]).decode(errors="replace")
                self.height = struct.unpack_from("<i", p, i + n)[0]
                self.s.sendall(frame("verack", b""))
            elif cmd == "verack":
                got_va = True
        self.s.sendall(frame("getaddr", b""))

    def recv(self):
        """Next message. Large buffered reads; the buffer is consumed by an offset and compacted
        only occasionally (no per-message memmove of the whole buffer)."""
        while True:
            b, i = self.buf, self.pos
            if len(b) - i >= 24:
                if b[i:i + 4] != MAGIC:
                    raise ConnectionError("bad magic")
                n = struct.unpack_from("<I", b, i + 16)[0]
                if n > 4_000_000:
                    raise ConnectionError("oversized message")
                if len(b) - i >= 24 + n:
                    cmd = bytes(b[i + 4:i + 16]).rstrip(b"\0").decode(errors="replace")
                    p = bytes(b[i + 24:i + 24 + n])
                    self.pos = i + 24 + n
                    if self.pos > (4 << 20):
                        del b[:self.pos]
                        self.pos = 0
                    self.last_cmds = (self.last_cmds + [cmd])[-8:]
                    if cmd == "ping":
                        self.s.sendall(frame("pong", p))
                        continue
                    if cmd in ("addr", "addrv2"):
                        self.addrs += parse_addr(cmd, p)
                        continue
                    # Answer what peers ask of us (we serve nothing): a request left unanswered
                    # times out at the peer, which then drops the connection.
                    if cmd == "getaddr":
                        self.s.sendall(frame("addr", b"\0"))
                        continue
                    if cmd == "getheaders":
                        self.s.sendall(frame("headers", b"\0"))
                        continue
                    if cmd in ("getblocks", "mempool"):
                        self.s.sendall(frame("inv", b"\0"))
                        continue
                    if cmd == "getdata":
                        self.s.sendall(frame("notfound", p))
                        continue
                    return cmd, p
            d = self.s.recv(1 << 22)
            if not d:
                raise ConnectionError("peer closed")
            b += d

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


def parse_addr(cmd, p):
    """Addresses of full nodes (NODE_NETWORK) on port 8233 from addr / addrv2 (IPv4 and IPv6)."""
    out = []
    try:
        n, i = read_cs(p, 0)
        for _ in range(min(n, 1000)):
            if cmd == "addr":
                services = struct.unpack_from("<Q", p, i + 4)[0]
                ip6, port = p[i + 12:i + 28], struct.unpack_from(">H", p, i + 28)[0]
                i += 30
                if port == 8233 and services & NODE_NETWORK:
                    if ip6[:12] == b"\0" * 10 + b"\xff\xff":
                        out.append(socket.inet_ntoa(ip6[12:]))
                    elif ip6[0] & 0xe0 == 0x20:
                        out.append(socket.inet_ntop(socket.AF_INET6, ip6))
            else:
                i += 4
                services, i = read_cs(p, i)
                net, i = p[i], i + 1
                alen, i = read_cs(p, i)
                a = p[i:i + alen]
                i += alen
                port = struct.unpack_from(">H", p, i)[0]
                i += 2
                if port == 8233 and services & NODE_NETWORK:
                    if net == 1 and alen == 4:
                        out.append(socket.inet_ntoa(a))
                    elif net == 2 and alen == 16 and a[0] & 0xe0 == 0x20:
                        out.append(socket.inet_ntop(socket.AF_INET6, a))
    except (IndexError, struct.error, OSError):
        pass
    return out


def dns_candidates():
    ips = list(KNOWN)
    for s in SEEDS:
        for fam in (socket.AF_INET, socket.AF_INET6):
            try:
                ips += [a[4][0] for a in socket.getaddrinfo(s, 8233, fam, socket.SOCK_STREAM)]
            except OSError:
                pass
    return list(dict.fromkeys(norm(i) for i in ips))


class PeerStat:
    def __init__(self):
        self.fails = 0            # consecutive failed sessions/handshakes (backoff exponent)
        self.until = 0.0          # do not connect before this time
        self.bytes = 0            # lifetime bytes delivered
        self.blocks = 0
        self.secs = 0.0           # lifetime connected seconds
        self.ua = "?"
        self.spb = 0.15           # EWMA seconds per block while busy (peer service time)
        self.rate = 0.0           # bytes/s of the current/last session


class Fetcher:
    """Download blocks [start, end) by hash from many peers; deliver them in height order.

    hash_at(h) gives the display-order hash of height h. A block is placed by its
    hashPrevBlock bytes (raw slice, no parsing) against the hashes of the requested heights.
    """
    STALL, COOL_MAX, TARGET_RESPONSE_S, MAX_REQ_BYTES, MAX_RUN, HOL = 25, 3600, 2.0, 1_000_000, 16, 4

    def __init__(self, hash_at, start, end, book, log=print, peers=40, max_buffer=768 << 20, size_hint=None):
        self.hash_at, self.next, self.end, self.log = hash_at, start, end, log
        self.npeers, self.max_buffer, self.book = peers, max_buffer, Path(book)
        self.size_hint = size_hint or (lambda h: 2000 if h < 300_000 else 20_000)
        self.lock = threading.Condition()
        self.todo = collections.deque()
        self.issue = start
        self.done, self.buffered, self.inflight = {}, 0, {}
        self.avg = {}
        self.peers = {}                 # ip -> Peer (connected)
        self.connecting = set()         # ips with a handshake in progress
        self.st = collections.defaultdict(PeerStat)
        self.stop = False
        self.stats = {"bytes": 0, "blocks": 0, "requeued": 0, "t0": time.time()}
        self.per_peer = collections.Counter()
        self.prev_index = {}
        self.hol = {}
        self.drops = collections.Counter()
        self.rejects = collections.Counter()
        self.droplog = collections.deque(maxlen=30)
        self.known = self.load_book()
        self.bad = {}  # compatibility (unused)
        threading.Thread(target=self.maintain, daemon=True).start()

    # ---------------------------------------------------------- address book
    def load_book(self):
        try:
            return list(dict.fromkeys(norm(l) for l in self.book.read_text().splitlines() if l.strip()))
        except OSError:
            return []

    def save_book(self):
        with self.lock:
            ranked = sorted(set(self.known) | set(self.peers), key=lambda ip: -self.st[ip].rate)
        tmp = self.book.with_suffix(".new")
        tmp.write_text("\n".join(ranked[:3000]) + "\n")
        tmp.replace(self.book)

    def backoff(self, ip, served_well=False):
        s = self.st[ip]
        if served_well:
            s.fails = 0
            s.until = time.time() + 60          # Zebra rotated us out: come back after a minute
        else:
            s.fails += 1
            s.until = time.time() + min(self.COOL_MAX, 60 * 2 ** (s.fails - 1))

    # ---------------------------------------------------------- scheduling
    def est(self, h):
        return self.avg.get(h // 1000) or self.size_hint(h)

    def run_for(self, ip):
        """Blocks per request for this peer: ~TARGET_RESPONSE_S of its measured service time,
        <= 16 blocks (and <= 1 MB, applied in take_run): Zebra's limits."""
        s = self.st[ip]
        return max(1, min(self.MAX_RUN, int(self.TARGET_RESPONSE_S / max(s.spb, 0.01))))

    def take_run(self, runlen):
        nx = self.next
        if nx not in self.done and self.inflight.get(nx) == 1 and nx not in self.todo:
            t = self.hol.setdefault(nx, time.time())
            if time.time() - t > self.HOL:
                self.hol[nx] = time.time() + 1e9
                return [x for x in range(nx, nx + 2) if x < self.issue and x not in self.done]
        if self.todo:
            h = self.todo.popleft()
            run, budget = [h], self.MAX_REQ_BYTES - self.est(h)
            while self.todo and self.todo[0] == run[-1] + 1 and budget > self.est(run[-1] + 1) and len(run) < runlen:
                run.append(self.todo.popleft())
                budget -= self.est(run[-1])
            return run
        if self.issue >= self.end or self.buffered + sum(self.est(h) for h in self.inflight) > self.max_buffer:
            return None
        run, budget = [], self.MAX_REQ_BYTES
        while self.issue < self.end and len(run) < runlen and (not run or budget > self.est(self.issue)):
            run.append(self.issue)
            budget -= self.est(self.issue)
            self.issue += 1
        return run

    def endgame_run(self):
        spare = sorted(h for h, n in self.inflight.items() if n < 2 and h not in self.done)
        return spare[:2] or None

    def _release(self, h):
        n = self.inflight.get(h, 1) - 1
        if n <= 0:
            self.inflight.pop(h, None)
            if h not in self.done and h >= self.next and h not in self.todo:
                self.todo.appendleft(h)
                self.stats["requeued"] += 1
        else:
            self.inflight[h] = n

    def worker(self, peer):
        ip, s = peer.ip, self.st[peer.ip]
        zcashd = "MagicBean" in peer.user_agent
        depth = self.depth_for(peer.user_agent)  # requests queued at the peer (served one at a time)
        out = collections.OrderedDict()  # rid -> [set of heights, sent time]
        last = t_start = time.time()
        rid, served, nbytes = 0, 0, 0
        reason = "stop"
        try:
            while not self.stop:
                with self.lock:
                    # Fast peers get a deeper pipeline (requests wait in TCP; Zebra serves one at a time).
                    want = depth + (2 if s.spb < 0.08 and served > 32 else 0)
                    while len(out) < want:
                        run = self.take_run(32 if zcashd else self.run_for(ip)) or \
                            (self.endgame_run() if self.issue >= self.end else None)
                        if not run:
                            break
                        for h in run:
                            self.inflight[h] = self.inflight.get(h, 0) + 1
                            self.prev_index[self.hash_at(h - 1)] = h
                        rid += 1
                        out[rid] = [set(run), time.time()]
                        peer.s.sendall(frame("getdata", varint(len(run)) + b"".join(
                            struct.pack("<I", MSG_BLOCK) + bytes.fromhex(self.hash_at(h))[::-1] for h in run)))
                    if not out:
                        last = time.time()
                        self.lock.wait(0.5)
                        continue
                if time.time() - last > self.STALL:
                    raise TimeoutError("stalled")
                try:
                    cmd, p = peer.recv()
                except (TimeoutError, socket.timeout):
                    continue
                if cmd == "notfound":
                    raise LookupError("notfound")
                if cmd != "block":
                    continue
                now = time.time()
                with self.lock:
                    h = self.prev_index.get(p[4:36][::-1].hex())
                    if h is None:
                        continue
                    # Service time: gap between consecutive blocks while requests are queued.
                    s.spb = 0.8 * s.spb + 0.2 * min(5.0, now - last)
                    last = now
                    served += 1
                    nbytes += len(p)
                    # Requests are served in order: a block of request r completes every request
                    # before r; what they still miss was dropped by the peer (byte limit): re-queue.
                    owner = next((k for k, v in out.items() if h in v[0]), None)
                    for k in (list(out) if owner is not None else []):
                        hs = out[k][0]
                        if k == owner:
                            hs.discard(h)
                            n = self.inflight.get(h, 1) - 1
                            if n <= 0:
                                self.inflight.pop(h, None)
                            else:
                                self.inflight[h] = n
                            if not hs:
                                del out[k]
                            break
                        for x in hs:
                            self._release(x)
                        del out[k]
                    if h not in self.done and h >= self.next:
                        self.done[h] = p
                        self.buffered += len(p)
                        self.stats["bytes"] += len(p)
                        self.stats["blocks"] += 1
                        self.per_peer[ip] += len(p)
                        b = h // 1000
                        self.avg[b] = int(0.9 * self.avg[b] + 0.1 * len(p)) if b in self.avg else len(p)
                        self.lock.notify_all()
                    el = now - t_start
                    if el > 5:
                        s.rate = nbytes / el
                    if self.evict(ip, el):
                        reason = "evicted (slow)"
                        break
        except (OSError, ConnectionError, TimeoutError, ValueError, LookupError, struct.error) as e:
            reason = f"{e.__class__.__name__}: {str(e)[:30]}"
        finally:
            el = time.time() - t_start
            with self.lock:
                for hs, _ in out.values():
                    for x in hs:
                        self._release(x)
                self.peers.pop(ip, None)
                self.known += [norm(a) for a in peer.addrs]
                s.bytes += nbytes
                s.blocks += served
                s.secs += el
                self.drops[reason] += 1
                self.droplog.append((peer.user_agent, round(el), served, round(nbytes / max(el, 1) / 1e6, 3), reason))
                self.backoff(ip, served_well=served >= 50 and not reason.startswith("evicted"))
                if reason.startswith("evicted"):
                    s.until = time.time() + 900
                self.lock.notify_all()
            peer.close()

    DEPTH = {"MagicBean": 3, "Zakura": 2, "Zebra": 2}

    def depth_for(self, ua):
        for k, d in self.DEPTH.items():
            if k in ua:
                return d
        return 2

    def evict(self, ip, el):
        """Drop a connected peer far slower than the others when candidates are waiting. Caller holds lock."""
        if el < 120 or len(self.peers) < max(4, self.npeers // 3):
            return False
        rates = sorted(self.st[x].rate for x in self.peers)
        med = rates[len(rates) // 2]
        now = time.time()
        waiting = any(x not in self.peers and x not in self.connecting and now >= self.st[x].until
                      for x in self.known[:300])
        return waiting and self.st[ip].rate < 0.15 * med

    # ---------------------------------------------------------- peers
    def maintain(self):
        """Keep npeers connections: at most one per IP (connected or connecting), a few new
        handshakes at a time, exponential backoff per IP, best-scored addresses first."""
        last_save, last_dns = 0, 0
        while not self.stop:
            with self.lock:
                busy = set(self.peers) | self.connecting
                need = self.npeers - len(busy)
                self.known = list(dict.fromkeys(self.known))[-5000:]
            if need > 0:
                if time.time() - last_dns > 300 or len(self.known) < 2 * self.npeers:
                    extra = dns_candidates()
                    with self.lock:
                        self.known = list(dict.fromkeys(self.known + extra))
                    last_dns = time.time()
                now = time.time()
                with self.lock:
                    cands = [ip for ip in self.known if ip not in busy and now >= self.st[ip].until]
                    fast = sorted([ip for ip in cands if self.st[ip].rate > 0], key=lambda ip: -self.st[ip].rate)
                rest = [ip for ip in cands if ip not in set(fast)]
                random.shuffle(rest)
                for ip in (fast + rest)[:min(need, 6)]:
                    with self.lock:
                        if ip in self.peers or ip in self.connecting:
                            continue
                        self.connecting.add(ip)
                    threading.Thread(target=self.try_peer, args=(ip,), daemon=True).start()
            if time.time() - last_save > 120:
                try:
                    self.save_book()
                except OSError:
                    pass
                last_save = time.time()
            time.sleep(1)

    def try_peer(self, ip):
        try:
            p = Peer(ip)
        except (OSError, TimeoutError, ConnectionError, ValueError, struct.error, IndexError) as e:
            with self.lock:
                self.connecting.discard(ip)
                self.rejects[e.__class__.__name__] += 1
                self.backoff(ip)
            return
        with self.lock:
            self.connecting.discard(ip)
            self.st[ip].ua = p.user_agent
            if (ip in self.peers or len(self.peers) >= self.npeers or not p.services & NODE_NETWORK
                    or p.height < min(self.end - 1, self.issue + 5000)):
                self.known += [norm(a) for a in p.addrs]
                p.close()
                self.rejects["behind, not NODE_NETWORK, or full"] += 1
                self.st[ip].until = time.time() + 1800
                return
            self.peers[ip] = p
        p.s.settimeout(2)
        threading.Thread(target=self.worker, args=(p,), daemon=True).start()

    # ---------------------------------------------------------- consumer side
    def take(self, max_blocks, max_bytes=256 << 20, wait=True):
        out = []
        with self.lock:
            while self.next not in self.done:
                if not wait or self.stop:
                    return out
                self.lock.wait(1)
            size = 0
            while self.next in self.done and len(out) < max_blocks and size < max_bytes:
                raw = self.done.pop(self.next)
                self.buffered -= len(raw)
                self.prev_index.pop(self.hash_at(self.next - 1), None)
                out.append((self.next, raw))
                size += len(raw)
                self.next += 1
            self.lock.notify_all()
        return out

    def rate(self):
        el = time.time() - self.stats["t0"]
        return self.stats["blocks"] / el, self.stats["bytes"] / el / 1e6

    def peer_table(self, n=12):
        """Per-peer MB/s (current session if connected, else lifetime average), best first."""
        rows = []
        with self.lock:
            for ip, s in self.st.items():
                live = ip in self.peers
                if s.blocks or live:
                    r = s.rate if live else (s.bytes / s.secs if s.secs else 0)
                    rows.append((r / 1e6, ip, s.ua, live, round(s.spb, 2)))
        rows.sort(reverse=True)
        return [f"{ip} {ua} {'up' if live else 'down'} {r:.3f}MB/s spb={spb}" for r, ip, ua, live, spb in rows[:n]]

    def close(self):
        self.stop = True
        with self.lock:
            for p in list(self.peers.values()):
                p.close()
        try:
            self.save_book()
        except OSError:
            pass
