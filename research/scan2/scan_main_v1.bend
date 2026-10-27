# Batch trial decryption (scan2: 64-bit fields, prepared ivk, GLV, batched inversion): reads vectors/out/batch_N.bin (ivk || N x (epk || ct[0..4])),
# spreads the outputs over a balanced tree of 2^depth leaves, and runs the filter on
# every leaf in parallel: `scan!` on the GPU (Metal), or `+RTS --gpu off` on CPU threads.
#
#   ./scan_main <batch.bin> <depth> <N>
import Base
import ../../zcash/halo2/lib/words.bend as Wd
import ./scan_v1.bend as Z

# --- bytes -> words -----------------------------------------------------------

def words(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}:
      words(rest, (b0 .|. (b1 << 8n) .|. (b2 << 16n) .|. (b3 << 24n) : U32) <> acc)
    case _:
      acc

def rev(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Con{h, t}:
      rev(t, h <> acc)
    case Nil{}:
      acc

# --- words -> leaves of `per` records ------------------------------------------

type LList is Data:
  LNil{}
  LCons{+rs: Z.Recs, next: LList}

type St is Data:
  St{+left: U32, +per: U32, cur: Z.Recs, leaves: LList}

def St.push(full: Bool, r: Z.Rec, +per: U32, +left: U32, cur: Z.Recs, leaves: LList) -> St:
  match full:
    case True{}:
      St{per, per, Z.RNil{}, LCons{Z.RCons{r, cur}, leaves}}
    case False{}:
      St{(left - 1 : U32), per, Z.RCons{r, cur}, leaves}

def St.step(r: Z.Rec, st: St) -> St:
  St{left, per, cur, leaves} = st
  St.push(U32.is_eq(left, 1), r, per, left, cur, leaves)

def St.leaves(st: St) -> LList:
  St{_, _, _, leaves} = st
  leaves

def recs(ws: +List<U32>, st: St) -> St:
  match ws:
    case Con{e0, Con{e1, Con{e2, Con{e3, Con{e4, Con{e5, Con{e6, Con{e7, Con{c, rest}}}}}}}}}:
      recs(rest, St.step(Z.Rec{Wd.W{e0, e1, e2, e3, e4, e5, e6, e7}, c}, st))
    case _:
      st

def lrev(xs: LList, acc: LList) -> LList:
  match xs:
    case LCons{h, t}:
      lrev(t, LCons{h, acc})
    case LNil{}:
      acc

# --- leaves -> balanced tree ------------------------------------------------------

type TList is Data:
  TNil{}
  TCons{+t: Z.Tree, next: TList}

def to_tlist(xs: LList, acc: TList) -> TList:
  match xs:
    case LCons{h, t}:
      to_tlist(t, TCons{Z.Leaf{h}, acc})
    case LNil{}:
      acc

def trev(xs: TList, acc: TList) -> TList:
  match xs:
    case TCons{h, t}:
      trev(t, TCons{h, acc})
    case TNil{}:
      acc

def pair_up(xs: TList, acc: TList) -> TList:
  match xs:
    case TCons{a, TCons{b, rest}}:
      pair_up(rest, TCons{Z.Node{a, b}, acc})
    case TCons{a, TNil{}}:
      TCons{a, acc}
    case TNil{}:
      acc

def levels(k: Nat, xs: TList) -> TList:
  match k:
    case 0n:
      xs
    case 1n+j:
      levels(j, trev(pair_up(xs, TNil{}), TNil{}))

def head(xs: TList) -> Z.Tree:
  match xs:
    case TCons{h, _}:
      h
    case TNil{}:
      Z.Leaf{Z.RNil{}}

# --- results -----------------------------------------------------------------------

type WS is Data:
  WS{+idx: U32, +n: U32, hits: +List<U32>}

def WS.put(b: Bool, +idx: U32, +n: U32, hits: +List<U32>) -> WS:
  match b:
    case True{}:
      WS{(idx + 1 : U32), (n + 1 : U32), idx <> hits}
    case False{}:
      WS{(idx + 1 : U32), n, hits}

def WS.add(f: U32, st: WS) -> WS:
  WS{idx, n, hits} = st
  WS.put(U32.is_eq(f, 1), idx, n, hits)

def flags(fs: Z.Flags, st: WS) -> WS:
  match fs:
    case Z.FCons{f, t}:
      flags(t, WS.add(f, st))
    case Z.FNil{}:
      st

def walk(t: Z.RTree, st: WS) -> WS:
  match t:
    case Z.RLeaf{fs}:
      flags(fs, st)
    case Z.RNode{l, r}:
      walk(r, walk(l, st))

def show_list(xs: +List<U32>, acc: String) -> String:
  match xs:
    case Con{h, t}:
      show_list(t, acc ++ " " ++ U32.show(h))
    case Nil{}:
      acc

def hits_n(st: WS) -> U32:
  WS{_, n, _} = st
  n

def report(st: WS) -> String:
  WS{_, n, hits} = st
  "hits " ++ U32.show(n) ++ "\n" ++ show_list(rev(hits, Nil{}), "")

# --- the parallel scan ------------------------------------------------------------

def run_gpu(+k: Nat, +t: Z.Tree, +ivk: Z.Prep) -> Z.RTree & Z.Tree:
  (Z.scan!(k, t, ivk), t)

def fst(p: Z.RTree & Z.Tree) -> Z.RTree:
  (a, _) = p
  a

def sc_of(ws: +List<U32>) -> Wd.W:
  match ws:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, _}}}}}}}}:
      Wd.W{a, b, c, d, e, f, g, h}
    case _:
      Wd.W{0, 0, 0, 0, 0, 0, 0, 0}

def drop8(ws: +List<U32>) -> +List<U32>:
  match ws:
    case Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, rest}}}}}}}}:
      rest
    case _:
      Nil{}

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

type Args is Type:
  Args{path: String, depth: U32, n: U32}

def parse_args(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{d, Con{n, _}}}}:
      Args{p, num(d), num(n)}
    case _:
      Args{"", 0, 0}

def go(a: Args) -> IO(Unit):
  Args{path, +depth, +n} = a
  +per = U32.max(1, (n >> U32.to_nat(depth) : U32))
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, (32 + n * 36 : U32))
    +ws : +List<U32> = rev(words(bytes_of(r), Nil{}), Nil{})
    +ivk : Z.Prep = Z.prep(sc_of(ws))
    leaves : LList = lrev(St.leaves(recs(drop8(ws), St{per, per, Z.RNil{}, LNil{}})), LNil{})
    +tree : Z.Tree = head(levels(U32.to_nat(depth), to_tlist(lrev(leaves, LNil{}), TNil{})))
    t0 : Nat <- IO.now()
    cold : Z.RTree & Z.Tree = run_gpu(U32.to_nat(depth), tree, ivk)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    res : Z.RTree & Z.Tree = run_gpu(U32.to_nat(depth), tree, ivk)
    t2 : Nat <- IO.now()
    IO.print("scan_ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " cold_ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " cold_hits " ++ U32.show(hits_n(walk(fst(cold), WS{0, 0, Nil{}}))) ++ " outputs " ++ U32.show(n))
    IO.print(report(walk(fst(res), WS{0, 0, Nil{}})))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
