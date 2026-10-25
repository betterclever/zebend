# Anchor validity for real mainnet Ironwood transactions, in Bend.
#   ./anchors_main ../../node/state/out/cmx.bin window_heights.bin
# 1. Frontier of the Ironwood tree after the first n0 leaves, from parallel subtree roots
#    (one complete subtree per set bit of n0).
# 2. Replay the window's leaves block by block, recording the root at the end of each block.
# 3. For each transaction, H.find a history entry with root == anchor in an earlier block.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../node/state/sinsemilla.bend as S
import ./hist.bend as H
import ./inputs.bend as I

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_of(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_of(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def ws_of(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_of(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      acc

def bytes_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> List<&2, U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def leaves_of(bs: List<&2, U32>) -> +List<Wd.W>:
  List.reverse(&2, Wd.W, ws_of(List.reverse(&2, U32, words_of(bs, Nil{})), Nil{}))

def u32s_of(bs: List<&2, U32>) -> +List<U32>:
  List.reverse(&2, U32, words_of(bs, Nil{}))

# --- frontier from parallel subtree roots ------------------------------------------

def subtree(+l: Nat, +start: Nat, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> Wd.W:
  S.subroot(l, S.ltree(l, List.take(&2, Wd.W, List.drop(&2, Wd.W, leaves, start), Nat.pow(2n, l))), g, es)

# Level l holds a pending left sibling iff bit l of n is set: the complete subtree of 2^l
# leaves starting at floor(n / 2^(l+1)) * 2^(l+1).
def om(bit: Nat, +l: Nat, +n: Nat, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> Maybe<&2, Wd.W>:
  match bit:
    case 0n:
      None{}
    case 1n+_:
      +blk = Nat.pow(2n, 1n+l)
      Some{subtree(l, Nat.mul(Nat.div(n, blk), blk), leaves, g, es)}

def ommers(k: Nat, +l: Nat, +n: Nat, +leaves: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> +List<Maybe<&2, Wd.W>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      om(Nat.mod(Nat.div(n, Nat.pow(2n, l)), 2n), l, n, leaves, g, es) <> ommers(p, 1n+l, n, leaves, g, es)

# --- block-by-block replay -----------------------------------------------------------

def is_last(+h: U32, hs: +List<U32>) -> Bool:
  match hs:
    case Nil{}:
      True{}
    case Con{n, _}:
      U32.is_ne(n, h)

def add_if(c: Bool, +h: U32, +f: +List<Maybe<&2, Wd.W>>, +g: S.Gens, +es: +List<Wd.W>, acc: +List<H.HE>) -> +List<H.HE>:
  match c:
    case True{}:
      H.HE{U32.to_nat(h), S.froot(f, 0n, None{}, g, es)} <> acc
    case False{}:
      acc

def replay(ls: +List<Wd.W>, hs: +List<U32>, +f: +List<Maybe<&2, Wd.W>>, +g: S.Gens, +es: +List<Wd.W>, acc: +List<H.HE>) -> +List<H.HE>:
  match ls hs:
    case Con{w, lt} Con{+h, +ht}:
      +f2 = S.push(f, 0n, w, g)
      replay(lt, ht, f2, g, es, add_if(is_last(h, ht), h, f2, g, es, acc))
    case _ _:
      acc

# --- output --------------------------------------------------------------------------

def he_line(e: H.HE) -> String:
  H.HE{h, r} = e
  Nat.show(h) ++ " " ++ Wd.hex(r)

def print_hist(xs: +List<H.HE>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{e, rest}:
      do IO<Unit>:
        IO.print("hist " ++ he_line(e))
        print_hist(rest)

def verdict(m: Maybe<&2, H.HE>) -> String:
  match m:
    case Some{e}:
      H.HE{h, _} = e
      "VALID: equals the tree root at the end of block " ++ Nat.show(h)
    case None{}:
      "INVALID: no earlier block ends with this root"

def check(txs: +List<I.Tx>, +hist: +List<H.HE>) -> IO(Unit):
  match txs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{t, rest}:
      I.Tx{name, +height, +anchor} = t
      do IO<Unit>:
        IO.print("anchor " ++ name ++ " (block " ++ Nat.show(height) ++ ") " ++ Wd.hex(anchor) ++ ": " ++ verdict(H.find(hist, anchor, height)))
        check(rest, hist)

def run(lb: List<&2, U32>, hb: List<&2, U32>) -> IO(Unit):
  +leaves : +List<Wd.W> = leaves_of(lb)
  +hs : +List<U32> = u32s_of(hb)
  +g : S.Gens = S.gens()
  +es : +List<Wd.W> = S.empties(g)
  +n0 : Nat = U32.to_nat(I.n0())
  +f0 : +List<Maybe<&2, Wd.W>> = ommers(32n, 0n, n0, leaves, g, es)
  +win : +List<Wd.W> = List.drop(&2, Wd.W, leaves, n0)
  +hist : +List<H.HE> = H.HE{I.activation_minus_1(), S.nth(es, 32n)} <> List.reverse(&2, H.HE, replay(win, hs, f0, g, es, Nil{}))
  do IO<Unit>:
    IO.print("leaves " ++ Nat.show(List.length(&2, Wd.W, leaves)) ++ ", frontier after " ++ Nat.show(n0) ++ ", window leaves " ++ Nat.show(List.length(&2, U32, hs)))
    print_hist(hist)
    check(I.txs(), hist)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    fl : File <- IO.try(File, File.open("../../node/state/out/cmx.bin", "r"))
    rl : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(fl, (I.leaf_count() * 32 : U32))
    fh : File <- IO.try(File, File.open("window_heights.bin", "r"))
    rh : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(fh, 1048576)
    run(bytes_of(rl), bytes_of(rh))
