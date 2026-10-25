# Strict parsing of the Halo 2 verifier's bundle input (halo2/verifier/bundle_main.bend):
#   u32 LE np, u32 LE ni, u32 LE plen, the proof (plen bytes), np * ni instance values.
# bundle_main trusted all three header words: ni = 2^32 - 1 drove it to ~8 GB and a crash,
# np = 2^32 - 1 never finished, and trailing bytes were ignored. Here the header is checked
# against the Orchard shape before anything is allocated:
#   1 <= np <= 2439 (the most 820-byte actions a 2,000,000-byte block can hold);
#   ni = 10 (the Orchard / Ironwood action circuit's public inputs);
#   plen = 2720 + 2272 np (orchard validate_proof_size);
#   total length = 12 + plen + 32 np ni exactly;
#   every instance value is a canonical Pallas base field element.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../halo2/lib/fp.bend as Fp
import ./hb.bend as H

def max_actions() -> U32:
  2439

def instances() -> U32:
  10

# n words, all present (the total length was checked first), each < p.
def canon_go(n: Nat, +xs: +List<U32>) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+m:
      Wd.is_lt(H.w32(xs), Fp.modulus()) && canon_go(m, H.drop(xs, 32))

def shape_ok(+n: U32, +np: U32, +ni: U32, +plen: U32) -> Bool:
  U32.is_le(1, np) && U32.is_le(np, max_actions()) && U32.is_eq(ni, instances()) &&
  U32.is_eq(plen, (2720 + 2272 * np : U32)) && U32.is_eq(n, (12 + plen + 320 * np : U32))

def ivals_ok(ok: Bool, +xs: +List<U32>, +np: U32, +plen: U32) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      canon_go(U32.to_nat((10 * np : U32)), H.drop(xs, (12 + plen : U32)))

def head_ok(have: Bool, +xs: +List<U32>, +n: U32) -> Bool:
  match have:
    case False{}:
      False{}
    case True{}:
      +np = H.le32(xs)
      +plen = H.le32(H.drop(xs, 8))
      ivals_ok(shape_ok(n, np, H.le32(H.drop(xs, 4)), plen), xs, np, plen)

# A well-formed bundle input; check this before handing the bytes to the verifier.
def valid(+xs: +List<U32>) -> Bool:
  +n = H.length(xs)
  head_ok(U32.is_le(12, n), xs, n)

def np_of(+xs: +List<U32>) -> U32:
  H.le32(xs)
