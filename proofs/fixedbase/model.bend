import Base
import ../opt_gates/term.bend as T
import ../msm_chunk/model.bend as MC

# Models of the fixed-base scalar handling of the fast Halo 2 verifier, over msm_chunk's
# commutative monoid (Nat, +): a point is a Nat, k·P is k * P, scalars are Nats (Fp.add is
# +; msm_chunk/README.md, "Why Nat points suffice" and "Scalars", says why identities proven
# here hold in the Pallas/Vesta group).

# --- research/perf4/v/bt.bend: fixed-base terms, sparse to dense ---------------------------
# vlib.FX{i: U32, s: Fp}: the proof's term s * fixed[i]. U32 indices are Nats here (bt only
# counts i up to nfixed() = 46, so (i + 1 : U32) never wraps).

type FX is Data:
  FX{i: Nat, s: Nat}

# Fp.sel(Bool.to_u32(c), a, b): c selects a
def sel(c: Bool, +a: Nat, +b: Nat) -> Nat:
  match c:
    case True{}:
      a
    case False{}:
      b

# bt.fx_sum: the sum of the scalars of every term on fixed base i
def fx_sum(+i: Nat, xs: +List<FX>, +acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{FX{+j, +s}, t}:
      fx_sum(i, t, sel(Nat.is_eq(i, j), Nat.add(acc, s), acc))

# bt.fx_dense_go
def fx_dense_go(n: Nat, +i: Nat, +xs: +List<FX>) -> +List<Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      fx_sum(i, xs, 0n) <> fx_dense_go(k, 1n+i, xs)

# bt.fx_dense: the fixed-base scalars as a dense vector, base 0 first
def fx_dense(+xs: +List<FX>) -> +List<Nat>:
  fx_dense_go(46n, 0n, xs)

# The specification: sum over the terms of s * fixed[i] (a term whose index is past the
# last base contributes nothing, as fx_dense drops it).
def sparse(+fs: +List<Nat>, xs: +List<FX>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{FX{+j, +s}, t}:
      Nat.add(Nat.mul(s, T.nth(fs, j)), sparse(fs, t))

def zeros(n: Nat) -> +List<Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      0n <> zeros(k)
