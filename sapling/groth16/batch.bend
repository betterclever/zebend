# Batch verification of Groth16 proofs that share a verifying key (as groth16 0.2's
# batch::Verifier, which sapling-crypto's BatchValidator uses), with 128-bit random weights z_j:
#   prod_j e(z_j A_j, B_j) * e(Psi, -gamma) * e(sum_j z_j C_j, -delta) * e((sum_j z_j) alpha, -beta) == 1,
#   Psi = sum_i (sum_j z_j a_ij) IC_i  (a_0j = 1).
# One multi Miller loop (the squarings shared by all terms) and one final exponentiation.
# Line evaluations follow the crate's formulas, so a batch of one has the crate's values.
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as R
import ./fq.bend as F
import ./fq2.bend as E
import ./fq12.bend as T
import ./g1.bend as G1
import ./g2.bend as G2
import ./pairing.bend as PR
import ./groth16.bend as V
import ./io.bend as IO2

# A proof in a batch: its weight z (4 LE words), decoded points, inputs (8 words each).
type It is Data:
  It{z: +List<U32>, d: V.Dec, ins: +List<U32>}

# A Miller loop term whose G2 point is the proof's B (computed on the fly).
type Dyn is Data:
  Dyn{r: PR.R2, b: G2.Aff, za: G1.Aff}

type DF is Data:
  DF{d: Dyn, f: T.Fq12}

type FS is Data:
  FS{f: T.Fq12, ds: +List<Dyn>}

# The three fixed terms (Psi, -gamma), (Delta, -delta), (Y alpha, -beta); e*: 1 = use the
# term (0: the point is the identity, skipped as the crate does). FxB is never built: it
# makes Fx boxed (Bend's 247-word parameter limit).
type Fx is Data:
  Fx{pg: G1.Aff, pd: G1.Aff, pb: G1.Aff, eg: U32, ed: U32, eb: U32}
  FxB{x: Fx}

def mk_fx(pg: G1.Aff, pd: G1.Aff, pb: G1.Aff, eg: U32, ed: U32, eb: U32) -> Fx:
  Fx{pg, pd, pb, eg, ed, eb}

def w8(+ws: +List<U32>) -> Wd.W:
  Wd.W{IO2.w_at(0n, ws), IO2.w_at(1n, ws), IO2.w_at(2n, ws), IO2.w_at(3n, ws), IO2.w_at(4n, ws), IO2.w_at(5n, ws), IO2.w_at(6n, ws), IO2.w_at(7n, ws)}

