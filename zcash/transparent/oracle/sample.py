#!/usr/bin/env python3
"""Sample mainnet blocks per era, download them over P2P, and build ZTV1 records.

    python3 sample.py ERA TARGET_INPUTS [CAP]

Heights are drawn with random.Random(f"{SEED}-{era}") without replacement from the era's
height range; block hashes come from lightwalletd (tv-oracle hashes); full raw blocks come
from mainnet peers (the node/follow/p2pblocks.py Peer transport, imported read-only). Blocks are
identified by recomputing their header hash here (transport bookkeeping only; nothing is
validated by this script). Batches are drawn until the blocks give TARGET_INPUTS inputs
(counted by `tv-oracle count`, which applies the per-block CAP), then `tv-oracle build`
fetches the prevouts and writes data/real/<era>_<k>.ztv (+ .expect/.sighash/.meta).
"""
import hashlib, os, queue, random, struct, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # zcash/transparent/
sys.path.insert(0, os.path.join(ROOT, "..", "..", "node", "follow"))
import p2pblocks  # noqa: E402

SEED = 20261026
DATA = os.path.join(ROOT, "data")
BLOCKS = os.path.join(DATA, "blocks")
BIN = os.path.join(HERE, "target", "release", "tv-oracle")
TIP = 3_530_516  # lightwalletd tip when the sample was drawn (fixed for reproducibility)
ERAS = {
    "preoverwinter": (1, 347_499), "overwinter": (347_500, 419_199), "sapling": (419_200, 653_599),
    "blossom": (653_600, 902_999), "heartwood": (903_000, 1_046_399), "canopy": (1_046_400, 1_687_103),
    "nu5": (1_687_104, 2_726_399), "nu6_0": (2_726_400, 3_146_399), "nu6_1": (3_146_400, 3_364_599),
    "nu6_2": (3_364_600, 3_428_142), "nu6_3": (3_428_143, TIP),
}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def block_hash(raw):
    p = 140
    f = raw[p]
    n, w = (f, 1) if f < 0xfd else ((struct.unpack("<H", raw[p + 1:p + 3])[0], 3) if f == 0xfd else (struct.unpack("<I", raw[p + 1:p + 5])[0], 5))
    hdr = raw[:p + w + n]
    return hashlib.sha256(hashlib.sha256(hdr).digest()).digest()[::-1].hex()


