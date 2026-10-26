# batch_main <vk_spend.bin> <vk_output.bin> <vk_sprout.bin> <set.bin> [chunk]
# Batch verification of every record of set.bin (verify_main's format). Records are split
# into chunks (default 128) verified in parallel; in each chunk the proofs that decode are
# batch-verified per kind with random 128-bit weights. A chunk whose batch fails is
# re-verified proof by proof, so every record still gets its own verdict:
#   verdicts <digit per record: 1 valid, 0 rejected at decoding, 2 rejected by the pairing check>
#   n <records> valid <count> ms <time> batches <run> failed <batches that fell back>
import Base
import ./fq12.bend as T
import ./groth16.bend as V
import ./batch.bend as BV
import ./io.bend as IO2

type Rec is Data:
  Rec{kind: U32, pw: +List<U32>, ins: +List<U32>}

def rlen(+kind: U32) -> Nat:
  match kind:
    case 0:
      106n
    case 1:
      90n
    case _:
      122n

def recs(fuel: Nat, +ws: +List<U32>) -> +List<Rec>:
  match fuel ws:
    case 1n+k Con{+kind, _}:
      +r = List.drop(&2, U32, ws, 2n)
      Rec{kind, List.take(&2, U32, r, 48n), List.drop(&2, U32, r, 48n)} <> recs(k, List.drop(&2, U32, ws, rlen(kind)))
    case _ _:
      Nil{}

# A record with its weight and decoded proof.
type RD is Data:
  RD{kind: U32, z: +List<U32>, d: V.Dec, ins: +List<U32>}

def rd_of(x: Rec, +z: +List<U32>) -> RD:
  Rec{+kind, +pw, +ins} = x
  RD{kind, z, V.decode(pw), ins}

def rds(xs: +List<Rec>, +zs: +List<U32>) -> +List<RD>:
  match xs:
    case Con{+x, t}:
      rd_of(x, List.take(&2, U32, zs, 4n)) <> rds(t, List.drop(&2, U32, zs, 4n))
    case Nil{}:
      Nil{}

def it_if(b: Bool, +z: +List<U32>, +d: V.Dec, +ins: +List<U32>, rest: +List<BV.It>) -> +List<BV.It>:
  match b:
    case True{}:
      BV.It{z, d, ins} <> rest
    case False{}:
      rest

# The decoded proofs of one kind, as batch items.
def items(xs: +List<RD>, +k: U32) -> +List<BV.It>:
  match xs:
    case Con{RD{+kind, +z, +d, +ins}, t}:
      it_if(Bool.and(U32.is_eq(kind, k), U32.is_eq(V.dec_ok(d), 1)), z, d, ins, items(t, k))
    case _:
      Nil{}

