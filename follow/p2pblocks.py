"""Block transport for `zebend follow`: fetch raw blocks from Zcash mainnet peers over P2P.

This module only moves bytes. It frames messages (the 4-byte P2P checksum uses hashlib,
as required by the wire protocol) and asks peers for blocks by the hashes that the Bend
P2P client computed. It does not validate anything: every received block is handed to the
Bend components, which recompute the header hash, merkle root, txids and everything else.
"""
import collections, hashlib, random, socket, struct, threading, time

MAGIC = bytes.fromhex("24e92764")
PROTO = 170190
KNOWN_PEERS = ["136.115.98.175", "34.80.219.125", "54.39.196.12", "38.190.136.76"]
SEEDS = ["mainnet.seeder.zfnd.org", "dnsseed.z.cash", "dnsseed.str4d.xyz", "mainnet.is.yolo.money"]
MSG_BLOCK = 2
CHUNK = 8  # blocks per getdata; peers may not answer large requests in full


def _checksum(p):
    return hashlib.sha256(hashlib.sha256(p).digest()).digest()[:4]


def _frame(cmd, p):
    return MAGIC + cmd.encode().ljust(12, b"\0") + struct.pack("<I", len(p)) + _checksum(p) + p


def _netaddr(ip, port):
    return struct.pack("<Q", 0) + b"\0" * 10 + b"\xff\xff" + socket.inet_aton(ip) + struct.pack(">H", port)


def _version(ip):
    ua = b"/Zebend-follow:0.1/"
    return (struct.pack("<iQq", PROTO, 0, int(time.time())) + _netaddr(ip, 8233) + _netaddr("0.0.0.0", 0)
            + struct.pack("<Q", random.getrandbits(64)) + bytes([len(ua)]) + ua + struct.pack("<i", 0) + b"\0")


def _varint(n):
    if n < 0xfd:
        return bytes([n])
    return b"\xfd" + struct.pack("<H", n) if n <= 0xffff else b"\xfe" + struct.pack("<I", n)


class Peer:
    def __init__(self, ip, timeout=30):
        self.ip = ip
        self.s = socket.create_connection((ip, 8233), timeout=timeout)
        self.buf = b""
        self.user_agent = "?"
        self.s.sendall(_frame("version", _version(ip)))
        got_version = got_verack = False
        deadline = time.time() + timeout
        while not (got_version and got_verack):
            if time.time() > deadline:
                raise TimeoutError("handshake timeout")
            cmd, p = self.recv()
            if cmd == "version":
                got_version = True
                n = p[80]
                self.user_agent = p[81:81 + n].decode(errors="replace")
                self.s.sendall(_frame("verack", b""))
            elif cmd == "verack":
                got_verack = True

    def recv(self):
        while True:
            if len(self.buf) >= 24:
                n = struct.unpack("<I", self.buf[16:20])[0]
                if len(self.buf) >= 24 + n:
                    cmd = self.buf[4:16].rstrip(b"\0").decode()
                    p = self.buf[24:24 + n]
                    self.buf = self.buf[24 + n:]
                    if cmd == "ping":
                        self.s.sendall(_frame("pong", p))
                        continue
                    return cmd, p
            d = self.s.recv(1 << 20)
            if not d:
                raise ConnectionError("peer closed")
            self.buf += d

    def blocks(self, display_hashes, prev_of_first):
        """Request blocks by display-order hash (as computed by the Bend P2P client).

        Peers may answer out of order, so each block is placed by its header's
        hashPrevBlock field against the requested chain (prev_of_first, then the requested
        hashes). The Bend block check later confirms each block header equals the
        verified header at its height, so a misplacement cannot pass.
        """
        prevs = [prev_of_first] + display_hashes[:-1]
        got = []
        for c in range(0, len(display_hashes), CHUNK):
            got += self._chunk(display_hashes[c:c + CHUNK], prevs[c:c + CHUNK])
        return got

    def _chunk(self, hashes, prevs):
        """Fetch a few blocks; re-request the ones a peer silently skipped.

        Zebra caps the bytes it returns for one getdata and drops the rest without a
        notfound, so after a quiet period the still-missing blocks are asked for again.
        """
        slot = {p: i for i, p in enumerate(prevs)}
        got = [None] * len(hashes)
        for _ in range(6):
            missing = [h for h, b in zip(hashes, got) if b is None]
            if not missing:
                break
            inv = _varint(len(missing)) + b"".join(struct.pack("<I", MSG_BLOCK) + bytes.fromhex(h)[::-1] for h in missing)
            self.s.sendall(_frame("getdata", inv))
            quiet_until = time.time() + 10
            while any(b is None for b in got) and time.time() < quiet_until:
                try:
                    cmd, p = self.recv()
                except (TimeoutError, OSError):
                    break
                if cmd == "block":
                    i = slot.get(p[4:36][::-1].hex())
                    if i is not None and got[i] is None:
                        got[i] = p
                        quiet_until = time.time() + 10
                elif cmd == "notfound":
                    raise LookupError("peer does not have a requested block")
        if any(b is None for b in got):
            raise TimeoutError(f"peer sent {sum(b is not None for b in got)}/{len(hashes)} blocks after 6 requests")
        return got

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


