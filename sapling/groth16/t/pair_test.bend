# pair_test <in.bin>: per vector (128 words: P x y | Q x0 x1 y0 y1 | P compressed (48 B) |
# Q compressed (96 B) | scalar (32 B LE)) prints
#   g1 <decoded P>   g2 <decoded Q>   smul <[s]P affine>   ml <MillerLoop(P, Q)>   pair <e(P, Q)>
# t/pair_test.py compares with the oracle's `vectors` output (bls12_381 crate).
import Base
import ../fq.bend as F
import ../fq2.bend as E
import ../fq12.bend as T
import ../g1.bend as G1
import ../g2.bend as G2
import ../pairing.bend as PR
import ../enc.bend as Enc
import ../io.bend as IO2
import ./show.bend as Sh

def mono(+ws: +List<U32>) -> G1.Aff:
  G1.Aff{F.from_raw(IO2.raw_fq(ws)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, ws, 12n)))}

def mtwo(+ws: +List<U32>) -> G2.Aff:
  +d = List.drop(&2, U32, ws, 24n)
  G2.Aff{E.Fq2{F.from_raw(IO2.raw_fq(ws)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, ws, 12n)))}, E.Fq2{F.from_raw(IO2.raw_fq(d)), F.from_raw(IO2.raw_fq(List.drop(&2, U32, d, 12n)))}}

def smul(+p: G1.Aff, +s: +List<U32>) -> G1.Aff:
  G1.to_aff(G1.mul_scalar(G1.from_aff(p), IO2.w_at(0n, s), IO2.w_at(1n, s), IO2.w_at(2n, s), IO2.w_at(3n, s), IO2.w_at(4n, s), IO2.w_at(5n, s), IO2.w_at(6n, s), IO2.w_at(7n, s)))

def one_vec(+ws: +List<U32>) -> IO(Unit):
  +p = mono(ws)
  +q = mtwo(List.drop(&2, U32, ws, 24n))
  +ml = PR.miller1(p, q)
  do IO<Unit>:
    IO.print("g1 " ++ Sh.m_g1(Enc.g1(List.drop(&2, U32, ws, 72n))))
    IO.print("g2 " ++ Sh.m_g2(Enc.g2(List.drop(&2, U32, ws, 84n))))
    IO.print("smul " ++ Sh.g1a(smul(p, List.drop(&2, U32, ws, 108n))))
    IO.print("ml " ++ Sh.fq12(ml))
    IO.print("pair " ++ Sh.fq12(PR.final_exp(ml)))

def go(fuel: Nat, +ws: +List<U32>) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        one_vec(ws)
        go(k, List.drop(&2, U32, ws, 116n))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{p, _}}:
      do IO<Unit>:
        bs : List<&2, U32> <- IO2.read_all(p)
        +ws : +List<U32> = IO2.pack4(bs)
        go(Nat.div(List.length(&2, U32, ws), 116n), ws)
    case _:
      IO.print("usage: pair_test <in.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
