import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T

# A copy of the curve formulas of crypto/field3/lib64/vesta.bend (RCB 2015 Algorithms 7, 8
# and 9 with a = 0) and of research/perf4/lib/msm_ba.bend's add_aff, over the Z/p model
# (p = 1 + bp; B.add / B.sub / B.mul / B.sqr are T.fadd / T.fsub / T.fmul / T.fmul(x, x)).
# Statement by statement and argument by argument the same as the code, except:
#
#   * mul15 (15 * a, computed as 16a - a) is kept as a copy (m15), and the formulas are
#     written once more with 15 replaced by an arbitrary b3 (addb, add_affb, doubleb); the
#     laws are proven for y^2 = x^3 + b with b3 = 3b, for every b, and b3_ok shows that the
#     copy with m15 is the b = 5 instance (Vesta's and Pallas' curve). Pallas'
#     crypto/field3/lib64/pallas.bend has the same formulas over the other field.
#   * research/perf4/lib/vesta_lz.bend's add / add_aff / double are these formulas with
#     fq64.add_nr (an addition without the final conditional subtraction) where a sum feeds a
#     multiplication; in Z/p add_nr is add.
#
# To let b3_ok rewrite the two mul15 calls of a formula, each formula is split into the
# part before mul15 (the values passed to it) and the part after (addh etc., taking the
# mul15 results as arguments).

type Pt is Data:
  Pt{x: Nat, y: Nat, z: Nat}

type Aff is Data:
  Aff{x: Nat, y: Nat}

def px(p: Pt) -> Nat:
  Pt{x, _, _} = p
  x

def py(p: Pt) -> Nat:
  Pt{_, y, _} = p
  y

def pz(p: Pt) -> Nat:
  Pt{_, _, z} = p
  z

# vesta.mul15
def m15(+bp: Nat, +a: Nat) -> Nat:
  +a2 = T.fadd(bp, a, a)
  +a4 = T.fadd(bp, a2, a2)
  +a8 = T.fadd(bp, a4, a4)
  T.fsub(bp, T.fadd(bp, a8, a8), a)

# --- vesta.add (RCB Algorithm 7) ----------------------------------------------------------

# the value passed to the first mul15: t2 = z1 z2
def add_t2(+bp: Nat, p: Pt, q: Pt) -> Nat:
  Pt{_, _, +z1} = p
  Pt{_, _, +z2} = q
  T.fmul(bp, z1, z2)

# the value passed to the second mul15: y3a
def add_y3a(+bp: Nat, p: Pt, q: Pt) -> Nat:
  Pt{+x1, _, +z1} = p
  Pt{+x2, _, +z2} = q
  +t0 = T.fmul(bp, x1, x2)
  +t2 = T.fmul(bp, z1, z2)
  x3a = T.fmul(bp, T.fadd(bp, x1, z1), T.fadd(bp, x2, z2))
  T.fsub(bp, x3a, T.fadd(bp, t0, t2))

# the rest of add, given t2b = mul15(t2) and y3b = mul15(y3a)
def addh(+bp: Nat, p: Pt, q: Pt, +t2b: Nat, +y3b: Nat) -> Pt:
  Pt{+x1, +y1, +z1} = p
  Pt{+x2, +y2, +z2} = q
  +t0 = T.fmul(bp, x1, x2)
  +t1 = T.fmul(bp, y1, y2)
  +t2 = T.fmul(bp, z1, z2)
  t3a = T.fmul(bp, T.fadd(bp, x1, y1), T.fadd(bp, x2, y2))
  +t3 = T.fsub(bp, t3a, T.fadd(bp, t0, t1))
  t4a = T.fmul(bp, T.fadd(bp, y1, z1), T.fadd(bp, y2, z2))
  +t4 = T.fsub(bp, t4a, T.fadd(bp, t1, t2))
  +t0b = T.fadd(bp, T.fadd(bp, t0, t0), t0)
  +z3a = T.fadd(bp, t1, t2b)
  +t1b = T.fsub(bp, t1, t2b)
  x3 = T.fsub(bp, T.fmul(bp, t3, t1b), T.fmul(bp, t4, y3b))
  y3 = T.fadd(bp, T.fmul(bp, t1b, z3a), T.fmul(bp, y3b, t0b))
  z3 = T.fadd(bp, T.fmul(bp, z3a, t4), T.fmul(bp, t0b, t3))
  Pt{x3, y3, z3}

