#!/usr/bin/env python3
"""Cross-check the Bend root histories (seeds/<pool>_history.txt, make_history.py) against the
per-block roots in zcash/consensus/gaps/history/data/seed_leaves.lv (lightwalletd, authenticated as a
whole by block 3,522,000's ZIP 221 header commitment), and write seeds/ironwood_history.txt from
the .lv (no Bend Ironwood history before the start; labelled). Record: u32 h | hash 32 | u32 time |
u32 bits | field 32 | Sapling root 32 | Orchard root 32 | Ironwood root 32 | 3 x u32 counts."""
import json, struct
from pathlib import Path
HERE = Path(__file__).resolve().parent
lv = (HERE.parent / "history/data/seed_leaves.lv").read_bytes()
R = 184
per = {"sapling": {}, "orchard": {}, "ironwood": {}}
prev = {}
for i in range(0, len(lv), R):
    h, = struct.unpack_from("<I", lv, i)
    for k, pool in enumerate(("sapling", "orchard", "ironwood")):
        r = lv[i + 76 + 32 * k:i + 108 + 32 * k].hex()
        if prev.get(pool) != r:
            per[pool][h] = r
        prev[pool] = r
res = {}
for pool in ("sapling", "orchard"):
    p = HERE / "seeds" / f"{pool}_history.txt"
    bend = dict((int(h), r) for h, r in (l.split() for l in p.read_text().split("\n") if l)) if p.exists() else {}
    lvp = {h: r for h, r in per[pool].items() if h != 3428143 or True}
    common = [h for h in bend if h in lvp]
    eq = sum(1 for h in common if bend[h] == lvp[h])
    # every block where lightwalletd's root changes must be a Bend root block and vice versa
    res[pool] = {"bend_blocks": len(bend), "lv_change_blocks": len(lvp), "common": len(common), "equal": eq,
                 "bend_only": len(set(bend) - set(lvp)), "lv_only": len(set(lvp) - set(bend))}
with open(HERE / "seeds/ironwood_history.txt", "w") as f:
    for h in sorted(per["ironwood"]):
        f.write(f"{h} {per['ironwood'][h]}\n")
res["ironwood"] = {"lv_change_blocks": len(per["ironwood"]), "source": "seed_leaves.lv (lightwalletd; authenticated by header 3,522,000)"}
print(json.dumps(res, indent=1))
(HERE / "seeds/history_crosscheck.json").write_text(json.dumps(res, indent=1))
