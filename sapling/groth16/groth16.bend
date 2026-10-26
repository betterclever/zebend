# Groth16 verification over BLS12-381, as groth16 0.2 / bellman (used by sapling-crypto):
#   Proof::read: A, C compressed G1, B compressed G2; each must decode (flags, canonical,
#   on curve, prime-order subgroup) and must not be the identity.
#   verify_proof: acc = IC0 + sum input_i IC_{i+1};
#   accept iff final_exp(ML(A, B) ML(acc, -gamma) ML(C, -delta)) == e(alpha, beta).
import Base
import ./fq.bend as F
import ./fq2.bend as E
import ./fq12.bend as T
import ./g1.bend as G1
import ./g2.bend as G2
import ./pairing.bend as PR
import ./enc.bend as Enc
import ./io.bend as IO2

# ab = e(alpha, beta); gs, ds, bs: the lines of -gamma, -delta, -beta (bs: batch only);
# tabs: for each IC point P (IC0 first), the affine multiples [P, 2P, ..., 15P].
type PVK is Data:
  PVK{ab: T.Fq12, gs: +List<PR.Co>, ds: +List<PR.Co>, bs: +List<PR.Co>, alpha: G1.Aff, tabs: +List<+List<G1.Aff>>}

def aff1(+ws: +List<U32>) -> G1.Aff:
  G1.mk_aff(F.from_raw(IO2.raw_fq(ws)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, ws, 12n))))

def aff2(+ws: +List<U32>) -> G2.Aff:
  +d = List.drop(&2, U32, ws, 24n)
  G2.mk_aff(E.mk(F.from_raw(IO2.raw_fq(ws)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, ws, 12n)))), E.mk(F.from_raw(IO2.raw_fq(d)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, d, 12n)))))

def neg2(a: G2.Aff) -> G2.Aff:
  G2.Aff{x, y} = a
  G2.Aff{x, E.neg(y)}

def ics(n: Nat, +ws: +List<U32>) -> +List<G1.Aff>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      aff1(ws) <> ics(k, List.drop(&2, U32, ws, 24n))

def mults(n: Nat, +p: G1.Aff, +acc: G1.Pt) -> +List<G1.Aff>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      G1.to_aff(acc) <> mults(k, p, G1.add_aff(acc, p))

def tables(ps: +List<G1.Aff>) -> +List<+List<G1.Aff>>:
  match ps:
    case Con{+p, t}:
      mults(15n, p, G1.from_aff(p)) <> tables(t)
    case Nil{}:
      Nil{}

def mk_pvk(ab: T.Fq12, gs: +List<PR.Co>, ds: +List<PR.Co>, bs: +List<PR.Co>, alpha: G1.Aff, +ic: +List<G1.Aff>) -> PVK:
  PVK{ab, gs, ds, bs, alpha, tables(ic)}

# The oracle's vk_*.bin (canonical LE words): alpha_g1 | beta_g2 | gamma_g2 | delta_g2 |
# u32 n | n IC points. Prepared once: e(alpha, beta) and the lines of -gamma, -delta.
def prepare_vk(+ws: +List<U32>) -> PVK:
  +alpha = aff1(ws)
  +beta = aff2(List.drop(&2, U32, ws, 24n))
  +gamma = aff2(List.drop(&2, U32, ws, 72n))
  +delta = aff2(List.drop(&2, U32, ws, 120n))
  +n = U32.to_nat(IO2.w_at(168n, ws))
  mk_pvk(PR.final_exp(PR.miller1(alpha, beta)), PR.prepare(neg2(gamma)), PR.prepare(neg2(delta)), PR.prepare(neg2(beta)), alpha, ics(n, List.drop(&2, U32, ws, 169n)))

def nth(n: Nat, ps: +List<G1.Aff>) -> G1.Aff:
  match n ps:
    case 0n Con{+p, _}:
      p
    case 1n+k Con{_, t}:
      nth(k, t)
    case _ _:
      G1.mk_aff(F.zero(), F.zero())

def add_dig(acc: G1.Pt, +tab: +List<G1.Aff>, +d: U32) -> G1.Pt:
  match d:
    case 0:
      acc
    case _:
      G1.add_aff(acc, nth(U32.to_nat((d - 1 : U32)), tab))

# Window k (0 = most significant) of a 256-bit scalar given as 8 LE words: 4 bits.
def digit(+k: U32, +s: +List<U32>) -> U32:
  ((IO2.w_at(U32.to_nat((7 - (k >> 3n) : U32)), s) >> U32.to_nat((28 - 4 * (k .&. 7) : U32))) .&. 15 : U32)

def step(tabs: +List<+List<G1.Aff>>, +k: U32, acc: G1.Pt, +ins: +List<U32>) -> G1.Pt:
  match tabs:
    case Con{+t, ts}:
      step(ts, k, add_dig(acc, t, digit(k, ins)), List.drop(&2, U32, ins, 8n))
    case Nil{}:
      acc

