# 100 x (2^20 Array<U32> sets + 2^20 gets): the cost of one flat U32 get/set in emitted C
import Base

def fill(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- U32.mul(i, 2654435761)
      fill(p, a, U32.inc(i))

def sum.go(n: Nat, r: Array<U32> & U32, +i: U32, acc: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, x) = r
      (a, U32.add(acc, x))
    case 1n+p:
      (a, x) = r
      +j = U32.inc(i)
      sum.go(p, a[j], j, U32.add(acc, x))

def rep.k(bs: Array<U32> & U32) -> Array<U32> & U32:
  (b, s) = bs
  (fill(1048576n, b, 0), s)

def rep(a: Array<U32>, acc: U32) -> Array<U32> & U32:
  rep.k(sum.go(1048575n, a[0], 0, acc))

def reps(r: Nat, bs: Array<U32> & U32) -> U32:
  match r:
    case 0n:
      (b, s) = bs
      s
    case 1n+p:
      (b, s) = bs
      reps(p, rep(b, s))

def main() -> U32:
  reps(100n, (fill(1048576n, [0 : U32^20n], 0), 0))
