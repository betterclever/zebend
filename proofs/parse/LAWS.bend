# Laws about node/p2p's byte codecs and CompactSize (node/p2p/bytes.bend, imported as is),
# and about node/headers' splitting of a header stream (node/headers/main.bend).
import Base
import ../../node/p2p/bytes.bend as B
import ./canon.bend as C
import ../../node/headers/main.bend as M

# Little-endian 32-bit encode -> decode is the identity on every U32.
law le32_roundtrip:
  for +x: U32
  {B.get_le32(B.le32(x)) == x : U32}

# Little-endian 16-bit encode -> decode is the identity on every U32 below 2^16.
law le16_roundtrip:
  for +x: U32
  for h: {U32.is_lt(x, 65536) == True{} : Bool}
  {B.get_le16(B.le16(x)) == x : U32}

# CompactSize: decoding the encoding of any n gives n back, and consumes exactly the
# encoding's bytes, whatever follows it.
law compact_roundtrip:
  for +n: U32
  for +rest: +List<U32>
  {B.read_compact(B.append(B.compact(n), rest)) == B.Compact{n, B.length(B.compact(n))} : B.Compact}

# Finding: node/p2p's decoder also accepts NON-canonical encodings (zcashd rejects
# them): [0xfd, 5, 0] decodes to 5, whose canonical encoding is the single byte [5].
law noncanonical_accepted:
  {B.read_compact([253, 5, 0]) == B.Compact{5, 3} : B.Compact}

law noncanonical_differs:
  {B.compact(5) == [5] : +List<U32>}

# The canonical decoder rejects that input ...
law canon_rejects_example:
  {C.read_compact_canon([253, 5, 0]) == None{} : Maybe<&2, B.Compact>}

# ... accepts every canonical encoding, followed by anything ...
law canon_accepts:
  for +n: U32
  for +rest: +List<U32>
  {C.read_compact_canon(B.append(B.compact(n), rest)) == Some{B.Compact{n, B.length(B.compact(n))}} : Maybe<&2, B.Compact>}

# ... and whatever it accepts is canonical: the consumed bytes are exactly compact(value).
law canon_sound:
  for +xs: +List<U32>
  for +v: U32
  for +w: U32
  for h: {C.read_compact_canon(xs) == Some{B.Compact{v, w}} : Maybe<&2, B.Compact>}
  {B.is_eq(B.take_u(xs, w), B.compact(v)) == True{} : Bool}

# node/headers' split of a header stream into 1487-byte headers loses and invents
# nothing: concatenating the k pieces gives back the first k*1487 bytes.
law header_split_concat:
  for +k: Nat
  for +bs: +List<U32>
  {List.concat(&2, U32, M.split(k, bs)) == List.take(&2, U32, bs, Nat.mul(k, 1487n)) : +List<U32>}
