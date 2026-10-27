# Hex printing of tower elements (canonical coefficients, space separated, in the order
# c0.c0.c0 c0.c0.c1 c0.c1.c0 ... as the oracle prints them).
import Base
import ../fq.bend as F
import ../fq2.bend as E
import ../fq6.bend as S
import ../fq12.bend as T
import ../io.bend as IO2
import ../g1.bend as G1
import ../g2.bend as G2

def fq2(a: E.Fq2) -> String:
  E.Fq2{a0, a1} = a
  IO2.hex_fq(a0) ++ " " ++ IO2.hex_fq(a1)

def fq6(a: S.Fq6) -> String:
  match a:
    case S.Fq6{a0, a1, a2}:
      fq2(a0) ++ " " ++ fq2(a1) ++ " " ++ fq2(a2)
    case _:
      "?"

def fq12(a: T.Fq12) -> String:
  T.Fq12{a0, a1} = a
  fq6(a0) ++ " " ++ fq6(a1)

# raw words -> elements (Montgomery)
def mk2(+a: F.Fq, +b: F.Fq) -> E.Fq2:
  E.Fq2{F.from_raw(a), F.from_raw(b)}

# 12 consecutive raw Fq values -> Fq12 (order c0.c0.c0, c0.c0.c1, ...), the rest of the list
def fq12s(xs: +List<F.Fq>) -> +List<T.Fq12>:
  match xs:
    case Con{+a0, Con{+a1, Con{+a2, Con{+a3, Con{+a4, Con{+a5, Con{+a6, Con{+a7, Con{+a8, Con{+a9, Con{+a10, Con{+a11, rest}}}}}}}}}}}}:
      T.Fq12{S.Fq6{mk2(a0, a1), mk2(a2, a3), mk2(a4, a5)}, S.Fq6{mk2(a6, a7), mk2(a8, a9), mk2(a10, a11)}} <> fq12s(rest)
    case _:
      Nil{}


def g1a(a: G1.Aff) -> String:
  G1.Aff{x, y} = a
  IO2.hex_fq(x) ++ " " ++ IO2.hex_fq(y)

def g2a(a: G2.Aff) -> String:
  G2.Aff{x, y} = a
  fq2(x) ++ " " ++ fq2(y)

def m_g1(m: Maybe<&2, G1.Aff>) -> String:
  match m:
    case Some{a}:
      g1a(a)
    case None{}:
      "none"

def m_g2(m: Maybe<&2, G2.Aff>) -> String:
  match m:
    case Some{a}:
      g2a(a)
    case None{}:
      "none"
