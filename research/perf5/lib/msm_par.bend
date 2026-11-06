# Chunked parallel MSM for large n: the terms are split into `cnt` chunks, each chunk runs
# the batch-affine signed Pippenger (msm_ba.msm9, windows in parallel) on its own, and the
# chunk sums are added. cnt x windows tasks instead of windows tasks: Bend deals forks
# statically, so ~29 window tasks on 18 threads leave cores idle; many smaller tasks keep
# them busy. Normalisation (one batch inversion) also runs per chunk, in parallel.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/lib64/vesta.bend as V
import ./msm_ba.bend as BA

def mpar(+fuel: Nat, +cnt: Nat, +len: Nat, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  match fuel cnt:
    case 1n+f 1n+1n+_:
      +h = Nat.div(cnt, 2n)
      +m = Nat.div(Nat.mul(len, h), cnt)
      a b = mpar(f, h, m, c, List.take(&2, V.Pt, ps, m), List.take(&2, Wd.W, ss, m)) mpar(f, Nat.sub(cnt, h), Nat.sub(len, m), c, List.drop(&2, V.Pt, ps, m), List.drop(&2, Wd.W, ss, m))
      V.add(a, b)
    case _ _:
      BA.msm9(c, ps, ss)

def msm_par(+c: U32, +cnt: Nat, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  mpar(16n, cnt, List.length(&2, V.Pt, ps), c, ps, ss)

# Window width and chunk count by the number of terms (M5 Max, 18 threads). Chunks of about
# 2,048 terms: per-term cost grows ~2.4x from n = 2,048 to n = 65,536 in one chunk (list
# buckets fall out of cache), so a 262,144-term MSM is 3.5x faster as 128 chunks of 2,048
# (0.32 s vs 1.15 s) despite 128x the bucket reductions.
def sel_u(b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def chunk_terms() -> Nat:
  2048n

def pick_cnt(+n: Nat) -> Nat:
  Nat.max(1n, Nat.div(n, chunk_terms()))

def pick_c(+m: Nat) -> U32:
  sel_u(Nat.is_lt(m, 256n), 6, sel_u(Nat.is_lt(m, 1024n), 7, 9))

def msm_auto(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  +n = List.length(&2, V.Pt, ps)
  +cnt = pick_cnt(n)
  mpar(32n, cnt, n, pick_c(Nat.div(n, cnt)), ps, ss)
