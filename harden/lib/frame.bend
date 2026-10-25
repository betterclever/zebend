# Hardened P2P framing (replaces the checks in node/p2p/msg.bend parse):
#   magic 24 e9 27 64;
#   command: printable ASCII (0x20..0x7e) up to the first NUL, then only NULs
#     (zcashd CMessageHeader::IsCommandValid);
#   payload length <= 2 MiB, rejected from the 24-byte header alone, so a peer cannot make
#     us buffer an unbounded payload (MAX_PROTOCOL_MESSAGE_LENGTH);
#   checksum = SHA-256d(payload)[0..4].
# The length check comes before the "need more bytes" test, and 24 + len cannot wrap.
import Base
import ../../node/p2p/bytes.bend as B
import ../../node/p2p/sha256.bend as Sha
import ./hb.bend as H

def max_payload() -> U32:
  2097152

type Frame is Data:
  FBad{}
  FMore{}
  FGot{cmd: +List<U32>, len: U32, rest: +List<U32>}

# Twelve command bytes: printable until the first NUL, NUL after it. A fold over states
# 0 (before any NUL), 1 (after a NUL), >= 2 (invalid).
def cmd_byte(nul: Bool, +st: U32, +h: U32) -> U32:
  match nul:
    case True{}:
      (st .|. 1 : U32)
    case False{}:
      (Bool.to_u32(U32.is_ne(st, 0) || Bool.not(U32.is_le(32, h) && U32.is_le(h, 126))) << 1n : U32)

def cmd_go(xs: +List<U32>, +st: U32) -> U32:
  match xs:
    case Nil{}:
      st
    case Con{+h, t}:
      cmd_go(t, cmd_byte(U32.is_eq(h, 0), st, h))

def cmd_ok(+xs: +List<U32>) -> Bool:
  U32.is_lt(cmd_go(xs, 0), 2)

def got_check(ok: Bool, +xs: +List<U32>, +len: U32) -> Frame:
  match ok:
    case False{}:
      FBad{}
    case True{}:
      FGot{B.until_nul(H.take(H.drop(xs, 4), 12)), len, H.drop(xs, (24 + len : U32))}

def body(have: Bool, +xs: +List<U32>, +len: U32) -> Frame:
  match have:
    case False{}:
      FMore{}
    case True{}:
      got_check(B.is_eq(H.take(Sha.hash_d(H.take(H.drop(xs, 24), len)), 4), H.take(H.drop(xs, 20), 4)), xs, len)

def sized(ok: Bool, +xs: +List<U32>, +n: U32, +len: U32) -> Frame:
  match ok:
    case False{}:
      FBad{}
    case True{}:
      body(U32.is_le(len, (n - 24 : U32)), xs, len)

def headed(ok: Bool, +xs: +List<U32>, +n: U32) -> Frame:
  match ok:
    case False{}:
      FBad{}
    case True{}:
      +len = H.le32(H.drop(xs, 16))
      sized(U32.is_le(len, max_payload()), xs, n, len)

def framed(have: Bool, +xs: +List<U32>, +n: U32) -> Frame:
  match have:
    case False{}:
      FMore{}
    case True{}:
      headed(B.is_eq(H.take(xs, 4), [36, 233, 39, 100]) && cmd_ok(H.take(H.drop(xs, 4), 12)), xs, n)

# One message off the front of a receive buffer: FBad (drop the peer), FMore, or FGot.
def parse(+xs: +List<U32>) -> Frame:
  +n = H.length(xs)
  framed(U32.is_le(24, n), xs, n)
