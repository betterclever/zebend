# Batch-affine signed Pippenger check/bench: ./msm_ba_main <msm_N.bin> <c> <gpu 0|1> <N>
# The file holds N x (compressed Vesta point || scalar) then the expected sum (from
# halo2's best_multiexp). `MSM.sum!` runs on the GPU; `+RTS --gpu off -RTS` runs it on
# CPU threads instead.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../fast/lib32/vesta.bend as V
import ../lib/msm_ba.bend as BA

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
  Args{path: String, c: U32, depth: U32, n: U32}

def parse_args(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{c, Con{d, Con{n, _}}}}}:
      Args{p, num(c), num(d), num(n)}
    case _:
      Args{"", 0, 0, 0}

def run_n(g: Nat, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  match g:
    case 0n:
      BA.msm(c, ps, ss)
    case 1n:
      BA.msm_gpu(c, ps, ss)
    case 2n:
      BA.msm9(c, ps, ss)
    case _:
      BA.msm9_gpu(c, ps, ss)

def run(+g: U32, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  run_n(U32.to_nat(g), c, ps, ss)

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
  Args{path, +c, +depth, +n} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, (n * 64 + 32 : U32))
    +rd : Rd = read(U32.to_nat(n), rev(words(bytes_of(r), Nil{}), Nil{}), Rd{Nil{}, Nil{}, Wd.zero()})
    +ps : +List<V.Pt> = ps_of(rd)
    +ss : +List<Wd.W> = ss_of(rd)
    t0 : Nat <- IO.now()
    +cold : V.Pt = run(depth, c, ps, ss)
    +cw : Wd.W = V.encode(cold)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +res : V.Pt = run(depth, c, ps, ss)
    +got : Wd.W = V.encode(res)
    t2 : Nat <- IO.now()
    IO.print("batch-affine n " ++ U32.show(n) ++ " c " ++ U32.show(c) ++ " gpu " ++ U32.show(depth) ++ " warm_ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " cold_ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " cold " ++ verdict(Wd.is_eq(cw, want_of(rd))))
    IO.print("got  " ++ Wd.hex(got) ++ " " ++ verdict(Wd.is_eq(got, want_of(rd))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
