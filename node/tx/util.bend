# Byte-list helpers shared by the transaction layer. Bytes are U32 values in 0..255.
import Base
import ../../halo2/lib/words.bend as Wd

def bhex(xs: +List<U32>) -> String:
  match xs:
    case Con{b, t}:
      String.append(Wd.hex_byte(b), bhex(t))
    case Nil{}:
      ""

def gen(+k: Nat, +j: U32, acc: +List<U32>) -> +List<U32>:
  match k:
    case 0n:
      acc
    case 1n+p:
      gen(p, (j - 1 : U32), (((j - 1 : U32) * 7 + 3 : U32) % 256 : U32) <> acc)

# The test pattern byte[j] = (7j + 3) mod 256, for j < n.
def pattern(+n: U32) -> +List<U32>:
  gen(U32.to_nat(n), n, Nil{})
