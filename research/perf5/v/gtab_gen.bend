# gtab_gen <params_g.bin> <out.gtab> [c]: computes the fixed-base table of the IPA generators
# (lib/gtab.bend; window width c, default 9) and writes it with File.write_words.
import Base
import ../../../crypto/field3/lib64/vesta.bend as V
import ../lib/gtab.bend as GT
import ./pio.bend as P

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

def wrote(w: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = w
  match r:
    case Done{v}:
      do IO<Unit>:
        IO.print("wrote")
        File.close(f)
    case Fail{e}:
      (code, text) = e
      do IO<Unit>:
        IO.print("write failed " ++ U32.show(code))
        File.close(f)

def put(out: String, tab: Array<U32>, +nb: U32) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(out, "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_words(f, tab, nb)
    wrote(w)

def run(gp: String, out: String, +c: U32) -> IO(Unit):
  do IO<Unit>:
    +gs : +List<V.Pt> <- P.params(gp)
    +n : U32 = U32.from_nat(List.length(&2, V.Pt, gs))
    +nb : U32 = GT.nbytes(n, c)
    IO.print("gtab n " ++ U32.show(n) ++ " c " ++ U32.show(c) ++ " bytes " ++ U32.show(nb))
    put(out, GT.gen(c, gs, lg((nb / 4 : U32))), nb)

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 9)

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{out, Con{c, _}}}}:
      run(gp, out, num(c))
    case Con{_, Con{gp, Con{out, Nil{}}}}:
      run(gp, out, 9)
    case _:
      IO.print("usage: gtab_gen <params_g.bin> <out.gtab> [c]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
