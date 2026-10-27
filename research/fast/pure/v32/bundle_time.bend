# Times the phases of one bundle verification in-process, so the verify step can be
# compared with Rust's `proof.verify(&vk, &instances)` (which excludes params setup).
import Base
import ../../../../zcash/halo2/lib/words.bend as Wd
import ../lib32/vesta.bend as V
import ./vlib.bend as L
import ./orchard_dyn_fast.bend as O
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

def run(gpath: String, bpath: String) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- B.read_all(gpath)
    bb : List<&2, U32> <- B.read_all(bpath)
    t0 : Nat <- IO.now()
    +gs : +List<V.Pt> = B.points(B.items(L.pack4(gb)))
    IO.print("generators decompressed (non-identity): " ++ Nat.show(gs_len(gs, 0n)))
    +t1 : Nat <- IO.now()
    +inp : B.In = B.parse_bundle(bb)
    +st : L.St = O.verify(B.in_pr(inp), gs, B.in_np(inp), B.in_ni(inp))
    IO.print("result " ++ U32.show(L.st_ok(st)))
    t2 : Nat <- IO.now()
    IO.print("setup_ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " verify_ms " ++ Nat.show(Nat.sub(t2, t1)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{bp, _}}}:
      run(gp, bp)
    case _:
      IO.print("usage: bundle_time <params_g.bin> <bundle.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
