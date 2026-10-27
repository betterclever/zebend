"""Writes delta_gpu.bend: blockdelta with the point batch as a balanced tree under `check!`
(Metal GPU). Measured slower than one CPU core on this kernel (fast/README.md). Build only
with the always-inline fork and gate it (gpuv/t/aircalls.sh = 0, >= 20 identical runs)."""
s = open("delta.bend").read()
a = """      leaf_check(ps, Nil{})\n"""
b = """      +n = List.length(&2, T.Pt, ps)
      +d = depth_of(dmax, Nat.is_le(4n, n), 0n, n)
      +lanes = Nat.pow(2n, d)
      +tree = root(levels(d, leaves(lanes, Nat.div(n, lanes), Nat.mod(n, lanes), ps)))
      flatten(check!(d, tree), Nil{})\n"""
assert s.count(a) == 1
open("delta_gpu.bend", "w").write(s.replace(a, b))
