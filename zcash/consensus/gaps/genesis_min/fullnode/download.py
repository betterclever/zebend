#!/usr/bin/env python3
"""Download blocks from genesis into a bounded spool, ahead of the state builder (sync.py).

Blocks are never kept: sync.py consumes each spool chunk (CHUNK heights) and deletes it after
its window is committed. The spool is capped (--max-gb); the downloader pauses when it is
full. Restarts resume after the last complete chunk (or the state tip, whichever is higher).

Spool chunk files: spool/<first height>.blk, records of u32 LE height | u32 LE length | block.
A chunk is written as .part and renamed when complete (atomic).

usage: download.py [--from H] [--to H] [--peers N] [--max-gb G]
"""
import argparse, json, os, struct, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers, net

STATE = Path(os.environ.get("ZEBEND_STATE", HERE / "state"))  # instance state dir
HDRDIR = HERE / "state/hdr"  # Bend-verified header-hash index, shared by instances
SPOOL = Path(os.environ.get("ZEBEND_SPOOL", HERE / "spool"))
CHUNK = 1000


def spool_bytes():
    return sum(p.stat().st_size for p in SPOOL.glob("*.blk"))


def state_tip():
    import sqlite3
    try:
        db = sqlite3.connect(f"file:{STATE / 'chain.sqlite'}?mode=ro", uri=True)
        r = db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()
        return json.loads(r[0])["height"] if r else -1
    except sqlite3.Error:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", type=int, default=None)
    ap.add_argument("--to", type=int, default=None, help="stop before this height (default: last verified header + 1)")
    ap.add_argument("--peers", type=int, default=40)
    ap.add_argument("--max-gb", type=float, default=30)
    args = ap.parse_args()
    SPOOL.mkdir(parents=True, exist_ok=True)
    HDRDIR.mkdir(parents=True, exist_ok=True)
    for p in SPOOL.glob("*.part"):
        p.unlink()
    if (HDRDIR / "hashes.bin").exists():  # the Bend-computed, checkpoint-verified index
        idx = headers.Index(HDRDIR / "hashes.bin")
    else:
        headers.routing_index(HDRDIR / "routing.bin")
        idx = headers.Index(HDRDIR / "routing.bin")
    end = args.to or idx.n
    done = sorted(int(p.stem) for p in SPOOL.glob("*.blk"))
    start = args.start if args.start is not None else max([state_tip() + 1] + [d + CHUNK for d in done])
    log = lambda *a: print(time.strftime("%H:%M:%S"), *a, flush=True)
    log(f"download: heights {start}..{end - 1}, {args.peers} peers, spool cap {args.max_gb} GB")
    f = net.Fetcher(idx.display, start, end, STATE / "peers.txt", log=log, peers=args.peers,
                    max_buffer=512 << 20)
    h, t0, nbytes, last = start, time.time(), 0, time.time()
    hist = [(t0, start, 0)]
    w, cur = None, None
    while h < end:
        while spool_bytes() > args.max_gb * 1e9:
            time.sleep(5)
        for height, raw in f.take(2000, wait=True):
            c = max(height - height % CHUNK, start)
            if cur != c:
                if w:
                    w.close()
                    os.replace(SPOOL / f"{cur}.part", SPOOL / f"{cur}.blk")
                cur, w = c, open(SPOOL / f"{c}.part", "wb")
            w.write(struct.pack("<II", height, len(raw)) + raw)
            nbytes += len(raw)
            h = height + 1
            if h % CHUNK == 0 or h == end:
                w.close()
                os.replace(SPOOL / f"{cur}.part", SPOOL / f"{cur}.blk")
                w, cur = None, None
        if time.time() - last > 60:
            el = time.time() - t0
            hist.append((time.time(), h, nbytes))
            t5, h5, b5 = next((x for x in hist if x[0] >= time.time() - 300), hist[0])
            d5 = max(1e-9, time.time() - t5)
            log(f"height {h - 1}  run avg {(h - start) / el:6.1f} blocks/s {nbytes / el / 1e6:5.2f} MB/s  "
                f"last 5 min {(h - h5) / d5:6.1f} blocks/s {(nbytes - b5) / d5 / 1e6:5.2f} MB/s  "
                f"peers {len(f.peers)} (+{len(f.connecting)} connecting)  total {nbytes / 1e9:.2f} GB  "
                f"spool {spool_bytes() / 1e9:.2f} GB  requeued {f.stats['requeued']}")
            log(f"  drops {dict(f.drops)}  rejects {dict(f.rejects)}  book {len(set(f.known))}")
            log(f"  peers: {' | '.join(f.peer_table(10))}")
            last = time.time()
    if w:
        w.close()
        os.replace(SPOOL / f"{cur}.part", SPOOL / f"{cur}.blk")
    log(f"download done at {h}")
    f.close()


if __name__ == "__main__":
    main()
