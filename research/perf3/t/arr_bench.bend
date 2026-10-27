# Cost of reading a flat Array<U32> vs walking a shared list of 16-word records.
import Base

type R is Data:
  R{a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32, b0: U32, b1: U32, b2: U32, b3: U32, b4: U32, b5: U32, b6: U32, b7: U32}

def rsum(+r: R) -> U32:
  R{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7} = r
  (a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + b0 + b1 + b2 + b3 + b4 + b5 + b6 + b7 : U32)

def mk(n: Nat, +i: U32, acc: +List<R>) -> +List<R>:
  match n:
    case 0n:
      acc
    case 1n+k:
      mk(k, (i + 1 : U32), R{i, i, i, i, i, i, i, i, i, i, i, i, i, i, i, i} <> acc)

def walk(xs: +List<R>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      walk(t, (acc + rsum(h) : U32))

def walks(n: Nat, +xs: +List<R>, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      walks(k, xs, (acc + walk(xs, 0) : U32))

def fill(n: Nat, +i: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+k:
      fill(k, (i + 1 : U32), a[i] <- (i / 16 : U32))

def asum(n: Nat, +i: U32, r: Array<U32> & U32, acc: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, v) = r
      (a, (acc + v : U32))
    case 1n+k:
      (a, v) = r
      asum(k, (i + 1 : U32), a[i], (acc + v : U32))

def asums(n: Nat, r: Array<U32> & U32, acc: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, s) = r
      (a, (acc + s : U32))
    case 1n+k:
      (a, s) = r
      asums(k, asum(32768n, 0, (a, 0), 0), (acc + s : U32))

def snd(p: Array<U32> & U32) -> U32:
  (_, v) = p
  v

def main() -> IO(Unit):
  +xs : +List<R> = mk(2048n, 0, Nil{})
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +s1 : U32 = walks(300n, xs, 0)
    IO.print("list " ++ U32.show(s1))
    t1 : Nat <- IO.now()
    t1b : Nat <- IO.now()
    +s2 : U32 = snd(asums(300n, (fill(32768n, 0, [0 : U32^15n]), 0), 0))
    IO.print("array " ++ U32.show(s2))
    t2 : Nat <- IO.now()
    IO.print("list walk ms " ++ Nat.show(Nat.sub(t1, t0)) ++ "  array read ms " ++ Nat.show(Nat.sub(t2, t1b)) ++ "  (9.83M words each)")
