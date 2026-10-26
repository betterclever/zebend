#!/usr/bin/env python3
"""Drive the full-tree run and compare Bend's roots with the chain's.

  python3 check_tree.py chunks [GPU] [FROM_PART]   run tree_main over every complete chunk
                                    (one heavy.sh job per part file of 256 chunks), log to
                                    ../data/tree_logs/chunks_NNN.log
  python3 check_tree.py compare     Bend chunk roots vs the chain's level-16 subtree roots
                                    (GetSubtreeRoots, ../data/sapling_subtrees.txt); writes the
                                    Bend roots to ../data/bend_chunk_roots.bin
  python3 check_tree.py roots [GPU] full depth-32 roots at every height of
                                    ../data/sapling_trees.txt (GetTreeState), from the Bend chunk
                                    roots plus the partial chunk, compared with the chain
"""
import pathlib, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
D = here.parent / "data"
L = D / "leaves32"
LOG = D / "tree_logs"
LOG.mkdir(exist_ok=True)
HEAVY = str(here.parent.parent / "heavy.sh")


def nleaves():
    return sum((p.stat().st_size // 32) for p in sorted(L.glob("part_*.bin")))


def chunks(gpu="0", from_part=0):
    n = nleaves()
    full = n // 65536
    for p in range(from_part, (full + 255) // 256):
        first = 256 * p
        cnt = min(256, full - first)
        log = LOG / f"chunks_{p:03d}.log"
        cmd = [HEAVY, str(here / "tree_main"), "c", str(L / f"part_{p:03d}.bin"), str(first), str(first), str(cnt), gpu]
        print(" ".join(cmd), flush=True)
        with open(log, "w") as f:
            subprocess.run(cmd, stdout=f, check=False)
        print(open(log).read().strip().split("\n")[-1], flush=True)


def bend_roots():
    roots = {}
    for log in sorted(LOG.glob("chunks_*.log")):
        for l in open(log):
            p = l.split()
            if p and p[0] == "chunk":
                roots[int(p[1])] = (p[3], int(p[5]))
    return roots


def compare():
    roots = bend_roots()
    chain = {}
    for l in open(D / "sapling_subtrees.txt"):
        i, h, r = l.split()
        chain[int(i)] = r
    full = nleaves() // 65536
    ok = sum(1 for i in range(full) if roots.get(i, (None,))[0] == chain.get(i))
    missing = [i for i in range(full) if i not in roots]
    bad = [i for i in range(full) if i in roots and roots[i][0] != chain.get(i)]
    ms = sum(roots[i][1] for i in roots)
    print(f"complete chunks {full}; chain subtree roots {len(chain)}; Bend roots {len(roots)}")
    print(f"MATCH {ok}/{full}; mismatched {len(bad)} {bad[:10]}; missing {len(missing)} {missing[:10]}")
    print(f"Bend chunk-root time (sum of per-chunk ms) {ms / 1000:.1f} s")
    with open(D / "bend_chunk_roots.bin", "wb") as f:
        for i in range(full):
            f.write(bytes.fromhex(roots[i][0]) if i in roots else bytes(32))


def roots(gpu="0"):
    rows = [l.split() for l in open(D / "sapling_trees.txt") if l.strip() and not l.startswith("#")]
    ok = 0
    for h, size, want in rows:
        size = int(size)
        k = size // 65536
        part = L / f"part_{k // 256:03d}.bin"
        cmd = [HEAVY, str(here / "tree_main"), "r", str(part) if size % 65536 else "-", str(D / "bend_chunk_roots.bin"), str(size), gpu]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip().split("\n")[-1]
        got = out.split()[5] if out.startswith("size") else "?"
        m = got == want
        ok += m
        print(f"height {h} size {size}: bend {got} chain {want} {'MATCH' if m else 'MISMATCH'} ({out.split()[-1] if out else ''} ms)", flush=True)
    print(f"full roots MATCH {ok}/{len(rows)}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "chunks":
        chunks(a[1] if len(a) > 1 else "0", int(a[2]) if len(a) > 2 else 0)
    elif a[0] == "compare":
        compare()
    elif a[0] == "roots":
        roots(a[1] if len(a) > 1 else "0")
