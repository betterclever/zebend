
# ===========================================================================
# Halo 2 verifier runtime (hand-written). Concatenated after zc.bend + b2.bend
# by mklib.sh into vlib.bend.
# ===========================================================================

def fneg(a: F) -> F:
  fsub(FZERO(), a)

def R3() -> F:
  F{4345, 15006, 42393, 61829, 45521, 27333, 36667, 63142, 54316, 13631, 4116, 57229, 39184, 11565, 2338, 10979}

# canonical U8w -> Montgomery F (no range check)

def f_of_words(w: U8w) -> F:
  U8w{+a, +b, +c, +d, +e, +f, +g, +h} = w
  to_mont(words_to_f(a, b, c, d, e, f, g, h))

# Montgomery F -> canonical U8w

def words_of_f(a: F) -> U8w:
  f_to_words(from_mont(a))

# 1 if w < p (canonical encoding of an Fp element), else 0: the borrow out of w - p.

def lt_p(w: U8w) -> U32:
  U8w{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7} = w
  +b0 = {0 : U32}
  +d0 = (x0 - 1 - b0 : U32)
  +b1 = ((((x0 .^. 4294967295) .&. 1) .|. (((x0 .^. 1) .^. 4294967295) .&. d0)) >> 31n : U32)
  +d1 = (x1 - 2569875693 - b1 : U32)
  +b2 = ((((x1 .^. 4294967295) .&. 2569875693) .|. (((x1 .^. 2569875693) .^. 4294967295) .&. d1)) >> 31n : U32)
  +d2 = (x2 - 155040027 - b2 : U32)
  +b3 = ((((x2 .^. 4294967295) .&. 155040027) .|. (((x2 .^. 155040027) .^. 4294967295) .&. d2)) >> 31n : U32)
  +d3 = (x3 - 575052028 - b3 : U32)
  +b4 = ((((x3 .^. 4294967295) .&. 575052028) .|. (((x3 .^. 575052028) .^. 4294967295) .&. d3)) >> 31n : U32)
  +d4 = (x4 - 0 - b4 : U32)
  +b5 = ((((x4 .^. 4294967295) .&. 0) .|. (((x4 .^. 0) .^. 4294967295) .&. d4)) >> 31n : U32)
  +d5 = (x5 - 0 - b5 : U32)
  +b6 = ((((x5 .^. 4294967295) .&. 0) .|. (((x5 .^. 0) .^. 4294967295) .&. d5)) >> 31n : U32)
  +d6 = (x6 - 0 - b6 : U32)
  +b7 = ((((x6 .^. 4294967295) .&. 0) .|. (((x6 .^. 0) .^. 4294967295) .&. d6)) >> 31n : U32)
  +d7 = (x7 - 1073741824 - b7 : U32)
  +b8 = ((((x7 .^. 4294967295) .&. 1073741824) .|. (((x7 .^. 1073741824) .^. 4294967295) .&. d7)) >> 31n : U32)
  b8

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def bytes_of_word(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> acc

def bytes_of_u8w(w: U8w, acc: +List<U32>) -> +List<U32>:
  U8w{+a, +b, +c, +d, +e, +f, +g, +h} = w
  bytes_of_word(a, bytes_of_word(b, bytes_of_word(c, bytes_of_word(d, bytes_of_word(e, bytes_of_word(f, bytes_of_word(g, bytes_of_word(h, acc))))))))

# packs bytes (LE) into U32 words, 4 at a time; a short tail is zero-padded

def pack4(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+a, Nil{}}:
      a <> Nil{}
    case Con{+a, Con{+b, Nil{}}}:
      (a .|. (b << 8n) : U32) <> Nil{}
    case Con{+a, Con{+b, Con{+c, Nil{}}}}:
      (a .|. (b << 8n) .|. (c << 16n) : U32) <> Nil{}
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> pack4(rest)

def wat(i: Nat, ws: +List<U32>) -> U32:
  match i ws:
    case 0n Con{+h, _}:
      h
    case 1n+k Con{_, t}:
      wat(k, t)
    case _ Nil{}:
      0

def block(bs: +List<U32>) -> M16:
  +ws = pack4(bs)
  M16{wat(0n, ws), wat(1n, ws), wat(2n, ws), wat(3n, ws), wat(4n, ws), wat(5n, ws), wat(6n, ws), wat(7n, ws), wat(8n, ws), wat(9n, ws), wat(10n, ws), wat(11n, ws), wat(12n, ws), wat(13n, ws), wat(14n, ws), wat(15n, ws), wat(16n, ws), wat(17n, ws), wat(18n, ws), wat(19n, ws), wat(20n, ws), wat(21n, ws), wat(22n, ws), wat(23n, ws), wat(24n, ws), wat(25n, ws), wat(26n, ws), wat(27n, ws), wat(28n, ws), wat(29n, ws), wat(30n, ws), wat(31n, ws)}

# a 128-byte block (bytes in order, fewer means zero padding) as BLAKE2b message words

type Tr is Data:
  Tr{h: H8, t: U32, n: U32, buf: +List<U32>}

# BLAKE2b-512, personalization "Halo2-Transcript", no key

def tr_init() -> Tr:
  Tr{H8{4072524104, 1779033703, 2227873595, 3144134277, 4271175723, 1013904242, 1595750129, 2773480762, 2917565137, 1359893119, 725511199, 2600822924, 2486033443, 1842869401, 1879920408, 798008427}, 0, 0, Nil{}}

# BLAKE2b only compresses a full buffer once more input arrives (the last block is final)

def tr_byte_if(full: Bool, h: H8, +t: U32, +n: U32, buf: +List<U32>, +b: U32) -> Tr:
  match full:
    case True{}:
      Tr{b2_compress(h, block(List.reverse(&2, U32, buf)), (t + 128 : U32), 0), (t + 128 : U32), 1, b <> Nil{}}
    case False{}:
      Tr{h, t, (n + 1 : U32), b <> buf}

def tr_byte(tr: Tr, +b: U32) -> Tr:
  Tr{h, +t, +n, +buf} = tr
  tr_byte_if(U32.is_eq(n, 128), h, t, n, buf, b)

def tr_bytes(bs: +List<U32>, tr: Tr) -> Tr:
  match bs:
    case Nil{}:
      tr
    case Con{+b, rest}:
      tr_bytes(rest, tr_byte(tr, b))

# BLAKE2b finalization of a copy of the state: 64 bytes as an H8 (16 LE U32 words)

def tr_final(tr: Tr) -> H8:
  Tr{h, +t, +n, +buf} = tr
  b2_compress(h, block(List.reverse(&2, U32, buf)), (t + n : U32), 1)

# Fp::from_uniform_bytes: (lo + hi * 2^256) mod p, as Montgomery F

def from_uniform(o: H8) -> F:
  H8{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7} = o
  fadd(fmul(words_to_f(a0, a1, a2, a3, a4, a5, a6, a7), R2()), fmul(words_to_f(b0, b1, b2, b3, b4, b5, b6, b7), R3()))

def h8_lo(o: H8) -> U8w:
  H8{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, _, _, _, _, _, _, _, _} = o
  U8w{a0, a1, a2, a3, a4, a5, a6, a7}

def h8_hi(o: H8) -> U8w:
  H8{_, _, _, _, _, _, _, _, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7} = o
  U8w{b0, b1, b2, b3, b4, b5, b6, b7}

type VP is Data:
  VP{x: U8w, y: U8w}

def vp_x(p: VP) -> U8w:
  VP{+x, _} = p
  x

def vp_y(p: VP) -> U8w:
  VP{_, +y} = p
  y

type Proof is Data:
  Proof{items: +List<U8w>, ys: +List<U8w>, insts: +List<VP>}

type Log is Data:
  Log{name: String, val: U8w}

type St is Data:
  St{tr: Tr, pr: Proof, ok: U32, log: +List<Log>}

def st_new(pr: Proof) -> St:
  St{tr_init(), pr, 1, Nil{}}

def st_ok(st: St) -> U32:
  St{_, _, +ok, _} = st
  ok

def st_log(st: St) -> +List<Log>:
  St{_, _, _, +log} = st
  List.reverse(&2, Log, log)

def lg(st: St, name: String, +v: U8w) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr, pr, ok, Log{name, v} <> log}

