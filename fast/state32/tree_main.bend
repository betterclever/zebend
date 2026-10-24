# Rebuild Zcash mainnet's Ironwood note commitment tree in Bend and compare its root
# with the chain's own (lightwalletd GetTreeState) at every checkpoint height.
#   ./tree_main out/cmx.bin tree        parallel tree, CPU threads
#   ./tree_main out/cmx.bin gpu         parallel tree, `subroot!` on the GPU
#   ./tree_main out/cmx.bin frontier    sequential incremental frontier (a node's view)
import Base
import ../../halo2/lib/words.bend as Wd
import ./sinsemilla.bend as S
import ./checkpoints.bend as CK

# --- reading cm_x leaves (32-byte little-endian records) ---------------------------

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_of(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_of(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def ws_of(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_of(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      acc

def leaves_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> +List<Wd.W>:
  (_, res) = r
  match res:
    case Done{bs}:
      List.reverse(&2, Wd.W, ws_of(List.reverse(&2, U32, words_of(bs, Nil{})), Nil{}))
    case Fail{_}:
      Nil{}

# words_of and ws_of each reverse; the two List.reverse calls restore file order.

# --- parallel tree roots at each checkpoint ----------------------------------------

def show_ok(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

def root_of(+gpu: Bool, +n: U32, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> Wd.W:
  match gpu:
    case True{}:
      S.root_gpu(20n, List.take(&2, Wd.W, leaves, U32.to_nat(n)), g, es)
    case False{}:
      S.root(20n, List.take(&2, Wd.W, leaves, U32.to_nat(n)), g, es)

def check_tree(cps: +List<CK.CP>, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>, +gpu: Bool) -> IO(Unit):
  match cps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{cp, rest}:
      CK.CP{+height, +size, +want} = cp
      do IO<Unit>:
        t0 : Nat <- IO.now()
        +got : Wd.W = root_of(gpu, size, leaves, g, es)
        t1 : Nat <- IO.now()
        IO.print("height " ++ U32.show(height) ++ " size " ++ U32.show(size) ++ ": bend root " ++ Wd.hex(got) ++ " " ++ show_ok(Wd.is_eq(got, want)) ++ " (" ++ Nat.show(Nat.sub(t1, t0)) ++ " ms)")
        check_tree(rest, leaves, g, es, gpu)

# --- sequential frontier: append every leaf, compare at each checkpoint ------------

def head_is(+cps: +List<CK.CP>, +i: U32) -> Bool:
  match cps:
    case Nil{}:
      False{}
    case Con{cp, _}:
      CK.CP{_, size, _} = cp
      U32.is_eq(size, i)

def fr_report(cp: CK.CP, +got: Wd.W) -> String:
  CK.CP{height, size, want} = cp
  "height " ++ U32.show(height) ++ " size " ++ U32.show(size) ++ ": bend frontier root " ++ Wd.hex(got) ++ " " ++ show_ok(Wd.is_eq(got, want))

# `at` says whether the next checkpoint is at the current size i.
def fr_go(leaves: +List<Wd.W>, +cps: +List<CK.CP>, at: Bool, +i: U32, +f: +List<Maybe<&2, Wd.W>>, +g: S.Gens, +es: +List<Wd.W>, out: List<String>) -> List<String>:
  match leaves cps at:
    case _ Con{+cp, +rest} True{}:
      +line = fr_report(cp, S.froot(f, 0n, None{}, g, es))
      fr_go(leaves, rest, head_is(rest, i), i, f, g, es, line <> out)
    case Con{w, t} _ False{}:
      +j = (i + 1 : U32)
      fr_go(t, cps, head_is(cps, j), j, S.push(f, 0n, w, g), g, es, out)
    case _ _ _:
      out

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(x)
        print_all(rest)

# --- main --------------------------------------------------------------------------

type Args is Type:
  Args{path: String, mode: String}

def parse_args(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{m, _}}}:
      Args{p, m}
    case _:
      Args{"out/cmx.bin", "tree"}

def run_mode(frontier: Bool, +gpu: Bool, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> IO(Unit):
  match frontier:
    case True{}:
      do IO<Unit>:
        t0 : Nat <- IO.now()
        lines : List<String> = List.reverse(&1, String, fr_go(leaves, CK.checkpoints(), head_is(CK.checkpoints(), 0), 0, S.frontier_new(), g, es, Nil{}))
        t1 : Nat <- IO.now()
        print_all(lines)
        IO.print("frontier: appended all leaves in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    case False{}:
      check_tree(CK.checkpoints(), leaves, g, es, gpu)

def go(a: Args) -> IO(Unit):
  Args{path, +mode} = a
  +n = CK.leaf_count()
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, (n * 32 : U32))
    +leaves : +List<Wd.W> = leaves_of(r)
    IO.print("read " ++ Nat.show(List.length(&2, Wd.W, leaves)) ++ " Ironwood cm_x leaves (mainnet blocks 3428143..3528268); mode " ++ mode)
    +g : S.Gens = S.gens()
    +es : +List<Wd.W> = S.empties(g)
    run_mode(String.eq(mode, "frontier"), String.eq(mode, "gpu"), leaves, g, es)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
