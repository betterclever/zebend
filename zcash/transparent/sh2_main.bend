# sh FILE.ztv: debugging aid. For every input prints the sighash Bend computes for hash types
# 01 02 03 81 82 83 ("NONE" when the check would fail), with script code = the redeem script
# (last push of the scriptSig) for P2SH outputs, else the scriptPubKey:
#   r <k> in <i> ht <xx> <hex|NONE>
import Base
import ./util.bend as U
import ./sighash2/sighash.bend as SH
import ./script/interp.bend as I

def lp_take(+b: U32, +rest: +List<U32>) -> +List<U32>:
  +k = I.size_bytes(b)
  +sz = Bool.pick(U32, U32.is_le(b, 75), b, U.le32(U.take(rest, k)))
  U.take(U.drop(rest, k), U32.to_nat(sz))

def lp_next(+b: U32, +rest: +List<U32>) -> +List<U32>:
  +k = I.size_bytes(b)
  +sz = Bool.pick(U32, U32.is_le(b, 75), b, U.le32(U.take(rest, k)))
  U.drop(U.drop(rest, k), U32.to_nat(sz))

# The data of the last push (scripts here are push-only scriptSigs).
def last_push(fuel: Nat, +code: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match code:
        case Nil{}:
          acc
        case Con{+b, rest}:
          last_push(p, Bool.pick(+List<U32>, U32.is_le(b, 78), lp_next(b, rest), rest),
            Bool.pick(+List<U32>, U32.is_le(b, 78), lp_take(b, rest), Bool.pick(+List<U32>, U32.is_ge(b, 81) && U32.is_le(b, 96), (b - 80 : U32) <> Nil{}, Nil{})))

def sh_str(m: Maybe<&2, +List<U32>>) -> String:
  match m:
    case Some{h}:
      U.hex(h)
    case None{}:
      "NONE"

def one(+tx: SH.Tx, +pre: String, +i: Nat, +sc: +List<U32>, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> String:
  pre ++ " ht " ++ U.hex(ht <> Nil{}) ++ " " ++ sh_str(SH.sighash(tx, i, sc, spk, amount, ht)) ++ "\n"

def go_ins(xs: List<&2, SH.TxIn>, +i: Nat, +prevs: +List<U32>, +tx: SH.Tx, +k: U32) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+inp, t}:
      +n = U32.to_nat(U.u32_at(prevs, 8n))
      +spk = U.at(prevs, 12n, n)
      +sig = SH.in_script(inp)
      +sc = Bool.pick(+List<U32>, I.is_p2sh(spk), last_push(U.nlen(sig), sig, Nil{}), spk)
      +am = U.take(prevs, 8n)
      +pre = "r " ++ U32.show(k) ++ " in " ++ Nat.show(i)
      one(tx, pre, i, sc, spk, am, 1) ++ one(tx, pre, i, sc, spk, am, 2) ++ one(tx, pre, i, sc, spk, am, 3)
        ++ one(tx, pre, i, sc, spk, am, 129) ++ one(tx, pre, i, sc, spk, am, 130) ++ one(tx, pre, i, sc, spk, am, 131)
        ++ go_ins(t, 1n+i, U.drop(prevs, (12n + n : Nat)), tx, k)

def prevs_len(n: Nat, +ps: +List<U32>, +acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+p:
      +k = (12n + U32.to_nat(U.u32_at(ps, 8n)) : Nat)
      prevs_len(p, U.drop(ps, k), (acc + k : Nat))

def go(n: Nat, +k: U32, +xs: +List<U32>) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      +txlen = U32.to_nat(U.u32_at(xs, 8n))
      +tx = U.at(xs, 12n, txlen)
      +after = U.drop(xs, (12n + txlen : Nat))
      +pr = U.drop(after, 4n)
      +plen = prevs_len(U32.to_nat(U.u32_at(after, 0n)), pr, 0n)
      +prevs = U.take(pr, plen)
      +t = SH.parse(tx, U.u32_at(xs, 0n), prevs)
      go_ins(SH.tx_ins(t), 0n, prevs, t, k) ++ go(p, (k + 1 : U32), U.drop(pr, plen))

def path1(xs: List<String>) -> String:
  match xs:
    case Con{_, Con{a, _}}:
      a
    case _:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(path1(args), "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 200000000)
    +bs : +List<U32> = U.bytes_of(r)
    IO.print(go(U32.to_nat(U.u32_at(bs, 4n)), 0, U.drop(bs, 8n)))