def fetch_blocks(items, npeers=4):
    """items: list of (height, display hash). Writes BLOCKS/<height>.blk."""
    os.makedirs(BLOCKS, exist_ok=True)
    todo = queue.Queue()
    for h, hs in items:
        if not os.path.exists(os.path.join(BLOCKS, f"{h}.blk")):
            todo.put((h, hs))
    total = todo.qsize()
    if not total:
        return
    done = [0]
    lock = threading.Lock()
    ips = [ip for ip in p2pblocks.candidates()]
    random.Random().shuffle(ips)
    ip_q = queue.Queue()
    for ip in ips:
        ip_q.put(ip)

    def worker():
        peer = None
        fails = 0
        while True:
            batch = []
            try:
                while len(batch) < 2:
                    batch.append(todo.get_nowait())
            except queue.Empty:
                pass
            if not batch:
                return
            try:
                if peer is None:
                    if ip_q.empty():  # all candidates tried: refill after a pause
                        time.sleep(30)
                        cands = p2pblocks.candidates()
                        random.Random().shuffle(cands)
                        for ip in cands:
                            ip_q.put(ip)
                    ip = ip_q.get_nowait()
                    peer = p2pblocks.Peer(ip, timeout=10)
                    peer.s.settimeout(15)
                want = {hs: h for h, hs in batch}
                inv = p2pblocks._varint(len(batch)) + b"".join(struct.pack("<I", 2) + bytes.fromhex(hs)[::-1] for _, hs in batch)
                peer.s.sendall(p2pblocks._frame("getdata", inv))
                deadline = time.time() + 120
                while want and time.time() < deadline:
                    cmd, p = peer.recv()
                    if cmd == "notfound":
                        raise LookupError("notfound")
                    if cmd != "block":
                        continue
                    hs = block_hash(p)
                    if hs in want:
                        h = want.pop(hs)
                        tmp = os.path.join(BLOCKS, f".{h}.tmp")
                        with open(tmp, "wb") as f:
                            f.write(p)
                        os.replace(tmp, os.path.join(BLOCKS, f"{h}.blk"))
                        with lock:
                            done[0] += 1
                            if done[0] % 50 == 0:
                                log(f"  blocks {done[0]}/{total}")
                for hs, h in want.items():
                    todo.put((h, hs))
                if want:
                    raise TimeoutError("incomplete")
                fails = 0
            except queue.Empty:
                for it in batch:
                    todo.put(it)
                continue
            except Exception as e:  # noqa: BLE001 - transport errors: drop peer, retry elsewhere
                for h, hs in batch:
                    if not os.path.exists(os.path.join(BLOCKS, f"{h}.blk")):
                        todo.put((h, hs))
                if peer is not None:
                    peer.close()
                peer = None
                fails += 1
                time.sleep(min(30, 2 ** fails))

    ts = [threading.Thread(target=worker, daemon=True) for _ in range(npeers)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    missing = [h for h, _ in items if not os.path.exists(os.path.join(BLOCKS, f"{h}.blk"))]
    if missing:
        raise RuntimeError(f"{len(missing)} blocks not downloaded")


def hashes(heights):
    out = {}
    for c in range(0, len(heights), 200):
        r = subprocess.run([BIN, "hashes", *map(str, heights[c:c + 200])], check=True, capture_output=True, text=True)
        for line in r.stdout.split("\n"):
            if line.startswith("h "):
                _, h, hs = line.split()
                out[int(h)] = hs
    return out


def count(cap, heights):
    tot = {}
    for c in range(0, len(heights), 500):
        files = [os.path.join(BLOCKS, f"{h}.blk") for h in heights[c:c + 500]]
        r = subprocess.run([BIN, "count", str(cap), *files], check=True, capture_output=True, text=True)
        for line in r.stdout.split("\n"):
            if line:
                h, ntx, nin, st, si = map(int, line.split())
                tot[h] = (ntx, nin, st, si)
    return tot


def main():
    era, target = sys.argv[1], int(sys.argv[2])
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 300
    lo, hi = ERAS[era]
    # NU6.0 was sampled under the name "nu6" (files renamed to nu6_0_<k> afterwards).
    rng = random.Random(f"{SEED}-{ {'nu6_0': 'nu6'}.get(era, era)}")
    order = rng.sample(range(lo, hi + 1), min(hi - lo + 1, 200_000))
    taken, got, pos, batch = [], 0, 0, 40
    counts = {}
    while got < target and pos < len(order):
        hs = order[pos:pos + batch]
        pos += batch
        hmap = hashes(hs)
        fetch_blocks([(h, hmap[h]) for h in hs])
        c = count(cap, hs)
        counts.update(c)
        new = sum(c[h][1] for h in hs)
        got += new
        taken += hs
        per = max(got / len(taken), 0.5)
        batch = int(min(400, max(20, (target - got) / per * 1.1)))
        log(f"{era}: {len(taken)} blocks, {got}/{target} inputs (+{new}); next batch {batch}")
    os.makedirs(os.path.join(DATA, "real"), exist_ok=True)
    lst = os.path.join(DATA, "real", f"{era}.blocks")
    with open(lst, "w") as f:
        for h in sorted(taken):
            ntx, nin, st, si = counts[h]
            f.write(f"{h} {os.path.join(BLOCKS, f'{h}.blk')} txs {ntx} inputs {nin} capskip_txs {st} capskip_inputs {si}\n")
    log(f"{era}: building from {len(taken)} blocks")
    subprocess.run([BIN, "build", era, os.path.join(DATA, "real"), os.path.join(DATA, "prevtx"), str(cap), lst], check=True)


if __name__ == "__main__":
    main()
