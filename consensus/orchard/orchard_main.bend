# Rebuild Zcash mainnet's Orchard note commitment tree (50.5M leaves, NU5 activation to tip)
# in Bend, in chunks of 2^16 leaves read straight from the leaf file:
#   1. every complete chunk's subtree root, compared with the chain's own level-16 subtree
#      root (lightwalletd GetSubtreeRoots);
#   2. the full depth-32 root at each checkpoint (GetTreeState), from the chunk roots plus
#      the checkpoint's partial chunk.
# Chunk roots are computed in batches (each run well under the 10-minute heavy-job limit);
# the checkpoint pass reads the Bend-computed chunk roots back from got_roots.bend.
#   ./orchard_main LEAVES START COUNT GPU(0|1)    chunk roots
#   ./orchard_main LEAVES GPU(0|1)                checkpoint roots
#   ./orchard_main LEAVES GPU(0|1) a              Orchard anchors: the root at the end of the
#                                                 hinted block, recomputed, equals the anchor
import Base
import ../../halo2/lib/words.bend as Wd
import ../../node/state/sinsemilla.bend as S
import ./inputs.bend as I
import ./got_roots.bend as G
import ../anchors/hist.bend as H

def rec_bytes() -> U32:
  36

def chunk_leaves() -> U32:
  65536

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_of(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_of(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

# 9-word records (height, then cm_x); keep cm_x.
def recs_of(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}}:
      recs_of(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      acc

def leaves_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> File & +List<Wd.W>:
  (fl, res) = r
  match res:
    case Done{bs}:
      (fl, List.reverse(&2, Wd.W, recs_of(List.reverse(&2, U32, words_of(bs, Nil{})), Nil{})))
    case Fail{_}:
      (fl, Nil{})

# --- roots ---------------------------------------------------------------------------

def sub16(gpu: Bool, xs: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> Wd.W:
  match gpu:
    case True{}:
      S.subroot!(16n, S.ltree(16n, xs), g, es)
    case False{}:
      S.subroot(16n, S.ltree(16n, xs), g, es)

# The upper tree: chunk roots are level-16 nodes; levels 16..31.
def usub(+h: Nat, t: S.LTree, +g: S.Gens, +es: +List<Wd.W>) -> Wd.W:
  match h t:
    case _ S.LEmpty{}:
      S.nth(es, Nat.add(16n, h))
    case 0n S.LOne{w}:
      w
    case 1n+k S.LNode{l, r}:
      a b = usub(k, l, g, es) usub(k, r, g, es)
      S.crh(g, U32.from_nat(Nat.add(16n, k)), a, b)
    case _ _:
      Wd.zero()

def root_from(roots: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> Wd.W:
  usub(16n, S.ltree(16n, roots), g, es)

def ok_s(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

# --- pass 1: every complete chunk ---------------------------------------------------

type St is Type:
  St{file: File, roots: +List<Wd.W>, ok: Nat}

def chunk_done(+gpu: Bool, +c: Nat, fr: File & +List<Wd.W>, +want: Wd.W, st_roots: +List<Wd.W>, +ok: Nat, +g: S.Gens, +es: +List<Wd.W>) -> IO(St):
  (fl, xs) = fr
  +r = sub16(gpu, xs, g, es)
  +m = Wd.is_eq(r, want)
  do IO<St>:
    IO.print("chunk " ++ Nat.show(c) ++ " subtree root " ++ Wd.hex(r) ++ " " ++ ok_s(m))
    return St{fl, r <> st_roots, Nat.add(ok, b2n(m))}

def chunks(n: Nat, +gpu: Bool, +c: Nat, wants: +List<Wd.W>, st: St, +g: S.Gens, +es: +List<Wd.W>) -> IO(St):
  match n wants:
    case 1n+p Con{+want, wrest}:
      St{fl, roots, ok} = st
      do IO<St>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(c, Nat.mul(65536n, 36n))), (chunk_leaves() * rec_bytes() : U32))
        st2 : St <- chunk_done(gpu, c, leaves_of(r), want, roots, ok, g, es)
        chunks(p, gpu, 1n+c, wrest, st2, g, es)
    case _ _:
      IO.pure(St, st)

# --- pass 2: checkpoints --------------------------------------------------------------

def with_partial(rem: Nat, +k: Nat, +gpu: Bool, fr: File & +List<Wd.W>, +roots: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> File & Wd.W:
  match rem:
    case 0n:
      (fl, _) = fr
      (fl, root_from(List.take(&2, Wd.W, roots, k), g, es))
    case 1n+p:
      (fl, xs) = fr
      (fl, root_from(List.append(&2, Wd.W, List.take(&2, Wd.W, roots, k), [sub16(gpu, List.take(&2, Wd.W, xs, 1n+p), g, es)]), g, es))

def cp_str(+got: Wd.W, +cp: I.CP) -> String:
  I.CP{height, size, want} = cp
  "height " ++ U32.show(height) ++ " size " ++ U32.show(size) ++ ": bend root " ++ Wd.hex(got) ++ " " ++ ok_s(Wd.is_eq(got, want))

def cp_line(fr: File & Wd.W, +cp: I.CP) -> File & String:
  (fl, got) = fr
  (fl, cp_str(got, cp))

def say(fs: File & String) -> IO(File):
  (fl, s) = fs
  do IO<File>:
    IO.print(s)
    return fl

def cps(xs: +List<I.CP>, fl: File, +gpu: Bool, +roots: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> IO(Unit):
  match xs:
    case Con{+cp, rest}:
      I.CP{_, +size, _} = cp
      +n = U32.to_nat(size)
      +k = Nat.div(n, 65536n)
      do IO<Unit>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(k, Nat.mul(65536n, 36n))), (chunk_leaves() * rec_bytes() : U32))
        fl2 : File <- say(cp_line(with_partial(Nat.mod(n, 65536n), k, gpu, leaves_of(r), roots, g, es), cp))
        cps(rest, fl2, gpu, roots, g, es)
    case _:
      do IO<Unit>:
        File.close(fl)

def done(st: St, +n: Nat) -> IO(Unit):
  St{fl, _, ok} = st
  do IO<Unit>:
    IO.print("subtree roots matching the chain: " ++ Nat.show(ok) ++ "/" ++ Nat.show(n))
    File.close(fl)

def run_chunks(path: String, +start: Nat, +n: Nat, +gpu: Bool) -> IO(Unit):
  +g = S.gens()
  +es = S.empties(g)
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    st : St <- chunks(n, gpu, start, List.drop(&2, Wd.W, I.subtree_roots(), start), St{fl, Nil{}, 0n}, g, es)
    done(st, n)

def run_cps(path: String, +gpu: Bool) -> IO(Unit):
  +g = S.gens()
  +es = S.empties(g)
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    cps(I.checkpoints(), fl, gpu, G.got_roots(), g, es)

# --- pass 3: anchors ------------------------------------------------------------------

def words(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> File & +List<U32>:
  (fl, res) = r
  match res:
    case Done{bs}:
      (fl, List.reverse(&2, U32, words_of(bs, Nil{})))
    case Fail{_}:
      (fl, Nil{})

# Records n-1 and n: height(n-1) <= h < height(n), i.e. n is exactly the leaves through block h.
def between_w(xs: +List<U32>, +h: Nat) -> Bool:
  match xs:
    case Con{a, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{_, Con{b, _}}}}}}}}}}:
      Bool.and(Nat.is_lt(U32.to_nat(a), 1n+h), Nat.is_lt(h, U32.to_nat(b)))
    case _:
      False{}

