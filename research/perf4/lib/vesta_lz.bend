# Vesta add / mixed add / double (RCB 2015, a = 0, b3 = 15) with lazy reduction: where a sum
# feeds a multiplication whose other operand is fully reduced, the sum is fq64.add_nr (no
# final conditional subtraction). Bound (fq64.add_nr): a, b < m gives a + b < 2m; with the
# other operand < m the Montgomery product is < 2m before mul's own conditional subtraction,
# so every mul output is still in [0, m). Only ONE operand of a mul is ever lazy, and lazy
# values never reach add/sub/mul15/eq/encode. Same results as crypto/field3/lib64/vesta.bend.
import Base
import ../../../crypto/field3/fq64.bend as B
import ../../../crypto/field3/lib64/vesta.bend as V

# RCB Algorithm 7 (complete projective addition)
def add(p: V.Pt, q: V.Pt) -> V.Pt:
  V.Pt{+x1, +y1, +z1} = p
  V.Pt{+x2, +y2, +z2} = q
  +t0 = B.mul(x1, x2)
  +t1 = B.mul(y1, y2)
  +t2 = B.mul(z1, z2)
  t3a = B.mul(B.add_nr(x1, y1), B.add(x2, y2))
  +t3 = B.sub(t3a, B.add(t0, t1))
  t4a = B.mul(B.add_nr(y1, z1), B.add(y2, z2))
  +t4 = B.sub(t4a, B.add(t1, t2))
  x3a = B.mul(B.add_nr(x1, z1), B.add(x2, z2))
  y3a = B.sub(x3a, B.add(t0, t2))
  +t0b = B.add(B.add(t0, t0), t0)
  +t2b = V.mul15(t2)
  +z3a = B.add(t1, t2b)
  +t1b = B.sub(t1, t2b)
  +y3b = V.mul15(y3a)
  x3 = B.sub(B.mul(t3, t1b), B.mul(t4, y3b))
  y3 = B.add(B.mul(t1b, z3a), B.mul(y3b, t0b))
  z3 = B.add(B.mul(z3a, t4), B.mul(t0b, t3))
  V.Pt{x3, y3, z3}

# RCB Algorithm 8 (mixed addition, Q affine and not the identity)
def add_aff(p: V.Pt, q: V.Aff) -> V.Pt:
  V.Pt{+x1, +y1, +z1} = p
  V.Aff{+x2, +y2} = q
  +t0a = B.mul(x1, x2)
  +t1a = B.mul(y1, y2)
  t3a = B.mul(B.add_nr(x2, y2), B.add(x1, y1))
  +t3 = B.sub(t3a, B.add(t0a, t1a))
  +t4 = B.add(B.mul(y2, z1), y1)
  y3a = B.add(B.mul(x2, z1), x1)
  +x3a = B.add(t0a, t0a)
  +t0 = B.add(x3a, t0a)
  +t2 = V.mul15(z1)
  +z3a = B.add(t1a, t2)
  +t1 = B.sub(t1a, t2)
  +y3b = V.mul15(y3a)
  x3 = B.sub(B.mul(t3, t1), B.mul(t4, y3b))
  y3 = B.add(B.mul(t1, z3a), B.mul(y3b, t0))
  z3 = B.add(B.mul(z3a, t4), B.mul(t0, t3))
  V.Pt{x3, y3, z3}

# RCB Algorithm 9 (complete doubling)
def double(p: V.Pt) -> V.Pt:
  V.Pt{+x, +y, +z} = p
  +t0 = B.sqr(y)
  +z3a = B.add(t0, t0)
  +z3b = B.add(z3a, z3a)
  +z3c = B.add(z3b, z3b)
  t1 = B.mul(y, z)
  +t2 = V.mul15(B.sqr(z))
  x3a = B.mul(t2, z3c)
  y3a = B.add_nr(t0, t2)
  z3 = B.mul(t1, z3c)
  +t1b = B.add(t2, t2)
  t2b = B.add(t1b, t2)
  +t0b = B.sub(t0, t2b)
  +x3b = B.mul(t0b, B.mul(x, y))
  V.Pt{B.add(x3b, x3b), B.add(x3a, B.mul(t0b, y3a)), z3}