class Swarm:
    """Download blocks from several peers at once.

    Each worker thread owns one peer connection and keeps DEPTH single-block getdata
    requests in flight (Zebra stops answering a multi-block getdata after a byte budget).
    Blocks a peer has not delivered after STALL quiet seconds go back to the shared queue
    for any peer; a peer that delivers nothing in a round is dropped for a cool-down.
    Blocks are identified by their hashPrevBlock field against the requested chain; Bend
    later checks every block header against the verified header at its height.
    """
    DEPTH, STALL, COOL = 16, 20, 300

    def __init__(self, log=print, n=8, avoid=()):
        self.log, self.n, self.avoid = log, n, set(avoid)
        self.idle, self.bad, self.lock = [], {}, threading.Lock()
        self.stats = {}  # ip -> [blocks, bytes, requeued], for profiling
        self.last_warm = 0.0
        threading.Thread(target=self._keepalive, daemon=True).start()

    def _keepalive(self):
        """Idle connections still get pings: answer them (recv does) so peers keep us."""
        while True:
            time.sleep(15)
            with self.lock:
                for p in list(self.idle):
                    try:
                        p.s.settimeout(0.05)
                        while True:
                            p.recv()  # answers pings; anything else between windows is dropped
                    except (TimeoutError, socket.timeout):
                        p.s.settimeout(2)
                    except (OSError, ConnectionError, ValueError):
                        p.close()
                        self.idle.remove(p)

    def warm(self):
        """Handshake with every candidate at once and keep up to n working connections.

        One parallel round instead of serial retries: peers rate-limit IPs that reconnect
        often, so connections are opened rarely and kept."""
        self.last_warm = time.time()
        have = {p.ip for p in self.idle}
        ips = [ip for ip in candidates() if ip not in self.avoid and ip not in have
               and time.time() - self.bad.get(ip, 0) >= self.COOL]
        out = [None] * len(ips)

        def one(k):
            try:
                out[k] = Peer(ips[k], timeout=8)
                out[k].s.settimeout(2)
            except (OSError, TimeoutError, ConnectionError, IndexError):
                self.bad[ips[k]] = time.time()

        ts = [threading.Thread(target=one, args=(k,), daemon=True) for k in range(len(ips))]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        good = [p for p in out if p is not None]
        self.idle += good[:max(0, self.n - len(self.idle))]
        for p in good[max(0, self.n - len(have)):]:
            p.close()
        self.log(f"  swarm: {len(self.idle)} peers ({', '.join(p.ip for p in self.idle)})")

    def get(self, hashes, prev_of_first, sink):
        """Fetch every block; sink(i, raw) is called once per block, from worker threads.

        Each peer keeps DEPTH requests in flight, refilled as blocks arrive. When the queue is
        empty, idle peers also ask for blocks still in flight elsewhere (the first copy
        wins), so one slow peer cannot hold up the end of a window."""
        slot = {p: i for i, p in enumerate([prev_of_first] + hashes[:-1])}
        todo, done = collections.deque(range(len(hashes))), [False] * len(hashes)
        asked = [0] * len(hashes)  # how many peers have it in flight
        left, cv = [len(hashes)], threading.Condition()
        # Re-warm rarely: a handshake round to every candidate is what peers rate-limit.
        since = time.time() - self.last_warm
        if (len(self.idle) < self.n // 2 and since > self.COOL) or (not self.idle and since > 30):
            self.warm()
        with self.lock:
            peers, self.idle = self.idle[:self.n], self.idle[self.n:]

        def refill(peer, out):
            with cv:
                while len(out) < self.DEPTH:
                    if todo:
                        i = todo.popleft()
                    else:  # end game: a block in flight at another peer, asked at most twice
                        spare = [i for i in range(len(hashes)) if not done[i] and i not in out and asked[i] < 2]
                        if not spare:
                            break
                        i = spare[0]
                    asked[i] += 1
                    out[i] = time.time()
                    peer.s.sendall(_frame("getdata", _varint(1) + struct.pack("<I", MSG_BLOCK) + bytes.fromhex(hashes[i])[::-1]))

        def release(out):
            with cv:
                for i in out:
                    asked[i] -= 1
                    if not done[i] and i not in todo and asked[i] == 0:
                        todo.appendleft(i)
                cv.notify_all()

        def worker(peer):
            out, last = {}, time.time()  # in flight here: index -> time asked
            try:
                while True:
                    refill(peer, out)
                    with cv:
                        if not left[0]:
                            break
                    if not out:
                        with cv:
                            cv.wait(0.5)
                        continue
                    if time.time() - last > self.STALL:  # nothing from this peer for a while
                        raise TimeoutError("stalled")
                    try:
                        cmd, p = peer.recv()
                    except (TimeoutError, socket.timeout):
                        continue
                    if cmd != "block":
                        continue
                    i = slot.get(p[4:36][::-1].hex())
                    if i is None:
                        continue
                    last = time.time()
                    with cv:
                        fresh = not done[i]
                        done[i] = True
                        if i in out:
                            del out[i]
                            asked[i] -= 1
                    if fresh:
                        sink(i, p)
                        st = self.stats.setdefault(peer.ip, [0, 0, 0])
                        st[0] += 1
                        st[1] += len(p)
                        with cv:
                            left[0] -= 1
                            cv.notify_all()
                with self.lock:
                    self.idle.append(peer)  # outstanding duplicates are ignored next time
            except (OSError, ConnectionError, TimeoutError, ValueError):
                self.stats.setdefault(peer.ip, [0, 0, 0])[2] += len(out)
                peer.close()
                with self.lock:
                    self.bad[peer.ip] = time.time()
            finally:
                release(out)

        ts = [threading.Thread(target=worker, args=(p,), daemon=True) for p in peers]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        if left[0]:
            raise TimeoutError(f"swarm: {left[0]} of {len(hashes)} blocks undelivered (no usable peers)")


def candidates():
    ips = list(KNOWN_PEERS)
    for s in SEEDS:
        try:
            ips += [a[4][0] for a in socket.getaddrinfo(s, 8233, socket.AF_INET)]
        except OSError:
            pass
    seen = []
    for ip in ips:
        if ip not in seen:
            seen.append(ip)
    return seen


def connect(log=print, avoid=()):
    for ip in candidates():
        if ip in avoid:
            continue
        try:
            p = Peer(ip)
            log(f"  peer {ip} {p.user_agent}")
            return p
        except (OSError, TimeoutError, ConnectionError) as e:
            log(f"  peer {ip}: {e.__class__.__name__}")
    raise ConnectionError("no peer completed a handshake")
