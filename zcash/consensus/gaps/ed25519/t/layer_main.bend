# layer_main <set.bin>: per record, the intermediate values of ed25519.bend, in the format of
# `oracle layer`:  decode(A) decode(R) sha512(R||A||M) k S<l
# decode(X) is "-" if X does not decode, else the canonical re-encoding of the decoded point.
import Base
import ../ed25519.bend as E
import ../fp.bend as F
import ../fl.bend as L
import ../sha512.bend as H

def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

def hex(xs: +List<U32>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{+h, t}:
      SCon{hex_digit((h >> 4n : U32)), SCon{hex_digit((h .&. 15 : U32)), hex(t)}}

def le32(+x: U32) -> +List<U32>:
  [(x .&. 255 : U32), ((x >> 8n) .&. 255 : U32), ((x >> 16n) .&. 255 : U32), (x >> 24n : U32)]

def w8_bytes(w: E.W8) -> +List<U32>:
  E.W8{w0, w1, w2, w3, w4, w5, w6, w7} = w
  H.append(le32(w0), H.append(le32(w1), H.append(le32(w2), H.append(le32(w3),
    H.append(le32(w4), H.append(le32(w5), H.append(le32(w6), le32(w7))))))))

def raw_w8(a: F.Fp) -> E.W8:
  F.Fp{w0, w1, w2, w3, w4, w5, w6, w7} = a
  E.W8{w0, w1, w2, w3, w4, w5, w6, w7}

def set_top(w: E.W8, +b: U32) -> E.W8:
  E.W8{w0, w1, w2, w3, w4, w5, w6, w7} = w
  E.W8{w0, w1, w2, w3, w4, w5, w6, (w7 .|. (b << 31n) : U32)}

def encode(p: E.Pt) -> String:
  E.Pt{x, y, z, _} = p
  +zi = F.inv(z)
  hex(w8_bytes(set_top(raw_w8(F.to_raw(F.mul(y, zi))), F.low_bit(F.mul(x, zi)))))

def show_dec(m: Maybe<&2, E.Pt>) -> String:
  match m:
    case None{}:
      "-"
    case Some{p}:
      encode(p)

def bit(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def line(+pk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> String:
  +rb = E.take(sig, 32n)
  +s = E.w8(E.drop(sig, 32n))
  show_dec(E.decompress(E.w8(pk))) ++ " " ++ show_dec(E.decompress(E.w8(rb))) ++ " "
    ++ hex(H.hash(H.append(rb, H.append(pk, msg)))) ++ " " ++ hex(w8_bytes(E.challenge(rb, pk, msg))) ++ " "
    ++ bit(U32.is_eq(L.lt_p(E.fl_of(s)), 1))

def lines(fuel: Nat, +bs: +List<U32>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+f:
      +ml = E.get_le32(E.drop(bs, 96n))
      +rest = E.drop(bs, 100n)
      line(E.take(bs, 32n), E.take(E.drop(bs, 32n), 64n), E.take(rest, U32.to_nat(ml))) ++ "\n" ++ lines(f, E.drop(rest, U32.to_nat(ml)))

def got(f: File, res: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  match res:
    case Done{bytes}:
      do IO<List<&2, U32>>:
        File.close(f)
        return bytes
    case Fail{e}:
      do IO<List<&2, U32>>:
        File.close(f)
        return Nil{}

def got_pair(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  got(f, res)

def read_all(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 268435456)
    got_pair(r)

def run(setp: String) -> IO(Unit):
  do IO<Unit>:
    rb : List<&2, U32> <- read_all(setp)
    +bs : +List<U32> = rb
    IO.print(lines(U32.to_nat(E.get_le32(bs)), E.drop(bs, 4n)))

def run_args(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, _}}:
      run(a)
    case _:
      IO.print("usage: layer_main <set.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
