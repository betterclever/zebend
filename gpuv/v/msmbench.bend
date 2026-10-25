# msmbench <n> <mode>: n random (point, scalar) pairs; mode 0 = only build inputs (baseline),
# 1 = GPU GLV tree (msmg.msm_gpu), 2 = CPU Pippenger (msm_ba.msm9), 3 = CPU GLV tree.
# Prints the encoded result so modes can be compared, and the wall time in ms.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../field3/lib64/vesta.bend as V
import ../../perf3/lib_64/msm_ba.bend as BA
import ./msmg.bend as MG

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

def unwrap(m: Maybe<&2, V.Pt>) -> V.Pt:
  match m:
    case Some{p}:
      p
    case None{}:
      V.identity()

def gen() -> V.Pt:
  unwrap(V.decompress(Wd.W{0, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}))

def chain(n: Nat, +p: V.Pt) -> +List<V.Pt>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      p <> chain(k, V.add(V.double(p), gen()))

# q copies of a table of 256 distinct points (cheap to build, so the timing is the MSM's,
# not the input generator's).
def rep(q: Nat, +tbl: +List<V.Pt>) -> +List<V.Pt>:
  match q:
    case 0n:
      Nil{}
    case 1n+k:
      List.append(&2, V.Pt, tbl, rep(k, tbl))

def pts(+n: Nat, +p: V.Pt) -> +List<V.Pt>:
  rep(Nat.div(n, 256n), chain(256n, p))

def scs(n: Nat, +s: U32) -> +List<Wd.W>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      +a = xs(s)
      +b = xs(a)
      +c = xs(b)
      +d = xs(c)
      +e = xs(d)
      +f = xs(e)
      +g = xs(f)
      +h = xs(g)
      Wd.W{a, b, c, d, e, f, g, (h .&. 1073741823 : U32)} <> scs(k, h)

def fold(ps: +List<V.Pt>, ss: +List<Wd.W>, acc: U32) -> U32:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      fold(pt, st, (acc + Wd.low_bit(V.encode(p)) + Wd.low_bit(s) : U32))
    case _ _:
      acc

def run(+m: U32, +n: Nat) -> String:
  match m:
    case 0:
      U32.show(fold(pts(n, gen()), scs(n, 2463534242), 0))
    case 1:
      Wd.hex(V.encode(MG.msm_gpu(pts(n, gen()), scs(n, 2463534242))))
    case 2:
      Wd.hex(V.encode(BA.msm9(9, pts(n, gen()), scs(n, 2463534242))))
    case _:
      Wd.hex(V.encode(MG.msm_cpu(pts(n, gen()), scs(n, 2463534242))))

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{n, Con{m, _}}}:
      do IO<Unit>:
        t0x : Nat <- IO.now()
        +t0 : Nat = t0x
        IO.print(run(num(m), U32.to_nat(num(n))))
        t1x : Nat <- IO.now()
        +t1 : Nat = t1x
        IO.print("ms " ++ Nat.show(Nat.sub(t1, t0)))
    case _:
      IO.print("usage: msmbench n mode")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
