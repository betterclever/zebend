# bundle_main <params_g.bin> <bundle.bin> [-v]
#
# Verifies one Orchard-protocol (Orchard or Ironwood) bundle proof against the post-NU6.3
# circuit, with everything read at runtime:
#   params_g.bin : 2^k IPA generators, 64 bytes each (affine x || y, canonical LE Fq)
#   bundle.bin   : u32 LE np (actions), u32 LE ni (instance values per action),
#                  u32 LE proof length, the proof, then np*ni instance values (32 bytes each)
# Prints `result 1` (accept) or `result 0` (reject); `-v` also prints every intermediate.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fp64.bend as Fp
import ../../../crypto/field3/fq64.bend as Fq
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vlib.bend as L
import ./orchard_bt.bend as O
import ./bt.bend as BT
import ./pio.bend as P
import ../../flatio/words.bend as FW
import ../lib/fixb.bend as FB
import ./b2.bend as B2

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

# the bundle file as little-endian words
def parse_words(+ws: +List<U32>) -> In:
  +np = U32.to_nat(w_at(0n, ws))
  +ni = U32.to_nat(w_at(1n, ws))
  +nitems = U32.to_nat((w_at(2n, ws) / 32 : U32))
  +all = items(List.drop(&2, U32, ws, 3n))
  In{L.Proof{L.pre_items(np, List.take(&2, Wd.W, all, nitems)), fps(List.drop(&2, Wd.W, all, nitems))}, np, ni}

def parse_bundle(bs: +List<U32>) -> In:
  parse_words(L.pack4(bs))

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


# Bundles that came back empty (np = 0): a file the runtime failed to read. perf3's
# batch_main reads a failed open as an empty bundle and accepts it (at K > ~4096 files);
# here any such bundle rejects the batch.
def zero_nat(n: Nat) -> U32:
  match n:
    case 0n:
      1
    case _:
      0

def zero_u32(n: U32) -> U32:
  match n:
    case 0:
      1
    case _:
      0

# 1 iff a = b. par() once dropped every bundle past 2^fuel (fuel 12: K > 4096 verified only
# 4096 and still printed `result 1`), so the verdict now also requires that every one of
# the K bundles produced a Fin.
def same(+a: Nat, +b: Nat) -> U32:
  (zero_nat(Nat.sub(a, b)) .&. zero_nat(Nat.sub(b, a)) : U32)

# One task: a bundle's raw bytes and its random weight.
type Job is Data:
  Job{bs: +List<U32>, r: Fp.Fp}

# Parse, verify (up to the IPA check) and weight one bundle. An unreadable bundle (np = 0)
# counts as bad.
def job(+j: Job, +gs: +List<V.Pt>, +tabs: +List<FB.Tab>) -> BT.Acc:
  Job{+bs, +r} = j
  +x = parse_words(bs)
  +bad = zero_nat(in_np(x))
  BT.leaf(O.verify(in_pr(x), gs, tabs, in_np(x), in_ni(x)), r, bad)

# Verify K bundles as a balanced parallel tree, merging results at the nodes. A subtree that
# runs out of fuel contributes nothing, so its bundles are missing from the count n and the
# batch is rejected (see `same`).
def par(+fuel: Nat, +cnt: Nat, +xs: +List<Job>, +gs: +List<V.Pt>, +tabs: +List<FB.Tab>) -> BT.Acc:
  match fuel cnt xs:
    case _ 0n _:
      BT.none()
    case _ 1n Con{+x, _}:
      job(x, gs, tabs)
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par(f, h, List.take(&2, Job, xs, h), gs, tabs) par(f, Nat.sub(cnt, h), List.drop(&2, Job, xs, h), gs, tabs)
      BT.join(a, b)
    case _ _ _:
      BT.none()

# Fixed-base tables for the instance commitments (G_lag_0 .. G_lag_9), built in parallel
# when the batch is large enough to repay them (about 10k mixed additions per table).
def inst_tables_b(small: Bool) -> +List<FB.Tab>:
  match small:
    case True{}:
      Nil{}
    case False{}:
      FB.make(L.fb_c(), List.take(&2, V.Pt, O.G_LAG(), 10n))

def inst_tables(+k: Nat) -> +List<FB.Tab>:
  inst_tables_b(Nat.is_lt(k, 16n))

def zip_jobs(bs: +List<+List<U32>>, rs: +List<Fp.Fp>) -> +List<Job>:
  match bs rs:
    case Con{+b, bt} Con{+r, rt}:
      Job{b, r} <> zip_jobs(bt, rt)
    case _ _:
      Nil{}

def read_bundles(ps: List<String>, acc: +List<+List<U32>>) -> IO(+List<+List<U32>>):
  match ps:
    case Nil{}:
      IO.pure(+List<+List<U32>>, List.reverse(&2, +List<U32>, acc))
    case Con{p, t}:
      do IO<+List<+List<U32>>>:
        r : Array<U32> & U32 <- FW.load(p)
        read_bundles(t, P.words_of(r) <> acc)

# --- reading the bundle files on several IO threads ----------------------------------------
# Each file costs several IO effects (open, size, read, close); read one after another they
# took ~0.3 ms per file (1.2 s for 3,840). Groups of files are read by IO.fork'd actions and
# joined in order.

