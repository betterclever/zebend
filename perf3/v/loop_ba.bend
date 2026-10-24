# Verifies one bundle N times in-process (for sampling profilers).
import Base
import ../../halo2/lib/words.bend as Wd
import ../lib32/vesta.bend as V
import ./vlib.bend as L
import ./orchard_ba.bend as O
import ./bundle_ba.bend as B

def many(n: Nat, +pr: L.Proof, +gs: +List<V.Pt>, +np: Nat, +ni: Nat, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      many(k, pr, gs, np, ni, (acc + L.st_ok(O.verify(pr, gs, np, ni)) : U32))

def run(gpath: String, bpath: String, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- B.read_all(gpath)
    bb : List<&2, U32> <- B.read_all(bpath)
    +gs : +List<V.Pt> = B.points(B.items(L.pack4(gb)))
    +inp : B.In = B.parse_bundle(bb)
    t0 : Nat <- IO.now()
    +ok : U32 = many(n, B.in_pr(inp), gs, B.in_np(inp), B.in_ni(inp), 0)
    IO.print("ok " ++ U32.show(ok))
    t1 : Nat <- IO.now()
    IO.print("per_verify_ms " ++ Nat.show(Nat.div(Nat.sub(t1, t0), n)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{bp, Con{ns, _}}}}:
      run(gp, bp, Maybe.default(&2, Nat, Nat.read(ns), 1n))
    case _:
      IO.print("usage: loop_main <params_g.bin> <bundle.bin> <n>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
