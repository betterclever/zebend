# batch_gpu C L M chunk.bin...
#
# As batch_main, with the per-signature preparation on the GPU in leaves of L items. M = 0:
# the batch MSM on CPU threads (c = C); M > 0: on the GPU (msm_fast, c = C, 2^M chunks).
#
# Batch-verifies the RedPallas signatures of each chunk (see sig.bend; chunk format in
# oracle/src/main.rs) with c-bit MSM windows. Per chunk prints the indices of the invalid
# signatures (empty: all valid) and the verification time; reading and parsing are untimed.
import Base
import ./sig.bend as G

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
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 16777216)
    got_pair(r)

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def show_list(xs: +List<U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+x, t}:
      " " ++ U32.show(x) ++ show_list(t)

# Totals: signatures, rejected signatures, verification ms.
type Tot is Data:
  Tot{n: Nat, bad: Nat, ms: Nat}

def chunk(+c: U32, +lsz: Nat, +m: Nat, +p: String, t: Tot) -> IO(Tot):
  Tot{+n, +bad, +ms} = t
  do IO<Tot>:
    bb : List<&2, U32> <- read_all(p)
    +xs : +List<G.It> = G.parse(bb)
    +k : Nat = List.length(&2, G.It, xs)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +it : G.IT = G.gpu_tree(lsz, xs)
    +nl : Nat = G.it_leaves(it)
    tax : Nat <- IO.now()
    +ta : Nat = tax
    +pt : G.PT = G.gpu_run(it)
    +nl2 : Nat = G.pt_leaves(pt)
    tbx : Nat <- IO.now()
    +tb : Nat = tbx
    +pp : G.Pp = G.pt_flat(pt)
    +ng : Nat = G.pp_ngood(pp)
    tpx : Nat <- IO.now()
    +tp : Nat = tpx
    IO.print("  leaves " ++ Nat.show(nl2) ++ " tree_ms " ++ Nat.show(Nat.sub(ta, t0)) ++ " gpu_ms " ++ Nat.show(Nat.sub(tb, ta)) ++ " flat_ms " ++ Nat.show(Nat.sub(tp, tb)))
    +rej : +List<U32> = G.verify_m(m, c, pp)
    +nr : Nat = List.length(&2, U32, rej)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +dt : Nat = Nat.sub(t1, t0)
    IO.print("  digest " ++ G.digest(pp))
    IO.print(p ++ " n " ++ Nat.show(k) ++ " ms " ++ Nat.show(dt) ++ " prep_ms " ++ Nat.show(Nat.sub(tp, t0)) ++ " good " ++ Nat.show(ng) ++ " invalid" ++ show_list(rej))
    return Tot{(n + k : Nat), (bad + nr : Nat), (ms + dt : Nat)}

def chunks(+c: U32, +lsz: Nat, +m: Nat, ps: List<String>, t: Tot) -> IO(Tot):
  match ps:
    case Nil{}:
      IO.pure(Tot, t)
    case Con{p, rest}:
      do IO<Tot>:
        t2 : Tot <- chunk(c, lsz, m, p, t)
        chunks(c, lsz, m, rest, t2)

def report(t: Tot) -> IO(Unit):
  Tot{+n, +bad, +ms} = t
  IO.print("TOTAL signatures " ++ Nat.show(n) ++ " invalid " ++ Nat.show(bad) ++ " verify_ms " ++ Nat.show(ms) ++ " sigs_per_s " ++ Nat.show(Nat.div((n * 1000n : Nat), Nat.max(ms, 1n))))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{c, Con{l, Con{mm, rest}}}}:
      do IO<Unit>:
        t : Tot <- chunks(num(c), U32.to_nat(num(l)), U32.to_nat(num(mm)), rest, Tot{0n, 0n, 0n})
        report(t)
    case _:
      IO.print("usage: batch_gpu C L M chunk.bin...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
