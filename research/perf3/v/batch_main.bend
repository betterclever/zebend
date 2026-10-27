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
import ../fp32.bend as Fp
import ../fq32.bend as Fq
import ../lib32/vesta.bend as V
import ./vlib.bend as L
import ./orchard_bt.bend as O
import ./bt.bend as BT

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

def empties(xs: +List<In>, n: U32) -> U32:
  match xs:
    case Con{+x, t}:
      empties(t, (n + zero_nat(in_np(x)) : U32))
    case Nil{}:
      n

def vfin(+x: In, +gs: +List<V.Pt>) -> BT.Fin:
  O.verify(in_pr(x), gs, in_np(x), in_ni(x))

# Verify K bundles (up to the IPA check) as a balanced parallel tree.
def par(+fuel: Nat, +cnt: Nat, +xs: +List<In>, +gs: +List<V.Pt>) -> +List<BT.Fin>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      vfin(x, gs) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par(f, h, List.take(&2, In, xs, h), gs) par(f, Nat.sub(cnt, h), List.drop(&2, In, xs, h), gs)
      List.append(&2, BT.Fin, a, b)
    case _ _ _:
      Nil{}

def read_bundles(ps: List<String>, acc: +List<In>) -> IO(+List<In>):
  match ps:
    case Nil{}:
      IO.pure(+List<In>, List.reverse(&2, In, acc))
    case Con{p, t}:
      do IO<+List<In>>:
        bb : List<&2, U32> <- read_all(p)
        read_bundles(t, parse_bundle(bb) <> acc)

def weights(n: Nat, acc: +List<Fp.Fp>) -> IO(+List<Fp.Fp>):
  match n:
    case 0n:
      IO.pure(+List<Fp.Fp>, acc)
    case 1n+k:
      do IO<+List<Fp.Fp>>:
        a : U32 <- IO.try(U32, IO.random_u32())
        b : U32 <- IO.try(U32, IO.random_u32())
        c : U32 <- IO.try(U32, IO.random_u32())
        d : U32 <- IO.try(U32, IO.random_u32())
        weights(k, Fp.from_words(Wd.W{a, b, c, d, 0, 0, 0, 0}) <> acc)

def run(gpath: String, bpaths: List<String>) -> IO(Unit):
  do IO<Unit>:
    gb : List<&2, U32> <- read_all(gpath)
    +gs : +List<V.Pt> = points(items(L.pack4(gb)))
    +xs : +List<In> <- read_bundles(bpaths, Nil{})
    +k : Nat = List.length(&2, In, xs)
    +rs : +List<Fp.Fp> <- weights(k, Nil{})
    +warm : U32 = BT.is_id(V.identity())
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +fs : +List<BT.Fin> = par(32n, k, xs, gs)
    +nv : Nat = List.length(&2, BT.Fin, fs)
    +bad : U32 = (empties(xs, 0) + 1 - same(nv, k) : U32)
    +ok : U32 = (BT.batch(fs, rs, gs) .&. zero_u32(bad) : U32)
    IO.print("verified " ++ Nat.show(nv) ++ " unreadable_or_missing " ++ U32.show(bad))
    IO.print("batch K " ++ Nat.show(k) ++ " result " ++ U32.show(ok))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +dt : Nat = Nat.sub(t1, t0)
    IO.print("batch_ms " ++ Nat.show(dt) ++ " per_bundle_ms " ++ Nat.show(Nat.div(dt, k)) ++ " warm " ++ U32.show(warm))

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