def after_w(xs: +List<U32>, +h: Nat) -> Bool:
  match xs:
    case Con{a, _}:
      Nat.is_lt(h, U32.to_nat(a))
    case _:
      False{}

def between(fr: File & +List<U32>, +h: Nat) -> File & Bool:
  (fl, xs) = fr
  (fl, between_w(xs, h))

def after(fr: File & +List<U32>, +h: Nat) -> File & Bool:
  (fl, xs) = fr
  (fl, after_w(xs, h))

def size_ok(n: Nat, +h: Nat, fl: File) -> IO(File & Bool):
  match n:
    case 0n:
      do IO<File & Bool>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, 0, 36)
        return after(words(r), h)
    case 1n+p:
      do IO<File & Bool>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(p, 36n)), 72)
        return between(words(r), h)

def valid_s(b: Bool) -> String:
  match b:
    case True{}:
      "VALID"
    case False{}:
      "INVALID"

def ax_str(+ok_size: Bool, +root: Wd.W, +ax: I.Ax) -> String:
  I.Ax{name, block, anchor, height, size} = ax
  +v = Bool.and(ok_size, H.hits(anchor, block, H.HE{height, root}))
  "anchor " ++ name ++ " (block " ++ Nat.show(block) ++ ") " ++ Wd.hex(anchor) ++ ": " ++ valid_s(v) ++ " (hint: end of block " ++ Nat.show(height) ++ ", " ++ Nat.show(size) ++ " leaves, size " ++ ok_s(ok_size) ++ "; bend root " ++ Wd.hex(root) ++ ")"

def ax_out(sb: File & Bool, +root: Wd.W, +ax: I.Ax) -> File & String:
  (fl, b) = sb
  (fl, ax_str(b, root, ax))

def ax_one(fr: File & Wd.W, +ax: I.Ax) -> IO(File):
  (fl, root) = fr
  I.Ax{_, _, _, +h, +n} = ax
  do IO<File>:
    sb : File & Bool <- size_ok(n, h, fl)
    say(ax_out(sb, root, ax))

def axs(xs: +List<I.Ax>, fl: File, +gpu: Bool, +roots: +List<Wd.W>, +g: S.Gens, +es: +List<Wd.W>) -> IO(Unit):
  match xs:
    case Con{+ax, rest}:
      I.Ax{_, _, _, _, +n} = ax
      +k = Nat.div(n, 65536n)
      do IO<Unit>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(k, Nat.mul(65536n, 36n))), (chunk_leaves() * rec_bytes() : U32))
        fl2 : File <- ax_one(with_partial(Nat.mod(n, 65536n), k, gpu, leaves_of(r), roots, g, es), ax)
        axs(rest, fl2, gpu, roots, g, es)
    case _:
      do IO<Unit>:
        File.close(fl)

def run_axs(path: String, +gpu: Bool) -> IO(Unit):
  +g = S.gens()
  +es = S.empties(g)
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    axs(I.anchors(), fl, gpu, G.got_roots(), g, es)

def num(s: String) -> Nat:
  U32.to_nat(Maybe.default(&2, U32, U32.read(s), 0))

def is_one(n: Nat) -> Bool:
  match n:
    case 1n:
      True{}
    case _:
      False{}

def is_gpu(s: String) -> Bool:
  is_one(num(s))

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{p, Con{a, Con{n, Con{m, _}}}}}:
      run_chunks(p, num(a), num(n), is_gpu(m))
    case Con{_, Con{p, Con{m, Con{_, Nil{}}}}}:
      run_axs(p, is_gpu(m))
    case Con{_, Con{p, Con{m, Nil{}}}}:
      run_cps(p, is_gpu(m))
    case _:
      IO.print("usage: orchard_main LEAVES START COUNT GPU(0|1)  |  orchard_main LEAVES GPU(0|1)")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
