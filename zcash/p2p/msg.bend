# Zcash P2P wire format (Bitcoin-derived): a 24-byte header
#   magic (4) | command, NUL-padded (12) | payload length LE (4) | SHA-256d(payload)[0..4]
# followed by the payload. Mainnet magic is 24 e9 27 64.
import Base
import ./bytes.bend as B
import ./sha256.bend as H

type Msg is Data:
  Msg{cmd: String, payload: +List<U32>}

type Parsed is Data:
  NeedMore{buf: +List<U32>}
  Got{msg: Msg, rest: +List<U32>}
  Bad{why: String}

def magic() -> +List<U32>:
  [36, 233, 39, 100]

def command_bytes(cmd: String) -> +List<U32>:
  B.take(B.append(B.of_string(cmd), B.zeros(12n)), 12n)

def checksum(+payload: +List<U32>) -> +List<U32>:
  B.take(H.hash_d(payload), 4n)

def frame(cmd: String, +payload: +List<U32>) -> +List<U32>:
  B.append(magic(), B.append(command_bytes(cmd),
    B.append(B.le32(B.length(payload)), B.append(checksum(payload), payload))))

def var_str(+s: String) -> +List<U32>:
  +bs = B.of_string(s)
  B.append(B.compact(B.length(bs)), bs)

# A network address without the time field (as in `version`): services, an
# IPv4-mapped IPv6 address, and the port in big-endian.
def net_addr(+ip4: +List<U32>, +port: U32) -> +List<U32>:
  B.append(B.zeros(8n), B.append(B.zeros(10n), B.append([255, 255],
    B.append(ip4, B.be16(port)))))

def ip4_push(+c: Char, +acc: U32, out: +List<U32>, dot: Bool) -> (U32 & +List<U32>):
  match dot:
    case True{}:
      (0, acc <> out)
    case False{}:
      ((acc * 10 + Char.to_u32(c) - 48 : U32), out)

def ip4_step(+c: Char, st: (U32 & +List<U32>)) -> (U32 & +List<U32>):
  (acc, out) = st
  ip4_push(c, acc, out, U32.is_eq(Char.to_u32(c), 46))

def ip4_fin(st: (U32 & +List<U32>)) -> +List<U32>:
  (acc, out) = st
  B.reverse(acc <> out)

def ip4_fold(s: String, st: (U32 & +List<U32>)) -> (U32 & +List<U32>):
  match s:
    case SNil{}:
      st
    case SCon{c, t}:
      ip4_fold(t, ip4_step(c, st))

def ip4_go(s: String, +acc: U32, out: +List<U32>) -> +List<U32>:
  ip4_fin(ip4_fold(s, (acc, out)))

def ip4_of(s: String) -> +List<U32>:
  ip4_go(s, 0, Nil{})

def version_payload(+proto: U32, +now: U32, +nonce: U32, +peer: String, +height: U32) -> +List<U32>:
  B.append(B.le32(proto),
  B.append(B.zeros(8n),
  B.append(B.le64(B.U64{now, 0}),
  B.append(net_addr(ip4_of(peer), 8233),
  B.append(net_addr([0, 0, 0, 0], 0),
  B.append(B.le64(B.U64{nonce, 2052149870}),
  B.append(var_str("/Zebend:0.1.0/"),
  B.append(B.le32(height), [0]))))))))

# getheaders: protocol version, one locator hash (internal byte order), stop = 0 (as many as allowed).
def getheaders_payload(+proto: U32, +locator: +List<U32>) -> +List<U32>:
  B.append(B.le32(proto), B.append([1], B.append(locator, B.zeros(32n))))

# Hardened framing (merged from tools/harden/lib/frame.bend; same verdicts as zcashd on 100k
# fuzzed frames):
#   magic 24 e9 27 64;
#   command: printable ASCII (0x20..0x7e) up to the first NUL, then only NULs;
#   payload length <= 2 MiB, rejected from the 24-byte header alone, so a peer cannot make
#     us buffer an unbounded payload (MAX_PROTOCOL_MESSAGE_LENGTH);
#   the length is compared as len <= n - 24, which cannot wrap;
#   checksum = SHA-256d(payload)[0..4].
def max_payload() -> U32:
  2097152

# Twelve command bytes, folded over states 0 (before any NUL), 1 (after a NUL), >= 2 (invalid).
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

def parse_check(ok: Bool, +buf: +List<U32>, +len: U32, +payload: +List<U32>) -> Parsed:
  match ok:
    case True{}:
      Got{Msg{B.to_cstring(B.take(B.drop(buf, 4n), 12n)), payload}, B.drop_u(B.drop(buf, 24n), len)}
    case False{}:
      Bad{"checksum mismatch on " ++ B.to_cstring(B.take(B.drop(buf, 4n), 12n))}

def parse_body(+buf: +List<U32>, +len: U32, have: Bool) -> Parsed:
  match have:
    case False{}:
      NeedMore{buf}
    case True{}:
      +payload = B.take_u(B.drop(buf, 24n), len)
      parse_check(B.is_eq(checksum(payload), B.take(B.drop(buf, 20n), 4n)), buf, len, payload)

def parse_sized(ok: Bool, +buf: +List<U32>, +n: U32, +len: U32) -> Parsed:
  match ok:
    case False{}:
      Bad{"payload length " ++ U32.show(len) ++ " over the 2 MiB limit"}
    case True{}:
      parse_body(buf, len, U32.is_le(len, (n - 24 : U32)))

def parse_magic(ok: Bool, +buf: +List<U32>, +n: U32) -> Parsed:
  match ok:
    case False{}:
      Bad{"bad magic or command " ++ B.hex(B.take(buf, 16n))}
    case True{}:
      +len = B.get_le32(B.drop(buf, 16n))
      parse_sized(U32.is_le(len, max_payload()), buf, n, len)

def parse_head(have: Bool, +buf: +List<U32>, +n: U32) -> Parsed:
  match have:
    case False{}:
      NeedMore{buf}
    case True{}:
      parse_magic(B.is_eq(B.take(buf, 4n), magic()) && cmd_ok(B.take(B.drop(buf, 4n), 12n)), buf, n)

# One complete message off the front of the receive buffer, if there is one.
def parse(+buf: +List<U32>) -> Parsed:
  +n = B.length(buf)
  parse_head(U32.is_le(24, n), buf, n)