def lgf(st: St, name: String, +v: F) -> St:
  lg(st, name, words_of_f(v))

def fail(st: St, +bit: U32) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr, pr, (ok .&. bit : U32), log}

def zero_w() -> U8w:
  U8w{0, 0, 0, 0, 0, 0, 0, 0}

# common_point: [1] || x || y ; common_scalar: [2] || repr

def ab_point(st: St, +p: VP) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr_bytes(1 <> bytes_of_u8w(vp_x(p), bytes_of_u8w(vp_y(p), Nil{})), tr), pr, ok, log}

def ab_scalar(st: St, +s: F) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr_bytes(2 <> bytes_of_u8w(words_of_f(s), Nil{}), tr), pr, ok, log}

# squeeze_challenge: absorb [0], hash a copy, Challenge255 -> Fp

type SF is Data:
  SF{v: F, st: St}

def sf_v(r: SF) -> F:
  SF{+v, _} = r
  v

def sf_st(r: SF) -> St:
  SF{_, +st} = r
  st

def squeeze(st: St) -> SF:
  St{tr, pr, +ok, +log} = st
  +tr1 = tr_byte(tr, 0)
  SF{from_uniform(tr_final(tr1)), St{tr1, pr, ok, log}}

# read_scalar: next item, must be canonical (< p), absorbed as a scalar

