# Verifies one bundle N times in-process (for sampling profilers).
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vlib.bend as L
import ./orchard_ba.bend as O
import ./bundle_ba.bend as B

# perf4: the bundle is parsed in every iteration (parsing now decompresses the proof's points
# ahead of the transcript, which perf3 did inside verify), so the loop times the same work.
def one(+bb: +List<U32>, +gs: +List<V.Pt>) -> U32:
  +x = B.parse_bundle(bb)
  L.st_ok(O.verify(B.in_pr(x), gs, B.in_np(x), B.in_ni(x)))

def many(n: Nat, +bb: +List<U32>, +gs: +List<V.Pt>, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      many(k, bb, gs, (acc + one(bb, gs) : U32))

def run(gpath: String, bpath: String, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- B.read_all(gpath)
    bb : List<&2, U32> <- B.read_all(bpath)
    +gs : +List<V.Pt> = B.points(B.items(L.pack4(gb)))
    t0 : Nat <- IO.now()
    +ok : U32 = many(n, bb, gs, 0)
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
