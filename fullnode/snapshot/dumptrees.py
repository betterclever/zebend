#!/usr/bin/env python3
"""Write a snapshot's note commitment trees at H as plain files (for reuse, e.g. trees_init.py).

  dumptrees.py SECTIONS_DIR OUT_DIR

SECTIONS_DIR: an export directory (produce.py --keep: work/export_<H>/, holding manifest.json),
or a .zsnap file (unpacked first). Writes, per pool (sprout, sapling, orchard, ironwood):
  <pool>.frontier   32 (Sprout 29) lines, "-" or the node hex: the frontier after block H
                    (the levels format of follow/frontier.bend, sapfront, sinfront, *_frontier)
  <pool>_history.txt  "height root" per block that appended notes (the anchor set), ascending
and trees.json: {pool: {size, root, roots, ...}, height, hash, digest, provenance}.
Root bytes are as the Bend tree programs print them (= anchors in transactions)."""
import json, struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    if src.is_file():
        d = out / "_sec"
        man = snap.unpack(src, d)
    else:
        d, man = src, json.loads((src / "manifest.json").read_text())
    out.mkdir(parents=True, exist_ok=True)
    secs = snap.sec_by_name(man)
    fronts = dict(snap.dec_frontier(r) for r in snap.records(d, secs["frontier"]))
    info = {"height": man["height"], "hash": man["hash"], "digest": man.get("digest"),
            "provenance": man.get("provenance"), "sources": man.get("sources")}
    for p in snap.POOLS:
        fr = fronts[p]
        n = 0
        with open(out / f"{p}_history.txt", "w") as f:
            for r in snap.records(d, secs[f"roots.{p}"]):
                f.write(f"{struct.unpack_from('>I', r, 0)[0]} {r[4:36].hex()}\n")
                n += 1
        if fr is not None:
            (out / f"{p}.frontier").write_text(snap.levels_text(fr["levels"]))
        info[p] = {"size": fr and fr["size"], "root": fr and fr["root"], "roots": n}
    (out / "trees.json").write_text(json.dumps(info, indent=1))
    if src.is_file():
        import shutil
        shutil.rmtree(out / "_sec")
    print(json.dumps(info))


if __name__ == "__main__":
    main()
