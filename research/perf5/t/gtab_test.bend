# Fixed-base table MSM check/bench (table built in memory from the file's bases): ./gtab_test
# was: ./msm_main <msm_N.bin> <c> <mode> <N> [chunks]
# mode 0 msm (carries), 2 msm9, 4 msm_par(c, chunks), 5 msm_auto
# The file holds N x (compressed Vesta point || scalar) then the expected sum (from
# halo2's best_multiexp). `MSM.sum!` runs on the GPU; `+RTS --gpu off -RTS` runs it on
# CPU threads instead.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/lib64/vesta.bend as V
import ../lib/msm_ba.bend as BA
import ../lib/msm_par.bend as MP
import ../lib/gtab.bend as GT

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

def run_n(g: Nat, +c: U32, +k: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  match g:
    case 0n:
      BA.msm(c, ps, ss)
    case 2n:
      BA.msm9(c, ps, ss)
    case 4n:
      MP.msm_par(c, U32.to_nat(k), ps, ss)
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

# least k with 2^k >= n (n <= 2^31)
def lg_sel(done: Bool, +k: Nat, +rest: Nat) -> Nat:
  match done:
    case True{}:
      k
    case False{}:
      rest

def lg_go(fuel: Nat, +n: U32, +k: Nat) -> Nat:
  match fuel:
    case 0n:
      k
    case 1n+f:
      lg_sel(U32.is_ge(U32.shln(1, k), n), k, lg_go(f, n, Nat.add(k, 1n)))

def lg(+n: U32) -> Nat:
  lg_go(32n, n, 0n)

def gen_only_k(r: Array<U32> & U32) -> U32:
  (a, +w) = r
  w

def gen_only(a: Array<U32>) -> U32:
  gen_only_k(a[16])

def runs2(n: Nat, +c: U32, +ss: +List<Wd.W>, +k: U32, +want: Wd.W, +acc: U32, p: Array<U32> & Array<U32>) -> U32:
  match n:
    case 0n:
      (a1, a2) = p
      acc
    case 1n+m:
      (a1, a2) = p
      +ok = Bool.to_u32(Wd.is_eq(V.encode(GT.msm(a1, c, ss, U32.to_nat(k))), want))
      runs2(m, c, ss, k, want, (acc + ok : U32), Array.fork(U32, a2))

def timed(tab: Array<U32>, +c: U32, +ss: +List<Wd.W>, +k: U32, +want: Wd.W, +n: U32) -> IO(Unit):
  do IO<Unit>:
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +ok : U32 = runs2(10n, c, ss, k, want, 0, Array.fork(U32, tab))
    t2x : Nat <- IO.now()
    +t2 : Nat = t2x
    IO.print("gtab n " ++ U32.show(n) ++ " c " ++ U32.show(c) ++ " tasks " ++ U32.show(k) ++ " msm_ms_x10 " ++ Nat.show(Nat.sub(t2, t1)) ++ " match " ++ U32.show(ok) ++ "/10")

def go(a: Args) -> IO(Unit):
  Args{path, +c, +depth, +n, +k} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, (n * 64 + 32 : U32))
    +rd : Rd = read(U32.to_nat(n), rev(words(bytes_of(r), Nil{}), Nil{}), Rd{Nil{}, Nil{}, Wd.zero()})
    +ps : +List<V.Pt> = ps_of(rd)
    +ss : +List<Wd.W> = ss_of(rd)
    timed(GT.gen(c, ps, lg((GT.nbytes(n, c) / 4 : U32))), c, ss, k, want_of(rd), n)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
