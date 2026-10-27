# zcash/consensus/gaps/trees/sprout_js.bend: the Sprout note commitment tree (node/trees/sprout.bend,
# copied: SHA256Compress MerkleCRH, depth 29) plus the JoinSplit anchor rule with zcashd's
# interstitial trees (zcashd CCoinsViewCache::HaveShieldedRequirements, Zebra
# zebra-state/src/service/check/anchors.rs sprout_anchors_refer_to_treestates).
#
# usage: sprout_js <in.frontier|-> <js.bin> <ext.bin> <out.frontier>
#   in.frontier:  the chain's Sprout tree before the window (29 lines, "-" or hex), "-" = empty.
#   js.bin:  u32 n, then per JoinSplit in chain order: u32 block index | u32 tx index |
#            anchor 32 | cm1 32 | cm2 32   (the tree's leaves are exactly cm1, cm2 of each)
#   ext.bin: u32 n, then per entry: root 32 | u32 has_frontier | 29 x (u32 present | 32 bytes)
#            roots of blocks BEFORE the window (the node's anchor index); a frontier is given
#            for roots whose tree an interstitial anchor may need (its root is re-checked here).
# The rule, per JoinSplit j of tx T in block b: anchor(j) must be
#   - the root after an earlier block: the window-start tree, the tree after an earlier block
#     of this window, or an ext root; or the empty tree's root; or
#   - an interstitial root of T: the root of tree(anchor(i)) + cm1(i) + cm2(i) for an earlier
#     JoinSplit i of T (tree(anchor(i)) being the tree whose root anchor(i) is).
# Prints per JoinSplit "js <k> <V>" (V: W window/earlier-block root or empty root, E ext root,
# I interstitial root, X none: INVALID; Z: the anchor's root is known but its frontier is not,
# so later interstitial roots of T cannot be formed - also printed as the reason when a later
# JoinSplit is X), per block that appends "root <block index> <tree size since window start> <hex>"
# and "front <block index> <29 levels, comma-separated>", then "size", "empty_root"; writes
# out.frontier.
import Base
import ../../../block/sha256.bend as S
import ../../../block/bytes.bend as Y
import ../../../block/util.bend as U

def depth() -> Nat:
  29n

def crh(+l: +List<U32>, +r: +List<U32>) -> +List<U32>:
  S.digest(S.compress(S.iv(), Y.append(l, r)))

def empties_go(n: Nat, +e: +List<U32>) -> List<&2, +List<U32>>:
  match n:
    case 0n:
      [e]
    case 1n+p:
      e <> empties_go(p, crh(e, e))

def empties() -> List<&2, +List<U32>>:
  empties_go(depth(), Y.zeros(32n))

