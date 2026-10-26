# Point encodings: compressed G1 (48 bytes) / G2 (96 bytes) big-endian with the three
# flag bits on top, as they sit in a Groth16 proof. Input words come from io.pack4
# (little-endian packing of the bytes), so each is byte-swapped first.
import Base
import ./fq.bend as F
import ./fq2.bend as E
import ./g1.bend as G1
import ./g2.bend as G2
import ./io.bend as IO2

def bswap(+w: U32) -> U32:
  (((w .&. 255) << 24n) .|. (((w >> 8n) .&. 255) << 16n) .|. (((w >> 16n) .&. 255) << 8n) .|. (w >> 24n) : U32)

# 12 LE-packed words of a 48-byte big-endian value -> raw Fq; mask: AND for the top word.
def be_fq(+ws: +List<U32>, +mask: U32) -> F.Fq:
  F.Fq{bswap(IO2.w_at(11n, ws)), bswap(IO2.w_at(10n, ws)), bswap(IO2.w_at(9n, ws)), bswap(IO2.w_at(8n, ws)), bswap(IO2.w_at(7n, ws)), bswap(IO2.w_at(6n, ws)), bswap(IO2.w_at(5n, ws)), bswap(IO2.w_at(4n, ws)), bswap(IO2.w_at(3n, ws)), bswap(IO2.w_at(2n, ws)), bswap(IO2.w_at(1n, ws)), (bswap(IO2.w_at(0n, ws)) .&. mask : U32)}

def flags(+ws: +List<U32>) -> U32:
  (bswap(IO2.w_at(0n, ws)) >> 29n : U32)

def g1(+ws: +List<U32>) -> Maybe<&2, G1.Aff>:
  G1.decode(flags(ws), be_fq(ws, 536870911))

def g2(+ws: +List<U32>) -> Maybe<&2, G2.Aff>:
  G2.decode(flags(ws), be_fq(ws, 536870911), be_fq(List.drop(&2, U32, ws, 12n), 4294967295))