def rd_scalar_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SF:
  Proof{items, +ys, +insts} = pr
  match items:
    case Nil{}:
      SF{FZERO(), St{tr, Proof{Nil{}, ys, insts}, 0, log}}
    case Con{+w, rest}:
      +v = f_of_words(w)
      SF{v, St{tr_bytes(2 <> bytes_of_u8w(w, Nil{}), tr), Proof{rest, ys, insts}, (ok .&. lt_p(w) : U32), log}}

def rd_scalar(st: St) -> SF:
  St{tr, pr, +ok, +log} = st
  rd_scalar_go(tr, pr, ok, log)

type SP is Data:
  SP{p: VP, st: St}

def sp_p(r: SP) -> VP:
  SP{+p, _} = r
  p

def sp_st(r: SP) -> St:
  SP{_, +st} = r
  st

# read_point: next item is the compressed point (x LE, bit 255 = sign of y); the y
# coordinate comes from the hint list and must match the sign bit.
# TODO(H1): check y^2 = x^3 + 5 over Fq and x < q, i.e. a real decompression.

def top_bit(w: U8w) -> U32:
  U8w{_, _, _, _, _, _, _, +h} = w
  (h >> 31n : U32)

def low_bit(w: U8w) -> U32:
  U8w{+a, _, _, _, _, _, _, _} = w
  (a .&. 1 : U32)

def clear_top(w: U8w) -> U8w:
  U8w{+a, +b, +c, +d, +e, +f, +g, +h} = w
  U8w{a, b, c, d, e, f, g, (h .&. 2147483647 : U32)}

def rd_point_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SP:
  Proof{items, ys, +insts} = pr
  match items ys:
    case Con{+c, rest} Con{+y, yrest}:
      +x = clear_top(c)
      +p = {VP{x, y} : VP}
      +good = U32.is_eq(top_bit(c), low_bit(y))
      SP{p, St{tr_bytes(1 <> bytes_of_u8w(x, bytes_of_u8w(y, Nil{})), tr), Proof{rest, yrest, insts}, (ok .&. b2u(good) : U32), log}}
    case _ _:
      SP{VP{zero_w(), zero_w()}, St{tr, Proof{Nil{}, Nil{}, insts}, 0, log}}

# an instance commitment, absorbed as a common point

def rd_point(st: St) -> SP:
  St{tr, pr, +ok, +log} = st
  rd_point_go(tr, pr, ok, log)

def rd_inst_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SP:
  Proof{+items, +ys, insts} = pr
  match insts:
    case Con{+p, rest}:
      SP{p, St{tr_bytes(1 <> bytes_of_u8w(vp_x(p), bytes_of_u8w(vp_y(p), Nil{})), tr), Proof{items, ys, rest}, ok, log}}
    case Nil{}:
      SP{VP{zero_w(), zero_w()}, St{tr, Proof{items, ys, Nil{}}, 0, log}}

def rd_inst(st: St) -> SP:
  St{tr, pr, +ok, +log} = st
  rd_inst_go(tr, pr, ok, log)

def hex_nib(+n: U32) -> Char:
  Char.from_u32((n + 48 + (39 * b2u(U32.is_gt(n, 9))) : U32))

def hex_byte(+b: U32) -> String:
  String.from_list(hex_nib(((b >> 4n) .&. 15 : U32)) <> hex_nib((b .&. 15 : U32)) <> Nil{})

def hex_bytes(bs: +List<U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case Con{+b, rest}:
      hex_byte(b) ++ hex_bytes(rest)

def hex_u8w(w: U8w) -> String:
  hex_bytes(bytes_of_u8w(w, Nil{}))

def log_line(l: Log) -> String:
  Log{+n, +v} = l
  n ++ " " ++ hex_u8w(v)

def print_log(xs: +List<Log>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+l, rest}:
      do IO<Unit>:
        IO.print(log_line(l))
        print_log(rest)
