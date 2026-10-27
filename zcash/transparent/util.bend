# Byte strings for the transparent components: +List<U32> of values 0..255.
import Base

def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

def hex_go(xs: +List<U32>, acc: String) -> String:
  match xs:
    case Con{+b, t}:
      SCon{hex_digit((b >> 4n : U32)), SCon{hex_digit((b .&. 15 : U32)), hex_go(t, acc)}}
    case Nil{}:
      acc

def hex(+xs: +List<U32>) -> String:
  hex_go(xs, "")

def cat(xs: +List<U32>, ys: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      h <> cat(t, ys)

def take(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Nil{}
    case Con{h, t} 1n+p:
      h <> take(t, p)

def drop(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      h <> t
    case Con{_, t} 1n+p:
      drop(t, p)

def at(+xs: +List<U32>, +pos: Nat, +n: Nat) -> +List<U32>:
  take(drop(xs, pos), n)

def len_go(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{_, t}:
      len_go(t, (acc + 1 : U32))

def len(xs: +List<U32>) -> U32:
  len_go(xs, 0)

def nlen(xs: +List<U32>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{_, t}:
      1n+nlen(t)

def head0(xs: +List<U32>) -> U32:
  match xs:
    case Con{b, _}:
      b
    case Nil{}:
      0

def byte_at(+xs: +List<U32>, +pos: Nat) -> U32:
  head0(drop(xs, pos))

def le32(xs: +List<U32>) -> U32:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case Con{a, Con{b, Con{c, _}}}:
      (a .|. (b << 8n) .|. (c << 16n) : U32)
    case Con{a, Con{b, _}}:
      (a .|. (b << 8n) : U32)
    case Con{a, _}:
      a
    case _:
      0

def u32_at(+xs: +List<U32>, +pos: Nat) -> U32:
  le32(drop(xs, pos))

def w4(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> acc

def le4(+w: U32) -> +List<U32>:
  w4(w, Nil{})

def zeros(n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      0 <> zeros(p)

def eq(xs: +List<U32>, ys: +List<U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{a, s} Con{b, t}:
      U32.is_eq(a, b) && eq(s, t)
    case _ _:
      False{}

def is_empty(xs: +List<U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def last0(xs: +List<U32>, +prev: U32) -> U32:
  match xs:
    case Nil{}:
      prev
    case Con{h, t}:
      last0(t, h)

# All but the last byte.
def init(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, Nil{}}:
      Nil{}
    case Con{h, t}:
      h <> init(t)

def cs_w(small: Bool, +n: U32) -> +List<U32>:
  match small:
    case True{}:
      [253, (n .&. 255 : U32), (n >> 8n : U32)]
    case False{}:
      254 <> le4(n)

def cs_s(small: Bool, +n: U32) -> +List<U32>:
  match small:
    case True{}:
      n <> Nil{}
    case False{}:
      cs_w(U32.is_lt(n, 65536), n)

# CompactSize encoding (values below 2^32).
def cs(+n: U32) -> +List<U32>:
  cs_s(U32.is_lt(n, 253), n)

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}