# Straus / Shamir: sum_i s_i P_i with shared doublings, 4-bit windows, precomputed tables.
def straus(n: Nat, +k: U32, acc: G1.Pt, +tabs: +List<+List<G1.Aff>>, +ins: +List<U32>) -> G1.Pt:
  match n:
    case 0n:
      acc
    case 1n+r:
      straus(r, (k + 1 : U32), step(tabs, k, G1.dbl_n(4n, acc), ins), tabs, ins)

# sum_i s_i IC_i over all IC points (scalars: 8 LE words each, IC0's first).
def msm_all(+tabs: +List<+List<G1.Aff>>, +ss: +List<U32>) -> G1.Pt:
  straus(64n, 0, G1.identity(), tabs, ss)

# IC0 + sum input_i IC_{i+1}.
def msm(+tabs: +List<+List<G1.Aff>>, +ins: +List<U32>) -> G1.Pt:
  msm_all(tabs, List.append(&2, U32, [1, 0, 0, 0, 0, 0, 0, 0], ins))

def pvk_ab(v: PVK) -> T.Fq12:
  PVK{+ab, _, _, _, _, _} = v
  ab

def pvk_gs(v: PVK) -> +List<PR.Co>:
  PVK{_, +gs, _, _, _, _} = v
  gs

def pvk_ds(v: PVK) -> +List<PR.Co>:
  PVK{_, _, +ds, _, _, _} = v
  ds

def pvk_bs(v: PVK) -> +List<PR.Co>:
  PVK{_, _, _, +bs, _, _} = v
  bs

def pvk_alpha(v: PVK) -> G1.Aff:
  PVK{_, _, _, _, +al, _} = v
  al

def pvk_tabs(v: PVK) -> +List<+List<G1.Aff>>:
  PVK{_, _, _, _, _, +tabs} = v
  tabs

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

# The pairing check on decoded points. acc = identity is skipped in the Miller loop, as
# the crate's multi_miller_loop does.
def check(+a: G1.Aff, +b: G2.Aff, +c: G1.Aff, +ins: +List<U32>, +v: PVK) -> U32:
  +accp = msm(pvk_tabs(v), ins)
  +eg = (1 - b2u(G1.is_identity(accp)) : U32)
  +ml = PR.miller(pvk_gs(v), pvk_ds(v), PR.mk_ps(b, a, G1.to_aff(accp), c, 1, eg, 1))
  (2 - T.eq(PR.final_exp(ml), pvk_ab(v)) : U32)

def check3(a: Maybe<&2, G1.Aff>, b: Maybe<&2, G2.Aff>, c: Maybe<&2, G1.Aff>, +ins: +List<U32>, +v: PVK) -> U32:
  match a b c:
    case Some{+a1} Some{+b1} Some{+c1}:
      check(a1, b1, c1, ins, v)
    case _ _ _:
      0

# One proof: 48 words (the 192 proof bytes, LE-packed) and its inputs. Returns 1 valid,
# 0 rejected while decoding the proof points, 2 rejected by the pairing equation.
def verify(+pw: +List<U32>, +ins: +List<U32>, +v: PVK) -> U32:
  check3(Enc.g1(pw), Enc.g2(List.drop(&2, U32, pw, 12n)), Enc.g1(List.drop(&2, U32, pw, 36n)), ins, v)

# ---- decoded proofs (for batching)

# ok = 0: the proof did not decode (then a, b, c are placeholders).
type Dec is Data:
  Dec{ok: U32, a: G1.Aff, b: G2.Aff, c: G1.Aff}

def z1() -> G1.Aff:
  G1.mk_aff(F.zero(), F.zero())

def dec3(a: Maybe<&2, G1.Aff>, b: Maybe<&2, G2.Aff>, c: Maybe<&2, G1.Aff>) -> Dec:
  match a b c:
    case Some{a1} Some{b1} Some{c1}:
      Dec{1, a1, b1, c1}
    case _ _ _:
      Dec{0, z1(), G2.mk_aff(E.zero(), E.zero()), z1()}

def decode(+pw: +List<U32>) -> Dec:
  dec3(Enc.g1(pw), Enc.g2(List.drop(&2, U32, pw, 12n)), Enc.g1(List.drop(&2, U32, pw, 36n)))

def dec_ok(d: Dec) -> U32:
  Dec{+ok, _, _, _} = d
  ok

def vd(+ok: U32, +a: G1.Aff, +b: G2.Aff, +c: G1.Aff, +ins: +List<U32>, +v: PVK) -> U32:
  match ok:
    case 0:
      0
    case _:
      check(a, b, c, ins, v)

# Single verification of a decoded proof: 1 valid, 0 not decoded, 2 pairing check failed.
def verify_dec(d: Dec, +ins: +List<U32>, +v: PVK) -> U32:
  Dec{+ok, +a, +b, +c} = d
  vd(ok, a, b, c, ins, v)