# vesta.add
def add(+bp: Nat, +p: Pt, +q: Pt) -> Pt:
  addh(bp, p, q, m15(bp, add_t2(bp, p, q)), m15(bp, add_y3a(bp, p, q)))

# vesta.add with 15 replaced by b3
def addb(+bp: Nat, +b3: Nat, +p: Pt, +q: Pt) -> Pt:
  addh(bp, p, q, T.fmul(bp, b3, add_t2(bp, p, q)), T.fmul(bp, b3, add_y3a(bp, p, q)))

# --- vesta.add_aff (RCB Algorithm 8) ------------------------------------------------------

def aff_t2(p: Pt) -> Nat:
  Pt{_, _, z1} = p
  z1

def aff_y3a(+bp: Nat, p: Pt, q: Aff) -> Nat:
  Pt{+x1, _, +z1} = p
  Aff{+x2, _} = q
  T.fadd(bp, T.fmul(bp, x2, z1), x1)

def add_affh(+bp: Nat, p: Pt, q: Aff, +t2: Nat, +y3b: Nat) -> Pt:
  Pt{+x1, +y1, +z1} = p
  Aff{+x2, +y2} = q
  +t0a = T.fmul(bp, x1, x2)
  +t1a = T.fmul(bp, y1, y2)
  t3a = T.fmul(bp, T.fadd(bp, x2, y2), T.fadd(bp, x1, y1))
  +t3 = T.fsub(bp, t3a, T.fadd(bp, t0a, t1a))
  +t4 = T.fadd(bp, T.fmul(bp, y2, z1), y1)
  +x3a = T.fadd(bp, t0a, t0a)
  +t0 = T.fadd(bp, x3a, t0a)
  +z3a = T.fadd(bp, t1a, t2)
  +t1 = T.fsub(bp, t1a, t2)
  x3 = T.fsub(bp, T.fmul(bp, t3, t1), T.fmul(bp, t4, y3b))
  y3 = T.fadd(bp, T.fmul(bp, t1, z3a), T.fmul(bp, y3b, t0))
  z3 = T.fadd(bp, T.fmul(bp, z3a, t4), T.fmul(bp, t0, t3))
  Pt{x3, y3, z3}

# vesta.add_aff
def add_aff(+bp: Nat, +p: Pt, +q: Aff) -> Pt:
  add_affh(bp, p, q, m15(bp, aff_t2(p)), m15(bp, aff_y3a(bp, p, q)))

def add_affb(+bp: Nat, +b3: Nat, +p: Pt, +q: Aff) -> Pt:
  add_affh(bp, p, q, T.fmul(bp, b3, aff_t2(p)), T.fmul(bp, b3, aff_y3a(bp, p, q)))

# --- vesta.double (RCB Algorithm 9) -------------------------------------------------------

def dbl_t2(+bp: Nat, p: Pt) -> Nat:
  Pt{_, _, +z} = p
  T.fmul(bp, z, z)

def doubleh(+bp: Nat, p: Pt, +t2: Nat) -> Pt:
  Pt{+x, +y, +z} = p
  +t0 = T.fmul(bp, y, y)
  +z3a = T.fadd(bp, t0, t0)
  +z3b = T.fadd(bp, z3a, z3a)
  +z3c = T.fadd(bp, z3b, z3b)
  t1 = T.fmul(bp, y, z)
  x3a = T.fmul(bp, t2, z3c)
  y3a = T.fadd(bp, t0, t2)
  z3 = T.fmul(bp, t1, z3c)
  +t1b = T.fadd(bp, t2, t2)
  t2b = T.fadd(bp, t1b, t2)
  +t0b = T.fsub(bp, t0, t2b)
  +x3b = T.fmul(bp, t0b, T.fmul(bp, x, y))
  Pt{T.fadd(bp, x3b, x3b), T.fadd(bp, x3a, T.fmul(bp, t0b, y3a)), z3}

# vesta.double
def double(+bp: Nat, +p: Pt) -> Pt:
  doubleh(bp, p, m15(bp, dbl_t2(bp, p)))

def doubleb(+bp: Nat, +b3: Nat, +p: Pt) -> Pt:
  doubleh(bp, p, T.fmul(bp, b3, dbl_t2(bp, p)))

