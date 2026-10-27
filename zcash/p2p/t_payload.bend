# Malformed payload handling: headers_valid / version_valid on synthetic payloads.
import Base
import ./bytes.bend as B
import ./node.bend as N

def hdr() -> +List<U32>:
  B.append(B.zeros(140n), B.append([253, 64, 5], B.append(B.zeros(1344n), [0])))

def hdrs(n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      B.append(hdr(), hdrs(p))

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "valid"
    case False{}:
      "rejected"

def ua(+n: U32) -> +List<U32>:
  B.append(B.zeros(80n), B.append(B.compact(n), B.append(B.zeros(U32.to_nat(n)), B.le32(3528000))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("headers 3 ok: " ++ yn(N.headers_valid(B.append([3], hdrs(3n)))))
    IO.print("headers count says 4, has 3: " ++ yn(N.headers_valid(B.append([4], hdrs(3n)))))
    IO.print("headers non-canonical count fd 03 00: " ++ yn(N.headers_valid(B.append([253, 3, 0], hdrs(3n)))))
    IO.print("headers trailing byte: " ++ yn(N.headers_valid(B.append([3], B.append(hdrs(3n), [7])))))
    IO.print("headers bad solution size: " ++ yn(N.headers_valid(B.append([1], B.append(B.zeros(140n), B.append([253, 65, 5], B.append(B.zeros(1345n), [0])))))))
    IO.print("headers 161: " ++ yn(N.headers_valid(B.append([161], hdrs(161n)))))
    IO.print("version ua 14: " ++ yn(N.version_valid(ua(14))))
    IO.print("version ua 257: " ++ yn(N.version_valid(ua(257))))
    IO.print("version truncated: " ++ yn(N.version_valid(B.take(ua(14), 96n))))
