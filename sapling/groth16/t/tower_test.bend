# tower_test <in.bin>: records of two Fq12 elements (24 raw Fq values). Prints per record:
#   fq2: mul sqr inv sqrt|none   (on a.c0.c0, b.c0.c0)
#   fq6: mul sqr inv frob        (on a.c0, b.c0)
#   fq12: mul sqr inv frob conj mul_by_014(a, b.c0.c0, b.c0.c1, b.c1.c1)
# one line each, checked by t/tower_test.py against ref/bls.py.
import Base
import ../fq.bend as F
import ../fq2.bend as E
import ../fq6.bend as S
import ../fq12.bend as T
import ../io.bend as IO2
import ./show.bend as Sh

def sq_str(r: Maybe<&2, E.Fq2>) -> String:
  match r:
    case Some{+x}:
      Sh.fq2(x)
    case None{}:
      "none"

def c00(a: T.Fq12) -> E.Fq2:
  match a:
    case T.Fq12{S.Fq6{y, _, _}, _}:
      y
    case _:
      E.zero()

def c01(a: T.Fq12) -> E.Fq2:
  match a:
    case T.Fq12{S.Fq6{_, y, _}, _}:
      y
    case _:
      E.zero()

def c11(a: T.Fq12) -> E.Fq2:
  match a:
    case T.Fq12{_, S.Fq6{_, y, _}}:
      y
    case _:
      E.zero()

def c0(a: T.Fq12) -> S.Fq6:
  T.Fq12{x, _} = a
  x

def lines(+a: T.Fq12, +b: T.Fq12) -> IO(Unit):
  +x = c00(a)
  +y = c00(b)
  +u = c0(a)
  +v = c0(b)
  do IO<Unit>:
    IO.print("fq2 " ++ Sh.fq2(E.mul(x, y)) ++ " " ++ Sh.fq2(E.sqr(x)) ++ " " ++ Sh.fq2(E.inv(x)) ++ " " ++ sq_str(E.sqrt(x)))
    IO.print("fq6 " ++ Sh.fq6(S.mul(u, v)) ++ " " ++ Sh.fq6(S.sqr(u)) ++ " " ++ Sh.fq6(S.inv(u)) ++ " " ++ Sh.fq6(S.frob(u)))
    IO.print("fq12 " ++ Sh.fq12(T.mul(a, b)) ++ " " ++ Sh.fq12(T.sqr(a)) ++ " " ++ Sh.fq12(T.inv(a)) ++ " " ++ Sh.fq12(T.frob(a)) ++ " " ++ Sh.fq12(T.conj(a)) ++ " " ++ Sh.fq12(T.mul_by_014(a, c00(b), c01(b), c11(b))))

def go(xs: +List<T.Fq12>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, rest}}:
      do IO<Unit>:
        lines(a, b)
        go(rest)
    case _:
      IO.pure(Unit, Unit{})

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{p, _}}:
      do IO<Unit>:
        bs : List<&2, U32> <- IO2.read_all(p)
        go(Sh.fq12s(IO2.fqs(IO2.pack4(bs))))
    case _:
      IO.print("usage: tower_test <in.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
