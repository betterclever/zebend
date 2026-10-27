#!/usr/bin/env python3
"""Lab benchmark: replay real mainnet blocks through a lab node one block at a time, as they
would arrive at the tip, and time each one from arrival to committed verdict.

  replay.py --lab <lab>/node --variant base|fast --from H0 --n N --blocks DIR --out OUT.jsonl
            [--gap-min S --gap-max S --seed K] [--only H,H,...]

Runs IN the lab node's code (sys.path = <lab>/node; ZEBEND_STATE/SPOOL = the lab's). Steps:
  1. roll the lab state back to H0 (store.rollback_to, the undo data; H0 is moved down to a
     window start so the ZIP 221 state is restored exactly, as sync.py does on a reorg);
  2. base: block h is written to the lab spool as chunk <h>.blk (what live.py/download.py do);
     fast: the lab header index is cut back to H0 and block h is handed to tipfeed exactly as a
     block received from a peer (Bend header checks, index append, in-memory buffer);
  3. sync.main(--to H0+N) validates and commits; prof.py records each window's stages;
  4. the next block arrives a random gap (gap-min..gap-max s) after the previous commit.
One JSON line per block: height, size, t_arrive, t_commit, latency, stages of its window.
"""
import argparse, json, os, random, struct, sys, threading, time
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lab", required=True)
    ap.add_argument("--variant", choices=["base", "fast"], required=True)
    ap.add_argument("--from", dest="h0", type=int, required=True)
    ap.add_argument("--n", type=int, required=True)
    ap.add_argument("--blocks", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--gap-min", type=float, default=0.5)
    ap.add_argument("--gap-max", type=float, default=6.0)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    lab = Path(a.lab).resolve()
    assert lab.name == "node" and lab != Path("/Users/betterclever/projects/zecathon/zebend/node"), "lab only"
    os.environ.update(ZEBEND_STATE=str(lab / "state"), ZEBEND_SPOOL=str(lab / "spool"), BEND_NO_TELEMETRY="1")
    sys.path.insert(0, str(lab))
    sys.path.insert(0, str(lab / "fasttip"))
    sys.path.append(str(Path(__file__).resolve().parents[1]))  # prof.py for the base lab
    import store as S, history as HI
    st = S.Store(lab / "state")
    assert st.tip()["height"] >= a.h0, f"lab state tip {st.tip()['height']} is below {a.h0}: rebuild the lab (mklab.sh)"
    h0 = HI.window_start_below(st, a.h0)
    if st.tip()["height"] != h0:
        t = time.time()
        st.rollback_to(h0)
        print(f"rolled back to {h0} in {time.time() - t:.1f} s", flush=True)
    st.close()
    for p in (lab / "spool").glob("*"):
        p.unlink()
    last = a.h0 + a.n  # the requested end (h0 may have moved down to a window start)
    blocks = {h: (Path(a.blocks) / f"{h}.bin").read_bytes() for h in range(h0 + 1, last + 1)}
    hdr = lab / "state/hdr"
    if a.variant == "fast":  # the pushed blocks' headers are verified again by tipfeed (Bend)
        with open(hdr / "hashes.bin", "r+b") as f:
            f.truncate((h0 + 1) * 32)
        with open(hdr / "extra.bin", "r+b") as f:
            f.truncate((h0 - 3528280 + 1) * 1487)
    import sync, prof
    out = Path(a.out)
    out.unlink(missing_ok=True)
    P = prof.install(sync, None)
    feed = None
    if a.variant == "fast":
        import tipfeed
        feed = tipfeed.TipFeed(prof=P, peers=0, fallback=False, log=lambda *x: print(*x, flush=True))
        sync.BLOCK_SOURCE = feed.buffer
        if os.environ.get("FT_INPROC", "1") == "1":
            import rules, inproc
            rules.HOOK_RUNNER = inproc.run_hook
        feed.start()
    print(f"load average at start {[round(x, 1) for x in os.getloadavg()]}", flush=True)
    rng = random.Random(a.seed)
    arrive = {}
    done = threading.Event()

    def feeder():
        for h in range(h0 + 1, last + 1):
            time.sleep(rng.uniform(a.gap_min, a.gap_max))
            P.add("idle_gap", 0)  # (marker only)
            arrive[h] = time.time()
            if feed is None:
                tmp = lab / "spool" / f"{h}.part"
                tmp.write_bytes(struct.pack("<II", h, len(blocks[h])) + blocks[h])
                os.replace(tmp, lab / "spool" / f"{h}.blk")
            else:
                feed.inject(blocks[h], t_inv=arrive[h])
            while not any(w["last"] is not None and w["last"] >= h for w in P.windows):
                time.sleep(0.002)
        done.set()

    threading.Thread(target=feeder, daemon=True).start()
    sys.argv = ["sync.py", "--to", str(last)]
    try:
        sync.main()
    finally:
        if feed is not None:
            feed.stop()
    rows = []
    load = [round(x, 1) for x in os.getloadavg()]
    for w in P.windows:
        if w["last"] is None:
            continue
        hs = [h for h in arrive if h <= w["last"] and not any(r["height"] == h for r in rows)]
        for h in hs:
            rows.append({"height": h, "size": len(blocks[h]), "t_arrive": arrive[h], "t_commit": w["t_commit"],
                         "latency": round(w["t_commit"] - arrive[h], 4), "window": len(hs), "pick_to_commit": w.get("pick_to_commit"),
                         "load": load, "stages": w["stages"],
                         "procs": w["procs"], **({"feed": w.get("feed")} if w.get("feed") else {})})
    with open(out, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    lat = sorted(r["latency"] for r in rows)
    if lat:
        print(f"{a.variant}: {len(lat)} blocks, latency median {lat[len(lat) // 2]:.3f} s, "
              f"p90 {lat[int(len(lat) * 0.9)]:.3f} s, max {lat[-1]:.3f} s", flush=True)


if __name__ == "__main__":
    main()
