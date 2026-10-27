#!/usr/bin/env python3
"""layer_diff.py RUST BEND: compare `oracle layer` and `layer_main` outputs column by column."""
import sys
r = [l.split() for l in open(sys.argv[1]) if l.strip()]
b = [l.split() for l in open(sys.argv[2]) if l.strip()]
assert len(r) == len(b), (len(r), len(b))
names = ["decode(A)", "decode(R)", "sha512", "k", "S<l"]
bad = [0] * 5
for i, (x, y) in enumerate(zip(r, b)):
    for j in range(5):
        if x[j] != y[j]:
            bad[j] += 1
            if sum(bad) <= 5:
                print(f"record {i} {names[j]}: rust {x[j]} bend {y[j]}")
nd = sum(1 for x in r if x[0] == "-") + sum(1 for x in r if x[1] == "-")
print(f"{len(r)} records ({2 * len(r) - nd} of {2 * len(r)} encodings decode per Rust): " +
      ", ".join(f"{n} {len(r) - k}/{len(r)}" for n, k in zip(names, bad)))
sys.exit(1 if any(bad) else 0)
