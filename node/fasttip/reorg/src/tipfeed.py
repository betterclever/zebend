"""fasttip: push-based pickup of new blocks at the tip (replaces live.py's 60 s polling).

Transport + bookkeeping only; every check is Bend, as in tiphdr.py / sync.py:
  * a few long-lived P2P connections (node/net.py's Peer: handshake, ping/pong, and polite
    answers to getaddr/getheaders/getdata) listen for block announcements: `inv` (MSG_BLOCK)
    and unsolicited `headers`. (Zcash has no BIP 152 compact blocks: neither zcashd nor Zebra
    implements cmpctblock/sendcmpct, so there is nothing to subscribe to there.)
  * an announced block we do not have is requested AT ONCE (getdata) from the announcing peer;
  * a received block whose hashPrevBlock is our verified tip: its header is checked by the same
    Bend programs as tiphdr.py, in-process and in parallel: follow's equihash7 (Equihash, hash <=
    target, prev links, difficulty, with the 113 previous headers) and node/hdr/hdrchain
    (SHA-256d of the header + its link to our tip). The acceptance rule is tiphdr.append's. The
    header is appended to state/hdr/extra.bin and Bend's hash to state/hdr/hashes.bin, exactly as
    tiphdr.py does, and the block goes to an in-memory buffer that sync.py reads (BLOCK_SOURCE)
    instead of a spool chunk;
  * a block that does not extend our tip (we missed one): getheaders to that peer; a header batch
    that extends our tip is checked the same way (one equihash7 + one hdrchain run per batch) and
    its blocks are requested;
  * a block or header batch that does not extend our tip and links (directly, or through other
    such headers kept in a side store) to a block of our verified chain below the tip is a
    COMPETING CHAIN (forkswitch.py): the push path decides at once. A missing link is asked for
    with getheaders + locator (to the announcing push peer, else one short-lived connection).
    The competing headers are checked in Bend (same programs and rule as above, on top of the
    fork point); if they carry strictly more chain work than ours above the fork point, the
    header index is switched (crash-safe) and sync.py's own rollback (store.rollback_to, undo
    data) and block pickup do the rest. Less or equal work: ignored. Deeper than the undo depth
    (600): refused, loudly (`REORG REFUSED`);
  * safety net for a missed inv (measured: a connected peer does not always announce every
    block): every --hdr-poll s one push peer, round-robin, is asked `getheaders` over its
    existing connection (no new connection, one small message); new headers take the path above.
    Each block records how it was first seen: "inv", "headers" (unsolicited or this poll) or none
    (fallback / spool);
  * follow tap (--follow-tap): zebend_follow.py already listens to announcements on its own,
    well-connected peers and writes each block it receives to node/follow/work/win/<h>/block.bin
    before verifying it. tipfeed reads such a file (read-only, as sync.py reads follow's roots),
    once its size has been stable for 30 ms, and treats the bytes like a block from a peer (same
    Bend header checks; a block that does not extend the verified tip is ignored). No extra peer
    connection. Its "announcement" time is follow's receipt time (the file's mtime);
  * fallback = the old live.py cycle (tiphdr.py, then download.py into the spool for missing
    blocks), run when push is quiet for 3 x --every s, when no push peer is connected, or when
    kicked (missed block / failed check). A fork the fallback sees goes to the same fork choice
    (getheaders + locator, Bend checks, more work only); tiphdr.drop_tip is no longer used here.

hashlib is used only to NAME blocks for routing (which getdata a block answers; which inv we
already have), as headers.routing_index and net.py do; the index only ever receives Bend's hashes.
"""
import hashlib, json, os, queue, random, re, shutil, socket, struct, subprocess, sys, threading, time
from pathlib import Path

NODE = Path(__file__).resolve().parents[1]
if str(NODE) not in sys.path:
    sys.path.insert(0, str(NODE))
import headers, net  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent))
import forkswitch as FS  # noqa: E402

HDR = 1487
HDRDIR = NODE / "state/hdr"
FOLLOW_BIN = NODE.parent / "node/follow/bin"  # as tiphdr.py (read-only use)
HDRCHAIN = NODE / "hdr/hdrchain"
FOLLOW_WIN = Path(os.environ.get("ZEBEND_FOLLOW_WORK", NODE.parent / "node/follow/work")) / "win"
WORK = NODE / "work/fasttip"
CTX = 113  # PoWAveragingWindow (102 from NU7) + PoWMedianBlockSpan, as tiphdr.py
EXTRA_FIRST = 3528280
MSG_BLOCK = 2
# Peers other components hold (Zebra: one connection per source IP): follow's Bend P2P header peer
# and swarm seeds, tiphdr.py's first choices. Push peers are picked elsewhere (IPv6 first: a
# different source address from the IPv4 connections the other components hold).
RESERVED = set(net.KNOWN)
KNOWN_DEPTH = 800        # our verified hashes kept in memory (fork points up to this deep are recognised)
HEADERS_FULL = 160       # Zebra answers getheaders with at most 160 headers: a full reply may continue


def sha256d(b):  # routing names only (see module doc)
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def _idx():
    return headers.Index(HDRDIR / "hashes.bin")


