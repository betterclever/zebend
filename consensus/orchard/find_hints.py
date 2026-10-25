#!/usr/bin/env python3
"""Hints for the Orchard anchor check: for each real Orchard anchor in node/tx, the latest
earlier block whose chain Orchard root (GetTreeState) equals it, and that block's tree size.
The hint is untrusted: orchard_main recomputes the root at that size from the leaves and checks
the size is exactly the leaves through that block."""
import re, subprocess, pathlib
HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent
ORA = str(HERE.parent / "oracle/target/release/consensus-oracle")
EMPTY = "ae2935f1dfd8a24aed7c70df7de3a668eb7a49b1319880dde2bbd9031ae5d82f"
out = []
for i in range(29):
    t = (ROOT / f"node/tx/mainnet/tx_{i}.txt").read_text()
    m = re.search(r"^orchard\.anchor (\w+)", t, re.M)
    if not m:
        continue
    b, a = int(re.search(r"^height (\d+)", t, re.M).group(1)), m.group(1)
    if a == EMPTY:
        out.append(f"tx_{i} {b} {a} 1687103 0")
        continue
    hit = None
    for lo in range(b - 1, b - 401, -50):
        rows = subprocess.run([ORA, "trees", "orchard"] + [str(h) for h in range(lo, lo - 50, -1)],
                              capture_output=True, text=True, check=True).stdout.split("\n")
        hit = next((r.split() for r in rows if r.endswith(a)), None)
        if hit:
            break
    assert hit, f"tx_{i}: anchor not found in 400 blocks"
    out.append(f"tx_{i} {b} {a} {hit[0]} {hit[1]}")
    print(out[-1], flush=True)
(HERE / "anchor_hints.txt").write_text("\n".join(out) + "\n")
