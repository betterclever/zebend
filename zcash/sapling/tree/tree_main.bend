# Rebuild Zcash mainnet's Sapling note commitment tree in Bend, in chunks of 2^16 leaves
# (the same design as zcash/consensus/orchard): every complete chunk's root is a level-16
# subtree root, compared (by check_tree.py) with the chain's own GetSubtreeRoots; full
# depth-32 roots at checkpoints are built from the chunk roots plus the partial chunk.
# Leaf files hold 32-byte cmu values (split_leaves.py: 2^24 leaves = 256 chunks per part).
#
#   tree_main c PART FIRST START COUNT MODE  chunk roots (MODE 0 CPU, 1 GPU, 2 CPU batched-inv): chunks START..START+COUNT-1 of the
#                                            part file whose first chunk index is FIRST
#   tree_main r PART ROOTS SIZE GPU          the full root of the first SIZE leaves: ROOTS
#                                            holds the (Bend-computed) roots of every complete
#                                            chunk (32 bytes each); PART is the part file that
#                                            holds leaf SIZE's chunk (or "-" if SIZE is a
#                                            multiple of 2^16)
#   tree_main b PART FIRST START COUNT K x  as c, CPU, K chunks at a time in parallel
#   tree_main e                              the 33 empty roots
#   tree_main f PART N                       incremental frontier over the first N leaves
import Base
import ../../halo2/lib/words.bend as Wd
import ./pedersen.bend as PH
import ./stree.bend as T

def chunk_leaves() -> U32:
  65536

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

