# gpu_dec MODE D L: decompress 2^D * L Vesta encodings (x uniform below 2^254, random sign;
# about half are points) in a fork tree of depth D, L per leaf (tail-recursive leaf walk),
# on the GPU with `dec_tree!` (CPU threads under +RTS --gpu off). MODE: 0 = field3
# decompress, 1 = decomp decompress (table sqrt), 2 = decomp decompress_ct (fixed work).
# Prints the valid count and a digest of every decoded point (identical across modes,
# runs and devices if correct) and the time of the tree run.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as Fq
import ../../../crypto/field3/lib64/vesta.bend as V
import ../vesta_dec.bend as VD

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

def rw(+s: U32) -> Wd.W:
  +s1 = xs(s)
  +s2 = xs(s1)
  +s3 = xs(s2)
  +s4 = xs(s3)
  +s5 = xs(s4)
  +s6 = xs(s5)
  +s7 = xs(s6)
  +s8 = xs(s7)
  Wd.W{s1, s2, s3, s4, s5, s6, s7, ((s8 .&. 1073741823 : U32) .|. ((s .&. 1 : U32) << 31n) : U32)}

def next8(+s: U32) -> U32:
  xs(xs(xs(xs(xs(xs(xs(xs(s))))))))

type D is Data:
  D{sum: U32, ok: U32}

def dadd(a: D, b: D) -> D:
  D{+x, +y} = a
  D{+u, +v} = b
  D{(x + u : U32), (y + v : U32)}

def fold(+h: U32, w: Wd.W) -> U32:
  Wd.W{a, b, c, d, e, f, g, k} = w
  xs((xs((xs((xs((xs((xs((xs((xs((h .^. a : U32)) .^. b : U32)) .^. c : U32)) .^. d : U32)) .^. e : U32)) .^. f : U32)) .^. g : U32)) .^. k : U32))

def pt_hash(+s: U32, p: V.Pt) -> D:
  V.Pt{x, y, z} = p
  D{fold(fold(fold(s, Fq.to_words(x)), Fq.to_words(y)), Fq.to_words(z)), 1}

def m_hash(+s: U32, m: Maybe<&2, V.Pt>) -> D:
  match m:
    case Some{p}:
      pt_hash(s, p)
    case None{}:
      D{xs((s .^. 2779096485 : U32)), 0}

def c_hash(+s: U32, c: VD.Dec) -> D:
  VD.Dec{+ok, p} = c
  m_hash(s, VD.mk_maybe(ok, p))

def one(+mode: U32, +s: U32) -> D:
  match mode:
    case 0:
      m_hash(s, V.decompress(rw(s)))
    case 1:
      m_hash(s, VD.decompress(rw(s)))
    case _:
      c_hash(s, VD.decompress_ct(rw(s)))

def leaf(n: Nat, +mode: U32, +s: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      leaf(k, mode, next8(s), dadd(a, one(mode, s)))

def dec_tree(+d: Nat, +mode: U32, +seed: U32, +l: Nat) -> D:
  match d:
    case 0n:
      leaf(l, mode, (seed * 2654435761 + 4242 : U32), D{0, 0})
    case 1n+p:
      a b = dec_tree(p, mode, (seed * 2 : U32), l) dec_tree(p, mode, (seed * 2 + 1 : U32), l)
      dadd(a, b)

def run(+mode: U32, +d: Nat, +l: Nat) -> D:
  dec_tree!(d, mode, 1, l)

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def line(+mode: U32, +d: U32, +l: U32, r: D, +ms: Nat) -> String:
  D{+s, +k} = r
  "mode " ++ U32.show(mode) ++ " depth " ++ U32.show(d) ++ " leaf " ++ U32.show(l) ++ " valid " ++ U32.show(k) ++ " digest " ++ U32.show(s) ++ " ms " ++ Nat.show(ms)

def go(+mode: U32, +d: U32, +l: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : D = run(mode, U32.to_nat(d), U32.to_nat(l))
    t1 : Nat <- IO.now()
    IO.print(line(mode, d, l, r, Nat.sub(t1, t0)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{m, Con{d, Con{l, _}}}}:
      go(num(m), num(d), num(l))
    case _:
      IO.print("usage: gpu_dec MODE D L")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
