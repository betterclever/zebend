# zebend follow: node/tx's transaction report plus what the follower needs to route data.
# Usage: txx <tx.bin> <tx.ctx>
#   Prints node/tx's report (txid, sighash, RedPallas verdicts, Halo 2 public inputs), then
#   each Orchard-protocol bundle's proof bytes ("<pool>.proof <hex>") and every transparent
#   input's outpoint ("vin <i> <prevout txid, internal order> <index>"), so the driver never
#   has to parse transaction bytes to find them.
import Base
import ../node/tx/tx.bend as T

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

# A bundle's proof sits after flags (1) || valueBalance (8) || anchor (32), CompactSize-prefixed.
def proof_line(any: Bool, +xs: +List<U32>, b: T.Bnd) -> String:
  match any:
    case True{}:
      T.Bnd{+f, _, _, +tail, _, _} = b
      +off = (tail + 41n : Nat)
      T.line(T.pool_name(f) ++ ".proof", T.at(xs, (off + T.cs_size(xs, off) : Nat), T.cs_val(xs, off)))
    case False{}:
      ""

def vin_lines(k: Nat, +i: Nat, +xs: +List<U32>, +pos: Nat) -> String:
  match k:
    case 0n:
      ""
    case 1n+p:
      +sp = (pos + 36n : Nat)
      +next = (((sp + T.cs_size(xs, sp) : Nat) + T.cs_val(xs, sp) : Nat) + 4n : Nat)
      T.line("vin " ++ Nat.show(i), T.at(xs, pos, 32n)) ++ T.nline("vin " ++ Nat.show(i) ++ " index", U32.to_nat(T.u32_at(xs, (pos + 32n : Nat))))
        ++ vin_lines(p, (i + 1n : Nat), xs, next)

def extras(+xs: +List<U32>, tx: T.Tx) -> String:
  T.Tx{_, _, +nvin, +vin0, _, _, _, +orch, +iron} = tx
  vin_lines(nvin, 0n, xs, vin0) ++ proof_line(T.nat_pos(T.bnd_n(orch)), xs, orch) ++ proof_line(T.nat_pos(T.bnd_n(iron)), xs, iron)

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
    +xs : +List<U32> = bytes_of(r)
    IO.print(T.report(xs, ctx_amounts(ctx), ctx_scripts(ctx)) ++ extras(xs, T.parse(xs)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