# the paths in groups of `size`, in order
def grp(xs: List<String>, +size: Nat, +left: Nat, cur: List<String>, acc: List<List<String>>) -> List<List<String>>:
  match xs left:
    case Nil{} _:
      List.reverse(&1, List<String>, List.reverse(&1, String, cur) <> acc)
    case Con{x, t} 0n:
      grp(t, size, Nat.sub(size, 1n), x <> Nil{}, List.reverse(&1, String, cur) <> acc)
    case Con{x, t} 1n+k:
      grp(t, size, k, x <> cur, acc)

def fork_reads(gs: List<List<String>>) -> IO(List<Chan(+List<+List<U32>>)>):
  match gs:
    case Nil{}:
      IO.pure(List<Chan(+List<+List<U32>>)>, Nil{})
    case Con{g, t}:
      do IO<List<Chan(+List<+List<U32>>)>>:
        c : Chan(+List<+List<U32>>) <- IO.fork(+List<+List<U32>>, read_bundles(g, Nil{}))
        cs : List<Chan(+List<+List<U32>>)> <- fork_reads(t)
        return c <> cs

def join_reads(cs: List<Chan(+List<+List<U32>>)>) -> IO(+List<+List<U32>>):
  match cs:
    case Nil{}:
      IO.pure(+List<+List<U32>>, Nil{})
    case Con{c, t}:
      do IO<+List<+List<U32>>>:
        a : +List<+List<U32>> <- IO.join(+List<+List<U32>>, c)
        b : +List<+List<U32>> <- join_reads(t)
        return List.append(&2, +List<U32>, a, b)

# groups of 64 files
def read_par(ps: List<String>) -> IO(+List<+List<U32>>):
  do IO<+List<+List<U32>>>:
    cs : List<Chan(+List<+List<U32>>)> <- fork_reads(grp(ps, 64n, 64n, Nil{}, Nil{}))
    join_reads(cs)

# Random weights r_i (128 bits each). r_i = the low 128 bits of BLAKE2b(seed || i) with a
# 256-bit seed from the OS (IO.random_u32), so a batch of K needs 8 random reads, not 4K.
type Seed is Data:
  Seed{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

def low128(+o: B2.H8) -> Fp.Fp:
  B2.H8{+h0, +h1, +h2, +h3, _, _, _, _, _, _, _, _, _, _, _, _} = o
  Fp.from_words(Wd.W{h0, h1, h2, h3, 0, 0, 0, 0})

def prf(+s: Seed, +i: U32) -> Fp.Fp:
  Seed{+a, +b, +c, +d, +e, +f, +g, +h} = s
  low128(B2.b2_compress(L.tr_h(L.tr_init()), B2.M16{a, b, c, d, e, f, g, h, i, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 36, 1))

def weights_go(n: Nat, +s: Seed, +i: U32) -> +List<Fp.Fp>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      prf(s, i) <> weights_go(k, s, (i + 1 : U32))

def weights(n: Nat) -> IO(+List<Fp.Fp>):
  do IO<+List<Fp.Fp>>:
    a : U32 <- IO.try(U32, IO.random_u32())
    b : U32 <- IO.try(U32, IO.random_u32())
    c : U32 <- IO.try(U32, IO.random_u32())
    d : U32 <- IO.try(U32, IO.random_u32())
    e : U32 <- IO.try(U32, IO.random_u32())
    f : U32 <- IO.try(U32, IO.random_u32())
    g : U32 <- IO.try(U32, IO.random_u32())
    h : U32 <- IO.try(U32, IO.random_u32())
    return weights_go(n, Seed{a, b, c, d, e, f, g, h}, 0)

def run(+gpath: String, bpaths: List<String>) -> IO(Unit):
  do IO<Unit>:
    tsx : Nat <- IO.now()
    +ts : Nat = tsx
    +gs : +List<V.Pt> <- P.params(gpath)
    ot : P.OT <- P.load_opt(gpath ++ ".gtab")
    +crs : +List<U32> <- P.rands(32n, Nil{})
    +raw : +List<+List<U32>> <- read_par(bpaths)
    +k : Nat = List.length(&2, +List<U32>, raw)
    +rs : +List<Fp.Fp> <- weights(k)
    +warm : U32 = BT.is_id(V.identity())
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +tabs : +List<FB.Tab> = inst_tables(k)
    +acc : BT.Acc = par(32n, k, zip_jobs(raw, rs), gs, tabs)
    +nv : Nat = BT.acc_n(acc)
    tpx : Nat <- IO.now()
    +tp : Nat = tpx
    +bad : U32 = (BT.acc_bad(acc) + 1 - same(nv, k) : U32)
    +cv : U32 = BT.check_opt(acc, gs, O.FIXED_PTS(), ot, crs)
    +ok : U32 = (cv .&. 1 .&. zero_u32(bad) : U32)
    IO.print("verified " ++ Nat.show(nv) ++ " unreadable_or_missing " ++ U32.show(bad))
    IO.print("batch K " ++ Nat.show(k) ++ " result " ++ U32.show(ok))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +dt : Nat = Nat.sub(t1, t0)
    IO.print("batch_ms " ++ Nat.show(dt) ++ " per_bundle_ms " ++ Nat.show(Nat.div(dt, k)) ++ " warm " ++ U32.show(warm))
    IO.print("gtab " ++ U32.show((cv >> 1n : U32)) ++ " read_ms " ++ Nat.show(Nat.sub(t0, ts)) ++ " proofs_ms " ++ Nat.show(Nat.sub(tp, t0)) ++ " final_ms " ++ Nat.show(Nat.sub(t1, tp)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{gp, rest}}:
      run(gp, rest)
    case _:
      IO.print("usage: batch_main <params_g.bin> <bundle.bin>...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
