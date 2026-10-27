#!/usr/bin/env python3
"""ZIP 221 check of a snapshot's tree roots at H against block H+1's hashBlockCommitments, in Bend
(consensus/gaps/history: bin/history; node data V3 for NU6.3 carries the Sapling, Orchard and
Ironwood roots after each block).

Block H+1's header commits (hashBlockCommitments = BLAKE2b("ZcashBlockCommit", historyRoot ||
authDataRoot || 0^32)) to the history tree of the current epoch's blocks ..H. Its last leaf is
block H: hash, time, nBits, per-pool tx counts (Bend parses them from raw block H) and the
Sapling/Orchard/Ironwood roots after H, which the consumer takes from the snapshot's FRONTIERS
(digest-verified sections). The rest of the tree (blocks ..H-1) is the MMR peaks: an untrusted
hint carried in the snapshot's manifest (`history_hint`, ~3 KB). A MATCH at H+1 therefore means
(BLAKE2b collision resistance) that the snapshot's three roots at H are the chain's, whatever the
hint was; a wrong hint or a wrong root gives MISMATCH, never a pass.

  histcheck.py hint SECTIONS_DIR STATE0 BLOCKS_SPOOL OUT.json   (producer: peaks of blocks ..H-1)
  histcheck.py embed SNAP.zsnap HINT.json OUT.zsnap               (put the hint into the untrusted manifest)
  histcheck.py check SNAP.zsnap BLOCKS_SPOOL                     (what consume.py --history-blocks runs)

`hint` chains bin/history from STATE0 (a history state file of the NU6.3 tree up to some height
L, e.g. consensus/gaps/history/work/tip/st_3529999.st) over blocks L+1..H-1 of BLOCKS_SPOOL, with
side roots from the snapshot's root histories: every MATCH in that run also checks the
snapshot's Sapling/Orchard/Ironwood root histories for those blocks against the chain.
"""
import json, os, re, struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402
from snap import SnapError, log  # noqa: E402
import headers  # noqa: E402  (fullnode/headers.py: Bend/Equihash-verified headers)

REPO = HERE.parents[1]
HISTORY_BIN = Path(os.environ.get("ZEBEND_HISTORY_BIN", REPO / "consensus/gaps/history/bin/history"))
HDR = 1487
NU63 = 3428143          # current epoch's activation (tree V3: Sapling, Orchard, Ironwood roots)
NU7 = 3543405           # next activation: the tree restarts there
SIDE = ["sapling", "orchard", "ironwood"]
WINDOW = 400


def spool_blocks(spool, lo, hi):
    """{height: raw} for lo..hi from a download.py spool directory (chunks of u32 h | u32 len | raw)."""
    out = {}
    for p in sorted(Path(spool).glob("*.blk"), key=lambda p: int(p.stem)):
        d = p.read_bytes()
        i = 0
        while i < len(d):
            h, n = struct.unpack_from("<II", d, i)
            if lo <= h <= hi:
                out[h] = d[i + 8:i + 8 + n]
            i += 8 + n
    return out


def run_history(state_in, heights, raw, side, work, tag):
    """bin/history over `heights` (one window). side[h] = (sap, orch, iw) bytes (zeros = unchanged).
    Returns ({h: verdict line}, state_out bytes)."""
    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    wp, sp, so, si = (work / f"hist_{tag}.{x}" for x in ("win", "side", "out", "in"))
    with open(wp, "wb") as f:
        for h in heights:
            exp = headers.header(h)
            if raw[h][:HDR] != exp:
                raise SnapError(f"block {h}: raw header != verified header")
            f.write(struct.pack("<I", h) + exp + struct.pack("<I", len(raw[h])) + raw[h])
    sp.write_bytes(b"".join(struct.pack("<I", h) + b"".join(side[h]) for h in heights))
    if state_in is None:
        sin = "-"
    else:
        si.write_bytes(state_in)
        sin = str(si)
    out = ""
    for _ in range(3):   # an empty output (rare Bend runtime issue) is rerun, never a pass
        r = subprocess.run([str(HISTORY_BIN), sin, str(wp), str(sp), str(so), "main"], capture_output=True, text=True)
        out = r.stdout
        if out.strip():
            break
    lines = {int(h): rest for h, rest in re.findall(r"^hist (\d+) (.*)$", out, re.M)}
    st = so.read_bytes() if so.exists() else None
    for p in (wp, sp, so, si):
        p.unlink(missing_ok=True)
    return lines, st


def roots_maps(d, man, lo):
    secs = snap.sec_by_name(man)
    return {p: {h: r[4:36] for r in snap.records(d, secs[f"roots.{p}"])
                for h in (struct.unpack_from(">I", r, 0)[0],) if h >= lo} for p in SIDE}