class BlockBuffer:
    """Blocks whose headers are verified and indexed, by height; sync.py's BLOCK_SOURCE.

    take(after, ...) returns the contiguous blocks after `after`, each re-checked against the
    CURRENT index (hash and prev link), so a block of a branch that tiphdr.py has since cut is
    never handed out (sync.py would otherwise stop on 'hash != verified chain hash')."""

    def __init__(self):
        self.cv = threading.Condition()
        self.blocks = {}   # height -> (raw, internal hash)
        self.seq = self.seen = 0
        self.meta = {}     # height -> timing dict (inv, recv, header, put)
        self.after = None  # the tip sync last asked from (its committed/resolved tip)
        self.recent = {}   # height -> (raw, hint) of blocks handed out (re-served after a rollback)

    def put(self, h, raw, hint, meta=None):
        with self.cv:
            self.blocks[h] = (raw, hint)
            if meta is not None:
                self.meta[h] = meta
            self.seq += 1
            self.cv.notify_all()

    def take(self, after, max_blocks=2000, max_bytes=96 << 20):
        with self.cv:  # the index is opened under the lock a reorg switch holds (forkswitch)
            idx = _idx()
            try:
                self.seen = self.seq
                self.after = after
                for k in [k for k in self.blocks if k <= after]:
                    del self.blocks[k]
                out, h, size = [], after + 1, 0
                while (h in self.blocks or h in self.recent) and len(out) < max_blocks and size < max_bytes:
                    # a block handed out before (recent) is served again if it is still on the index:
                    # sync.py may roll back below a fork point (to a ZIP 221 window start)
                    raw, hint = self.blocks[h] if h in self.blocks else self.recent[h]
                    if h >= idx.n or idx.internal(h) != hint or raw[4:36] != idx.internal(h - 1):
                        if h in self.blocks:
                            for k in [k for k in self.blocks if k >= h]:
                                del self.blocks[k]
                        self.recent.pop(h, None)
                        break
                    out.append((h, raw))
                    size += len(raw)
                    h += 1
                now = time.time()
                for hh, raw in out:
                    self.meta.setdefault(hh, {}).setdefault("t_take", now)
                    self.recent[hh] = (raw, idx.internal(hh))
                for k in [k for k in self.recent if k <= h - 1 - 64]:  # the last 64 blocks handed out
                    del self.recent[k]
                return out
            finally:
                idx.f.close()

    def drop_above(self, h):
        with self.cv:
            for d in (self.blocks, self.recent):
                for k in [k for k in d if k > h]:
                    del d[k]

    def wait(self, secs):
        """sync.py's idle wait: returns as soon as a block was put since the last take()."""
        with self.cv:
            self.cv.wait_for(lambda: self.seq != self.seen, timeout=secs)