def nth(+xs: List<&2, +List<U32>>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Y.zeros(32n)
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+k:
      nth(t, k)

def push(lv: List<&2, Maybe<&2, +List<U32>>>, carry: +List<U32>) -> List<&2, Maybe<&2, +List<U32>>>:
  match lv:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      match m:
        case None{}:
          Some{carry} <> rest
        case Some{left}:
          None{} <> push(rest, crh(left, carry))

def nones(n: Nat) -> List<&2, Maybe<&2, +List<U32>>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      None{} <> nones(p)

def fstep(m: Maybe<&2, +List<U32>>, acc: Maybe<&2, +List<U32>>, +l: Nat, +es: List<&2, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match m:
    case Some{left}:
      match acc:
        case Some{a}:
          Some{crh(left, a)}
        case None{}:
          Some{crh(left, nth(es, l))}
    case None{}:
      match acc:
        case Some{a}:
          Some{crh(a, nth(es, l))}
        case None{}:
          None{}

def froot(lv: List<&2, Maybe<&2, +List<U32>>>, +l: Nat, acc: Maybe<&2, +List<U32>>, +es: List<&2, +List<U32>>) -> +List<U32>:
  match lv:
    case Nil{}:
      match acc:
        case Some{a}:
          a
        case None{}:
          nth(es, depth())
    case Con{m, rest}:
      froot(rest, 1n+l, fstep(m, acc, l, es), es)

# ---------------------------------------------------------------- IO

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def leaves_rev(n: Nat, +bs: +List<U32>, acc: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match n:
    case 0n:
      acc
    case 1n+p:
      leaves_rev(p, Y.drop(bs, 32n), Y.take(bs, 32n) <> acc)

def leaves_of(+bs: +List<U32>) -> List<&2, +List<U32>>:
  List.reverse(&2, +List<U32>, leaves_rev(U32.to_nat((Y.length(bs) / 32 : U32)), bs, Nil{}))

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_rev(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_rev(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def words(+bs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, words_rev(bs, Nil{}))

def level_sel(dash: Bool, s: String) -> Maybe<&2, +List<U32>>:
  match dash:
    case True{}:
      None{}
    case False{}:
      Some{Y.of_hex(s)}

def level_of(+s: String) -> Maybe<&2, +List<U32>>:
  level_sel(String.eq(s, "-") || String.eq(s, ""), s)

def levels_of(n: Nat, ls: +List<String>) -> List<&2, Maybe<&2, +List<U32>>>:
  match n ls:
    case 0n _:
      Nil{}
    case 1n+p Con{l, rest}:
      level_of(l) <> levels_of(p, rest)
    case 1n+p Nil{}:
      None{} <> levels_of(p, Nil{})

def show_level(m: Maybe<&2, +List<U32>>) -> String:
  match m:
    case None{}:
      "-"
    case Some{w}:
      U.bhex(w)

def show_frontier(lv: List<&2, Maybe<&2, +List<U32>>>) -> String:
  match lv:
    case Nil{}:
      ""
    case Con{m, rest}:
      show_level(m) ++ "\n" ++ show_frontier(rest)


# ---------------------------------------------------------------- JoinSplit anchor rule

type Fr is Data:
  Fr{lv: List<&2, Maybe<&2, +List<U32>>>}

type Known is Data:
  Known{root: +List<U32>, p: Nat, f: Maybe<&2, Fr>}

type J is Data:
  J{blk: U32, tx: U32, anchor: +List<U32>, cm1: +List<U32>, cm2: +List<U32>}

def le4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  w4(a, b, c, d)

def u32_at(+bs: +List<U32>) -> U32:
  Y.get_le32(bs)

def js_list(n: Nat, +bs: +List<U32>) -> +List<J>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      J{u32_at(bs), u32_at(Y.drop(bs, 4n)), Y.take(Y.drop(bs, 8n), 32n), Y.take(Y.drop(bs, 40n), 32n), Y.take(Y.drop(bs, 72n), 32n)}
        <> js_list(p, Y.drop(bs, 104n))

def lvl_sel(absent: Bool, +bs: +List<U32>) -> Maybe<&2, +List<U32>>:
  match absent:
    case True{}:
      None{}
    case False{}:
      Some{Y.take(Y.drop(bs, 4n), 32n)}

def lvl_of(+bs: +List<U32>) -> Maybe<&2, +List<U32>>:
  lvl_sel(U32.is_eq(u32_at(bs), 0), bs)

def fr_levels(n: Nat, +bs: +List<U32>) -> List<&2, Maybe<&2, +List<U32>>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      lvl_of(bs) <> fr_levels(p, Y.drop(bs, 36n))

def ext_fr(has: Bool, +bs: +List<U32>) -> Maybe<&2, Fr>:
  match has:
    case True{}:
      Some{Fr{fr_levels(depth(), bs)}}
    case False{}:
      None{}

def ext_len(has: Bool) -> Nat:
  match has:
    case True{}:
      (depth() * 36n : Nat)
    case False{}:
      0n

def ext_list(n: Nat, +bs: +List<U32>) -> +List<Known>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +has = Bool.not(U32.is_eq(u32_at(Y.drop(bs, 32n)), 0))
      Known{Y.take(bs, 32n), 0n, ext_fr(has, Y.drop(bs, 36n))} <> ext_list(p, Y.drop(bs, (36n + ext_len(has) : Nat)))

# A known root usable by a JoinSplit of block b: produced at p <= b (p = k+1 after block k of
# the window; 0: the window-start tree and ext roots).
type Hit is Data:
  Hit{found: Bool, f: Maybe<&2, Fr>}

def find2(rest: +List<Known>, ok: Bool, f: Maybe<&2, Fr>, +a: +List<U32>, +b: Nat) -> Hit:
  match rest ok:
    case _ True{}:
      Hit{True{}, f}
    case Nil{} False{}:
      Hit{False{}, None{}}
    case Con{Known{+r, +p, f2}, r2} False{}:
      find2(r2, Y.is_eq(r, a) && Nat.is_lt(p, 1n+b), f2, a, b)

def find(+ks: +List<Known>, +a: +List<U32>, +b: Nat) -> Hit:
  find2(ks, False{}, None{}, a, b)

def push2(f: List<&2, Maybe<&2, +List<U32>>>, +c1: +List<U32>, +c2: +List<U32>) -> List<&2, Maybe<&2, +List<U32>>>:
  push(push(f, c1), c2)

def inter_add(m: Maybe<&2, Fr>, +c1: +List<U32>, +c2: +List<U32>, +es: List<&2, +List<U32>>, +inter: +List<Known>) -> +List<Known>:
  match m:
    case None{}:
      inter
    case Some{fr}:
      Fr{lv} = fr
      +f2 = push2(lv, c1, c2)
      Known{froot(f2, 0n, None{}, es), 0n, Some{Fr{f2}}} <> inter

type Ver is Data:
  Ver{v: String, f: Maybe<&2, Fr>}

def ver_frontier_tag(m: Maybe<&2, Fr>, +tag: String) -> Ver:
  match m:
    case None{}:
      Ver{"Z", None{}}
    case Some{fr}:
      Ver{tag, Some{fr}}

def v_empty(is_empty: Bool) -> Ver:
  match is_empty:
    case True{}:
      Ver{"W", Some{Fr{nones(depth())}}}
    case False{}:
      Ver{"X", None{}}

def ver_e(m: Maybe<&2, Fr>) -> Ver:
  match m:
    case None{}:
      Ver{"E", None{}}
    case Some{fr}:
      Ver{"E", Some{fr}}

def v_ext(h: Hit, +a: +List<U32>, +es: List<&2, +List<U32>>) -> Ver:
  Hit{found, f} = h
  match found:
    case True{}:
      ver_e(f)
    case False{}:
      v_empty(Y.is_eq(a, nth(es, depth())))

def v_win(h: Hit, +a: +List<U32>, +b: Nat, +ext: +List<Known>, +es: List<&2, +List<U32>>) -> Ver:
  Hit{found, f} = h
  match found:
    case True{}:
      ver_frontier_tag(f, "W")
    case False{}:
      v_ext(find(ext, a, b), a, es)

def v_inter(h: Hit, +a: +List<U32>, +b: Nat, +win: +List<Known>, +ext: +List<Known>, +es: List<&2, +List<U32>>) -> Ver:
  Hit{found, f} = h
  match found:
    case True{}:
      ver_frontier_tag(f, "I")
    case False{}:
      v_win(find(win, a, b), a, b, ext, es)

def ver_s(v: Ver) -> String:
  Ver{s, _} = v
  s

def ver_f(v: Ver) -> Maybe<&2, Fr>:
  Ver{_, f} = v
  f

def show_lv(lv: List<&2, Maybe<&2, +List<U32>>>) -> String:
  match lv:
    case Nil{}:
      ""
    case Con{m, Nil{}}:
      show_level(m)
    case Con{m, rest}:
      show_level(m) ++ "," ++ show_lv(rest)

type S2 is Type:
  S2{f: List<&2, Maybe<&2, +List<U32>>>, win: +List<Known>, inter: +List<Known>, cur: U32, curb: U32, k: Nat, size: Nat, lines: List<String>}

def same_tx(+b: U32, +t: U32, +cb: U32, +ct: U32) -> Bool:
  U32.is_eq(b, cb) && U32.is_eq(t, ct)

def keep_inter(same: Bool, inter: +List<Known>) -> +List<Known>:
  match same:
    case True{}:
      inter
    case False{}:
      Nil{}

# After the last JoinSplit of block b: the block's root becomes usable from block b+1 on.
def close_blk(last: Bool, +b: U32, +t: U32, +f: List<&2, Maybe<&2, +List<U32>>>, +size: Nat, +es: List<&2, +List<U32>>, win: +List<Known>, inter: +List<Known>, +k: Nat, lines: List<String>) -> S2:
  match last:
    case True{}:
      +r = froot(f, 0n, None{}, es)
      S2{f, Known{r, 1n+U32.to_nat(b), Some{Fr{f}}} <> win, inter, b, t, k, size,
         ("front " ++ U32.show(b) ++ " " ++ show_lv(f)) <> ("root " ++ U32.show(b) ++ " " ++ Nat.show(size) ++ " " ++ U.bhex(r)) <> lines}
    case False{}:
      S2{f, win, inter, b, t, k, size, lines}

def next_blk(xs: +List<J>) -> U32:
  match xs:
    case Nil{}:
      4294967295
    case Con{J{b, _, _, _, _}, _}:
      b

def step(j: J, +rest: +List<J>, s: S2, +ext: +List<Known>, +es: List<&2, +List<U32>>) -> S2:
  J{+b, +t, +a, +c1, +c2} = j
  S2{+f, +win, +inter, +cb, +ct, +k, +size, lines} = s
  +inter1 = keep_inter(same_tx(b, t, cb, ct), inter)
  +bn = U32.to_nat(b)
  +v = v_inter(find(inter1, a, bn), a, bn, win, ext, es)
  +inter2 = inter_add(ver_f(v), c1, c2, es, inter1)
  +f2 = push2(f, c1, c2)
  +line = "js " ++ Nat.show(k) ++ " " ++ ver_s(v)
  close_blk(Bool.not(U32.is_eq(next_blk(rest), b)), b, t, f2, (size + 2n : Nat), es, win, inter2, 1n+k, line <> lines)

def walk(xs: +List<J>, s: S2, +ext: +List<Known>, +es: List<&2, +List<U32>>) -> S2:
  match xs:
    case Nil{}:
      s
    case Con{+j, +rest}:
      walk(rest, step(j, rest, s, ext, es), ext, es)

def s_lines(s: S2) -> List<String>:
  S2{_, _, _, _, _, _, _, l} = s
  l

def s_f(s: S2) -> List<&2, Maybe<&2, +List<U32>>>:
  S2{f, _, _, _, _, _, _, _} = s
  f

def s_size(s: S2) -> Nat:
  S2{_, _, _, _, _, _, +n, _} = s
  n

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(x)
        print_all(rest)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def text_of(r: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, res) = r
  match res:
    case Done{s}:
      do IO<String>:
        File.close(f)
        return s
    case Fail{_}:
      do IO<String>:
        File.close(f)
        return ""

def read_text_if(dash: Bool, p: String) -> IO(String):
  match dash:
    case True{}:
      IO.pure(String, "")
    case False{}:
      do IO<String>:
        f : File <- IO.try(File, File.open(p, "r"))
        r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 8000)
        text_of(r)

def read_bin(p: String) -> IO(+List<U32>):
  do IO<+List<U32>>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 200000000)
    return bytes_of(r)

type Paths is Type:
  Paths{fin: String, js: String, ext: String, fout: String}

def paths(xs: List<String>) -> Paths:
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, _}}}}}:
      Paths{a, b, c, d}
    case _:
      Paths{"-", "", "", ""}

