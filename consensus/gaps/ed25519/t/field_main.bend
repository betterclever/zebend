# field_main <pairs.bin>: u32 count, then count x (a 32 bytes | b 32 bytes), raw 256-bit LE.
# Per pair prints (hex, canonical LE):  Fp: a mod p, a*b, a^2, a+b, a-b, a^-1, a^((p-5)/8),
# low_bit(a), a < p; Fl: a mod l, a*b, a+b, a < l.  (field_test.py checks against Python.)
import Base
import ../ed25519.bend as E
import ../fp.bend as F
import ../fl.bend as L
import ./layer_main.bend as T

def fph(a: F.Fp) -> String:
  T.hex(T.w8_bytes(T.raw_w8(F.to_raw(a))))

def flh(a: L.Fl) -> String:
  T.hex(T.w8_bytes(E.w8_of_fl(L.to_raw(a))))

def u(+x: U32) -> String:
  U32.show(x)

def line(+aw: E.W8, +bw: E.W8) -> String:
  +a = F.from_raw(E.fp_of(aw))
  +b = F.from_raw(E.fp_of(bw))
  +la = L.from_raw(E.fl_of(aw))
  +lb = L.from_raw(E.fl_of(bw))
  fph(a) ++ " " ++ fph(F.mul(a, b)) ++ " " ++ fph(F.sqr(a)) ++ " " ++ fph(F.add(a, b)) ++ " " ++ fph(F.sub(a, b))
    ++ " " ++ fph(F.inv(a)) ++ " " ++ fph(F.pow_p58(a)) ++ " " ++ u(F.low_bit(a)) ++ " " ++ u(F.lt_p(E.fp_of(aw)))
    ++ " " ++ flh(la) ++ " " ++ flh(L.mul(la, lb)) ++ " " ++ flh(L.add(la, lb)) ++ " " ++ u(L.lt_p(E.fl_of(aw)))

def lines(fuel: Nat, +bs: +List<U32>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+f:
      line(E.w8(bs), E.w8(E.drop(bs, 32n))) ++ "\n" ++ lines(f, E.drop(bs, 64n))

def run(setp: String) -> IO(Unit):
  do IO<Unit>:
    rb : List<&2, U32> <- T.read_all(setp)
    +bs : +List<U32> = rb
    IO.print(lines(U32.to_nat(E.get_le32(bs)), E.drop(bs, 4n)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, _}}:
      run(a)
    case _:
      IO.print("usage: field_main <pairs.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
