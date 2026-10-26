# fq_test <pairs.bin>: for each pair of raw 384-bit values (a, b) (12 LE words each) prints
#   lt_p(a) lt_half(a) | a*b  a^2  a+b  a-b  -a  a^-1  sqrt(a) or "none"
# (a, b reduced mod p first, via from_raw); t/fq_test.py checks every value with Python integers.
import Base
import ../fq.bend as F
import ../io.bend as IO2

def sq_str(r: Maybe<&2, F.Fq>) -> String:
  match r:
    case Some{+x}:
      IO2.hex_fq(x)
    case None{}:
      "none"

def line(+ra: F.Fq, +rb: F.Fq) -> String:
  +a = F.from_raw(ra)
  +b = F.from_raw(rb)
  U32.show(F.lt_p(ra)) ++ " " ++ U32.show(F.lt_half(ra)) ++ " " ++ IO2.hex_fq(F.mul(a, b)) ++ " " ++ IO2.hex_fq(F.sqr(a)) ++ " " ++ IO2.hex_fq(F.add(a, b)) ++ " " ++ IO2.hex_fq(F.sub(a, b)) ++ " " ++ IO2.hex_fq(F.neg(a)) ++ " " ++ IO2.hex_fq(F.inv(a)) ++ " " ++ sq_str(F.sqrt(a))

def go(xs: +List<F.Fq>) -> IO(Unit):
  match xs:
    case Con{+a, Con{+b, rest}}:
      do IO<Unit>:
        IO.print(line(a, b))
        go(rest)
    case _:
      IO.pure(Unit, Unit{})

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{p, _}}:
      do IO<Unit>:
        bs : List<&2, U32> <- IO2.read_all(p)
        go(IO2.fqs(IO2.pack4(bs)))
    case _:
      IO.print("usage: fq_test <pairs.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
