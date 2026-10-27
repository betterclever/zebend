# Flat-array input helpers (File.read_words, bend-fork zebend >= 3fbef653): params_g.bin as
# points and files as word lists, without one List cell per byte.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as Fq
import ../../../crypto/field3/lib64/vesta.bend as V
import ../../flatio/words.bend as FW

type XY is Data:
  XY{x: Wd.W, y: Wd.W}

def w16_16(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, +w14: U32) -> Array<U32> & XY:
  (a, +w15) = r
  (a, XY{Wd.W{w0, w1, w2, w3, w4, w5, w6, w7}, Wd.W{w8, w9, w10, w11, w12, w13, w14, w15}})

def w16_15(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32) -> Array<U32> & XY:
  (a, +w14) = r
  w16_16(a[(o + 15 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14)

def w16_14(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32) -> Array<U32> & XY:
  (a, +w13) = r
  w16_15(a[(o + 14 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13)

def w16_13(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32) -> Array<U32> & XY:
  (a, +w12) = r
  w16_14(a[(o + 13 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12)

def w16_12(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32) -> Array<U32> & XY:
  (a, +w11) = r
  w16_13(a[(o + 12 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11)

def w16_11(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32) -> Array<U32> & XY:
  (a, +w10) = r
  w16_12(a[(o + 11 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)

def w16_10(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32) -> Array<U32> & XY:
  (a, +w9) = r
  w16_11(a[(o + 10 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9)

def w16_9(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32) -> Array<U32> & XY:
  (a, +w8) = r
  w16_10(a[(o + 9 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8)

def w16_8(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32) -> Array<U32> & XY:
  (a, +w7) = r
  w16_9(a[(o + 8 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7)

def w16_7(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32) -> Array<U32> & XY:
  (a, +w6) = r
  w16_8(a[(o + 7 : U32)], o, w0, w1, w2, w3, w4, w5, w6)

def w16_6(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32) -> Array<U32> & XY:
  (a, +w5) = r
  w16_7(a[(o + 6 : U32)], o, w0, w1, w2, w3, w4, w5)

def w16_5(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32) -> Array<U32> & XY:
  (a, +w4) = r
  w16_6(a[(o + 5 : U32)], o, w0, w1, w2, w3, w4)

def w16_4(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32) -> Array<U32> & XY:
  (a, +w3) = r
  w16_5(a[(o + 4 : U32)], o, w0, w1, w2, w3)

def w16_3(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32) -> Array<U32> & XY:
  (a, +w2) = r
  w16_4(a[(o + 3 : U32)], o, w0, w1, w2)

def w16_2(r: Array<U32> & U32, +o: U32, +w0: U32) -> Array<U32> & XY:
  (a, +w1) = r
  w16_3(a[(o + 2 : U32)], o, w0, w1)

def w16_1(r: Array<U32> & U32, +o: U32) -> Array<U32> & XY:
  (a, +w0) = r
  w16_2(a[(o + 1 : U32)], o, w0)

def w16(a: Array<U32>, +o: U32) -> Array<U32> & XY:
  w16_1(a[o], o)

# n points from (x || y) 64-byte records; r holds the record at word o
def pts(n: Nat, +o: U32, r: Array<U32> & XY) -> +List<V.Pt>:
  match n:
    case 0n:
      (a, +xy) = r
      XY{+x, +y} = xy
      Nil{}
    case 1n+k:
      (a, +xy) = r
      XY{+x, +y} = xy
      V.from_aff(V.Aff{Fq.from_words(x), Fq.from_words(y)}) <> pts(k, (o + 16 : U32), w16(a, (o + 16 : U32)))

def params_of(r: Array<U32> & U32) -> +List<V.Pt>:
  (a, +nb) = r
  pts(U32.to_nat((nb / 64 : U32)), 0, w16(a, 0))

# the generators of params_g.bin (2^k records of 64 bytes)
def params(path: String) -> IO(+List<V.Pt>):
  do IO<+List<V.Pt>>:
    r : Array<U32> & U32 <- FW.load(path)
    return params_of(r)

# n words from word o on; r holds word o
def wlist(n: Nat, +o: U32, r: Array<U32> & U32) -> +List<U32>:
  match n:
    case 0n:
      (a, +w) = r
      Nil{}
    case 1n+k:
      (a, +w) = r
      w <> wlist(k, (o + 1 : U32), a[(o + 1 : U32)])

# a whole file as little-endian words (the last one zero-padded)
def words_of(r: Array<U32> & U32) -> +List<U32>:
  (a, +nb) = r
  wlist(U32.to_nat(((nb + 3) / 4 : U32)), 0, a[0])

# --- an optional file (a missing or unreadable file is ONone, not an error) ------------

type OT is Type:
  ONone{}
  OSome{a: Array<U32>, n: U32}

def opt_got(m: File & Result<&1, &1, U32 & String, Array<U32> & U32>) -> IO(OT):
  (f, r) = m
  match r:
    case Done{an}:
      (a, n) = an
      do IO<OT>:
        File.close(f)
        return OSome{a, n}
    case Fail{e}:
      do IO<OT>:
        File.close(f)
        return ONone{}

def opt_sized(p: File & Result<&1, &1, U32 & String, U32>) -> IO(OT):
  (f, r) = p
  match r:
    case Done{n}:
      do IO<OT>:
        m : File & Result<&1, &1, U32 & String, Array<U32> & U32> <- File.read_words(f, n)
        opt_got(m)
    case Fail{e}:
      do IO<OT>:
        File.close(f)
        return ONone{}

def opt_open(r: Result<&1, &1, U32 & String, File>) -> IO(OT):
  match r:
    case Done{f}:
      do IO<OT>:
        p : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        opt_sized(p)
    case Fail{e}:
      IO.pure(OT, ONone{})

def load_opt(path: String) -> IO(OT):
  do IO<OT>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    opt_open(r)

def rands(n: Nat, acc: +List<U32>) -> IO(+List<U32>):
  match n:
    case 0n:
      IO.pure(+List<U32>, acc)
    case 1n+k:
      do IO<+List<U32>>:
        a : U32 <- IO.try(U32, IO.random_u32())
        rands(k, a <> acc)
