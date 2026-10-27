# bundle_main <params_g.bin> <bundle.bin> [-v]
#
# Verifies one Orchard-protocol (Orchard or Ironwood) bundle proof against the post-NU6.3
# circuit, with everything read at runtime:
#   params_g.bin : 2^k IPA generators, 64 bytes each (affine x || y, canonical LE Fq)
#   bundle.bin   : u32 LE np (actions), u32 LE ni (instance values per action),
#                  u32 LE proof length, the proof, then np*ni instance values (32 bytes each)
# Prints `result 1` (accept) or `result 0` (reject); `-v` also prints every intermediate.
import Base
import ../lib/words.bend as Wd
import ../lib/fp.bend as Fp
import ../lib/fq.bend as Fq
import ../lib/vesta.bend as V
import ./vlib.bend as L
import ./orchard_dyn_fast.bend as O
import ../../wire/bundle.bend as BU

def items(ws: +List<U32>) -> +List<Wd.W>:
  match ws:
    case Con{+a, Con{+b, Con{+c, Con{+d, Con{+e, Con{+f, Con{+g, Con{+h, rest}}}}}}}}:
      Wd.W{a, b, c, d, e, f, g, h} <> items(rest)
    case _:
      Nil{}

def fps(xs: +List<Wd.W>) -> +List<Fp.Fp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+w, rest}:
      Fp.from_words(w) <> fps(rest)

def points(xs: +List<Wd.W>) -> +List<V.Pt>:
  match xs:
    case Con{+x, Con{+y, rest}}:
      V.from_aff(V.Aff{Fq.from_words(x), Fq.from_words(y)}) <> points(rest)
    case _:
      Nil{}

def w_at(i: Nat, ws: +List<U32>) -> U32:
  match i ws:
    case 0n Con{+h, _}:
      h
    case 1n+k Con{_, t}:
      w_at(k, t)
    case _ Nil{}:
      0

type In is Data:
  In{pr: L.Proof, np: Nat, ni: Nat}

def in_pr(x: In) -> L.Proof:
  In{+pr, _, _} = x
  pr

def in_np(x: In) -> Nat:
  In{_, +np, _} = x
  np

def in_ni(x: In) -> Nat:
  In{_, _, +ni} = x
  ni

def parse_bundle(bs: +List<U32>) -> In:
  +ws = L.pack4(bs)
  +np = U32.to_nat(w_at(0n, ws))
  +ni = U32.to_nat(w_at(1n, ws))
  +nitems = U32.to_nat((w_at(2n, ws) / 32 : U32))
  +all = items(List.drop(&2, U32, ws, 3n))
  In{L.Proof{List.take(&2, Wd.W, all, nitems), fps(List.drop(&2, Wd.W, all, nitems))}, np, ni}

def got(f: File, res: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  match res:
    case Done{bytes}:
      do IO<List<&2, U32>>:
        File.close(f)
        return bytes
    case Fail{e}:
      do IO<List<&2, U32>>:
        File.close(f)
        return Nil{}

def got_pair(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  got(f, res)

def read_all(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 8388608)
    got_pair(r)

def report(+verbose: Bool, +st: L.St) -> IO(Unit):
  match verbose:
    case True{}:
      do IO<Unit>:
        L.print_log(L.st_log(st))
        IO.print("result " ++ U32.show(L.st_ok(st)))
    case False{}:
      IO.print("result " ++ U32.show(L.st_ok(st)))

def verify_bytes(gpath: String, bb: List<&2, U32>, +verbose: Bool) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- read_all(gpath)
    +inp : In = parse_bundle(bb)
    +st : L.St = O.verify(in_pr(inp), points(items(L.pack4(gb))), in_np(inp), in_ni(inp))
    report(verbose, st)

# The input is checked by zcash/wire/bundle.bend (header shape, exact length, canonical
# instance values) before parsing, so a malformed file is `result 0` with bounded memory.
def checked(ok: Bool, gpath: String, bb: List<&2, U32>, +verbose: Bool) -> IO(Unit):
  match ok:
    case True{}:
      verify_bytes(gpath, bb, verbose)
    case False{}:
      IO.print("result 0")

def run(gpath: String, bpath: String, +verbose: Bool) -> IO(Unit):
  do IO<Unit>:
    +bb : List<&2, U32> <- read_all(bpath)
    checked(BU.valid(bb), gpath, bb, verbose)

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{bp, Nil{}}}}:
      run(gp, bp, False{})
    case Con{_, Con{gp, Con{bp, Con{_, _}}}}:
      run(gp, bp, True{})
    case _:
      IO.print("usage: bundle_main <params_g.bin> <bundle.bin> [-v]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