def wl(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  [a, b, c, d, e, f, g, h]

# [z] P for a 128-bit z (4 LE words).
def mul128(+p: G1.Pt, +z: +List<U32>) -> G1.Pt:
  G1.mul_w(32n, IO2.w_at(0n, z), G1.mul_w(32n, IO2.w_at(1n, z), G1.mul_w(32n, IO2.w_at(2n, z), G1.mul_w(32n, IO2.w_at(3n, z), G1.identity(), p), p), p), p)

def z_fr(+z: +List<U32>) -> R.Fr:
  R.from_words(Wd.W{IO2.w_at(0n, z), IO2.w_at(1n, z), IO2.w_at(2n, z), IO2.w_at(3n, z), 0, 0, 0, 0})

# ---- per-proof parts

def dyn_of(+z: +List<U32>, d: V.Dec) -> Dyn:
  V.Dec{_, +a, +b, _} = d
  Dyn{PR.r_of(b), b, G1.to_aff(mul128(G1.from_aff(a), z))}

def dyns(xs: +List<It>) -> +List<Dyn>:
  match xs:
    case Con{It{+z, +d, _}, t}:
      dyn_of(z, d) <> dyns(t)
    case _:
      Nil{}

def zc(+z: +List<U32>, d: V.Dec) -> G1.Pt:
  V.Dec{_, _, _, +c} = d
  mul128(G1.from_aff(c), z)

# sum_j z_j C_j
def delta(xs: +List<It>, acc: G1.Pt) -> G1.Pt:
  match xs:
    case Con{It{+z, +d, _}, t}:
      delta(t, G1.add(acc, zc(z, d)))
    case _:
      acc

# acc_i += z * x_i for the scalars x = [1, a_1, ..., a_n] (8 words each).
def upd(acc: +List<R.Fr>, +z: R.Fr, +ws: +List<U32>) -> +List<R.Fr>:
  match acc:
    case Con{+a, t}:
      R.add(a, R.mul(z, R.from_words(w8(ws)))) <> upd(t, z, List.drop(&2, U32, ws, 8n))
    case Nil{}:
      Nil{}

def sums(xs: +List<It>, acc: +List<R.Fr>) -> +List<R.Fr>:
  match xs:
    case Con{It{+z, _, +ins}, t}:
      sums(t, upd(acc, z_fr(z), List.append(&2, U32, [1, 0, 0, 0, 0, 0, 0, 0], ins)))
    case _:
      acc

def zeros(n: Nat) -> +List<R.Fr>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      R.zero() <> zeros(k)

def fr_words(xs: +List<R.Fr>) -> +List<U32>:
  match xs:
    case Con{+x, t}:
      List.append(&2, U32, wl(R.to_words(x)), fr_words(t))
    case Nil{}:
      Nil{}

def head_fr(xs: +List<R.Fr>) -> R.Fr:
  match xs:
    case Con{+x, _}:
      x
    case Nil{}:
      R.zero()

# ---- the multi Miller loop with dynamic terms

def dummy() -> Dyn:
  Dyn{PR.R2{E.zero(), E.zero(), E.zero()}, G2.mk_aff(E.zero(), E.zero()), V.z1()}

def h_fin(st: PR.St, +b: G2.Aff, +za: G1.Aff, f: T.Fq12) -> DF:
  PR.St{r, co} = st
  DF{Dyn{r, b, za}, PR.ell(f, co, za)}

def h_code(+code: U32, r: PR.R2, +b: G2.Aff, +za: G1.Aff, f: T.Fq12) -> DF:
  match code:
    case 0:
      h_fin(PR.dbl_step(r), b, za, f)
    case _:
      h_fin(PR.add_step(r, b), b, za, f)

def h(+code: U32, d: Dyn, f: T.Fq12) -> DF:
  Dyn{r, +b, +za} = d
  h_code(code, r, b, za, f)

def tail_d(xs: +List<Dyn>) -> +List<Dyn>:
  match xs:
    case Con{_, t}:
      t
    case Nil{}:
      Nil{}

# One doubling (code 0) or addition (code 1) step on every dynamic term, multiplying its
# line into f. df carries the term updated last (a dummy at the start).
def dyn_go(ds: +List<Dyn>, +code: U32, df: DF, out: +List<Dyn>) -> FS:
  match ds df:
    case Con{+d, t} DF{prev, f}:
      dyn_go(t, code, h(code, d, f), prev <> out)
    case Nil{} DF{prev, f}:
      FS{f, tail_d(List.reverse(&2, Dyn, prev <> out))}

def dyn_run(+code: U32, fs: FS) -> FS:
  FS{f, ds} = fs
  dyn_go(ds, code, DF{dummy(), f}, Nil{})

def fx1(fs: FS, c: PR.Co, +p: G1.Aff, +e: U32) -> FS:
  FS{f, ds} = fs
  FS{PR.ell_if(e, f, c, p), ds}

def fx_all(fs: FS, g: PR.Co, d: PR.Co, b: PR.Co, fx: Fx) -> FS:
  match fx:
    case Fx{+pg, +pd, +pb, +eg, +ed, +eb}:
      fx1(fx1(fx1(fs, g, pg, eg), d, pd, ed), b, pb, eb)
    case _:
      fs

def sqr_fs(fs: FS) -> FS:
  FS{f, ds} = fs
  FS{T.sqr(f), ds}

def f_of(fs: FS) -> T.Fq12:
  FS{f, _} = fs
  T.conj(f)

def ml_b(s: PR.Sc, fs: FS, gs: +List<PR.Co>, ds: +List<PR.Co>, bs: +List<PR.Co>, +fx: Fx) -> T.Fq12:
  match s gs ds bs:
    case PR.SD{t} Con{g, gt} Con{d, dt} Con{b, bt}:
      ml_b(t, fx_all(dyn_run(0, fs), g, d, b, fx), gt, dt, bt, fx)
    case PR.SA{t} Con{g, gt} Con{d, dt} Con{b, bt}:
      ml_b(t, fx_all(dyn_run(1, fs), g, d, b, fx), gt, dt, bt, fx)
    case PR.SS{t} _ _ _:
      ml_b(t, sqr_fs(fs), gs, ds, bs, fx)
    case PR.SEnd{} _ _ _:
      f_of(fs)
    case _ _ _ _:
      T.one()

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def nz(+p: G1.Pt) -> U32:
  (1 - b2u(G1.is_identity(p)) : U32)

def mul_fr(+p: G1.Aff, w: Wd.W) -> G1.Pt:
  Wd.W{a, b, c, d, e, f, g, h} = w
  G1.mul_scalar(G1.from_aff(p), a, b, c, d, e, f, g, h)

# 1 if the batch equation holds, else 0.
def batch_eq(+xs: +List<It>, +v: V.PVK, +ss: +List<R.Fr>) -> U32:
  +psi = V.msm_all(V.pvk_tabs(v), fr_words(ss))
  +dl = delta(xs, G1.identity())
  +ya = mul_fr(V.pvk_alpha(v), R.to_words(head_fr(ss)))
  T.eq(PR.final_exp(ml_b(PR.sched(), FS{T.one(), dyns(xs)}, V.pvk_gs(v), V.pvk_ds(v), V.pvk_bs(v), mk_fx(G1.to_aff(psi), G1.to_aff(dl), G1.to_aff(ya), nz(psi), nz(dl), nz(ya)))), T.one())

def is_nil(xs: +List<It>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def batch_if(b: Bool, +xs: +List<It>, +v: V.PVK) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      batch_eq(xs, v, sums(xs, zeros(List.length(&2, +List<G1.Aff>, V.pvk_tabs(v)))))

# 1 if every proof in xs is valid (with overwhelming probability), else 0. Empty: 1.
def batch(+xs: +List<It>, +v: V.PVK) -> U32:
  batch_if(is_nil(xs), xs, v)
