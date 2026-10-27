# Runs the batch verifier's per-proof part (orchard_bt.verify: transcript, decompression,
# instance commitments, gates, IPA scalars; no MSM), parse included, N times in-process on one bundle, serially.
import Base
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vlib.bend as L
import ./orchard_bt.bend as O
import ./bt.bend as BT
import ./batch_main.bend as B
import ../lib/fixb.bend as FB

def one(+bb: +List<U32>, +gs: +List<V.Pt>, +tabs: +List<FB.Tab>) -> U32:
  +x = B.parse_bundle(bb)
  BT.fin_ok(O.verify(B.in_pr(x), gs, tabs, B.in_np(x), B.in_ni(x)))

def many(n: Nat, +bb: +List<U32>, +gs: +List<V.Pt>, +tabs: +List<FB.Tab>, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      many(k, bb, gs, tabs, (acc + one(bb, gs, tabs) : U32))

def run(gpath: String, bpath: String, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- B.read_all(gpath)
    bb : List<&2, U32> <- B.read_all(bpath)
    +gs : +List<V.Pt> = B.points(B.items(L.pack4(gb)))
    tbx : Nat <- IO.now()
    +tb : Nat = tbx
    +tabs : +List<FB.Tab> = B.inst_tables(n)
    +nt : Nat = List.length(&2, FB.Tab, tabs)
    ttx : Nat <- IO.now()
    +tt : Nat = ttx
    IO.print("tables " ++ Nat.show(nt) ++ " build_ms " ++ Nat.show(Nat.sub(tt, tb)))
    t0 : Nat <- IO.now()
    +ok : U32 = many(n, bb, gs, tabs, 0)
    IO.print("ok " ++ U32.show(ok))
    t1 : Nat <- IO.now()
    IO.print("per_proof_us " ++ Nat.show(Nat.div(Nat.mul(Nat.sub(t1, t0), 1000n), n)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{bp, Con{ns, _}}}}:
      run(gp, bp, Maybe.default(&2, Nat, Nat.read(ns), 1n))
    case _:
      IO.print("usage: loop_bt <params_g.bin> <bundle.bin> <n>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
