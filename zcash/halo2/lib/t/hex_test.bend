import Base
import ../words.bend as Wd
import ../fp.bend as Fp

def rt(+w: Wd.W) -> Bool:
  Wd.is_eq(Maybe.default(&2, Wd.W, Wd.from_hex(Wd.hex(w)), Wd.zero()), w)

def main() -> IO(Unit):
  +w = Fp.to_words(Fp.from_u32(3735928559))
  do IO<Unit>:
    IO.print(Wd.hex(w))
    IO.print(Bool.show(rt(w)))
    IO.print(Bool.show(rt(Wd.W{1, 2, 3, 4, 4294967295, 2864434397, 0, 2147483648})))
    IO.print(Wd.hex(Maybe.default(&2, Wd.W, Wd.from_hex("01000000000000000000000000000000000000000000000000000000000000AB"), Wd.zero())))
