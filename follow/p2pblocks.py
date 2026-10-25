"""Block transport for `zebend follow`: fetch raw blocks from Zcash mainnet peers over P2P.

This module only moves bytes. It frames messages (the 4-byte P2P checksum uses hashlib,
as required by the wire protocol) and asks peers for blocks by the hashes that the Bend
P2P client computed. It does not validate anything: every received block is handed to the
Bend components, which recompute the header hash, merkle root, txids and everything else.
"""
import hashlib, random, socket, struct, time

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
        inv = _varint(len(hashes)) + b"".join(struct.pack("<I", MSG_BLOCK) + bytes.fromhex(h)[::-1] for h in hashes)
        self.s.sendall(_frame("getdata", inv))
        slot = {p: i for i, p in enumerate(prevs)}
        got = [None] * len(hashes)
        deadline = time.time() + 60
        while any(b is None for b in got):
            if time.time() > deadline:
                raise TimeoutError(f"peer sent {sum(b is not None for b in got)}/{len(hashes)} blocks in 60 s")
            cmd, p = self.recv()
            if cmd == "block":
                i = slot.get(p[4:36][::-1].hex())
                if i is not None:
                    got[i] = p
            elif cmd == "notfound":
                raise LookupError("peer does not have a requested block")
        return got

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


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
