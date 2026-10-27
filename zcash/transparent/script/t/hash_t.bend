# hash_t FILE: records u32 len || bytes -> "ripemd160 sha1 sha256 hash160 hash256" (hex) per line.
import Base
import ../../util.bend as U
import ../rmd_sha1.bend as H
import ../../../block/sha256.bend as S

def line(+m: +List<U32>) -> String:
  U.hex(H.ripemd160(m)) ++ " " ++ U.hex(H.sha1(m)) ++ " " ++ U.hex(S.hash(m)) ++ " "
    ++ U.hex(H.ripemd160(S.hash(m))) ++ " " ++ U.hex(S.hash_d(m)) ++ "\n"

def go(fuel: Nat, +xs: +List<U32>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+p:
      +n = U32.to_nat(U.le32(xs))
      +rest = U.drop(xs, (4n + n : Nat))
      line(U.at(xs, 4n, n)) ++ Bool.pick(String, U.is_empty(rest), "", go(p, rest))

def path1(xs: List<String>) -> String:
  match xs:
    case Con{_, Con{a, _}}:
      a
    case _:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(path1(args), "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 50000000)
    +bs : +List<U32> = U.bytes_of(r)
    IO.print(go(U32.to_nat(U.len(bs)), bs))
