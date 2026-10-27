"""Fetch real Zcash TESTNET data around NU7 activation (height 4,465,026, branch 0x77190ad9).

Transport and bookkeeping only: nothing here decides validity (Bend does). The tx parser
below only walks byte layouts to find transparent inputs/outputs, value balances and sizes.

Run on the Mac (needs network; grpcurl from lwd-build):

    cd ROOT/consensus/nu7/testnet
    python3 fetch.py scan        # lightwalletd compact blocks 4,454,979..tip -> lwd/compact.jsonl
    python3 fetch.py headers     # P2P getheaders -> headers.bin/.json, hashes.txt, headers_pre.bin/.json
    python3 fetch.py blocks      # P2P getdata for sets (a)-(d) -> raw.bin/raw.idx (spool)
    python3 fetch.py prevtx      # lightwalletd GetTransaction for spent outputs -> prevtx/<txid>.hex
    python3 fetch.py write       # blocks.bin, ctx.bin, blocks.json, summary.json
    python3 fetch.py all         # all of the above in order

Block sets: (a) 4,464,826..4,467,026, (b) 4,497,748..4,498,148, (c) blocks in 4,467,027..tip with
ntx > 1, (d) blocks in 4,455,000..4,459,999 with ntx > 1 (ntx from compact blocks with all pool
types, which include coinbase and transparent-only txs). Fetched in order a, b, d, c; c in height
order until raw.bin reaches ZT_SPOOL_MAX bytes (default 800 MB; late testnet blocks are ~1.5 MB).
raw.bin duplicates blocks.bin and may be deleted once `write` has run (it is the resume spool).

Every stage is resumable (re-running continues from the files on disk). Data goes to
ROOT/consensus/nu7/data/testnet/ (override with ZT_DATA=...). `headers` / `scan` extend to the
current tip each time they are run.

Formats (all integers little-endian):
  headers.bin      contiguous 1487-byte headers (version .. 1344-byte solution incl. its fd4005
                   CompactSize prefix), heights headers.json first..last.
  headers_pre.bin  same, for heights PRE_FIRST..4,459,999 (needed for set (d) and its MTP times).
  hashes.txt       "height hash" per line, hash in display (big-endian) hex, for headers.bin.
  blocks.bin       per block: u32 height | 1487-byte header | u32 len | raw block (len bytes).
  ctx.bin          per block (blocks.bin order): u32 L | L bytes =
                   u32 height | u32 nt | nt x u32 times (heights h-nt..h-1) |
                   per spent transparent input in block order (coinbase excluded):
                   u32 value lo | u32 value hi | u32 creating height | u32 from-coinbase |
                   u32 script len | script.   (node/rules.py block_records; no pools header)
  prevtx/<txid>.hex  raw creating txs fetched from lightwalletd (txid in display order);
                   prevtx/index.json {txid: height}.
"""
import base64, hashlib, json, os, random, socket, struct, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DATA = Path(os.environ.get("ZT_DATA", ROOT / "zcash/consensus/nu7/data/testnet"))
GRPCURL = "/Users/betterclever/projects/zecathon/lwd-build/bin/grpcurl"
LWD = os.environ.get("ZT_LWD", "testnet.zec.rocks:443")
SVC = "cash.z.wallet.sdk.rpc.CompactTxStreamer"

NU7 = 4_465_026
FIRST = 4_460_000          # headers.bin first height
PRE_FIRST = 4_454_980      # headers_pre.bin first height (set (d) starts 4,455,000; 11 earlier times + slack)
SCAN_FIRST = PRE_FIRST - 1 # compact blocks from here (gives the locator hash for headers_pre)
SET_A = (4_464_826, 4_467_026)
SET_B = (4_497_748, 4_498_148)
SET_D = (4_455_000, 4_459_999)
HDR = 1487

