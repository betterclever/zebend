"""Lab tool: a local legacy-P2P peer on 127.0.0.1 serving a chain we choose (reorg tests).

Speaks the framing of node/net.py: version/verack, ping/pong, getheaders (Zebra rules: headers
after the highest locator hash on our best chain, at most 160, each followed by a 0 tx count;
no common hash: from the first header we have), getdata (blocks we hold; notfound otherwise),
and inv announcements on demand. Headers and blocks are real mainnet data (files); the mock only
decides which chain it calls best.
"""
import hashlib, socket, struct, threading, time
import net  # the lab's node/net.py (framing only)


def sha256d(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


class MockPeer:
    def __init__(self, log=print):
        self.log = log
        self.srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(4)
        self.port = self.srv.getsockname()[1]
        self.best = []            # [(height, header)] in order: our best chain (a suffix is enough)
        self.blocks = {}          # name -> raw block
        self.conn = None
        self.lock = threading.Lock()
        self.served = {"getheaders": 0, "getdata": 0, "blocks": 0}
        threading.Thread(target=self._accept, daemon=True).start()

    def set_best(self, pairs):
        with self.lock:
            self.best = list(pairs)

    def add_block(self, raw):
        self.blocks[sha256d(raw[:1487])] = raw

    def announce(self, name):
        with self.lock:
            c = self.conn
        if c is not None:
            c.sendall(net.frame("inv", net.varint(1) + struct.pack("<I", 2) + name))
            return True
        return False

    def _accept(self):
        while True:
            c, _ = self.srv.accept()
            with self.lock:
                self.conn = c
            threading.Thread(target=self._serve, args=(c,), daemon=True).start()

    def _version(self):
        ua = b"/MockZebra:0.0/"
        h = self.best[-1][0] if self.best else 0
        return (struct.pack("<iQq", net.PROTO, 1, int(time.time())) + net.netaddr("127.0.0.1", 8233)
                + net.netaddr("0.0.0.0", 0) + struct.pack("<Q", 7) + bytes([len(ua)]) + ua + struct.pack("<i", h) + b"\0")

    def _serve(self, c):
        buf = b""
        try:
            while True:
                d = c.recv(1 << 20)
                if not d:
                    return
                buf += d
                while len(buf) >= 24:
                    n = struct.unpack_from("<I", buf, 16)[0]
                    if len(buf) < 24 + n:
                        break
                    cmd = buf[4:16].rstrip(b"\0").decode()
                    p, buf = buf[24:24 + n], buf[24 + n:]
                    self._handle(c, cmd, p)
        except OSError:
            return

    def _handle(self, c, cmd, p):
        if cmd == "version":
            c.sendall(net.frame("version", self._version()) + net.frame("verack", b""))
        elif cmd == "ping":
            c.sendall(net.frame("pong", p))
        elif cmd == "getheaders":
            self.served["getheaders"] += 1
            k, i = net.read_cs(p, 4)
            loc = [p[i + 32 * j:i + 32 * j + 32] for j in range(k)]
            with self.lock:
                names = [sha256d(hd) for _, hd in self.best]
                start = 0
                for x in loc:  # the first (highest) locator hash on our best chain
                    if x in names:
                        start = names.index(x) + 1
                        break
                out = [hd for _, hd in self.best[start:start + 160]]
            c.sendall(net.frame("headers", net.varint(len(out)) + b"".join(hd + b"\0" for hd in out)))
        elif cmd == "getdata":
            self.served["getdata"] += 1
            k, i = net.read_cs(p, 0)
            miss = []
            for j in range(k):
                typ, name = struct.unpack_from("<I", p, i + 36 * j)[0], p[i + 36 * j + 4:i + 36 * j + 36]
                if typ == 2 and name in self.blocks:
                    self.served["blocks"] += 1
                    c.sendall(net.frame("block", self.blocks[name]))
                else:
                    miss.append(p[i + 36 * j:i + 36 * j + 36])
            if miss:
                c.sendall(net.frame("notfound", net.varint(len(miss)) + b"".join(miss)))
