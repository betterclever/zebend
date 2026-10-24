import Base
import ../../halo2/lib/words.bend as Wd
import ../lib32/pallas.bend as V
import ../lib/glv_pallas.bend as G

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      0
    case False{}:
      1

def bad(+p: V.Pt, +k: Wd.W) -> U32:
  b2u(V.is_eq(G.mul(p, k), V.scalar_mul(p, k)))

def unwrap(m: Maybe<&2, V.Pt>) -> V.Pt:
  match m:
    case Some{p}:
      p
    case None{}:
      V.identity()

def gen() -> V.Pt:
  unwrap(V.decompress(Wd.W{0, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}))

def edges() -> +List<Wd.W>:
  Wd.W{0, 0, 0, 0, 0, 0, 0, 0} <>
  Wd.W{1, 0, 0, 0, 0, 0, 0, 0} <>
  Wd.W{2, 0, 0, 0, 0, 0, 0, 0} <>
  Wd.W{3, 0, 0, 0, 0, 0, 0, 0} <>
  Wd.W{0, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824} <>
  Wd.W{4294967295, 2353457952, 160737501, 575052028, 0, 0, 0, 1073741824} <>
  Wd.W{1353322063, 715772640, 1203778479, 267208317, 485953370, 1360901336, 675173006, 109156952} <>
  Wd.W{2941645233, 1637685312, 3251926318, 307843710, 3809013926, 2934065959, 3619794289, 964584871} <>
  Wd.W{2941645234, 1637685312, 3251926318, 307843710, 3809013926, 2934065959, 3619794289, 964584871} <>
  Wd.W{1353322064, 715772640, 1203778479, 267208317, 485953370, 1360901336, 675173006, 109156952} <>
  Wd.W{0, 0, 0, 2147483648, 0, 0, 0, 0} <>
  Wd.W{4294967295, 4294967295, 4294967295, 2147483647, 0, 0, 0, 0} <>
  Wd.W{0, 0, 0, 0, 1, 0, 0, 0} <>
  Wd.W{1, 0, 0, 0, 1, 0, 0, 0} <>
  Wd.W{0, 0, 0, 0, 0, 0, 256, 0} <>
  Wd.W{2147483648, 3324212624, 80368750, 287526014, 0, 0, 0, 536870912} <>
  Wd.W{2147483649, 3324212624, 80368750, 287526014, 0, 0, 0, 536870912} <>
  Nil{}

def edge_loop(ks: +List<Wd.W>, +p: V.Pt, acc: U32) -> U32:
  match ks:
    case Con{+k, t}:
      edge_loop(t, p, (acc + bad(p, k) + bad(V.identity(), k) : U32))
    case Nil{}:
      acc

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

type St is Data:
  St{p: V.Pt, s: U32, bad: U32}

def xs_n(n: Nat, +s: U32) -> U32:
  match n:
    case 0n:
      s
    case 1n+k:
      xs_n(k, xs(s))

def rand_w(+s: U32) -> Wd.W:
  Wd.W{xs_n(1n, s), xs_n(2n, s), xs_n(3n, s), xs_n(4n, s), xs_n(5n, s), xs_n(6n, s), xs_n(7n, s), (xs_n(8n, s) .&. 1073741823 : U32)}

def step(st: St) -> St:
  St{+p, +s, +b} = st
  St{V.scalar_mul(p, Wd.W{s, 1, 0, 0, 0, 0, 0, 0}), xs_n(8n, s), (b + bad(p, rand_w(s)) : U32)}

def loop(n: Nat, st: St) -> St:
  match n:
    case 0n:
      st
    case 1n+k:
      loop(k, step(st))

def bad_of(st: St) -> U32:
  St{_, _, b} = st
  b

def main() -> IO(Unit):
  do IO<Unit>:
    t : Nat <- IO.now()
    +x : U32 = U32.from_nat(t)
    IO.print("random mismatches " ++ U32.show(bad_of(loop(300n, St{gen(), (x .^. 2463534242 : U32), 0}))) ++ " / 300")
    IO.print("edge mismatches (34 cases) " ++ U32.show(edge_loop(edges(), V.scalar_mul(gen(), Wd.W{((x .&. 0) + 1 : U32), 0, 0, 0, 0, 0, 0, 0}), 0)))