MAGIC = bytes.fromhex("fa1af9bf")
PORT = 18233
PROTOS = [170190, 170180]
SEEDS = ["testnet.seeder.zfnd.org", "dnsseed.testnet.z.cash"]


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def dsha(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def disp(h):  # internal-order bytes -> display hex
    return h[::-1].hex()


# ------------------------------------------------------------------ lightwalletd (grpcurl)

def grpc(method, req, timeout=600):
    r = subprocess.run([GRPCURL, "-max-time", str(timeout), "-d", json.dumps(req), LWD, f"{SVC}/{method}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"grpcurl {method}: {r.stderr.strip()[:300]}")
    return r.stdout


def json_stream(s):
    dec, i, out = json.JSONDecoder(), 0, []
    while True:
        while i < len(s) and s[i].isspace():
            i += 1
        if i >= len(s):
            return out
        o, i = dec.raw_decode(s, i)
        out.append(o)


def lwd_tip():
    return int(json.loads(grpc("GetLightdInfo", {}, 30))["blockHeight"])


COMPACT = DATA / "lwd" / "compact.jsonl"


def load_compact():
    out = {}
    if COMPACT.exists():
        for line in COMPACT.read_text().splitlines():
            if line.strip():
                o = json.loads(line)
                out[o["h"]] = o
    return out


def stage_scan():
    COMPACT.parent.mkdir(parents=True, exist_ok=True)
    have = load_compact()
    start = max(have) + 1 if have else SCAN_FIRST
    tip = lwd_tip()
    log(f"scan: compact blocks {start}..{tip} from {LWD}")
    with open(COMPACT, "a") as f:
        h = start
        while h <= tip:
            e = min(h + 1999, tip)
            for att in range(5):
                try:
                    blks = json_stream(grpc("GetBlockRange", {"start": {"height": h}, "end": {"height": e},
                                                              "poolTypes": ["TRANSPARENT", "SAPLING", "ORCHARD", "IRONWOOD"]}))
                    break
                except Exception as ex:
                    log("  retry", h, ex)
                    time.sleep(5 * (att + 1))
            else:
                raise SystemExit("scan failed")
            if len(blks) != e - h + 1:
                raise SystemExit(f"scan: got {len(blks)} blocks for {h}..{e}")
            for b in blks:
                hh = int(b["height"])
                txs = sorted(b.get("vtx", []), key=lambda t: int(t.get("index", 0)))
                if [int(t.get("index", 0)) for t in txs] != list(range(len(txs))):
                    log(f"  warning: compact block {hh} tx indices not 0..n-1")
                f.write(json.dumps({"h": hh, "hash": disp(base64.b64decode(b["hash"])),
                                    "prev": disp(base64.b64decode(b["prevHash"])), "time": b["time"],
                                    "ntx": len(txs), "txids": [disp(base64.b64decode(t["txid"])) for t in txs]}) + "\n")
            f.flush()
            h = e + 1
    log("scan: done, tip", tip)


# ------------------------------------------------------------------ P2P

def frame(cmd, p):
    return MAGIC + cmd.encode().ljust(12, b"\0") + struct.pack("<I", len(p)) + dsha(p)[:4] + p


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


class Peer:
    def __init__(self, ip, proto, timeout=10):
        self.ip = ip
        self.s = socket.create_connection((ip, PORT), timeout=timeout)
        self.buf = bytearray()
        ua = b"/Zebend-nu7-testnet-fetch:0.1/"
        v = (struct.pack("<iQq", proto, 0, int(time.time())) + netaddr(ip, PORT) + netaddr("0.0.0.0", 0)
             + struct.pack("<Q", random.getrandbits(64)) + bytes([len(ua)]) + ua + struct.pack("<i", 0) + b"\0")
        self.s.sendall(frame("version", v))
        gv = gva = False
        dl = time.time() + timeout
        while not (gv and gva):
            if time.time() > dl:
                raise TimeoutError("handshake timeout")
            cmd, p = self.recv()
            if cmd == "version":
                gv = True
                n, i = read_cs(p, 80)
                self.ua = p[i:i + n].decode(errors="replace")
                self.height = struct.unpack_from("<i", p, i + n)[0]
                self.s.sendall(frame("verack", b""))
            elif cmd == "verack":
                gva = True
            elif cmd == "reject":
                raise ConnectionError("reject " + p[:80].hex())

    def recv(self):
        while True:
            b = self.buf
            if len(b) >= 24:
                if b[:4] != MAGIC:
                    raise ConnectionError("bad magic")
                n = struct.unpack_from("<I", b, 16)[0]
                if n > 4_000_000:
                    raise ConnectionError("oversized")
                if len(b) >= 24 + n:
                    cmd = bytes(b[4:16]).rstrip(b"\0").decode(errors="replace")
                    p = bytes(b[24:24 + n])
                    del b[:24 + n]
                    if cmd == "ping":
                        self.s.sendall(frame("pong", p))
                        continue
                    if cmd == "getaddr":
                        self.s.sendall(frame("addr", b"\0")); continue
                    if cmd == "getheaders":
                        self.s.sendall(frame("headers", b"\0")); continue
                    if cmd in ("getblocks", "mempool"):
                        self.s.sendall(frame("inv", b"\0")); continue
                    if cmd == "getdata":
                        self.s.sendall(frame("notfound", p)); continue
                    return cmd, p
            d = self.s.recv(1 << 20)
            if not d:
                raise ConnectionError("peer closed")
            b += d

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


def candidates():
    ips = []
    for s in SEEDS:
        try:
            ips += [a[4][0] for a in socket.getaddrinfo(s, PORT, socket.AF_INET, socket.SOCK_STREAM)]
        except OSError as e:
            log("seeder", s, "failed:", e)
    ips = list(dict.fromkeys(ips))
    random.shuffle(ips)
    return ips


def connect_some(n, min_height, tried=None):
    """Up to n connected peers (one connection per IP) whose advertised height >= min_height."""
    out, tried = [], tried if tried is not None else set()
    for ip in candidates():
        if len(out) >= n:
            break
        if ip in tried:
            continue
        tried.add(ip)
        for proto in PROTOS:
            try:
                p = Peer(ip, proto)
                if p.height < min_height:
                    log(f"  peer {ip} {p.ua} height {p.height} < {min_height}, skip")
                    p.close()
                    break
                p.proto = proto
                log(f"  peer {ip} {p.ua} h={p.height} proto={proto}")
                out.append(p)
                break
            except Exception as e:
                log(f"  peer {ip} proto {proto}: {e}")
    return out


def parse_headers_msg(p):
    n, i = read_cs(p, 0)
    out = []
    for _ in range(n):
        ns, j = read_cs(p, i + 140)
        end = j + ns
        out.append(p[i:end])
        _, i = read_cs(p, end)
    return out


def fetch_headers(peer, locator_hash, want):
    """Headers following locator_hash (internal order) until `want` collected or tip."""
    out = []
    loc = locator_hash
    while len(out) < want:
        peer.s.sendall(frame("getheaders", struct.pack("<I", peer.proto) + varint(1) + loc + b"\0" * 32))
        dl = time.time() + 60
        while True:
            if time.time() > dl:
                if out:
                    return out  # at the tip some peers do not answer an empty getheaders
                raise TimeoutError("getheaders timeout")
            try:
                cmd, p = peer.recv()
            except socket.timeout:
                continue
            if cmd == "headers":
                break
        hs = parse_headers_msg(p)
        if not hs:
            break
        if hs[0][4:36] != loc:
            raise ConnectionError("headers do not follow locator")
        out += hs
        loc = dsha(hs[-1])
        if len(out) % 8000 < 160:
            log(f"  {len(out)} headers")
    return out[:want]


def stage_headers():
    comp = load_compact()
    tip = max(comp)
    tried = set()
    peers = connect_some(3, tip - 10, tried)
    if not peers:
        raise SystemExit("headers: no testnet peer reachable")
    used = []

    def extend(path, first, last):
        hs = []
        if path.exists():
            b = path.read_bytes()
            hs = [b[i:i + HDR] for i in range(0, len(b) - len(b) % HDR, HDR)]
        have_last = first + len(hs) - 1
        if last is not None and have_last >= last:
            return hs[:last - first + 1]
        loc = dsha(hs[-1]) if hs else bytes.fromhex(comp[first - 1]["hash"])[::-1]
        want = (last - have_last) if last is not None else 10 ** 9
        for p in list(peers):
            try:
                new = fetch_headers(p, loc, want)
                used.append(f"{p.ip} ({p.ua})")
                hs += new
                break
            except Exception as e:
                log(f"  peer {p.ip} failed: {e}")
                p.close()
                peers.remove(p)
        return hs[:(last - first + 1)] if last is not None else hs

    for path, first, last in ((DATA / "headers_pre.bin", PRE_FIRST, FIRST - 1), (DATA / "headers.bin", FIRST, None)):
        hs = extend(path, first, last)
        # cheap checks: linkage, hash == lightwalletd compact-block hash at every height we scanned
        bad_link = [first + k for k in range(1, len(hs)) if hs[k][4:36] != dsha(hs[k - 1])]
        mism, cmp = [], 0
        for k, hd in enumerate(hs):
            c = comp.get(first + k)
            if c:
                cmp += 1
                if disp(dsha(hd)) != c["hash"]:
                    mism.append(first + k)
        bad_size = [first + k for k, hd in enumerate(hs) if len(hd) != HDR or hd[140:143] != b"\xfd\x40\x05"]
        log(f"headers {path.name}: {first}..{first + len(hs) - 1} ({len(hs)}); link breaks {bad_link[:5]}; "
            f"lwd-hash compared {cmp}, mismatches {mism[:5]}; bad size {bad_size[:5]}")
        if bad_link or bad_size:
            raise SystemExit("headers: chain check failed, not writing " + path.name)
        path.write_bytes(b"".join(hs))
        spot = sorted(random.sample(range(len(hs)), min(20, len(hs))))
        spot_res = [[first + k, disp(dsha(hs[k])), comp.get(first + k, {}).get("hash") == disp(dsha(hs[k]))] for k in spot]
        meta = {"first": first, "last": first + len(hs) - 1, "count": len(hs), "tip_hash": disp(dsha(hs[-1])),
                "source": "P2P getheaders from " + ", ".join(dict.fromkeys(used)),
                "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "checks": {"prev_hash_links_ok": True, "lwd_hash_compared": cmp, "lwd_hash_mismatches": mism,
                           "spot_check_20": spot_res}}
        path.with_suffix(".json").write_text(json.dumps(meta, indent=1))
        if path.name == "headers.bin":
            with open(DATA / "hashes.txt", "w") as f:
                for k, hd in enumerate(hs):
                    f.write(f"{first + k} {disp(dsha(hd))}\n")
    for p in peers:
        p.close()


class Headers:
    def __init__(self):
        self.parts = []
        for name in ("headers_pre.bin", "headers.bin"):
            m = json.loads((DATA / name).with_suffix(".json").read_text())
            self.parts.append((m["first"], m["last"], (DATA / name).read_bytes()))
        self.last = self.parts[-1][1]

    def get(self, h):
        for f, l, b in self.parts:
            if f <= h <= l:
                return b[(h - f) * HDR:(h - f + 1) * HDR]
        return None

    def time(self, h):
        return struct.unpack_from("<I", self.get(h), 100)[0]


# ------------------------------------------------------------------ block selection and spool

def selection(comp, last):
    sets = {"a": [h for h in range(SET_A[0], SET_A[1] + 1) if h <= last],
            "b": [h for h in range(SET_B[0], SET_B[1] + 1) if h <= last],
            "c": [h for h in range(SET_A[1] + 1, last + 1) if comp[h]["ntx"] > 1],
            "d": [h for h in range(SET_D[0], SET_D[1] + 1) if comp[h]["ntx"] > 1]}
    return sets


IDX = DATA / "raw.idx"
SPOOL_MAX = int(os.environ.get("ZT_SPOOL_MAX", 800_000_000))
SPOOL = DATA / "raw.bin"


def load_idx():
    out = {}
    if IDX.exists():
        for line in IDX.read_text().splitlines():
            f = line.split()
            if len(f) == 3:
                out[int(f[0])] = (int(f[1]), int(f[2]))
    return out


def stage_blocks():
    comp = load_compact()
    H = Headers()
    sets = selection(comp, min(H.last, max(comp)))
    # (d) is small, so it goes before (c); (c) is fetched in height order until the spool
    # reaches SPOOL_MAX bytes (late testnet blocks are up to 1.5 MB each).
    order = sets["a"] + sets["b"] + sets["d"] + sets["c"]
    order = list(dict.fromkeys(order))
    have = load_idx()
    if SPOOL.exists() and SPOOL.stat().st_size >= SPOOL_MAX:
        log(f"blocks: spool at {SPOOL.stat().st_size} >= SPOOL_MAX {SPOOL_MAX}; not fetching more")
        return
    todo = [h for h in order if h not in have]
    log(f"blocks: sets a={len(sets['a'])} b={len(sets['b'])} c={len(sets['c'])} d={len(sets['d'])}; "
        f"have {len(have)}, todo {len(todo)}")
    if not todo:
        return
    by_hash = {dsha(H.get(h)): h for h in todo}
    lock = threading.Lock()
    queue = list(todo)
    mism = []
    spool = open(SPOOL, "ab")
    idxf = open(IDX, "a")
    done = [0]

    def worker(peer):
        fails, bs = 0, 16
        while True:
            with lock:
                if spool.tell() >= SPOOL_MAX:
                    queue.clear()
                batch = queue[:bs]
                del queue[:bs]
            if not batch:
                return
            got = set()
            try:
                peer.s.sendall(frame("getdata", varint(len(batch)) + b"".join(struct.pack("<I", 2) + dsha(H.get(h)) for h in batch)))
                got = set()
                dl = time.time() + 60
                while len(got) < len(batch):
                    if time.time() > dl:
                        raise TimeoutError("getdata timeout")
                    cmd, p = peer.recv()
                    if cmd == "notfound":
                        raise ConnectionError("notfound")
                    if cmd != "block":
                        continue
                    hh = dsha(p[:HDR])
                    h = by_hash.get(hh)
                    if h is None or h not in batch:
                        continue
                    if p[:HDR] != H.get(h):
                        mism.append(h)
                        got.add(h)
                        continue
                    with lock:
                        off = spool.tell()
                        spool.write(p)
                        spool.flush()
                        idxf.write(f"{h} {off} {len(p)}\n")
                        idxf.flush()
                        done[0] += 1
                        if done[0] % 500 == 0:
                            log(f"  {done[0]}/{len(todo)} blocks")
                    got.add(h)
                fails = 0
                bs = min(16, bs + 1)
            except Exception as e:
                bs = max(1, bs // 4)  # Zebra stops a getdata response at 1 MB: big blocks need small batches
                with lock:
                    queue[:0] = [h for h in batch if h not in got]
                fails += 1
                log(f"  peer {peer.ip}: {e}")
                if fails >= 3:
                    peer.close()
                    return
                time.sleep(5 * fails)

    tried = set()
    while True:
        with lock:
            if not queue:
                break
        peers = connect_some(4, max(todo), tried)
        if not peers:
            if len(tried) > 60:
                break
            tried.clear()
            time.sleep(30)
            continue
        ts = [threading.Thread(target=worker, args=(p,)) for p in peers]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        for p in peers:
            p.close()
    spool.close()
    idxf.close()
    left = load_idx()
    log(f"blocks: have {len(left)}; header mismatches {mism}; missing {len([h for h in todo if h not in left])}")


def read_block(h, idx, f):
    o, n = idx[h]
    f.seek(o)
    return f.read(n)


# ------------------------------------------------------------------ tx parser (layouts only)

class P:
    def __init__(self, b, i=0):
        self.b, self.i = b, i

    def take(self, n):
        x = self.b[self.i:self.i + n]
        if len(x) != n:
            raise ValueError("truncated")
        self.i += n
        return x

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def i64(self):
        return struct.unpack("<q", self.take(8))[0]

    def cs(self):
        v, self.i = read_cs(self.b, self.i)
        return v


def parse_tx(b, i=0):
    """-> dict(ver, ins[(prev_txid_internal, idx)], outs[(value, script)], vb (net shielded value into
    transparent: sapling+orchard+ironwood balances + sum(vpub_new - vpub_old)), sapling, orchard,
    ironwood flags, coinbase, end offset)."""
    p = P(b, i)
    hdr = p.u32()
    ver = hdr & 0x7fffffff
    grp = p.u32() if ver >= 3 else 0
    if ver >= 5:
        p.take(12)  # branch id, lock time, expiry
    ins, outs = [], []
    for _ in range(p.cs()):
        prev = p.take(32); k = p.u32(); p.take(p.cs()); p.u32()
        ins.append((prev, k))
    for _ in range(p.cs()):
        v = p.i64(); outs.append((v, p.take(p.cs())))
    vb, sap, orch, iron = 0, False, False, False
    if ver <= 4:
        p.take(4)  # lock
        if ver >= 3:
            p.take(4)  # expiry
    if ver == 4:
        svb = p.i64()
        ns = p.cs(); p.take(384 * ns)
        no = p.cs(); p.take(948 * no)
        if ns or no:
            vb += svb; sap = True
    if 2 <= ver <= 4:
        nj = p.cs()
        for _ in range(nj):
            old = p.i64(); new = p.i64()
            vb += new - old
            p.take(1802 - 16 if ver < 4 else 1698 - 16)
        if nj:
            p.take(96)
    if ver == 4 and sap:
        p.take(64)
    if ver >= 5:
        ns = p.cs(); p.take(96 * ns)
        no = p.cs(); p.take(756 * no)
        if ns or no:
            sap = True
            vb += p.i64()
            if ns:
                p.take(32)
            p.take(192 * ns + 64 * ns + 192 * no + 64)
        for kind in (("orchard",) if ver == 5 else ("orchard", "ironwood")):
            na = p.cs(); p.take(820 * na)
            if na:
                p.take(1); vb += p.i64(); p.take(32)
                p.take(p.cs()); p.take(64 * na + 64)
                if kind == "orchard":
                    orch = True
                else:
                    iron = True
    cb = len(ins) == 1 and ins[0][0] == b"\0" * 32 and ins[0][1] == 0xffffffff
    return {"ver": ver, "grp": grp, "ins": ins, "outs": outs, "vb": vb, "sapling": sap, "orchard": orch,
            "ironwood": iron, "coinbase": cb, "start": i, "end": p.i}


def parse_block(raw):
    n, i = read_cs(raw, HDR)
    txs = []
    for _ in range(n):
        t = parse_tx(raw, i)
        txs.append(t)
        i = t["end"]
    if i != len(raw):
        raise ValueError(f"block parse consumed {i} of {len(raw)} bytes")
    return txs


# ------------------------------------------------------------------ spent outputs

PREV = DATA / "prevtx"


def stage_prevtx():
    comp = load_compact()
    idx = load_idx()
    PREV.mkdir(exist_ok=True)
    ix_path = PREV / "index.json"
    pidx = json.loads(ix_path.read_text()) if ix_path.exists() else {}
    local = set()
    for h in idx:
        local.update(comp[h]["txids"])
    need = set()
    with open(SPOOL, "rb") as f:
        for h in sorted(idx):
            for t in parse_block(read_block(h, idx, f)):
                if not t["coinbase"]:
                    for prev, _ in t["ins"]:
                        tid = disp(prev)
                        if tid not in local and tid not in pidx:
                            need.add(tid)
    log(f"prevtx: {len(need)} creating txs to fetch (have {len(pidx)})")

    def get(tid):
        for att in range(5):
            try:
                o = json.loads(grpc("GetTransaction", {"hash": base64.b64encode(bytes.fromhex(tid)[::-1]).decode()}, 60))
                return tid, base64.b64decode(o["data"]), int(o.get("height", 0))
            except Exception as e:
                err = e
                time.sleep(2 * (att + 1))
        log("  failed", tid, err)
        return tid, None, None

    n = 0
    with ThreadPoolExecutor(6) as ex:
        for tid, raw, height in ex.map(get, sorted(need)):
            if raw is None:
                continue
            (PREV / f"{tid}.hex").write_text(raw.hex())
            pidx[tid] = height
            n += 1
            if n % 200 == 0:
                ix_path.write_text(json.dumps(pidx))
                log(f"  {n}/{len(need)}")
    ix_path.write_text(json.dumps(pidx))
    log(f"prevtx: fetched {n}; missing {len(need) - n}")


# ------------------------------------------------------------------ outputs

def stage_write():
    comp = load_compact()
    H = Headers()
    idx = load_idx()
    sets = selection(comp, min(H.last, max(comp)))
    membership = {}
    for k, hs in sets.items():
        for h in hs:
            membership.setdefault(h, []).append(k)
    heights = sorted(h for h in membership if h in idx)
    missing = sorted(h for h in membership if h not in idx)
    pidx = json.loads((PREV / "index.json").read_text()) if (PREV / "index.json").exists() else {}
    made = {}   # (txid display, vout) -> (value, script, height, cb) from blocks of blocks.bin
    prevcache = {}
    blocks_out, problems = [], []
    hist = {"pre": {}, "post": {}}
    v4_post = 0
    post_fee_blocks = 0
    total_fees = {"pre": 0, "post": 0}
    unknown_spends = 0
    fb = open(DATA / "blocks.bin", "wb")
    fc = open(DATA / "ctx.bin", "wb")
    with open(SPOOL, "rb") as f:
        for h in heights:
            raw = read_block(h, idx, f)
            hd = H.get(h)
            if raw[:HDR] != hd or disp(dsha(raw[:HDR])) != comp[h]["hash"]:
                problems.append([h, "header/hash mismatch"]); continue
            try:
                txs = parse_block(raw)
            except Exception as e:
                problems.append([h, f"parse: {e}"]); continue
            if len(txs) != comp[h]["ntx"]:
                problems.append([h, f"ntx {len(txs)} != compact {comp[h]['ntx']}"])
            txids = comp[h]["txids"] if len(comp[h]["txids"]) == len(txs) else [None] * len(txs)
            # txid sanity for v1-v4 (sha256d); v5/v6 (ZIP 244) are left to Bend
            for t, tid in zip(txs, txids):
                if t["ver"] <= 4 and tid and disp(dsha(raw[t["start"]:t["end"]])) != tid:
                    problems.append([h, f"v{t['ver']} txid mismatch {tid}"])
            nt = min(11, h)
            times = [H.time(x) for x in range(h - nt, h)]
            rec = [struct.pack("<II", h, nt), b"".join(struct.pack("<I", x) for x in times)]
            ntin, fees_block, fee_ok = 0, 0, True
            era = "post" if h >= NU7 else "pre"
            for t, tid in zip(txs, txids):
                hist[era][t["ver"]] = hist[era].get(t["ver"], 0) + 1
                if era == "post" and t["ver"] == 4:
                    v4_post += 1
                tin = 0
                if not t["coinbase"]:
                    for prev, k in t["ins"]:
                        pt = disp(prev)
                        u = made.get((pt, k))
                        if u is None and pt in pidx:
                            if pt not in prevcache:
                                prevcache[pt] = parse_tx(bytes.fromhex((PREV / f"{pt}.hex").read_text()))
                            pt_tx = prevcache[pt]
                            if k < len(pt_tx["outs"]):
                                v, s = pt_tx["outs"][k]
                                u = (v, s, pidx[pt], pt_tx["coinbase"])
                        if u is None:
                            unknown_spends += 1
                            problems.append([h, f"unknown spent output {pt}:{k}"])
                            fee_ok = False
                            continue
                        v, s, ph, cb = u
                        tin += v
                        ntin += 1
                        rec.append(struct.pack("<IIIII", v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF, ph, int(cb), len(s)) + bytes(s))
                    fees_block += tin - sum(v for v, _ in t["outs"]) + t["vb"]
                if tid:
                    for k, (v, s) in enumerate(t["outs"]):
                        made[(tid, k)] = (v, s, h, t["coinbase"])
            rec = b"".join(rec)
            fb.write(struct.pack("<I", h) + hd + struct.pack("<I", len(raw)) + raw)
            fc.write(struct.pack("<I", len(rec)) + rec)
            if fee_ok:
                total_fees[era] += fees_block
            if era == "post" and len(txs) > 1:
                post_fee_blocks += 1
            cbt = txs[0]
            blocks_out.append({"height": h, "hash": comp[h]["hash"], "sets": membership[h], "ntx": len(txs),
                               "size": len(raw), "tx_versions": [t["ver"] for t in txs],
                               "n_transparent_inputs": ntin,
                               "has_sapling": any(t["sapling"] for t in txs), "has_orchard": any(t["orchard"] for t in txs),
                               "has_ironwood": any(t["ironwood"] for t in txs),
                               "fees": fees_block if fee_ok else None,
                               "coinbase_outputs": [[v, s.hex()] for v, s in cbt["outs"]]})
    fb.close(); fc.close()
    (DATA / "blocks.json").write_text(json.dumps(blocks_out, indent=0))
    summary = {
        "blocks_written": len(blocks_out), "heights": [heights[0], heights[-1]] if heights else None,
        "per_set_selected": {k: len(v) for k, v in sets.items()},
        "per_set_written": {k: sum(1 for b in blocks_out if k in b["sets"]) for k in sets},
        "missing_blocks": missing, "problems": problems,
        "post_nu7_blocks_with_non_coinbase_txs": post_fee_blocks,
        "post_nu7_blocks_with_nonzero_fees": sum(1 for b in blocks_out if b["height"] >= NU7 and b["fees"]),
        "tx_version_histogram": {"pre_nu7": hist["pre"], "post_nu7": hist["post"]},
        "v4_txs_after_activation": v4_post, "unknown_spent_outputs": unknown_spends,
        "total_fees_zat": total_fees, "headers_last": H.last, "lwd_tip_scanned": max(comp),
        "prevtx_fetched": len(pidx),
        "selection_basis": "lightwalletd GetBlockRange compact blocks with poolTypes=[TRANSPARENT,SAPLING,ORCHARD,IRONWOOD] (includes coinbase and transparent-only txs); ntx cross-checked against full blocks",
    }
    (DATA / "summary.json").write_text(json.dumps(summary, indent=1))
    log(json.dumps({k: v for k, v in summary.items() if k not in ("problems", "missing_blocks")}, indent=1))
    log(f"problems: {len(problems)} (first: {problems[:5]}); missing: {len(missing)}")


STAGES = {"scan": stage_scan, "headers": stage_headers, "blocks": stage_blocks, "prevtx": stage_prevtx, "write": stage_write}

if __name__ == "__main__":
    DATA.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:] or ["all"]
    for a in args:
        for s in (list(STAGES) if a == "all" else [a]):
            STAGES[s]()
