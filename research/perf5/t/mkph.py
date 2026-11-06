#!/usr/bin/env python3
"""mkph.py SRC PH OUT: a phase-limited copy of lib/msm_sb.bend for timing (results are WRONG
for PH < 3): PH 0 = load only, 1 = + count/scatter, 2 = + levels, 3 = everything."""
import sys
s = open(sys.argv[1]).read(); ph = sys.argv[2]
pre = f'''def PH() -> U32:
  {ph}

def lvf(z: Bool) -> Nat:
  match z:
    case True{{}}:
      0n
    case False{{}}:
      32n

'''
s = s.replace("# --- levels ---", pre + "# --- levels ---", 1)
s = s.replace("  win4(levels(32n, LC{mx, cn, tmp, sc}, half, h2),", "  win4(levels(lvf(U32.is_lt(PH(), 2)), LC{mx, cn, tmp, sc}, half, h2),")
s = s.replace("  win5(bred(c, half, h2, cn, tmp), ks, pts, dg, sc)", "  win5(bred(c, U32.min(half, (PH() * 100000 : U32)), h2, cn, tmp), ks, pts, dg, sc)")
s = s.replace("  +nw = BA.windows9(c)\n", "  +nw = U32.min(BA.windows9(c), (PH() * 100 : U32))\n")
assert s.count("PH()") == 4, s.count("PH()")
open(sys.argv[3], "w").write(s)
