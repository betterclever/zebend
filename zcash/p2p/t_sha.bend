import Base
import ./bytes.bend as B
import ./sha256.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("sha256(\"\")    " ++ B.hex(H.hash(Nil{})))
    IO.print("sha256(\"abc\") " ++ B.hex(H.hash(B.of_string("abc"))))
    IO.print("sha256(448b)  " ++ B.hex(H.hash(B.of_string("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))))
    IO.print("sha256d(abc)  " ++ B.hex(H.hash_d(B.of_string("abc"))))