def run(s: S2, fout: String, +es: List<&2, +List<U32>>) -> IO(Unit):
  S2{f, _, _, _, _, _, +size, lines} = s
  do IO<Unit>:
    print_all(List.reverse(&1, String, lines))
    IO.print("size " ++ Nat.show(size))
    IO.print("empty_root " ++ U.bhex(nth(es, depth())))
    w : File <- IO.try(File, File.open(fout, "w"))
    wr : File & Result<&1, &1, U32 & String, Unit> <- File.write(w, show_frontier(f))
    close_pair(wr)

def go(p: Paths) -> IO(Unit):
  Paths{+fin, jp, xp, fout} = p
  +es = empties()
  do IO<Unit>:
    ft0 : String <- read_text_if(String.eq(fin, "-"), fin)
    +ft : String = ft0
    jb0 : +List<U32> <- read_bin(jp)
    +jb : +List<U32> = jb0
    xb0 : +List<U32> <- read_bin(xp)
    +xb : +List<U32> = xb0
    +f0 : List<&2, Maybe<&2, +List<U32>>> = levels_of(depth(), String.split(ft, '\n'))
    +js : +List<J> = js_list(U32.to_nat(u32_at(jb)), Y.drop(jb, 4n))
    +ext : +List<Known> = ext_list(U32.to_nat(u32_at(xb)), Y.drop(xb, 4n))
    +win0 : +List<Known> = Known{froot(f0, 0n, None{}, es), 0n, Some{Fr{f0}}} <> Nil{}
    run(walk(js, S2{f0, win0, Nil{}, 4294967295, 4294967295, 0n, 0n, Nil{}}, ext, es), fout, es)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
