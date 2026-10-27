"""Parallel note commitment tree build for the producer (Sapling, Orchard, Ironwood), in Bend.

The one-process build (snap.run_tree) pushes every leaf and prints a root after every block, in
order: at the tip that is ~74M Sapling and ~50M Orchard leaves at ~3-4k Bend hashes/s per
process (measured: 1M Orchard leaves in 6.2 min), i.e. hours. Here the leaves are cut into
segments of whole blocks and every segment runs in its own Bend process:

  start frontier of segment k (leaf offset s):
      bin seed mode (consensus/gaps/trees/{sapling,orchard}_frontier, "seed mode"): the
      frontier of a tree of q*2^16 + r leaves from q level-16 CHUNK ROOTS plus the r leaves of
      the partial chunk (r leaves read from this store's leaf log);
  then the same Bend program as the one-process build (bin/sapfront, bin/sinfront) pushes the
      segment's leaves block by block from that frontier: one root per block + end frontier.

Chunk roots are HINTS: taken from earlier Bend runs where available (sapling/data/
bend_chunk_roots.bin, consensus/orchard/logs/chunks_*.log), computed here otherwise (sapfront/
sinfront over the chunk's 2^16 leaves). They are not trusted: CONTINUITY must hold at every
segment boundary, i.e. segment k's end frontier (pushed from leaves) == segment k+1's start
frontier (built from hints). By induction from segment 0 (empty start), each start frontier is
then the frontier of this store's own leaf log, so every per-block root is exactly what the
one-process build would print. A wrong hint fails continuity; the build then refuses.
"""
import re, struct, subprocess, time
from pathlib import Path

import snap
from snap import SnapError, levels_text, TREE, _bend

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CH = 1 << 16
SEG_LEAVES = 1 << 18          # leaves per segment (cut at the first block that crosses a chunk boundary after this)
SEG_BLOCKS = 20000            # blocks per segment (bounds the Bend output held in memory)
SEED_TOOL = {"sapling": HERE / "work/fast/tools/sapling_frontier",
             "orchard": HERE / "work/fast/tools/orchard_frontier",
             "ironwood": HERE / "work/fast/tools/orchard_frontier"}