# --- msm_ba.add_aff: the affine chord with a precomputed inverse ---------------------------

def aadd(+bp: Nat, +x1: Nat, +y1: Nat, +x2: Nat, +y2: Nat, +inv: Nat) -> Aff:
  +lam = T.fmul(bp, T.fsub(bp, y2, y1), inv)
  +x3 = T.fsub(bp, T.fsub(bp, T.fmul(bp, lam, lam), x1), x2)
  Aff{x3, T.fsub(bp, T.fmul(bp, lam, T.fsub(bp, x1, x3)), y1)}

# --- the specification: chord and tangent ---------------------------------------------------

# y^2 == x^3 + b
def OnCurve(+bp: Nat, +b: Nat, +x: Nat, +y: Nat) -> Data:
  {T.fmul(bp, y, y) == T.fadd(bp, T.fmul(bp, x, T.fmul(bp, x, x)), b) : Nat}

# Y^2 Z == X^3 + b Z^3
def OnCurveP(+bp: Nat, +b: Nat, p: Pt) -> Data:
  Pt{+x, +y, +z} = p
  {T.fmul(bp, T.fmul(bp, y, y), z) == T.fadd(bp, T.fmul(bp, x, T.fmul(bp, x, x)), T.fmul(bp, b, T.fmul(bp, z, T.fmul(bp, z, z)))) : Nat}

# the chord through (x1, y1) and (x2, y2), with di = 1 / (x2 - x1)
def chord_l(+bp: Nat, +y1: Nat, +y2: Nat, +di: Nat) -> Nat:
  T.fmul(bp, T.fsub(bp, y2, y1), di)

def chord_x(+bp: Nat, +x1: Nat, +y1: Nat, +x2: Nat, +y2: Nat, +di: Nat) -> Nat:
  +l = chord_l(bp, y1, y2, di)
  T.fsub(bp, T.fsub(bp, T.fmul(bp, l, l), x1), x2)

def chord_y(+bp: Nat, +x1: Nat, +y1: Nat, +x2: Nat, +y2: Nat, +di: Nat) -> Nat:
  T.fsub(bp, T.fmul(bp, chord_l(bp, y1, y2, di), T.fsub(bp, x1, chord_x(bp, x1, y1, x2, y2, di))), y1)

# the tangent at (x, y), with ti = 1 / (2 y): slope 3 x^2 / (2 y)
def tan_l(+bp: Nat, +x: Nat, +ti: Nat) -> Nat:
  +xx = T.fmul(bp, x, x)
  T.fmul(bp, T.fadd(bp, T.fadd(bp, xx, xx), xx), ti)

def tan_x(+bp: Nat, +x: Nat, +ti: Nat) -> Nat:
  +l = tan_l(bp, x, ti)
  T.fsub(bp, T.fsub(bp, T.fmul(bp, l, l), x), x)

def tan_y(+bp: Nat, +x: Nat, +y: Nat, +ti: Nat) -> Nat:
  T.fsub(bp, T.fmul(bp, tan_l(bp, x, ti), T.fsub(bp, x, tan_x(bp, x, ti))), y)

# b3 = 3 b
def b3(+bp: Nat, +b: Nat) -> Nat:
  T.fadd(bp, T.fadd(bp, b, b), b)

# No point of order 2: x^3 + b != 0 for every x. True for Pallas and Vesta (their groups have
# prime order, so no point (x, 0)); not proven here, a hypothesis where a law needs it.
def NoT2(+bp: Nat, +b: Nat) -> Type:
  @t: Nat -> L.Le(t, bp) -> {T.fadd(bp, T.fmul(bp, t, T.fmul(bp, t, t)), b) == 0n : Nat} -> Empty

# (X : Y : Z) has Z invertible (Z zi == 1) and affine coordinates (x, y) = (X zi, Y zi), the
# values vesta.to_aff computes.
def Rep(+bp: Nat, +X: Nat, +Y: Nat, +Z: Nat, +zi: Nat, +x: Nat, +y: Nat) -> Data:
  Sigma<&2, &2, {T.fmul(bp, Z, zi) == 1n : Nat}, _ => Sigma<&2, &2, {T.fmul(bp, X, zi) == x : Nat}, _ => {T.fmul(bp, Y, zi) == y : Nat}>>
