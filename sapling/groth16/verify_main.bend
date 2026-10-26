# verify_main <vk_spend.bin> <vk_output.bin> <vk_sprout.bin> <set.bin>
# Verifies every record of set.bin (the oracle's format: u32 kind (0 Sapling spend, 1 Sapling
# output, 2 Sprout JoinSplit), u32 tag, 192-byte proof, 7 / 5 / 9 32-byte inputs) in
# parallel and prints
#   verdicts <one digit per record: 1 valid, 0 rejected at point decoding, 2 rejected by the pairing check>
#   n <records> valid <count> ms <verification time, after VK preparation>
import Base
import ./fq12.bend as T
import ./groth16.bend as V
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

def vkind(+kind: U32, +pw: +List<U32>, +ins: +List<U32>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> U32:
  match kind:
    case 0:
      V.verify(pw, ins, vs)
    case 1:
      V.verify(pw, ins, vo)
    case _:
      V.verify(pw, ins, vj)

def vrec(+x: Rec, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> U32:
  Rec{+kind, +pw, +ins} = x
  vkind(kind, pw, ins, vs, vo, vj)

# Balanced parallel tree over the records.
def par(+fuel: Nat, +cnt: Nat, +xs: +List<Rec>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> +List<U32>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      vrec(x, vs, vo, vj) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par(f, h, List.take(&2, Rec, xs, h), vs, vo, vj) par(f, Nat.sub(cnt, h), List.drop(&2, Rec, xs, h), vs, vo, vj)
      List.append(&2, U32, a, b)
    case _ _ _:
      Nil{}

def digits(xs: +List<U32>) -> String:
  match xs:
    case Con{+x, t}:
      SCon{Char.from_u32((48 + x : U32)), digits(t)}
    case Nil{}:
      SNil{}

def sum(xs: +List<U32>, +acc: Nat) -> Nat:
  match xs:
    case Con{+x, t}:
      sum(t, Nat.add(acc, U32.to_nat((x .&. 1 : U32))))
    case Nil{}:
      acc

def run(sp: String, op: String, jp: String, setp: String) -> IO(Unit):
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
    +warm : U32 = (T.eq(V.pvk_ab(vs), V.pvk_ab(vo)) + 1 : U32)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +rs : +List<U32> = par(32n, k, xs, vs, vo, vj)
    +nv : Nat = sum(rs, 0n)
    IO.print("verdicts " ++ digits(rs))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("n " ++ Nat.show(List.length(&2, U32, rs)) ++ " valid " ++ Nat.show(nv) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " warm " ++ U32.show(warm))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, _}}}}}:
      run(a, b, c, d)
    case _:
      IO.print("usage: verify_main <vk_spend.bin> <vk_output.bin> <vk_sprout.bin> <set.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
