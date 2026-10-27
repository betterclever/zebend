# MSM check/bench: ./msm_main <msm_N.bin> <c> <mode> <N> [chunks]
# mode 0 msm (carries), 2 msm9, 4 msm_par(c, chunks), 5 msm_auto, 6 msm9 repeated `chunks` times (profiling)
# The file holds N x (compressed Vesta point || scalar) then the expected sum (from
# halo2's best_multiexp). `MSM.sum!` runs on the GPU; `+RTS --gpu off -RTS` runs it on
# CPU threads instead.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/lib64/vesta.bend as V
import ../lib/msm_ba.bend as BA
import ../lib/msm_par.bend as MP
import ../lib/msm_fa.bend as FA

def words(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}:
      words(rest, (b0 .|. (b1 << 8n) .|. (b2 << 16n) .|. (b3 << 24n) : U32) <> acc)
    case _:
      acc

def rev(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Con{h, t}:
      rev(t, h <> acc)
    case Nil{}:
      acc

type Rd is Data:
  Rd{ps: +List<V.Pt>, ss: +List<Wd.W>, want: Wd.W}

def pt_of(+w: Wd.W) -> V.Pt:
  Maybe.default(&2, V.Pt, V.decompress(w), V.identity())

def rd_push(+p: Wd.W, +s: Wd.W, r: Rd) -> Rd:
  Rd{ps, ss, want} = r
  Rd{pt_of(p) <> ps, s <> ss, want}

def rd_want(+w: Wd.W, r: Rd) -> Rd:
  Rd{ps, ss, _} = r
  Rd{ps, ss, w}

# Consumes n (point, scalar) records then the expected point.
def read(n: Nat, ws: +List<U32>, r: Rd) -> Rd:
  match n ws:
    case 1n+k Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, Con{b0, Con{b1, Con{b2, Con{b3, Con{b4, Con{b5, Con{b6, Con{b7, rest}}}}}}}}}}}}}}}}:
      read(k, rest, rd_push(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}, Wd.W{b0, b1, b2, b3, b4, b5, b6, b7}, r))
    case 0n Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, _}}}}}}}}:
      rd_want(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}, r)
    case _ _:
      r

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

type Args is Type:
  Args{path: String, c: U32, depth: U32, n: U32, p: U32}

def parse_args(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{c, Con{d, Con{n, Con{k, _}}}}}}:
      Args{p, num(c), num(d), num(n), num(k)}
    case Con{_, Con{p, Con{c, Con{d, Con{n, _}}}}}:
      Args{p, num(c), num(d), num(n), 1}
    case _:
      Args{"", 0, 0, 0, 1}

def rep(n: Nat, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>, +acc: V.Pt) -> V.Pt:
  match n:
    case 0n:
      acc
    case 1n+m:
      rep(m, c, ps, ss, BA.msm9(c, ps, ss))

def rep_fa(n: Nat, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>, +acc: V.Pt) -> V.Pt:
  match n:
    case 0n:
      acc
    case 1n+m:
      rep_fa(m, c, ps, ss, FA.msm(c, ps, ss))

def run_n(g: Nat, +c: U32, +k: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  match g:
    case 0n:
      BA.msm(c, ps, ss)
    case 2n:
      BA.msm9(c, ps, ss)
    case 4n:
      MP.msm_par(c, U32.to_nat(k), ps, ss)
    case 6n:
      rep(U32.to_nat(k), c, ps, ss, V.identity())
    case 7n:
      FA.msm(c, ps, ss)
    case 8n:
      rep_fa(U32.to_nat(k), c, ps, ss, V.identity())
    case _:
      MP.msm_auto(ps, ss)

def run(+g: U32, +c: U32, +k: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  run_n(U32.to_nat(g), c, k, ps, ss)

def ps_of(r: Rd) -> +List<V.Pt>:
  Rd{ps, _, _} = r
  ps

def ss_of(r: Rd) -> +List<Wd.W>:
  Rd{_, ss, _} = r
  ss

def want_of(r: Rd) -> Wd.W:
  Rd{_, _, w} = r
  w

def verdict(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

def go(a: Args) -> IO(Unit):
  Args{path, +c, +depth, +n, +k} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, (n * 64 + 32 : U32))
    +rd : Rd = read(U32.to_nat(n), rev(words(bytes_of(r), Nil{}), Nil{}), Rd{Nil{}, Nil{}, Wd.zero()})
    +ps : +List<V.Pt> = ps_of(rd)
    +ss : +List<Wd.W> = ss_of(rd)
    t0 : Nat <- IO.now()
    +cold : V.Pt = run(depth, c, k, ps, ss)
    +cw : Wd.W = V.encode(cold)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +res : V.Pt = run(depth, c, k, ps, ss)
    +got : Wd.W = V.encode(res)
    t2 : Nat <- IO.now()
    IO.print("batch-affine n " ++ U32.show(n) ++ " c " ++ U32.show(c) ++ " mode " ++ U32.show(depth) ++ " chunks " ++ U32.show(k) ++ " warm_ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " cold_ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " cold " ++ verdict(Wd.is_eq(cw, want_of(rd))))
    IO.print("got  " ++ Wd.hex(got) ++ " " ++ verdict(Wd.is_eq(got, want_of(rd))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