def make_hint(d, state0_file, spool, out, work):
    """Producer: history peaks of blocks ..H-1 (the hint), checking every block L+1..H-1 on the way."""
    man = json.loads((Path(d) / "manifest.json").read_text())
    H = man["height"]
    if not NU63 < H < NU7:
        raise SnapError(f"H={H} is not inside the NU6.3 epoch: hint not built")
    st = Path(state0_file).read_bytes()
    if st[:4] != b"ZHT1":
        raise SnapError("not a history state file")
    L = struct.unpack_from("<I", st, 8)[0]
    rm = roots_maps(d, man, L + 1)
    raw = spool_blocks(spool, L + 1, H + 1)
    miss = [h for h in range(L + 1, H + 2) if h not in raw]
    if miss:
        raise SnapError(f"blocks missing from {spool}: {miss[:5]} ({len(miss)})")
    side = {h: tuple(rm[p].get(h, bytes(32)) for p in SIDE) for h in range(L + 1, H)}
    t = time.time()
    n_match, a = 0, L + 1
    while a < H:
        b = min(a + WINDOW - 1, H - 1)
        hs = list(range(a, b + 1))
        lines, st = run_history(st, hs, raw, side, work, f"hint_{a}")
        bad = [(h, lines.get(h)) for h in hs if not (lines.get(h) or "").startswith("MATCH")]
        if bad:
            raise SnapError(f"history check fails at {bad[0][0]}: {bad[0][1]!r}")
        n_match += len(hs)
        a = b + 1
    if struct.unpack_from("<I", st, 8)[0] != H - 1:
        raise SnapError("history state does not end at H-1")
    hint = {"height": H - 1, "state": st.hex(),
            "origin": f"bin/history chained from a state at {L} over blocks {L + 1}..{H - 1}: {n_match}/{n_match} MATCH"}
    res = check(d, man, hint, raw, work)
    hint["producer_check"] = res
    Path(out).write_text(json.dumps(hint, indent=1))
    log(f"hint: {hint['origin']} ({time.time() - t:.0f} s); check at H+1: {res['result']}")
    return hint


def check(d, man, hint, raw, work):
    """Consumer: leaf H from raw block H + the snapshot's frontier roots at H, peaks from the hint;
    Bend must MATCH block H+1's hashBlockCommitments."""
    H = man["height"]
    t = time.time()
    if not NU63 < H < NU7 - 1:
        return {"result": "NOT APPLICABLE", "why": f"H={H} not inside the NU6.3 epoch"}
    if not hint or hint.get("height") != H - 1:
        return {"result": "NOT CHECKED", "why": "no history hint for H-1 in the snapshot"}
    for h in (H, H + 1):
        if h not in raw:
            return {"result": "NOT CHECKED", "why": f"raw block {h} not available"}
    fronts = dict(snap.dec_frontier(r) for r in snap.records(d, snap.sec_by_name(man)["frontier"]))
    if any(fronts[p] is None for p in SIDE):
        return {"result": "NOT CHECKED", "why": "frontier unknown"}
    side = {H: tuple(bytes.fromhex(fronts[p]["root"]) for p in SIDE), H + 1: (bytes(32),) * 3}
    lines, _ = run_history(bytes.fromhex(hint["state"]), [H, H + 1], raw, side, work, "check")
    v = lines.get(H + 1, "")
    res = {"result": "MATCH" if v.startswith("MATCH") else "MISMATCH",
           "line": f"hist {H + 1} {v}"[:220], "line_H": f"hist {H} {lines.get(H, '')}"[:220],
           "roots_at_H": {p: fronts[p]["root"] for p in SIDE}, "secs": round(time.time() - t, 2)}
    return res


def embed(src, hint_file, out):
    """Rewrite the container header with manifest["history_hint"] (the manifest is untrusted and
    not part of the digest; the zstd stream is copied unchanged)."""
    import shutil
    man, off = snap.read_header(src)
    hint = json.loads(Path(hint_file).read_text())
    man["history_hint"] = {k: hint[k] for k in ("height", "state", "origin")}
    hdr = json.dumps(man).encode()
    with open(src, "rb") as f, open(out, "wb") as g:
        g.write(snap.MAGIC + struct.pack("<I", len(hdr)) + hdr)
        f.seek(off)
        shutil.copyfileobj(f, g, 16 << 20)


def main():
    a = sys.argv[1:]
    work = HERE / "work" / f"hist_{os.getpid()}"
    if a and a[0] == "hint":
        make_hint(a[1], a[2], a[3], a[4], work)
    elif a and a[0] == "embed":
        embed(a[1], a[2], a[3])
    elif a and a[0] == "check":
        man, _ = snap.read_header(a[1])
        d = work / "sec"
        man = snap.unpack(a[1], d)
        raw = spool_blocks(a[2], man["height"], man["height"] + 1)
        print(json.dumps(check(d, man, man.get("history_hint"), raw, work)))
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
