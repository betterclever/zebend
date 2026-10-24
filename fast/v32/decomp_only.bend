# Process that only reads params_g.bin and decompresses the 2048 generators (to separate
# that one-time setup cost from the verify cost; Rust does it once at key setup).
import Base
import ../../halo2/lib/words.bend as Wd
import ../lib32/vesta.bend as V
import ./vlib.bend as L
import ./bundle_main.bend as B

def cnt(b: Bool) -> Nat:
  match b:
    case True{}:
      0n
    case False{}:
      1n

# Counts non-identity points; touching every point forces its decompression here.
def gs_len(xs: +List<V.Pt>, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{+p, t}:
      gs_len(t, Nat.add(acc, cnt(V.is_identity(p))))

def run(gpath: String) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- B.read_all(gpath)
    +n : Nat = gs_len(B.points(B.items(L.pack4(gb))), 0n)
    IO.print("generators decompressed (non-identity): " ++ Nat.show(n))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, _}}:
      run(gp)
    case _:
      IO.print("usage: decomp_only <params_g.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