def pick(+kind: U32, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> V.PVK:
  match kind:
    case 0:
      vs
    case 1:
      vo
    case _:
      vj

def okk(+kind: U32, +os: U32, +oo: U32, +oj: U32) -> U32:
  match kind:
    case 0:
      os
    case 1:
      oo
    case _:
      oj

# Per record: not decoded -> 0; its kind's batch held -> 1; else single verification.
def verd(+ok: U32, +bok: U32, +d: V.Dec, +ins: +List<U32>, +v: V.PVK) -> U32:
  match ok bok:
    case 0 _:
      0
    case _ 0:
      V.verify_dec(d, ins, v)
    case _ _:
      1

def verdicts(xs: +List<RD>, +os: U32, +oo: U32, +oj: U32, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  match xs:
    case Con{RD{+kind, _, +d, +ins}, t}:
      verd(V.dec_ok(d), okk(kind, os, oo, oj), d, ins, pick(kind, vs, vo, vj)) <> verdicts(t, os, oo, oj, vs, vo, vj)
    case _:
      Nil{}

# (batch failures in this chunk) followed by the chunk's verdicts
def chunk3(+xs: +List<RD>, +os: U32, +oo: U32, +oj: U32, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  (3 - os - oo - oj : U32) <> verdicts(xs, os, oo, oj, vs, vo, vj)

def chunk2(+xs: +List<RD>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  chunk3(xs, BV.batch(items(xs, 0), vs), BV.batch(items(xs, 1), vo), BV.batch(items(xs, 2), vj), vs, vo, vj)

def chunk(+xs: +List<Rec>, +zs: +List<U32>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  chunk2(rds(xs, zs), vs, vo, vj)

type Ck is Data:
  Ck{xs: +List<Rec>, zs: +List<U32>}

def chunks(fuel: Nat, +c: Nat, +xs: +List<Rec>, +zs: +List<U32>) -> +List<Ck>:
  match fuel xs:
    case 1n+k Con{_, _}:
      Ck{List.take(&2, Rec, xs, c), List.take(&2, U32, zs, Nat.mul(4n, c))} <> chunks(k, c, List.drop(&2, Rec, xs, c), List.drop(&2, U32, zs, Nat.mul(4n, c)))
    case _ _:
      Nil{}

def run_ck(x: Ck, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  Ck{+xs, +zs} = x
  chunk(xs, zs, vs, vo, vj)

# Balanced parallel tree over chunks; each result list is [failures, verdicts...].
def par(+fuel: Nat, +cnt: Nat, +xs: +List<Ck>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<+List<U32>>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      run_ck(x, vs, vo, vj) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par(f, h, List.take(&2, Ck, xs, h), vs, vo, vj) par(f, Nat.sub(cnt, h), List.drop(&2, Ck, xs, h), vs, vo, vj)
      List.append(&2, +List<U32>, a, b)
    case _ _ _:
      Nil{}

def digits(xs: +List<U32>) -> String:
  match xs:
    case Con{+x, t}:
      SCon{Char.from_u32((48 + x : U32)), digits(t)}
    case Nil{}:
      SNil{}

def all_digits(xs: +List<+List<U32>>) -> String:
  match xs:
    case Con{Con{_, +vs}, t}:
      digits(vs) ++ all_digits(t)
    case _:
      SNil{}

def fails(xs: +List<+List<U32>>, +acc: Nat) -> Nat:
  match xs:
    case Con{Con{+f, _}, t}:
      fails(t, Nat.add(acc, U32.to_nat(f)))
    case _:
      acc

def count1(s: String, +acc: Nat) -> Nat:
  match s:
    case SCon{+c, t}:
      count1(t, Nat.add(acc, U32.to_nat(Bool.to_u32(U32.is_eq(Char.to_u32(c), 49)))))
    case SNil{}:
      acc

def rand(n: Nat, acc: +List<U32>) -> IO(+List<U32>):
  match n:
    case 0n:
      IO.pure(+List<U32>, acc)
    case 1n+k:
      do IO<+List<U32>>:
        a : U32 <- IO.try(U32, IO.random_u32())
        rand(k, a <> acc)

# low bit forced: z != 0
def nonzero(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Con{+a, Con{+b, Con{+c, Con{+d, t}}}}:
      (a .|. 1 : U32) <> b <> c <> d <> nonzero(t)
    case _:
      Nil{}

def run(sp: String, op: String, jp: String, setp: String, +c: Nat) -> IO(Unit):
  do IO<Unit>:
    sb : List<&2, U32> <- IO2.read_all(sp)
    ob : List<&2, U32> <- IO2.read_all(op)
    jb : List<&2, U32> <- IO2.read_all(jp)
    rb : List<&2, U32> <- IO2.read_all(setp)
    +vs : V.PVK = V.prepare_vk(IO2.pack4(sb))
    +vo : V.PVK = V.prepare_vk(IO2.pack4(ob))
    +vj : V.PVK = V.prepare_vk(IO2.pack4(jb))
    +ws : +List<U32> = IO2.pack4(rb)
    +xs : +List<Rec> = recs(List.length(&2, U32, ws), ws)
    +k : Nat = List.length(&2, Rec, xs)
    zr : +List<U32> <- rand(Nat.mul(4n, k), Nil{})
    +zs : +List<U32> = nonzero(zr)
    +warm : U32 = (T.eq(V.pvk_ab(vs), V.pvk_ab(vo)) + 1 : U32)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +cks : +List<Ck> = chunks(k, c, xs, zs)
    +rs : +List<+List<U32>> = par(32n, List.length(&2, Ck, cks), cks, vs, vo, vj)
    +ds : String = all_digits(rs)
    +nv : Nat = count1(ds, 0n)
    IO.print("verdicts " ++ ds)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("n " ++ Nat.show(String.length(ds)) ++ " valid " ++ Nat.show(nv) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " chunks " ++ Nat.show(List.length(&2, Ck, cks)) ++ " failed " ++ Nat.show(fails(rs, 0n)) ++ " warm " ++ U32.show(warm))

def pnat(s: String, +acc: Nat) -> Nat:
  match s:
    case SCon{+c, t}:
      pnat(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((Char.to_u32(c) - 48 : U32))))
    case SNil{}:
      acc

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, Con{b, Con{j, Con{c, Nil{}}}}}}:
      run(a, b, j, c, 128n)
    case Con{_, Con{a, Con{b, Con{j, Con{c, Con{n, _}}}}}}:
      run(a, b, j, c, pnat(n, 0n))
    case _:
      IO.print("usage: batch_main <vk_spend.bin> <vk_output.bin> <vk_sprout.bin> <set.bin> [chunk]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
