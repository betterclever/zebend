# Zcash transparent script interpreter, part 1: values, numbers, signature checks and the
# opcode handlers. It follows zcash_script 0.6 (the Rust interpreter Zebra uses):
# interpreter.rs, opcode/mod.rs, signature.rs, num.rs, script/iter.rs.
#
# A stack is a list of byte strings with the top first. A handler returns R3: ok = False
# means the script fails (every interpreter error ends the script with "invalid").
import Base
import ../util.bend as U
import ./rmd_sha1.bend as H
import ../../node/block/sha256.bend as S2
import ../secp/fe.bend as F
import ../secp/sc.bend as Sc
import ../secp/gtab.bend as G
import ../secp/ec.bend as E
import ../sighash/sighash.bend as SH

# Verification flags (zcash_script interpreter::Flags bits).
def f_p2sh() -> U32:
  1

def f_strictenc() -> U32:
  2

def f_lows() -> U32:
  8

def f_nulldummy() -> U32:
  16

def f_sigpushonly() -> U32:
  32

def f_minimaldata() -> U32:
  64

def f_discourage_nops() -> U32:
  128

def f_cleanstack() -> U32:
  256

def f_cltv() -> U32:
  512

def has(+flags: U32, +bit: U32) -> Bool:
  U32.is_ne((flags .&. bit : U32), 0)

# What a signature check needs from the transaction: the parsed tx, the input
# index, the spent output (scriptPubKey, amount as 8 bytes LE), nLockTime, and whether this
# input's nSequence is final (0xffffffff).
type Ctx is Data:
  Ctx{+tx: SH.Tx, +nin: Nat, +spk: +List<U32>, +amount: +List<U32>, +lock: U32, +final: Bool}

# flags, the script being executed (the scriptCode of its signature checks), the context.
type Env is Data:
  Env{+flags: U32, +script: +List<U32>, +ctx: Ctx}

def env_flags(e: Env) -> U32:
  Env{f, _, _} = e
  f

type R3 is Data:
  R3{+ok: Bool, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +ops: U32}

def fail3() -> R3:
  R3{False{}, Nil{}, Nil{}, 0}

def lift(m: Maybe<&2, List<&2, +List<U32>>>, +alt: List<&2, +List<U32>>, +ops: U32) -> R3:
  match m:
    case Some{s}:
      R3{True{}, s, alt, ops}
    case None{}:
      fail3()

# ------------------------------------------------------------------ values

# Anything but (negative) zero is true.
def ctb(xs: +List<U32>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+b, Nil{}}:
      U32.is_ne((b .&. 127 : U32), 0)
    case Con{+b, t}:
      U32.is_ne(b, 0) || ctb(t)

def vbool(b: Bool) -> +List<U32>:
  match b:
    case True{}:
      1 <> Nil{}
    case False{}:
      Nil{}

