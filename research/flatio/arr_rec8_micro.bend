# 100 x (2^17 Array<F8> sets + gets), F8 = 8 U32s stored inline: one get/set moves 8 words
import Base

type F8 is Data:
  F8{v0: U32, v1: U32, v2: U32, v3: U32, v4: U32, v5: U32, v6: U32, v7: U32}

def mk(+i: U32) -> F8:
  F8{i, (i + 1 : U32), (i + 2 : U32), (i + 3 : U32), (i + 4 : U32), (i + 5 : U32), (i + 6 : U32), (i + 7 : U32)}

def f8sum(x: F8) -> U32:
  F8{a, b, c, d, e, f, g, h} = x
  (a + b + c + d + e + f + g + h : U32)

def fill(n: Nat, a: Array<F8>, +i: U32) -> Array<F8>:
  match n:
    case 0n:
      a
    case 1n+p:
      fill(p, Array.set(F8, a, i, mk(i)), U32.inc(i))

def sum.go(n: Nat, r: Array<F8> & F8, +i: U32, acc: U32) -> Array<F8> & U32:
  match n:
    case 0n:
      (a, x) = r
      (a, U32.add(acc, f8sum(x)))
    case 1n+p:
      (a, x) = r
      +j = U32.inc(i)
      sum.go(p, Array.get(F8, a, j), j, U32.add(acc, f8sum(x)))

def rep.k(bs: Array<F8> & U32) -> Array<F8> & U32:
  (b, s) = bs
  (fill(131072n, b, 0), s)

def rep(a: Array<F8>, acc: U32) -> Array<F8> & U32:
  rep.k(sum.go(131071n, Array.get(F8, a, 0), 0, acc))

def reps(r: Nat, bs: Array<F8> & U32) -> U32:
  match r:
    case 0n:
      (b, s) = bs
      s
    case 1n+p:
      (b, s) = bs
      reps(p, rep(b, s))

def main() -> U32:
  reps(100n, (fill(131072n, [F8{0,0,0,0,0,0,0,0} : F8^17n], 0), 0))