def hint_roots(pool):
    """{chunk index: root bytes} from earlier Bend runs (untrusted; checked by continuity)."""
    out = {}
    try:
        if pool == "sapling":
            d = (REPO / "sapling/data/bend_chunk_roots.bin").read_bytes()
            out = {k: d[k * 32:k * 32 + 32] for k in range(len(d) // 32)}
        elif pool == "orchard":
            for p in sorted((REPO / "consensus/orchard/logs").glob("chunks_*.log")):
                for k, r in re.findall(r"^chunk (\d+) subtree root ([0-9a-f]{64}) MATCH$", p.read_text(), re.M):
                    out[int(k)] = bytes.fromhex(r)
    except OSError:
        pass
    return out


def parse_levels(text, depth):
    lv = [l.strip() if l.strip() != "-" else None for l in text.splitlines()][:depth]
    if len(lv) != depth:
        raise SnapError(f"frontier with {len(lv)} levels")
    return lv


def segments(blocks):
    """[(first block idx, end block idx (excl), first leaf, end leaf)]"""
    segs, i0, s, off, nb = [], 0, 0, 0, 0
    for j, (_h, c) in enumerate(blocks):
        end = off + c
        nb += 1
        crossed = end // CH != off // CH
        if nb >= SEG_BLOCKS or (end - s >= SEG_LEAVES and crossed):
            segs.append((i0, j + 1, s, end))
            i0, s, nb = j + 1, end, 0
        off = end
    if i0 < len(blocks):
        segs.append((i0, len(blocks), s, off))
    return segs


def build(pool, lf, blocks, work, ex, log=snap.log):
    """lf: snap.LeafFile of the pool's leaf log; blocks: [(height, count)] (all from genesis).
    Returns (per-block roots [hex], final levels, empty root, stats)."""
    tool, depth = TREE[pool]
    work = Path(work) / f"pt_{pool}"
    work.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    segs = segments(blocks)
    N = segs[-1][3] if segs else 0
    need = max((s // CH for _, _, s, _ in segs), default=0)
    hints = hint_roots(pool)
    have = {k: hints[k] for k in range(need) if k in hints}
    missing = [k for k in range(need) if k not in have]

    def chunk_root(k):
        d = work / f"c{k}"
        fin, lfp, cf, fo = (Path(f"{d}.{x}") for x in ("in", "leaves", "counts", "out"))
        fin.write_text(levels_text([None] * depth))
        lfp.write_bytes(lf[k * CH * 32:(k + 1) * CH * 32])
        cf.write_bytes(struct.pack("<I", CH))
        _bend([tool, fin, lfp, cf, fo])
        lv = parse_levels(fo.read_text(), depth)
        for x in (fin, lfp, cf, fo):
            x.unlink(missing_ok=True)
        if [i for i, v in enumerate(lv) if v] != [16]:
            raise SnapError(f"{pool} chunk {k}: frontier after 2^16 leaves is not one level-16 node")
        return k, bytes.fromhex(lv[16])

    if missing:
        log(f"  {pool}: {len(have)} chunk-root hints, computing {len(missing)} chunk roots in Bend")
        for k, r in ex.map(chunk_root, missing):
            have[k] = r
    croots = b"".join(have[k] for k in range(need))
    t1 = time.time()

    def seg(k):
        i0, i1, s, e = segs[k]
        d = work / f"s{k}"
        if s == 0:
            start = [None] * depth
        else:
            q = s // CH
            rp, pp, so = (Path(f"{d}.{x}") for x in ("croots", "partial", "start"))
            rp.write_bytes(croots[:q * 32])
            pp.write_bytes(lf[q * CH * 32:s * 32])
            out = _bend([SEED_TOOL[pool], rp, pp, so])
            if "seed chunks" not in out:
                raise SnapError(f"{pool} segment {k}: seed mode failed: {out[-200:]}")
            start = parse_levels(so.read_text(), depth)
            for x in (rp, pp, so):
                x.unlink(missing_ok=True)
        fin, lfp, cf, fo = (Path(f"{d}.{x}") for x in ("in", "leaves", "counts", "out"))
        fin.write_text(levels_text(start))
        lfp.write_bytes(lf[s * 32:e * 32])
        cf.write_bytes(b"".join(struct.pack("<I", c) for _, c in blocks[i0:i1]))
        out = _bend([tool, fin, lfp, cf, fo])
        got = [l.split() for l in out.splitlines() if l.startswith("root ")]
        if len(got) != i1 - i0:
            raise SnapError(f"{pool} segment {k}: {len(got)} roots for {i1 - i0} blocks")
        end = parse_levels(fo.read_text(), depth)
        empty = snap._kv(out).get("empty_root")
        for x in (fin, lfp, cf, fo):
            x.unlink(missing_ok=True)
        return start, end, [g[3] for g in got], empty

    res = list(ex.map(seg, range(len(segs))))
    bad = [k for k in range(len(segs) - 1) if res[k][1] != res[k + 1][0]]
    if bad:
        raise SnapError(f"{pool}: continuity FAILS at {len(bad)} segment boundaries (first after segment {bad[0]}, "
                        f"leaf {segs[bad[0]][3]}): a chunk-root hint is wrong")
    roots = [r for x in res for r in x[2]]
    stats = {"leaves": N, "blocks": len(blocks), "segments": len(segs),
             "continuity": f"{len(segs) - 1}/{len(segs) - 1} boundaries equal",
             "chunk_roots": {"hints_used": len(have) - len(missing), "computed": len(missing)},
             "secs": {"chunk_roots": round(t1 - t0, 1), "segments": round(time.time() - t1, 1)}}
    log(f"  {pool}: {stats}")
    return roots, res[-1][1], res[-1][3], stats