def slen(xs: List<&2, +List<U32>>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{_, t}:
      1n+slen(t)

def nth(xs: List<&2, +List<U32>>, n: Nat) -> +List<U32>:
  match xs n:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      nth(t, p)
    case _ _:
      Nil{}

def remove_nth(xs: List<&2, +List<U32>>, n: Nat) -> List<&2, +List<U32>>:
  match xs n:
    case Con{_, t} 0n:
      t
    case Con{h, t} 1n+p:
      h <> remove_nth(t, p)
    case _ _:
      Nil{}

def stake(xs: List<&2, +List<U32>>, n: Nat) -> List<&2, +List<U32>>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Nil{}
    case Con{h, t} 1n+p:
      h <> stake(t, p)

def sdrop(xs: List<&2, +List<U32>>, n: Nat) -> List<&2, +List<U32>>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      h <> t
    case Con{_, t} 1n+p:
      sdrop(t, p)

# ------------------------------------------------------------------ script numbers

type Num is Data:
  Num{+neg: Bool, +mag: U32}

def second_last(xs: +List<U32>, +prev: U32, +cur: U32) -> U32:
  match xs:
    case Nil{}:
      prev
    case Con{h, t}:
      second_last(t, cur, h)

# BIP62 rule 4: no excess high zero byte (this also rejects negative zero).
def non_minimal(+v: +List<U32>, +len: U32) -> Bool:
  +last = U.last0(v, 0)
  U32.is_zero((last .&. 127 : U32)) && (U32.is_le(len, 1) || U32.is_zero((second_last(v, 0, 0) .&. 128 : U32)))

def num_of(+v: +List<U32>, +len: U32) -> Num:
  +raw = U.le32(v)
  +sb = (1 << U32.to_nat(((len * 8) - 1 : U32)) : U32)
  +mag = (raw .&. U32.not(sb) : U32)
  Num{U32.is_ne((raw .&. sb : U32), 0) && U32.is_ne(mag, 0), mag}

def num_ok(ok: Bool, +v: +List<U32>, +len: U32) -> Maybe<&2, Num>:
  match ok:
    case True{}:
      Some{Bool.pick(Num, U32.is_zero(len), Num{False{}, 0}, num_of(v, len))}
    case False{}:
      None{}

# num::parse with the default 4-byte limit.
def parse_num(+v: +List<U32>, +minimal: Bool) -> Maybe<&2, Num>:
  +len = U.len(v)
  num_ok(U32.is_le(len, 4) && Bool.not(minimal && U32.is_ne(len, 0) && non_minimal(v, len)), v, len)

def mag_bytes(n: Nat, +m: U32) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Bool.pick(+List<U32>, U32.is_zero(m), Nil{}, (m .&. 255 : U32) <> mag_bytes(p, (m >> 8n : U32)))

def set_sign_h(hi: Bool, +bs: +List<U32>, +last: U32, +neg: Bool) -> +List<U32>:
  match hi:
    case True{}:
      U.cat(bs, Bool.pick(U32, neg, 128, 0) <> Nil{})
    case False{}:
      U.cat(U.init(bs), Bool.pick(U32, neg, (last .|. 128 : U32), last) <> Nil{})

def set_sign(+bs: +List<U32>, +neg: Bool) -> +List<U32>:
  +last = U.last0(bs, 0)
  set_sign_h(U32.is_ne((last .&. 128 : U32), 0), bs, last, neg)

def ser(n: Num) -> +List<U32>:
  Num{+neg, +mag} = n
  Bool.pick(+List<U32>, U32.is_zero(mag), Nil{}, set_sign(mag_bytes(4n, mag), neg))

def mk(+neg: Bool, +mag: U32) -> Num:
  Num{neg && U32.is_ne(mag, 0), mag}

def nadd(x: Num, y: Num) -> Num:
  Num{+xn, +xm} = x
  Num{+yn, +ym} = y
  Bool.pick(Num, Bool.not(Bool.xor(xn, yn)), mk(xn, (xm + ym : U32)),
    Bool.pick(Num, U32.is_ge(xm, ym), mk(xn, (xm - ym : U32)), mk(yn, (ym - xm : U32))))

def nneg(x: Num) -> Num:
  Num{+n, +m} = x
  mk(Bool.not(n), m)

def nlt(x: Num, y: Num) -> Bool:
  Num{+xn, +xm} = x
  Num{+yn, +ym} = y
  (xn && Bool.not(yn)) || (Bool.not(xn) && Bool.not(yn) && U32.is_lt(xm, ym)) || (xn && yn && U32.is_gt(xm, ym))

def neq(x: Num, y: Num) -> Bool:
  Num{+xn, +xm} = x
  Num{+yn, +ym} = y
  Bool.not(Bool.xor(xn, yn)) && U32.is_eq(xm, ym)

def nz(x: Num) -> Bool:
  Num{_, +m} = x
  U32.is_ne(m, 0)

# ------------------------------------------------------------------ stack operations

def o_dup(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, t}:
      Some{a <> a <> t}
    case _:
      None{}

def o_drop(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{_, t}:
      Some{t}
    case _:
      None{}

def o_2drop(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{_, Con{_, t}}:
      Some{t}
    case _:
      None{}

def o_2dup(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, Con{+b, t}}:
      Some{a <> b <> a <> b <> t}
    case _:
      None{}

def o_3dup(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, Con{+b, Con{+c, t}}}:
      Some{a <> b <> c <> a <> b <> c <> t}
    case _:
      None{}

def o_2over(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, Con{+c, Con{+d, t}}}}:
      Some{c <> d <> a <> b <> c <> d <> t}
    case _:
      None{}

def o_2rot(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, t}}}}}}:
      Some{e <> f <> a <> b <> c <> d <> t}
    case _:
      None{}

