# Usage: tx_main <tx.bin> <tx.ctx>
#   tx.bin: a raw v5/v6 transaction; tx.ctx: u32 len || spent-output amounts (i64 LE each)
#   || u32 len || spent-output scriptPubKeys (CompactSize-prefixed), as ZIP 244 hashes them.
# Prints the same "name hex" lines the Rust oracle writes, for a byte-for-byte diff.
import Base
import ./tx.bend as T

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def ctx_amounts(+c: +List<U32>) -> +List<U32>:
  T.at(c, 4n, U32.to_nat(T.u32_at(c, 0n)))

def ctx_scripts(+c: +List<U32>) -> +List<U32>:
  +alen = U32.to_nat(T.u32_at(c, 0n))
  +spos = (alen + 4n : Nat)
  T.at(c, (spos + 4n : Nat), U32.to_nat(T.u32_at(c, spos)))

type Paths is Type:
  Paths{tx: String, ctx: String}

def paths(xs: List<String>) -> Paths:
  match xs:
    case Con{_, Con{t, Con{c, _}}}:
      Paths{t, c}
    case _:
      Paths{"", ""}

def go(p: Paths) -> IO(Unit):
  Paths{tp, cp} = p
  do IO<Unit>:
    f : File <- IO.try(File, File.open(tp, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 4000000)
    g : File <- IO.try(File, File.open(cp, "r"))
    s : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(g, 4000000)
    +ctx : +List<U32> = bytes_of(s)
    IO.print(T.report(bytes_of(r), ctx_amounts(ctx), ctx_scripts(ctx)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