def words_go(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_go(rest, w4(a, b, c, d) <> acc)
    case _:
      List.reverse(&2, U32, acc)

def ws_go(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_go(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      List.reverse(&2, Wd.W, acc)

# 32 bytes at a time -> one 256-bit word (single pass, one final reverse).
def ws32(bs: List<&2, U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, Con{b4, Con{b5, Con{b6, Con{b7, Con{b8, Con{b9, Con{b10, Con{b11, Con{b12, Con{b13, Con{b14, Con{b15, Con{b16, Con{b17, Con{b18, Con{b19, Con{b20, Con{b21, Con{b22, Con{b23, Con{b24, Con{b25, Con{b26, Con{b27, Con{b28, Con{b29, Con{b30, Con{b31, rest}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      ws32(rest, Wd.W{w4(b0, b1, b2, b3), w4(b4, b5, b6, b7), w4(b8, b9, b10, b11), w4(b12, b13, b14, b15), w4(b16, b17, b18, b19), w4(b20, b21, b22, b23), w4(b24, b25, b26, b27), w4(b28, b29, b30, b31)} <> acc)
    case _:
      List.reverse(&2, Wd.W, acc)

def got(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> File & +List<Wd.W>:
  (fl, res) = r
  match res:
    case Done{bs}:
      (fl, ws32(bs, Nil{}))
    case Fail{_}:
      (fl, Nil{})

def sub16(gpu: Bool, xs: +List<Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match gpu:
    case True{}:
      T.subroot!(16n, T.ltree(16n, xs), g, es)
    case False{}:
      T.subroot_par(16n, T.ltree(16n, xs), g, es)

# A complete chunk. mode 0: CPU, parallel halves (stree.subroot_par); 1: GPU (subroot!);
# 2: CPU, level by level with batched inversion (stree.chunk_root).
def full16(+mode: Nat, +xs: +List<Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match mode:
    case 0n:
      T.subroot_par(16n, T.ltree(16n, xs), g, es)
    case 1n:
      T.subroot!(16n, T.ltree(16n, xs), g, es)
    case _:
      T.chunk_root(xs, g)

# --- chunk roots ---------------------------------------------------------------------

def chunk_one(fx: File & +List<Wd.W>, +gpu: Nat, +c: Nat, +tr: Nat, +g: PH.Tab, +es: +List<Wd.W>) -> IO(File):
  (fl, +xs) = fx
  +nx = List.length(&2, Wd.W, xs)
  do IO<File>:
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +root : Wd.W = full16(gpu, xs, g, es)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("chunk " ++ Nat.show(c) ++ " root " ++ Wd.hex(root) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " read_ms " ++ Nat.show(Nat.sub(t0, tr)) ++ " leaves " ++ Nat.show(nx))
    return fl

def chunks(n: Nat, +gpu: Nat, +first: Nat, +c: Nat, fl: File, +g: PH.Tab, +es: +List<Wd.W>) -> IO(File):
  match n:
    case 0n:
      IO.pure(File, fl)
    case 1n+p:
      do IO<File>:
        trx : Nat <- IO.now()
        +tr : Nat = trx
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(Nat.sub(c, first), Nat.mul(65536n, 32n))), (chunk_leaves() * 32 : U32))
        fl2 : File <- chunk_one(got(r), gpu, c, tr, g, es)
        chunks(p, gpu, first, 1n+c, fl2, g, es)

def run_chunks(path: String, +first: Nat, +start: Nat, +n: Nat, +gpu: Nat) -> IO(Unit):
  +g = PH.tab()
  +es = T.empties(g)
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    fl2 : File <- chunks(n, gpu, first, start, fl, g, es)
    File.close(fl2)


# --- many chunks at once: K chunks read, then their roots computed in parallel --------

def par_roots(+fuel: Nat, +cnt: Nat, +xs: +List<+List<Wd.W>>, +g: PH.Tab, +es: +List<Wd.W>) -> +List<Wd.W>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      T.subroot_par(16n, T.ltree(16n, x), g, es) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = par_roots(f, h, List.take(&2, +List<Wd.W>, xs, h), g, es) par_roots(f, Nat.sub(cnt, h), List.drop(&2, +List<Wd.W>, xs, h), g, es)
      List.append(&2, Wd.W, a, b)
    case _ _ _:
      Nil{}

def push_got(fx: File & +List<Wd.W>, acc: +List<+List<Wd.W>>) -> File & +List<+List<Wd.W>>:
  (fl, xs) = fx
  (fl, xs <> acc)

def rev_st(st: File & +List<+List<Wd.W>>) -> File & +List<+List<Wd.W>>:
  (fl, acc) = st
  (fl, List.reverse(&2, +List<Wd.W>, acc))

# Read k chunks starting at chunk `off` of the open part file.
def read_k(k: Nat, +off: Nat, st: File & +List<+List<Wd.W>>) -> IO(File & +List<+List<Wd.W>>):
  match k:
    case 0n:
      IO.pure(File & +List<+List<Wd.W>>, rev_st(st))
    case 1n+p:
      (fl, acc) = st
      do IO<File & +List<+List<Wd.W>>>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(off, Nat.mul(65536n, 32n))), (chunk_leaves() * 32 : U32))
        read_k(p, 1n+off, push_got(got(r), acc))

def show_roots(xs: +List<Wd.W>, +c: Nat, +ms: Nat) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print("chunk " ++ Nat.show(c) ++ " root " ++ Wd.hex(h) ++ " ms " ++ Nat.show(ms))
        show_roots(t, 1n+c, ms)

def batch_one(fx: File & +List<+List<Wd.W>>, +c: Nat, +k: Nat, +g: PH.Tab, +es: +List<Wd.W>) -> IO(File):
  (fl, xss) = fx
  do IO<File>:
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +rs : +List<Wd.W> = par_roots(16n, k, xss, g, es)
    +nr : Nat = List.length(&2, Wd.W, rs)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    show_roots(rs, c, Nat.div(Nat.sub(t1, t0), Nat.max(nr, 1n)))
    return fl


# Chunks START..START+COUNT-1 in batches of K (all K roots computed in parallel).
def batches(n: Nat, +k: Nat, +first: Nat, +c: Nat, +left: Nat, fl: File, +g: PH.Tab, +es: +List<Wd.W>) -> IO(File):
  match n:
    case 0n:
      IO.pure(File, fl)
    case 1n+p:
      +m = Nat.min(k, left)
      do IO<File>:
        fx : File & +List<+List<Wd.W>> <- read_k(m, Nat.sub(c, first), (fl, Nil{}))
        fl2 : File <- batch_one(fx, c, m, g, es)
        batches(p, k, first, Nat.add(c, m), Nat.sub(left, m), fl2, g, es)

def run_batches(path: String, +first: Nat, +start: Nat, +n: Nat, +k: Nat) -> IO(Unit):
  +g = PH.tab()
  +es = T.empties(g)
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    fl2 : File <- batches(Nat.div(Nat.add(n, Nat.sub(k, 1n)), k), k, first, start, n, fl, g, es)
    File.close(fl2)

# --- full roots ------------------------------------------------------------------------

def close_ret(fx: File & +List<Wd.W>) -> IO(+List<Wd.W>):
  (fl, xs) = fx
  do IO<+List<Wd.W>>:
    File.close(fl)
    return xs

def read_ws(path: String, +off: Nat, +len: Nat) -> IO(+List<Wd.W>):
  do IO<+List<Wd.W>>:
    fl : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(off), U32.from_nat(len))
    close_ret(got(r))

def with_partial(rem: Nat, +gpu: Bool, +roots: +List<Wd.W>, xs: +List<Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match rem:
    case 0n:
      T.root_from_chunks(roots, g, es)
    case 1n+p:
      T.root_from_chunks(List.append(&2, Wd.W, roots, [sub16(gpu, List.take(&2, Wd.W, xs, 1n+p), g, es)]), g, es)

# The partial chunk k's leaves (chunk k sits at index k mod 256 of its part file).
def read_part(part: String, +rem: Nat, +k: Nat) -> IO(+List<Wd.W>):
  match rem:
    case 0n:
      IO.pure(+List<Wd.W>, Nil{})
    case 1n+_:
      read_ws(part, Nat.mul(Nat.mod(k, 256n), Nat.mul(65536n, 32n)), Nat.mul(rem, 32n))

def run_root(part: String, rpath: String, +size: Nat, +gpu: Bool) -> IO(Unit):
  +g = PH.tab()
  +es = T.empties(g)
  +k = Nat.div(size, 65536n)
  +rem = Nat.mod(size, 65536n)
  do IO<Unit>:
    roots : +List<Wd.W> <- read_ws(rpath, 0n, Nat.mul(k, 32n))
    +rs : +List<Wd.W> = roots
    xs : +List<Wd.W> <- read_part(part, rem, k)
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +root : Wd.W = with_partial(rem, gpu, rs, xs, g, es)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("size " ++ Nat.show(size) ++ " chunks " ++ Nat.show(List.length(&2, Wd.W, rs)) ++ " root " ++ Wd.hex(root) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)))

# --- empty roots, frontier ----------------------------------------------------------------

def show_all(xs: +List<Wd.W>, +i: Nat) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print("empty " ++ Nat.show(i) ++ " " ++ Wd.hex(h))
        show_all(t, 1n+i)

def fpush(xs: +List<Wd.W>, lv: +List<Maybe<&2, Wd.W>>, +g: PH.Tab) -> +List<Maybe<&2, Wd.W>>:
  match xs:
    case Nil{}:
      lv
    case Con{h, t}:
      fpush(t, T.push(lv, 0n, h, g), g)

def run_frontier(part: String, +n: Nat) -> IO(Unit):
  +g = PH.tab()
  +es = T.empties(g)
  do IO<Unit>:
    xs : +List<Wd.W> <- read_ws(part, 0n, Nat.mul(n, 32n))
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    +root : Wd.W = T.froot(fpush(xs, T.frontier_new(), g), 0n, None{}, g, es)
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    IO.print("frontier " ++ Nat.show(n) ++ " root " ++ Wd.hex(root) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)))

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

# Dispatch on the argument count (the op letter is for readability).
def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{_, Con{p, Con{f, Con{a, Con{n, Con{k, Con{_, Nil{}}}}}}}}}:
      run_batches(p, num(f), num(a), num(n), num(k))
    case Con{_, Con{_, Con{p, Con{f, Con{a, Con{n, Con{m, Nil{}}}}}}}}:
      run_chunks(p, num(f), num(a), num(n), num(m))
    case Con{_, Con{_, Con{p, Con{rp, Con{s, Con{m, Nil{}}}}}}}:
      run_root(p, rp, num(s), is_gpu(m))
    case Con{_, Con{_, Nil{}}}:
      show_all(T.empties(PH.tab()), 0n)
    case Con{_, Con{_, Con{p, Con{n, Nil{}}}}}:
      run_frontier(p, num(n))
    case _:
      IO.print("usage: tree_main c PART FIRST START COUNT GPU | r PART ROOTS SIZE GPU | e | f PART N")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
