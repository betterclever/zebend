import Base
import ../../lib/fp.bend as Fp
import ../../lib/words.bend as Wd

type BF is Data:
  BF0{v: Fp.Fp}
  BF1{v: Fp.Fp, n: BF}

def ub(b: BF) -> Fp.Fp:
  match b:
    case BF0{+v}:
      v
    case BF1{+v, _}:
      v

def bmul(a: BF, b: BF) -> BF:
  BF0{Fp.mul(ub(a), ub(b))}

def badd(a: BF, b: BF) -> BF:
  BF0{Fp.add(ub(a), ub(b))}

def g(+a0: BF, +a1: BF, +a2: BF, +a3: BF, +a4: BF, +a5: BF, +a6: BF, +a7: BF, +a8: BF, +a9: BF, +a10: BF, +a11: BF, +a12: BF, +a13: BF, +a14: BF, +a15: BF, +a16: BF, +a17: BF, +a18: BF, +a19: BF, +a20: BF, +a21: BF, +a22: BF, +a23: BF, +a24: BF, +a25: BF, +a26: BF, +a27: BF, +a28: BF, +a29: BF, +a30: BF, +a31: BF, +a32: BF, +a33: BF, +a34: BF, +a35: BF, +a36: BF, +a37: BF, +a38: BF, +a39: BF) -> BF:
  +s1 = badd(a0, a1)
  +s2 = badd(s1, a2)
  +s3 = badd(s2, a3)
  +s4 = badd(s3, a4)
  +s5 = badd(s4, a5)
  +s6 = badd(s5, a6)
  +s7 = badd(s6, a7)
  +s8 = badd(s7, a8)
  +s9 = badd(s8, a9)
  +s10 = badd(s9, a10)
  +s11 = badd(s10, a11)
  +s12 = badd(s11, a12)
  +s13 = badd(s12, a13)
  +s14 = badd(s13, a14)
  +s15 = badd(s14, a15)
  +s16 = badd(s15, a16)
  +s17 = badd(s16, a17)
  +s18 = badd(s17, a18)
  +s19 = badd(s18, a19)
  +s20 = badd(s19, a20)
  +s21 = badd(s20, a21)
  +s22 = badd(s21, a22)
  +s23 = badd(s22, a23)
  +s24 = badd(s23, a24)
  +s25 = badd(s24, a25)
  +s26 = badd(s25, a26)
  +s27 = badd(s26, a27)
  +s28 = badd(s27, a28)
  +s29 = badd(s28, a29)
  +s30 = badd(s29, a30)
  +s31 = badd(s30, a31)
  +s32 = badd(s31, a32)
  +s33 = badd(s32, a33)
  +s34 = badd(s33, a34)
  +s35 = badd(s34, a35)
  +s36 = badd(s35, a36)
  +s37 = badd(s36, a37)
  +s38 = badd(s37, a38)
  +s39 = badd(s38, a39)
  +z = bmul(s39, a0)
  badd(z, a1)

def main() -> IO(Unit):
  +r = g(BF0{Fp.from_u32(1)}, BF0{Fp.from_u32(2)}, BF0{Fp.from_u32(3)}, BF0{Fp.from_u32(4)}, BF0{Fp.from_u32(5)}, BF0{Fp.from_u32(6)}, BF0{Fp.from_u32(7)}, BF0{Fp.from_u32(8)}, BF0{Fp.from_u32(9)}, BF0{Fp.from_u32(10)}, BF0{Fp.from_u32(11)}, BF0{Fp.from_u32(12)}, BF0{Fp.from_u32(13)}, BF0{Fp.from_u32(14)}, BF0{Fp.from_u32(15)}, BF0{Fp.from_u32(16)}, BF0{Fp.from_u32(17)}, BF0{Fp.from_u32(18)}, BF0{Fp.from_u32(19)}, BF0{Fp.from_u32(20)}, BF0{Fp.from_u32(21)}, BF0{Fp.from_u32(22)}, BF0{Fp.from_u32(23)}, BF0{Fp.from_u32(24)}, BF0{Fp.from_u32(25)}, BF0{Fp.from_u32(26)}, BF0{Fp.from_u32(27)}, BF0{Fp.from_u32(28)}, BF0{Fp.from_u32(29)}, BF0{Fp.from_u32(30)}, BF0{Fp.from_u32(31)}, BF0{Fp.from_u32(32)}, BF0{Fp.from_u32(33)}, BF0{Fp.from_u32(34)}, BF0{Fp.from_u32(35)}, BF0{Fp.from_u32(36)}, BF0{Fp.from_u32(37)}, BF0{Fp.from_u32(38)}, BF0{Fp.from_u32(39)}, BF0{Fp.from_u32(40)})
  do IO<Unit>:
    IO.print(Wd.hex(Fp.to_words(ub(r))))
