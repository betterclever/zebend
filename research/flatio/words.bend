# Helpers over File.read_words arrays (bytes packed little-endian, four to a U32).
# Needs the fork's File.read_words (bend-fork branch zebend >= 3fbef653).
import Base

law load.got:
  for m: File & Result<&1, &1, U32 & String, Array<U32> & U32>
  IO(Array<U32> & U32)

def load.got(m):
  (f, r) = m
  do IO<Array<U32> & U32>:
    an : Array<U32> & U32 <- IO.pass(Array<U32> & U32, r)
    u : Unit <- File.close(f)
    return an

law load.sized:
  for p: File & Result<&1, &1, U32 & String, U32>
  IO(Array<U32> & U32)

def load.sized(p):
  (f, r) = p
  do IO<Array<U32> & U32>:
    n : U32 <- IO.pass(U32, r)
    m : File & Result<&1, &1, U32 & String, Array<U32> & U32> <- File.read_words(f, n)
    load.got(m)

# The whole file at path: its words and its byte count (dies on an IO error).
def load(path: String) -> IO(Array<U32> & U32):
  do IO<Array<U32> & U32>:
    f : File <- IO.try(File, File.open(path, "r"))
    p : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    load.sized(p)

def byte.of(+i: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +w) = r
  (a, (U32.shrn(w, U32.to_nat(((i .&. 3) << 3n : U32))) .&. 255 : U32))

# Byte i.
def byte(a: Array<U32>, +i: U32) -> Array<U32> & U32:
  byte.of(i, a[(i >> 2n : U32)])

def bswap(+x: U32) -> U32:
  ((x << 24n) .|. ((x << 8n) .&. 16711680) .|. ((x >> 8n) .&. 65280) .|. (x >> 24n) : U32)

def be.of(r: Array<U32> & U32) -> Array<U32> & U32:
  (a, +w) = r
  (a, bswap(w))

# Word k read big-endian (SHA-2 message words).
def be(a: Array<U32>, +k: U32) -> Array<U32> & U32:
  be.of(a[k])
