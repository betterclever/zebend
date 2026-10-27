# ed_main <set.bin>
# Verifies every record of set.bin (u32 count, then per record: pk 32 | sig 64 | msg_len u32 |
# msg; little-endian) with ed25519.bend (ZIP 215) in parallel and prints
#   verdicts <one digit per record: 1 valid, 0 invalid>
#   n <records> valid <count> ms <verification time>
import Base
import ./ed25519.bend as E

type Rec is Data:
  Rec{pk: +List<U32>, sig: +List<U32>, msg: +List<U32>}

def recs(fuel: Nat, +bs: +List<U32>) -> +List<Rec>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      +ml = E.get_le32(E.drop(bs, 96n))
      +rest = E.drop(bs, 100n)
      Rec{E.take(bs, 32n), E.take(E.drop(bs, 32n), 64n), E.take(rest, U32.to_nat(ml))} <> recs(f, E.drop(rest, U32.to_nat(ml)))

def bit(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def vrec(+x: Rec) -> U32:
  Rec{+pk, +sig, +msg} = x
  bit(E.verify(pk, sig, msg))

# Balanced parallel tree over the records.
def par(+fuel: Nat, +cnt: Nat, +xs: +List<Rec>) -> +List<U32>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      vrec(x) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par(f, h, List.take(&2, Rec, xs, h)) par(f, Nat.sub(cnt, h), List.drop(&2, Rec, xs, h))
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
      sum(t, Nat.add(acc, U32.to_nat(x)))
    case Nil{}:
      acc

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
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 268435456)
    got_pair(r)

def run(setp: String) -> IO(Unit):
  do IO<Unit>:
    rb : List<&2, U32> <- read_all(setp)
    +bs : +List<U32> = rb
    +n : Nat = U32.to_nat(E.get_le32(bs))
    +xs : +List<Rec> = recs(n, E.drop(bs, 4n))
    +k : Nat = List.length(&2, Rec, xs)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +rs : +List<U32> = par(32n, k, xs)
    +nv : Nat = sum(rs, 0n)
    IO.print("verdicts " ++ digits(rs))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("n " ++ Nat.show(List.length(&2, U32, rs)) ++ " valid " ++ Nat.show(nv) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, _}}:
      run(a)
    case _:
      IO.print("usage: ed_main <set.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
