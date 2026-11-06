# loop_batch <params_g.bin> <n> <bundle.bin>...: runs the whole batch check (proofs + final MSM)
# n times in-process on the given bundles (for latency profiling; no process start-up).
# Uses <params_g.bin>.gtab when present.
import Base
import ../../../crypto/field3/fp64.bend as Fp
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vlib.bend as L
import ./orchard_bt.bend as O
import ./bt.bend as BT
import ./pio.bend as P
import ../lib/fixb.bend as FB
import ./batch_main.bend as B

def once(+raw: +List<+List<U32>>, +rs: +List<Fp.Fp>, +gs: +List<V.Pt>, +crs: +List<U32>, ot: P.OT) -> U32:
  +k = List.length(&2, +List<U32>, raw)
  +acc = B.par(32n, k, B.zip_jobs(raw, rs), gs, B.inst_tables(k))
  (BT.check_opt(acc, gs, O.FIXED_PTS(), ot, crs) .&. 1 : U32)

def loop_t(n: Nat, +raw: +List<+List<U32>>, +rs: +List<Fp.Fp>, +gs: +List<V.Pt>, +crs: +List<U32>, +sz: U32, +acc: U32, p: Array<U32> & Array<U32>) -> U32:
  match n:
    case 0n:
      (t1, t2) = p
      acc
    case 1n+m:
      (t1, t2) = p
      loop_t(m, raw, rs, gs, crs, sz, (acc + once(raw, rs, gs, crs, P.OSome{t1, sz}) : U32), Array.fork(U32, t2))

def loop_n(n: Nat, +raw: +List<+List<U32>>, +rs: +List<Fp.Fp>, +gs: +List<V.Pt>, +crs: +List<U32>, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+m:
      loop_n(m, raw, rs, gs, crs, (acc + once(raw, rs, gs, crs, P.ONone{}) : U32))

def loop(n: Nat, +raw: +List<+List<U32>>, +rs: +List<Fp.Fp>, +gs: +List<V.Pt>, +crs: +List<U32>, ot: P.OT) -> U32:
  match ot:
    case P.ONone{}:
      loop_n(n, raw, rs, gs, crs, 0)
    case P.OSome{t, sz}:
      loop_t(n, raw, rs, gs, crs, sz, 0, Array.fork(U32, t))

def run(+gpath: String, +n: Nat, bpaths: List<String>) -> IO(Unit):
  do IO<Unit>:
    +gs : +List<V.Pt> <- P.params(gpath)
    ot : P.OT <- P.load_opt(gpath ++ ".gtab")
    +crs : +List<U32> <- P.rands(32n, Nil{})
    +raw : +List<+List<U32>> <- B.read_bundles(bpaths, Nil{})
    +k : Nat = List.length(&2, +List<U32>, raw)
    +rs : +List<Fp.Fp> <- B.weights(k)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +ok : U32 = loop(n, raw, rs, gs, crs, ot)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("ok " ++ U32.show(ok) ++ "/" ++ Nat.show(n) ++ " K " ++ Nat.show(k) ++ " per_batch_us " ++ Nat.show(Nat.div(Nat.mul(Nat.sub(t1, t0), 1000n), n)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, Con{ns, rest}}}:
      run(gp, Maybe.default(&2, Nat, Nat.read(ns), 1n), rest)
    case _:
      IO.print("usage: loop_batch <params_g.bin> <n> <bundle.bin>...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