def o_2swap(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      Some{c <> d <> a <> b <> t}
    case _:
      None{}

def o_ifdup(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, +t}:
      Some{Bool.pick(List<&2, +List<U32>>, ctb(a), a <> a <> t, a <> t)}
    case _:
      None{}

def o_depth(+s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  Some{ser(Num{False{}, U32.from_nat(slen(s))}) <> s}

def o_nip(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{_, t}}:
      Some{a <> t}
    case _:
      None{}

def o_over(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{+b, t}}:
      Some{b <> a <> b <> t}
    case _:
      None{}

def o_rot(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, Con{c, t}}}:
      Some{c <> a <> b <> t}
    case _:
      None{}

def o_swap(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, t}}:
      Some{b <> a <> t}
    case _:
      None{}

def o_tuck(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, Con{b, t}}:
      Some{a <> b <> a <> t}
    case _:
      None{}

def o_size(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{+a, t}:
      Some{ser(Num{False{}, U.len(a)}) <> a <> t}
    case _:
      None{}

def o_equal(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, t}}:
      Some{vbool(U.eq(a, b)) <> t}
    case _:
      None{}

def keep_if(ok: Bool, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match ok:
    case True{}:
      Some{t}
    case False{}:
      None{}

def o_equalverify(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{b, t}}:
      keep_if(U.eq(a, b), t)
    case _:
      None{}

def o_verify(s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, t}:
      keep_if(ctb(a), t)
    case _:
      None{}

def hash_3(is3: Bool, +a: +List<U32>) -> +List<U32>:
  match is3:
    case True{}:
      H.ripemd160(S2.hash(a))
    case False{}:
      S2.hash_d(a)

def hash_2(is2: Bool, +k: U32, +a: +List<U32>) -> +List<U32>:
  match is2:
    case True{}:
      S2.hash(a)
    case False{}:
      hash_3(U32.is_eq(k, 3), a)

def hash_1(is1: Bool, +k: U32, +a: +List<U32>) -> +List<U32>:
  match is1:
    case True{}:
      H.sha1(a)
    case False{}:
      hash_2(U32.is_eq(k, 2), k, a)

def hash_0(is0: Bool, +k: U32, +a: +List<U32>) -> +List<U32>:
  match is0:
    case True{}:
      H.ripemd160(a)
    case False{}:
      hash_1(U32.is_eq(k, 1), k, a)

def hash_op(+k: U32, +a: +List<U32>) -> +List<U32>:
  hash_0(U32.is_eq(k, 0), k, a)

# k: 0 RIPEMD160, 1 SHA1, 2 SHA256, 3 HASH160, 4 HASH256
def o_hash(+k: U32, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, t}:
      Some{hash_op(k, a) <> t}
    case _:
      None{}

# PICK (roll = False) / ROLL (roll = True): n from the top; the stack must hold n + 1 more.
def pick_n(m: Maybe<&2, Num>, +roll: Bool, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match m:
    case Some{n}:
      Num{+neg, +mag} = n
      +k = U32.to_nat(mag)
      keep_if(Bool.not(neg) && Nat.is_lt(k, slen(t)),
        nth(t, k) <> Bool.pick(List<&2, +List<U32>>, roll, remove_nth(t, k), t))
    case None{}:
      None{}

def o_pick(+roll: Bool, +minimal: Bool, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, Con{+b, t}}:
      pick_n(parse_num(a, minimal), roll, b <> t)
    case _:
      None{}

# ------------------------------------------------------------------ numeric operations

# k: 0 1ADD, 1 1SUB, 2 NEGATE, 3 ABS, 4 NOT, 5 0NOTEQUAL
def un_res(+k: U32, x: Num) -> +List<U32>:
  Num{+n, +m} = x
  Bool.pick(+List<U32>, U32.is_eq(k, 0), ser(nadd(Num{n, m}, Num{False{}, 1})),
  Bool.pick(+List<U32>, U32.is_eq(k, 1), ser(nadd(Num{n, m}, Num{True{}, 1})),
  Bool.pick(+List<U32>, U32.is_eq(k, 2), ser(nneg(Num{n, m})),
  Bool.pick(+List<U32>, U32.is_eq(k, 3), ser(Num{False{}, m}),
  Bool.pick(+List<U32>, U32.is_eq(k, 4), vbool(U32.is_zero(m)), vbool(U32.is_ne(m, 0)))))))

def un_num(m: Maybe<&2, Num>, +k: U32, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match m:
    case Some{x}:
      Some{un_res(k, x) <> t}
    case None{}:
      None{}

def o_unary(+k: U32, +minimal: Bool, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{a, t}:
      un_num(parse_num(a, minimal), k, t)
    case _:
      None{}

# k: 0 ADD, 1 SUB, 2 BOOLAND, 3 BOOLOR, 4 NUMEQUAL, 5 NUMNOTEQUAL, 6 LESSTHAN,
#    7 GREATERTHAN, 8 LESSTHANOREQUAL, 9 GREATERTHANOREQUAL, 10 MIN, 11 MAX
def bin_res(+k: U32, +x: Num, +y: Num) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(k, 0), ser(nadd(x, y)),
  Bool.pick(+List<U32>, U32.is_eq(k, 1), ser(nadd(x, nneg(y))),
  Bool.pick(+List<U32>, U32.is_eq(k, 2), vbool(nz(x) && nz(y)),
  Bool.pick(+List<U32>, U32.is_eq(k, 3), vbool(nz(x) || nz(y)),
  Bool.pick(+List<U32>, U32.is_eq(k, 4), vbool(neq(x, y)),
  Bool.pick(+List<U32>, U32.is_eq(k, 5), vbool(Bool.not(neq(x, y))),
  Bool.pick(+List<U32>, U32.is_eq(k, 6), vbool(nlt(x, y)),
  Bool.pick(+List<U32>, U32.is_eq(k, 7), vbool(nlt(y, x)),
  Bool.pick(+List<U32>, U32.is_eq(k, 8), vbool(Bool.not(nlt(y, x))),
  Bool.pick(+List<U32>, U32.is_eq(k, 9), vbool(Bool.not(nlt(x, y))),
  Bool.pick(+List<U32>, U32.is_eq(k, 10), ser(Bool.pick(Num, nlt(y, x), y, x)), ser(Bool.pick(Num, nlt(x, y), y, x)))))))))))))

def bin_num2(m2: Maybe<&2, Num>, m1: Maybe<&2, Num>, +k: U32, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match m2 m1:
    case Some{y} Some{x}:
      Some{bin_res(k, x, y) <> t}
    case _ _:
      None{}

def o_binary(+k: U32, +minimal: Bool, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{x2, Con{x1, t}}:
      bin_num2(parse_num(x2, minimal), parse_num(x1, minimal), k, t)
    case _:
      None{}

def nev2(m2: Maybe<&2, Num>, m1: Maybe<&2, Num>, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match m2 m1:
    case Some{y} Some{x}:
      keep_if(neq(x, y), t)
    case _ _:
      None{}

def o_numequalverify(+minimal: Bool, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{x2, Con{x1, t}}:
      nev2(parse_num(x2, minimal), parse_num(x1, minimal), t)
    case _:
      None{}

def within3(mx: Maybe<&2, Num>, mmin: Maybe<&2, Num>, mmax: Maybe<&2, Num>, +t: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match mx mmin mmax:
    case Some{+x} Some{+lo} Some{+hi}:
      Some{vbool(Bool.not(nlt(x, lo)) && nlt(x, hi)) <> t}
    case _ _ _:
      None{}

# (x min max -- bool)
def o_within(+minimal: Bool, s: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match s:
    case Con{hi, Con{lo, Con{x, t}}}:
      within3(parse_num(x, minimal), parse_num(lo, minimal), parse_num(hi, minimal), t)
    case _:
      None{}

# ------------------------------------------------------------------ signatures

# A DER integer as zcash_script accepts it: non-empty, non-negative, no excess 0x00 padding.
def der_int_ok(xs: +List<U32>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+a, Nil{}}:
      U32.is_zero((a .&. 128 : U32))
    case Con{+a, Con{+b, _}}:
      Bool.pick(Bool, U32.is_zero(a), U32.is_ne((b .&. 128 : U32), 0), U32.is_zero((a .&. 128 : U32)))

def has_n(xs: +List<U32>, n: Nat) -> Bool:
  match xs n:
    case _ 0n:
      True{}
    case Con{_, t} 1n+p:
      has_n(t, p)
    case Nil{} 1n+p:
      False{}

# 0x02 len S, exactly to the end.
def der_s_ok(+sp: +List<U32>) -> Bool:
  U32.is_eq(U.byte_at(sp, 0n), 2) && has_n(sp, 2n) && U32.is_eq(U.byte_at(sp, 1n), (U.len(sp) - 2 : U32)) && der_int_ok(U.drop(sp, 2n))

def der_rs_ok(+c: +List<U32>) -> Bool:
  +rlen = U32.to_nat(U.byte_at(c, 1n))
  +rest = U.drop(c, 2n)
  U32.is_eq(U.byte_at(c, 0n), 2) && has_n(c, 2n) && has_n(rest, rlen) && der_int_ok(U.take(rest, rlen)) && der_s_ok(U.drop(rest, rlen))

# signature::Decoded::is_valid_encoding (BIP66 strict DER, consensus in Zcash from genesis).
def der_ok(+d: +List<U32>) -> Bool:
  +total = U.byte_at(d, 1n)
  has_n(d, 2n) && U32.is_eq(U.byte_at(d, 0n), 48) && U32.is_le(total, 70) && U32.is_eq(total, (U.len(d) - 2 : U32)) && der_rs_ok(U.drop(d, 2n))

# A DER integer's value as libsecp256k1 parses it: one leading zero skipped; more than 32
# bytes, or a value >= n, reads as 0.
def der_val(+x: +List<U32>) -> Sc.Sc:
  +y = Bool.pick(+List<U32>, U32.is_zero(U.head0(x)), U.drop(x, 1n), x)
  +len = U.len(y)
  +v = Sc.from_be(U.cat(U.zeros(U32.to_nat((32 - U32.min(len, 32) : U32))), y))
  Bool.pick(Sc.Sc, U32.is_le(len, 32) && Sc.is_lt_n(v), v, Sc.zero())

# d = 0x30 total 0x02 rlen r.. 0x02 slen s.. (already checked by der_ok)
def der_r(+d: +List<U32>) -> Sc.Sc:
  der_val(U.at(d, 4n, U32.to_nat(U.byte_at(d, 3n))))

def der_s(+d: +List<U32>) -> Sc.Sc:
  der_val(U.drop(d, (6n + U32.to_nat(U.byte_at(d, 3n)) : Nat)))

def pk_enc_ok(+pk: +List<U32>) -> Bool:
  +h = U.head0(pk)
  +len = U.len(pk)
  ((U32.is_eq(h, 2) || U32.is_eq(h, 3)) && U32.is_eq(len, 33)) || (U32.is_eq(h, 4) && U32.is_eq(len, 65))

def ht_strict_ok(+ht: U32) -> Bool:
  U32.is_zero(((ht .|. 131) .^. 131 : U32)) && U32.is_ne((ht .&. 3 : U32), 0)

def ecdsa_q(m: Maybe<&2, G.Af>, +r: Sc.Sc, +s: Sc.Sc, +h: +List<U32>) -> Bool:
  match m:
    case Some{q}:
      E.verify(q, r, s, h)
    case None{}:
      False{}

def ecdsa_h(m: Maybe<&2, +List<U32>>, +pk: +List<U32>, +r: Sc.Sc, +s: Sc.Sc) -> Bool:
  match m:
    case Some{h}:
      ecdsa_q(E.decode(pk), r, s, h)
    case None{}:
      False{}

# CallbackTransactionSignatureChecker::check_sig: non-empty key, a sighash, a valid signature.
def check_sig(+pk: +List<U32>, +r: Sc.Sc, +s: Sc.Sc, +ht: U32, +env: Env) -> Bool:
  Env{_, +script, +ctx} = env
  Ctx{+tx, +nin, +spk, +amount, _, _} = ctx
  Bool.not(U.is_empty(pk)) && ecdsa_h(SH.sighash(tx, nin, script, spk, amount, ht), pk, r, s)

def sv_pk(ok: Bool, +res: Bool) -> Maybe<&2, Bool>:
  match ok:
    case True{}:
      Some{res}
    case False{}:
      None{}

def sv_chk(ok: Bool, +pk: +List<U32>, +r: Sc.Sc, +s: Sc.Sc, +ht: U32, +env: Env) -> Maybe<&2, Bool>:
  match ok:
    case True{}:
      Some{check_sig(pk, r, s, ht, env)}
    case False{}:
      None{}

def sv_low(ok: Bool, +strict: Bool, +sig: +List<U32>, +pk: +List<U32>, +r: Sc.Sc, +s: Sc.Sc, +env: Env) -> Maybe<&2, Bool>:
  match ok:
    case True{}:
      sv_chk(Bool.not(strict) || pk_enc_ok(pk), pk, r, s, U.last0(sig, 0), env)
    case False{}:
      None{}

def sv_body(ok: Bool, +sig: +List<U32>, +pk: +List<U32>, +env: Env) -> Maybe<&2, Bool>:
  match ok:
    case True{}:
      +flags = env_flags(env)
      +d = U.init(sig)
      +s = der_s(d)
      sv_low(Bool.not(has(flags, f_lows())) || Sc.is_low(s), has(flags, f_strictenc()), sig, pk, der_r(d), s, env)
    case False{}:
      None{}

# Operation::is_sig_valid: None aborts the script (bad DER, bad hash type under STRICTENC,
# high S under LOW_S, bad key encoding under STRICTENC); Some(b) continues with result b.
def sv_empty(e: Bool, +strict: Bool, +sig: +List<U32>, +pk: +List<U32>, +env: Env) -> Maybe<&2, Bool>:
  match e:
    case True{}:
      sv_pk(Bool.not(strict) || pk_enc_ok(pk), False{})
    case False{}:
      sv_body(der_ok(U.init(sig)) && (Bool.not(strict) || ht_strict_ok(U.last0(sig, 0))), sig, pk, env)

def sig_valid(+sig: +List<U32>, +pk: +List<U32>, +env: Env) -> Maybe<&2, Bool>:
  sv_empty(U.is_empty(sig), has(env_flags(env), f_strictenc()), sig, pk, env)