class TipFeed:
    def __init__(self, prof=None, peers=4, log=print, book=None, every=60, fallback=True, hdr_poll=5.0, follow_tap=False):
        self.prof, self.npeers, self.log, self.every, self.use_fallback = prof, peers, log, every, fallback
        self.hdr_poll, self.follow_tap = hdr_poll, follow_tap
        self.book = Path(book) if book else Path(os.environ.get("ZEBEND_STATE", NODE / "state")) / "peers.txt"
        self.buffer = BlockBuffer()
        self.q = queue.Queue()
        self.lock = threading.RLock()     # feed bookkeeping
        self.hdr_lock = threading.Lock()  # header index appends (push path and the fallback's tiphdr.py)
        self.conns = {}                   # ip -> net.Peer
        self.connecting = set()
        self.backoff = {}                 # ip -> until
        self.inv_seen = {}                # internal hash -> (t first announcement, ip, "inv" | "headers")
        self.peer_info = {}               # ip -> {"t0", "invs", "blocks", "last"}
        self.inflight = {}                # internal hash -> (ip, t sent)
        self.orphans = {}                 # internal prev hash -> (raw, ip, t recv)
        self.known = {}                   # internal hash -> height (indexed headers near the tip)
        self.stop_ev, self.kick = threading.Event(), threading.Event()
        self.last_push = time.time()      # last header appended by the push path
        self.last_fallback = 0.0
        self.children = set()             # running fallback subprocesses (killed by stop())
        self.last_tap = 0.0               # last block the follow tap delivered
        self.fail_streak = 0              # consecutive failed handshakes (connect pacing)
        self.side = {}                    # name -> [header, raw block or None, ip, t]: headers not on our chain
        self.fork_seen = {}               # (branch tip name, length) -> verdict (each branch is decided once)
        self.want_seen = {}               # missing link name -> t asked (getheaders rate limit)
        self.last_probe = 0.0             # last short-lived getheaders connection (no push peer)
        self.reorgs = []                  # switches done: dicts for the log / tests
        self.refused = {}                 # fork height -> t of the last REORG REFUSED line
        self.stats = {"inv": 0, "blocks": 0, "headers_msgs": 0, "pushed": 0, "orphans": 0, "fallback runs": 0,
                      "dup blocks": 0, "header fails": 0, "forks seen": 0, "reorgs": 0, "forks ignored": 0,
                      "reorgs refused": 0}
        WORK.mkdir(parents=True, exist_ok=True)
        FS.reconcile(HDRDIR, self.log)  # an index switch interrupted by a crash leaves a consistent prefix
        self._refresh_known()

    # ------------------------------------------------------------ lifecycle
    def start(self):
        threading.Thread(target=self._processor, daemon=True, name="tipfeed-proc").start()
        if self.npeers > 0:
            threading.Thread(target=self._maintain, daemon=True, name="tipfeed-peers").start()
        if self.use_fallback:
            threading.Thread(target=self._fallback, daemon=True, name="tipfeed-fallback").start()
        if self.follow_tap:
            threading.Thread(target=self._tap, daemon=True, name="tipfeed-followtap").start()
        if self.follow_tap or self.npeers > 0:
            threading.Thread(target=self._gap_filler, daemon=True, name="tipfeed-gaps").start()
        if self.npeers > 0 or self.follow_tap:
            threading.Thread(target=self._status, daemon=True, name="tipfeed-status").start()
            if self.hdr_poll > 0:
                threading.Thread(target=self._poll_headers, daemon=True, name="tipfeed-hdrpoll").start()

    def stop(self):
        self.stop_ev.set()
        self.q.put(None)
        for p in list(self.children):  # the fallback's tiphdr.py / download.py (and their Bend children)
            try:
                os.killpg(p.pid, 15)
            except OSError:
                pass
        with self.lock:
            for p in list(self.conns.values()):
                p.close()

    def inject(self, raw, t_inv=None, ip="replay"):
        """A block as if a peer had announced (t_inv) and sent it now (replay benchmark)."""
        hint = sha256d(raw[:HDR])
        with self.lock:
            self.inv_seen.setdefault(hint, (t_inv or time.time(), ip, "inv"))
        self.q.put(("block", raw, ip, time.time()))

    # ------------------------------------------------------------ index helpers
    def _refresh_known(self):
        idx = _idx()
        try:
            top = idx.n - 1
            self.known = {idx.internal(h): h for h in range(max(0, top - KNOWN_DEPTH), top + 1)}
            self.top, self.top_hash = top, idx.internal(top)
        finally:
            idx.f.close()

    # ------------------------------------------------------------ peers (transport)
    def _candidates(self):
        try:
            ips = [net.norm(l) for l in self.book.read_text().splitlines() if l.strip()]
        except OSError:
            ips = []
        ips = [ip for ip in dict.fromkeys(ips) if ip not in RESERVED and not ip.startswith(("10.", "192.168.", "127."))]
        v6 = [ip for ip in ips if ":" in ip]
        v4 = [ip for ip in ips if ":" not in ip]
        random.shuffle(v6)
        random.shuffle(v4)
        out = []  # alternate IPv6 / IPv4: a peer that drops us on one family may keep us on the other
        for k in range(max(len(v6), len(v4))):
            out += v6[k:k + 1] + v4[k:k + 1]
        return out

    def _maintain(self):
        while not self.stop_ev.is_set():
            with self.lock:
                need = self.npeers - len(self.conns) - len(self.connecting)
                busy = set(self.conns) | self.connecting
            if need > 0:
                now = time.time()
                for ip in [ip for ip in self._candidates() if ip not in busy and self.backoff.get(ip, 0) <= now][:need]:
                    with self.lock:
                        self.connecting.add(ip)
                    threading.Thread(target=self._connect, args=(ip,), daemon=True).start()
                    # gentle: one handshake at a time, slower while peers keep refusing this IP
                    # (2 s, doubling per consecutive failure, at most 60 s)
                    time.sleep(min(60.0, 2.0 * 2 ** min(self.fail_streak, 5)))
            time.sleep(2)

    def _connect(self, ip):
        try:
            p = net.Peer(ip, timeout=8)
            if not p.services & net.NODE_NETWORK or p.height < self.top - 50:
                p.close()
                raise ConnectionError(f"behind ({p.height}) or not NODE_NETWORK")
        except Exception as e:  # noqa: transport
            with self.lock:
                self.connecting.discard(ip)
                self.backoff[ip] = time.time() + 1800
                self.fail_streak += 1
            return
        self.fail_streak = 0
        p.s.settimeout(1.0)
        with self.lock:
            self.connecting.discard(ip)
            self.conns[ip] = p
            self.peer_info[ip] = {"t0": time.time(), "invs": 0, "blocks": 0, "last": time.time(), "ua": p.user_agent}
        self.log(f"fasttip: push peer {ip} {p.user_agent} height {p.height} ({len(self.conns)} connected)")
        reason = "closed"
        try:
            self._reader(p)
        except Exception as e:  # noqa: transport
            reason = f"{e.__class__.__name__}: {str(e)[:60]}"
        finally:
            p.close()
            with self.lock:
                self.conns.pop(ip, None)
                self.backoff[ip] = time.time() + 300
                for hsh, (q, _) in list(self.inflight.items()):
                    if q == ip:
                        del self.inflight[hsh]
            info = self.peer_info.pop(ip, {})
            self.log(f"fasttip: push peer {ip} gone after {time.time() - info.get('t0', time.time()):.0f} s, "
                     f"{info.get('invs', 0)} block invs ({reason})")

    def _send(self, ip, cmd, payload):
        with self.lock:
            p = self.conns.get(ip)
        if p is None:
            return False
        try:
            p.s.sendall(net.frame(cmd, payload))
            return True
        except OSError:
            return False

    def _getdata(self, ip, hashes):
        now = time.time()
        with self.lock:
            for h in hashes:
                self.inflight[h] = (ip, now)
        return self._send(ip, "getdata", net.varint(len(hashes)) + b"".join(struct.pack("<I", MSG_BLOCK) + h for h in hashes))

    def _locator(self):
        """Our tip, dense for 16 blocks, then doubling back past the undo depth."""
        idx = _idx()
        try:
            top, loc, step, h = idx.n - 1, [], 1, idx.n - 1
            while h >= max(0, top - KNOWN_DEPTH) and len(loc) < 32:
                loc.append(idx.internal(h))
                if len(loc) >= 16:
                    step *= 2
                h -= step
            if top - KNOWN_DEPTH > 0:
                loc.append(idx.internal(top - KNOWN_DEPTH))  # fork points down to KNOWN_DEPTH are found
        finally:
            idx.f.close()
        return struct.pack("<I", net.PROTO) + net.varint(len(loc)) + b"".join(loc) + bytes(32)

    def _getheaders(self, ip, payload=None):
        return self._send(ip, "getheaders", payload or self._locator())

    def _reader(self, p):
        last = time.time()
        while not self.stop_ev.is_set():
            try:
                cmd, pl = p.recv()
            except (socket.timeout, TimeoutError):
                if time.time() - last > 900:
                    raise TimeoutError("idle 15 min")
                continue
            last = time.time()
            pi = self.peer_info.get(p.ip)
            if pi is not None:
                pi["last"] = last
            if len(p.addrs) > 2000:
                p.addrs = p.addrs[-1000:]
            if cmd == "inv":
                self._on_inv(p.ip, pl, last)
            elif cmd == "block":
                self.stats["blocks"] += 1
                self.q.put(("block", pl, p.ip, last))
            elif cmd == "headers":
                self.stats["headers_msgs"] += 1
                self.q.put(("headers", pl, p.ip, last))
            elif cmd == "notfound":
                n, i = net.read_cs(pl, 0)
                with self.lock:
                    for k in range(min(n, 50_000)):
                        self.inflight.pop(bytes(pl[i + 36 * k + 4:i + 36 * k + 36]), None)

    def _on_inv(self, ip, pl, now):
        n, i = net.read_cs(pl, 0)
        want = []
        with self.lock:
            for k in range(min(n, 50_000)):
                typ = struct.unpack_from("<I", pl, i + 36 * k)[0]
                if typ != MSG_BLOCK:
                    continue
                hsh = bytes(pl[i + 36 * k + 4:i + 36 * k + 36])
                self.stats["inv"] += 1
                if ip in self.peer_info:
                    self.peer_info[ip]["invs"] += 1
                self.inv_seen.setdefault(hsh, (now, ip, "inv"))
                if hsh in self.known or (hsh in self.side and self.side[hsh][1] is not None):
                    continue
                f = self.inflight.get(hsh)
                if f is None or (f[0] != ip and now - f[1] > 1.0):  # slow first announcer: ask this one too
                    want.append(hsh)
            if len(self.inv_seen) > 5000:
                for k in list(self.inv_seen)[:2500]:
                    del self.inv_seen[k]
        if want:
            self._getdata(ip, want)

    # ------------------------------------------------------------ processing (Bend checks)
    def _processor(self):
        while not self.stop_ev.is_set():
            item = self.q.get()
            if item is None:
                return
            kind, pl, ip, t = item
            try:
                if kind == "block":
                    self._on_block(pl, ip, t)
                else:
                    self._on_headers(pl, ip, t)
            except Exception as e:  # noqa: a bad message must not stop the feed
                self.log(f"fasttip: {kind} from {ip}: {e.__class__.__name__}: {e}")

    def _on_block(self, raw, ip, t_recv):
        if len(raw) < HDR + 1:
            return
        hint = sha256d(raw[:HDR])
        with self.lock:
            self.inflight.pop(hint, None)
        h = self.known.get(hint)
        if h is not None:  # header already verified (header batch path, or a duplicate)
            if h > self.top - 200 and raw[:HDR] == headers.header(h) and h not in self.buffer.blocks:
                if self._wanted(h):
                    self._put(h, raw, hint, ip, t_recv, None)
                    self._drain_orphans(hint)
                    return
            self.stats["dup blocks"] += 1
            return
        if raw[4:36] == self.top_hash:
            got = self._verify_append([raw[:HDR]], ip)
            if got:
                self._put(got[0][0], raw, hint, ip, t_recv, got[0][2])
                self._drain_orphans(hint)
            return
        # does not extend our tip: we missed a block (its parent comes later), or a competing chain
        with self.lock:
            self.orphans[raw[4:36]] = (raw, ip, t_recv)
            while len(self.orphans) > 64:
                self.orphans.pop(next(iter(self.orphans)))
        self.stats["orphans"] += 1
        self._note_side(raw[:HDR], raw, ip, t_recv)
        self._consider(hint, ip, "block", t_recv)

    def _wanted(self, h):
        """Hand a block to sync only if the state may still need it (sync drops older ones anyway)."""
        return True

    def _drain_orphans(self, hint):
        while True:
            with self.lock:
                o = self.orphans.pop(hint, None)
            if o is None:
                return
            raw, ip, t = o
            hint2 = sha256d(raw[:HDR])
            if hint2 in self.known:
                self._on_block(raw, ip, t)
                return
            got = self._verify_append([raw[:HDR]], ip)
            if not got:
                return
            self._put(got[0][0], raw, hint2, ip, t, got[0][2])
            hint = hint2

    def _on_headers(self, pl, ip, t):
        n, i = net.read_cs(pl, 0)
        hdrs = []
        for _ in range(min(n, 2000)):
            hdrs.append(bytes(pl[i:i + HDR]))
            i += HDR
            _, i = net.read_cs(pl, i)
        if not hdrs:
            return
        # skip the ones we have
        names = [sha256d(x) for x in hdrs]
        k = 0
        while k < len(hdrs) and names[k] in self.known:
            k += 1
        if not hdrs[k:] and n >= HEADERS_FULL and k and self.known.get(names[-1], self.top) < self.top - HEADERS_FULL:
            # a full reply of headers we have, far below our tip: the peer's chain forks deeper; continue
            self._getheaders(ip, struct.pack("<I", net.PROTO) + net.varint(1) + names[-1] + bytes(32))
            return
        hdrs, names = hdrs[k:], names[k:]
        if not hdrs:
            return
        with self.lock:
            for nm in names:
                self.inv_seen.setdefault(nm, (t, ip, "headers"))
        if hdrs[0][4:36] != self.top_hash:  # a competing chain (or a reply for a branch we hold in part)
            for x in hdrs:
                self._note_side(x, None, ip, t)
            switched = self._consider(names[-1], ip, "headers", t)
            if not switched and n >= HEADERS_FULL and names[-1] in self.side:  # the peer has more: continue
                self._getheaders(ip, struct.pack("<I", net.PROTO) + net.varint(1) + names[-1] + bytes(32))
            return
        got = self._verify_append(hdrs, ip)
        if not got:
            return
        want = []
        for (h, hint, _), name in zip(got, names):
            with self.lock:
                o = self.orphans.pop(self._prev_of(h), None)
            if o is not None and sha256d(o[0][:HDR]) == hint:
                self._put(h, o[0], hint, o[1], o[2], None)
            else:
                want.append(hint)
        if want:
            self._getdata(ip, want)

    # ------------------------------------------------------------ competing chains (forkswitch.py)
    def _note_side(self, hdr, raw, ip, t):
        """Keep a header (and its block, if we have it) that is not on our verified chain."""
        name = sha256d(hdr)
        if name in self.known:
            return name
        with self.lock:
            e = self.side.get(name)
            if e is None:
                self.side[name] = [hdr, raw, ip, t]
                while len(self.side) > 4000:
                    self.side.pop(next(iter(self.side)))
            elif raw is not None and e[1] is None:
                e[1] = raw
        return name

    def _branch_from(self, name):
        """Walk back from side header `name` to our verified chain, then forward through side
        headers that build on it. Returns (fork height, [headers above it]) or (None, missing name)."""
        with self.lock:
            back, cur = [], name
            while cur in self.side and cur not in self.known and len(back) < 4000:
                back.append(self.side[cur][0])
                cur = self.side[cur][0][4:36]
            if cur not in self.known:
                return None, cur
            branch = back[::-1]
            children = {}
            for nm, e in self.side.items():
                if nm not in self.known:
                    children.setdefault(e[0][4:36], []).append((e[3], nm))
            tip = sha256d(branch[-1]) if branch else cur
            while tip in children and len(branch) < 4000:  # the earliest-seen child on a tie
                _, tip = min(children[tip])
                branch.append(self.side[tip][0])
        return self.known[cur], branch

    def _consider(self, name, ip, why, t):
        """A header/block not extending our tip: decide at once if it is a competing chain."""
        fork_h, branch = self._branch_from(name)
        if fork_h is None:  # a link is missing: ask for the headers in between (or we missed a block)
            self._want_headers(ip, branch, why)
            return False
        if not branch:
            return False
        # fork_h == top: side headers that extend our tip (e.g. they arrived before their parent was
        # appended): the same path with nothing to drop (work > 0 = ours above the tip)
        return self._fork(fork_h, branch, ip, why, t)

    def _fork(self, F, branch, ip, why, t_first):
        key = (sha256d(branch[-1]), len(branch))
        v = self.fork_seen.get(key, 0)
        if not isinstance(v, int) or v >= 3:  # decided (ignored / switched / refused), or Bend failed 3 times
            return False
        self.fork_seen[key] = "decided"       # the paths below that may succeed on a retry reset it
        if len(self.fork_seen) > 2000:
            self.fork_seen.clear()
        self.stats["forks seen"] += 1
        t0 = time.perf_counter()
        with self.hdr_lock:
            idx = _idx()
            try:
                top = idx.n - 1
                if F > top or idx.internal(F) != branch[0][4:36]:
                    self._refresh_known()
                    self.fork_seen.pop(key, None)  # the index moved meanwhile: decide again next time
                    return False
                ours = [headers.header(h) for h in range(F + 1, top + 1)]
                ctx = [headers.header(h) for h in range(F - CTX + 1, F + 1)]
                base_hash = idx.internal(F)
            finally:
                idx.f.close()
            depth, st_tip = top - F, FS.state_tip(os.environ.get("ZEBEND_STATE", NODE / "state"))
            sdepth = (st_tip - F) if st_tip is not None else depth
            label = (f"competing chain from {ip} ({why}): forks after {F}, {len(branch)} header(s) {F + 1}..{F + len(branch)} "
                     f"tip {sha256d(branch[-1])[::-1].hex()[:16]}; ours {depth} header(s) {F + 1}..{top}")
            if F + 1 < FS.EXTRA_FIRST:
                ours = [b"\0" * HDR]  # below the fixed header files: never switched (refused below if it wins)
            w_ours, w_new = FS.chain_work(ours), FS.chain_work(branch)
            if w_new <= w_ours:
                self.stats["forks ignored"] += 1
                self.log(f"fasttip: {label}: work {w_new:.4g} <= ours {w_ours:.4g}: ignored (more work required)")
                return False
            ok, bend, detail = FS.bend_check(F, base_hash, ctx, branch, FOLLOW_BIN / "equihash7", HDRCHAIN, WORK,
                                             f"fork_{os.getpid()}_{F}")
            if not ok:
                # (a Bend run that gave no output is retried on the next announcement, at most 3 times)
                self.stats["header fails"] += 1
                self.fork_seen[key] = v + 1
                self.log(f"fasttip: {label}: rejected by Bend: {detail}")
                return False
            if F + 1 < FS.EXTRA_FIRST or max(depth, sdepth) > FS.UNDO_DEPTH:
                # a valid competing chain with more work that we cannot switch to: say so, loudly
                self.fork_seen[key] = "refused"  # (the same branch again: silent; a longer one: re-checked)
                if time.time() - self.refused.get(F, 0) < 600:  # loud, but once per fork point per 10 min
                    return False
                self.refused[F] = time.time()
                self.stats["reorgs refused"] += 1
                self.log(f"fasttip: REORG REFUSED: {label}: work {w_new:.4g} > ours {w_ours:.4g}, Bend PASS, but it is "
                         f"{max(depth, sdepth)} blocks deep (state tip {st_tip}): deeper than the undo depth {FS.UNDO_DEPTH} "
                         f"(or below the fixed header files at {FS.EXTRA_FIRST}). NOTHING CHANGED: this node stays on its "
                         f"chain and is now on a minority fork. Operator: restore a snapshot below {F} and resync.")
                return False
            with self.buffer.cv:  # no block is handed to sync while the index changes
                FS.switch_index(HDRDIR, F, branch, bend)
                self.buffer.drop_above(F)
            self._refresh_known()
            self.last_push = time.time()
            secs = time.perf_counter() - t0
        self.stats["reorgs"] += 1
        rec = {"t": time.time(), "fork": F, "dropped": depth, "added": len(branch), "ip": ip, "why": why,
               "t_first": t_first, "decide_s": round(secs, 4), "work_ours": w_ours, "work_new": w_new}
        self.reorgs.append(rec)
        self.log(f"fasttip: {'REORG' if depth else 'side headers extend the tip'}: {label}: work {w_new:.4g} > ours {w_ours:.4g}, Bend PASS (Equihash, target, links, "
                 f"difficulty, hash); header index switched in {secs * 1000:.0f} ms: dropped {depth} header(s), "
                 f"verified tip now {self.top}; sync.py rolls the state back to {F}")
        if self.prof is not None:
            self.prof.add("header", secs)
        want = []
        for k, (hdr, b) in enumerate(zip(branch, bend)):
            e = self.side.get(sha256d(hdr))
            if e is not None and e[1] is not None:
                self._put(F + 1 + k, e[1], b, e[2], e[3], secs)
            else:
                want.append(b)
        with self.lock:
            for k in [k for k in self.side if self.side[k][0] in branch]:
                self.side.pop(k, None)
            ips = sorted(self.conns)
        if want and ips:
            self._getdata(ip if ip in ips else random.choice(ips), want)
        return True

    def _want_headers(self, ip, missing, why):
        """The headers between our chain and a side header are missing: getheaders with our
        locator to the announcing push peer (or another), else one short-lived connection."""
        now = time.time()
        if now - self.want_seen.get(missing, 0) < 10:
            return
        self.want_seen[missing] = now
        if len(self.want_seen) > 2000:
            self.want_seen.clear()
        with self.lock:
            ips = sorted(self.conns)
        if ip in ips:
            self._getheaders(ip)
            return
        if ips:
            self._getheaders(random.choice(ips))
        # follow tap: follow usually writes the missing parent within milliseconds; ask the network
        # only if it is still missing after 3 s (no push peer, or the push peers do not answer)
        threading.Timer(3.0 if ips or str(ip).startswith("follow") else 0.0, self._probe, args=(missing, why)).start()

    def _probe(self, missing, why, peers=None):
        if self.stop_ev.is_set() or missing in self.side or missing in self.known:
            return
        if time.time() - self.last_probe < 20:
            return
        self.last_probe = time.time()
        import tiphdr  # node/tiphdr.py (read-only use: its peer order)
        with self.lock:
            busy = set(self.conns)
        for peer in [p for p in (peers or tiphdr.candidate_peers()) if p not in busy][:2]:
            t = time.time()
            try:
                p = net.Peer(peer, timeout=8)
            except Exception as e:  # noqa: transport
                self.log(f"fasttip: fork probe {peer}: {e.__class__.__name__}")
                continue
            try:
                p.s.sendall(net.frame("getheaders", self._locator()))
                p.s.settimeout(1.0)
                while time.time() - t < 15:
                    try:
                        cmd, pl = p.recv()
                    except (socket.timeout, TimeoutError):
                        continue
                    if cmd == "headers":
                        self.stats["fork probes"] = self.stats.get("fork probes", 0) + 1
                        self.log(f"fasttip: fork probe ({why}): getheaders to {peer} answered in {time.time() - t:.2f} s")
                        self.q.put(("headers", pl, peer, time.time()))
                        return
            except Exception as e:  # noqa: transport
                self.log(f"fasttip: fork probe {peer}: {e.__class__.__name__}: {e}")
            finally:
                p.close()

    def _prev_of(self, h):
        idx = _idx()
        try:
            return idx.internal(h - 1)
        finally:
            idx.f.close()

    def _put(self, h, raw, hint, ip, t_recv, t_hdr):
        with self.lock:
            inv = self.inv_seen.get(hint)
        meta = {"t_inv": inv[0] if inv else None, "inv_ip": inv[1] if inv else None, "seen_by": inv[2] if inv else None,
                "ip": ip, "t_recv": t_recv,
                "header_s": t_hdr, "t_put": time.time(), "size": len(raw)}
        self.buffer.put(h, raw, hint, meta)
        self.stats["pushed"] += 1

    def _verify_append(self, hdrs, ip):
        """Bend header checks of headers extending our verified tip, as tiphdr.py; on PASS append
        them to extra.bin and their Bend hashes to hashes.bin. Returns [(height, hash, secs)]."""
        t0 = time.perf_counter()
        with self.hdr_lock:
            idx = _idx()
            try:
                top = idx.n - 1
                if hdrs[0][4:36] != idx.internal(top):
                    self._refresh_known()
                    return None
                prev = b"".join(headers.header(h) for h in range(top - CTX + 1, top + 1))
                tip_hex = idx.internal(top).hex()
            finally:
                idx.f.close()
            # tiphdr.append's acceptance rule, verbatim (forkswitch.bend_check: equihash7 + hdrchain)
            ok, bend, detail = FS.bend_check(top, bytes.fromhex(tip_hex), [prev[k * HDR:(k + 1) * HDR] for k in range(CTX)],
                                             hdrs, FOLLOW_BIN / "equihash7", HDRCHAIN, WORK, f"{os.getpid()}_{top}")
            if not ok:
                self.stats["header fails"] += 1
                self.log(f"fasttip: headers {top + 1}..{top + len(hdrs)} from {ip} rejected by Bend: {detail}")
                return None
            with open(HDRDIR / "extra.bin", "ab") as f:
                f.write(b"".join(hdrs))
            with open(HDRDIR / "hashes.bin", "ab") as f:
                f.write(b"".join(bend))
            secs = time.perf_counter() - t0
            res = []
            for k, b in enumerate(bend):
                self.known[b] = top + 1 + k
                res.append((top + 1 + k, b, secs))
            self.top, self.top_hash = top + len(hdrs), bend[-1]
            self.last_push = time.time()
        if self.prof is not None:
            self.prof.add("header", secs)
        self.log(f"fasttip: appended {len(hdrs)} header(s) {top + 1}..{top + len(hdrs)} from {ip} "
                 f"(Equihash, target, links, difficulty, hash: Bend PASS, {secs * 1000:.0f} ms)")
        return res

    def _poll_headers(self):
        """Safety net for a missed inv: getheaders to one push peer every hdr_poll s (round-robin)."""
        k = 0
        while not self.stop_ev.wait(self.hdr_poll):
            with self.lock:
                ips = sorted(self.conns)
            if ips:
                self._getheaders(ips[k % len(ips)])
                k += 1

    def _tap_gaps(self, seen):
        """Blocks whose headers are verified but which sync has not got (e.g. announced while this
        process was down): follow keeps each live block in work/deferred/<h>/block.bin for its
        oracle checks (minutes). Same checks as any received block (header == verified header)."""
        after = self.buffer.after
        if after is None:
            return
        asked = []
        for h in range(after + 1, min(self.top, after + 50) + 1):
            if h in self.buffer.blocks or ("gap", h) in seen:
                continue
            found = False
            for d in ((FOLLOW_WIN.parent / "deferred" / str(h), FOLLOW_WIN / str(h)) if self.follow_tap else ()):
                p = d / "block.bin"
                try:
                    st = p.stat()
                    if time.time() - st.st_mtime < 0.1:
                        continue
                    raw = p.read_bytes()
                except OSError:
                    continue
                if len(raw) == st.st_size and len(raw) > HDR and raw[:HDR] == headers.header(h):
                    seen[("gap", h)] = time.time()
                    self.stats["follow gap fill"] = self.stats.get("follow gap fill", 0) + 1
                    self.q.put(("block", raw, "follow-gap", time.time()))
                    found = True
                    break
            if not found and time.time() - seen.get(("ask", h), 0) > 10:
                seen[("ask", h)] = time.time()
                asked.append(h)
            if not found:
                seen.setdefault(("miss", h), time.time())
        with self.lock:
            ips = sorted(self.conns)
        oldest = min([t for k, t in seen.items() if k[0] == "miss" and k[1] > after and k[1] not in self.buffer.blocks],
                     default=None)
        if oldest is not None and time.time() - oldest > (30 if ips else 10) and time.time() - self.last_fallback > 60:
            self.kick.set()  # verified headers whose blocks nobody delivers: the fallback downloads them
        if asked and ips:  # headers verified, block missing: ask a push peer by its verified hash
            idx = _idx()
            try:
                hs = [idx.internal(h) for h in asked if h < idx.n]
                hs = [x for x in hs if x not in self.inflight]  # already requested (push path)
            finally:
                idx.f.close()
            if hs:
                self.stats["gap getdata"] = self.stats.get("gap getdata", 0) + len(hs)
                self._getdata(random.choice(ips), hs)

    def _gap_filler(self):
        seen = {}
        while not self.stop_ev.wait(1.0):
            try:
                self._tap_gaps(seen)
            except Exception as e:  # noqa
                self.log(f"fasttip: gap fill: {e!r}")
            if len(seen) > 2000:
                seen.clear()

    def _tap(self):
        """Blocks follow received (node/follow/work/win/<h>/block.bin), read once their size is stable."""
        seen, sizes = {}, {}
        while not self.stop_ev.wait(0.01):
            try:
                names = os.listdir(FOLLOW_WIN)
            except OSError:
                continue
            top = self.top
            for n in names:
                if not n.isdigit():
                    continue
                h = int(n)
                # at or below our tip too: after a reorg follow writes the competing block at a
                # height we already have (the same directory, new bytes)
                if h <= top - 100 or h > top + 100:
                    continue
                p = FOLLOW_WIN / n / "block.bin"
                try:
                    st = p.stat()
                except OSError:
                    continue
                k = (st.st_size, st.st_mtime_ns)
                if seen.get(n) == k:
                    continue
                if sizes.get(n, (None, None, 0))[:2] != k:
                    sizes[n] = (*k, time.time())
                    continue
                if time.time() - sizes[n][2] < 0.03:
                    continue
                try:
                    raw = p.read_bytes()
                except OSError:
                    continue
                if len(raw) != st.st_size or len(raw) < HDR + 1:
                    continue
                seen[n] = k
                hint = sha256d(raw[:HDR])
                if hint in self.known or hint in self.side:
                    continue
                self.stats["follow tap"] = self.stats.get("follow tap", 0) + 1
                self.last_tap = time.time()
                with self.lock:
                    self.inv_seen.setdefault(hint, (st.st_mtime_ns / 1e9, "follow", "follow-tap"))
                self.q.put(("block", raw, "follow-tap", time.time()))
            if len(seen) > 500:
                for n in sorted(seen, key=lambda k: int(k))[:250]:
                    seen.pop(n, None)
                    sizes.pop(n, None)

    def _status(self):
        while not self.stop_ev.wait(300):
            now = time.time()
            with self.lock:
                peers = ", ".join(f"{ip} {v['ua']} up {now - v['t0']:.0f} s invs {v['invs']} quiet {now - v['last']:.0f} s"
                                  for ip, v in self.peer_info.items())
            self.log(f"fasttip status: verified tip {self.top}; {self.stats}; peers: {peers or 'none'}")

    # ------------------------------------------------------------ fallback (the old live.py cycle)
    def _fallback(self):
        while not self.stop_ev.is_set():
            kicked = self.kick.wait(self.every)
            self.kick.clear()
            if self.stop_ev.is_set():
                return
            with self.lock:
                polled = bool(self.conns) and self.hdr_poll > 0
                tap_live = self.follow_tap and time.time() - self.last_tap < 10 * self.every
                no_peers = self.npeers > 0 and not self.conns and not tap_live
            # with a push source (connected peers + header poll, or a productive follow tap) a missed
            # announcement is caught in seconds: the fallback then runs only when kicked, without any
            # push source, or after 10 x --every without a new header
            quiet = time.time() - self.last_push > (10 if (polled or tap_live) else 3) * self.every
            if not (kicked or quiet or no_peers or (self.npeers == 0 and not self.follow_tap)):
                continue
            if time.time() - self.last_fallback < 20:
                time.sleep(20)
            self.last_fallback = time.time()
            self.stats["fallback runs"] += 1
            why = "kicked" if kicked else "no push peers" if no_peers else "push quiet"
            try:
                self._poll_once(why)
            except Exception as e:  # noqa
                self.log(f"fasttip: fallback poll failed: {e.__class__.__name__}: {e}")

    def _child(self, argv, timeout, cwd=None):
        """Run a fallback subprocess in its own process group, so stop() can end it with its children
        (a tiphdr.py outliving this process would append to the header index next to its successor)."""
        p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=dict(os.environ),
                             start_new_session=True, cwd=cwd)
        self.children.add(p)
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, 15)
            out, _ = p.communicate()
        finally:
            self.children.discard(p)
        return out or ""

    def _fetch_headers(self):
        """tiphdr.py's header step, in-process: the same Bend P2P client (zebend-p2p: getheaders,
        SHA-256d hashes and links in Bend), the same peer order (tiphdr.candidate_peers), the same
        Bend checks and acceptance rule (_verify_append = tiphdr.append's rule; hashes from
        hdrchain), the same reorg rule (tiphdr.drop_tip). Unlike running tiphdr.py, the header-index
        lock is held only to check and append (milliseconds), not during the network round trips,
        so a block pushed meanwhile is not held up (measured with tiphdr.py under the lock: pushed
        blocks waited 68-125 s while its peers timed out)."""
        import tiphdr  # node/tiphdr.py (read-only use: peers, drop_tip)
        work = WORK / "p2p"
        no_link = False
        for peer in tiphdr.candidate_peers():
            if self.stop_ev.is_set():
                return "stopped"
            top, top_hex = self.top, self.top_hash[::-1].hex()
            shutil.rmtree(work, ignore_errors=True)
            (work / "out").mkdir(parents=True)
            out = self._child([str(FOLLOW_BIN / "zebend-p2p"), peer, "170190", str(top), top_hex, "13", str(top), top_hex],
                              180, cwd=work)
            no_link |= "does not link" in out
            hp, bp = work / "out/heights.txt", work / "out/headers.bin"
            if not (hp.exists() and bp.exists() and bp.stat().st_size):
                continue
            pairs = re.findall(r"^(\d+) ([0-9a-f]{64})$", hp.read_text(), re.M)
            raw = bp.read_bytes()
            if len(raw) != len(pairs) * HDR or not pairs or int(pairs[0][0]) != top + 1:
                continue
            hdrs = [raw[k * HDR:(k + 1) * HDR] for k in range(len(pairs))]
            if hdrs[0][4:36] != bytes.fromhex(top_hex)[::-1]:  # a fork: the push path's fork choice decides
                self._probe(b"fallback", "fallback", peers=[peer])
                return f"headers from {peer} do not link to our tip {top}: fork choice asked (getheaders + locator)"
            # headers the push path appended meanwhile are skipped; the rest must extend the tip
            hdrs = [x for x in hdrs if sha256d(x) not in self.known]
            if not hdrs:
                return f"0 new headers from {peer} (push path already has them)"
            if hdrs[0][4:36] != self.top_hash:
                if hdrs[0][4:36] in self.known:
                    continue  # a peer on a branch below our tip
                return f"headers from {peer} do not extend the tip {self.top}; next round"
            got = self._verify_append(hdrs, f"{peer} (fallback)")
            if got:
                return f"appended {len(got)} headers {got[0][0]}..{got[-1][0]} from {peer}"
        if no_link:  # peers do not know our tip: it may have lost a block race. The fork choice decides
            self.last_probe = 0.0  # (getheaders + locator, Bend checks, more work only); no blind header cut
            self._probe(b"no-link", "fallback")
            return "peers do not know our tip: fork choice asked (getheaders + locator)"
        return "no headers from any peer"

    def _missing_from(self):
        import download  # node/download.py (read-only use): spool + state tip helpers
        idx = _idx()
        n = idx.n
        idx.f.close()
        last = max([download.state_tip()] + [max(self.buffer.blocks, default=-1)])
        for p in sorted(download.SPOOL.glob("*.blk"), key=lambda p: int(p.stem)):
            d = p.read_bytes()
            i = 0
            while i + 8 <= len(d):
                h, k = struct.unpack_from("<II", d, i)
                last = max(last, h)
                i += 8 + k
        return last, n

    def _download(self, last, n):
        if last < n - 1 and not self.stop_ev.is_set():
            out = self._child([sys.executable, "-u", str(NODE / "download.py"), "--from", str(last + 1), "--to", str(n),
                               "--peers", "4"], 1800)
            for l in out.strip().splitlines()[-4:]:
                self.log(f"  {l}")

    def _poll_once(self, why):
        # blocks whose headers are already verified first (a gap nobody delivered), then new headers
        last, n = self._missing_from()
        if last < n - 1:
            self.log(f"fasttip fallback ({why}): verified to {n - 1}; have blocks to {last}: downloading")
            self._download(last, n)
        line = self._fetch_headers()
        self._refresh_known()
        last, n = self._missing_from()
        self.log(f"fasttip fallback ({why}): headers: {line}; verified to {n - 1}; have blocks to {last}")
        self._download(last, n)
