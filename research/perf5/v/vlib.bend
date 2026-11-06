# Halo 2 verifier runtime (hand-written), on H1's Pasta library (../lib) and the generated
# BLAKE2b compression function (b2.bend). Generated verifiers import this as `L`.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fp64.bend as Fp
import ../../../crypto/field3/fq64.bend as Fq
import ../../../crypto/field3/lib64/vesta.bend as V
import ../lib/glv_vesta_lz.bend as G
import ../lib/fixb.bend as FB
import ../lib/msm_ba.bend as BA
import ../../decomp/vesta_dec.bend as VD
import ../lib/fq2.bend as F2
import ./b2.bend as B

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

# --- byte lists ---------------------------------------------------------------

# the 4 little-endian bytes of a word, in front of acc
def bytes_of_word(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> acc

# the 32 little-endian bytes of W, in front of acc
def bytes_of_w(w: Wd.W, acc: +List<U32>) -> +List<U32>:
  Wd.W{+a, +b, +c, +d, +e, +f, +g, +h} = w
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

# a 128-byte block (bytes in order; fewer means zero padding) as BLAKE2b message words
def block(bs: +List<U32>) -> B.M16:
  +ws = pack4(bs)
  B.M16{wat(0n, ws), wat(1n, ws), wat(2n, ws), wat(3n, ws), wat(4n, ws), wat(5n, ws), wat(6n, ws), wat(7n, ws), wat(8n, ws), wat(9n, ws), wat(10n, ws), wat(11n, ws), wat(12n, ws), wat(13n, ws), wat(14n, ws), wat(15n, ws), wat(16n, ws), wat(17n, ws), wat(18n, ws), wat(19n, ws), wat(20n, ws), wat(21n, ws), wat(22n, ws), wat(23n, ws), wat(24n, ws), wat(25n, ws), wat(26n, ws), wat(27n, ws), wat(28n, ws), wat(29n, ws), wat(30n, ws), wat(31n, ws)}

# --- the Fiat-Shamir transcript (halo2 Blake2bRead / Blake2bWrite) -----------

# The pending input (n bytes) is kept as 32-bit little-endian words, not bytes: ws holds
# ceil(n/4) words, newest first; when n is not a multiple of 4 the head is the partial word
# (its missing high bytes zero). The block size (128) is a multiple of 4, so a block boundary
# is always a word boundary. Blocks are compressed lazily: tr_byte, which starts every
# absorbed item, first compresses the oldest block if n >= 128 (more input has arrived, so
# that block is not the last); an item then adds at most 65 bytes, so n < 193 always. A full
# buffer is never compressed before more input arrives: BLAKE2b compresses the last block
# with the final flag, in tr_final.
# h: chaining value; t: bytes compressed so far
type Tr is Data:
  Tr{h: B.H8, t: U32, n: U32, ws: +List<U32>}

# BLAKE2b-512, personalization "Halo2-Transcript", no key
def tr_init() -> Tr:
  Tr{B.H8{4072524104, 1779033703, 2227873595, 3144134277, 4271175723, 1013904242, 1595750129, 2773480762, 2917565137, 1359893119, 725511199, 2600822924, 2486033443, 1842869401, 1879920408, 798008427}, 0, 0, Nil{}}

def tr_h(tr: Tr) -> B.H8:
  Tr{h, _, _, _} = tr
  h

# the next 8 words of a newest-first list (as W{newest, ..}), and the rest
type Q8 is Data:
  Q8{w: Wd.W, rest: +List<U32>}

def pop8(ws: +List<U32>) -> Q8:
  match ws:
    case Con{+a, Con{+b, Con{+c, Con{+d, Con{+e, Con{+f, Con{+g, Con{+h, rest}}}}}}}}:
      Q8{Wd.W{a, b, c, d, e, f, g, h}, rest}
    case _:
      Q8{Wd.W{0, 0, 0, 0, 0, 0, 0, 0}, Nil{}}

def blk_s4(g3: Wd.W, g2: Wd.W, g1: Wd.W, q: Q8) -> B.M16:
  Wd.W{+w31, +w30, +w29, +w28, +w27, +w26, +w25, +w24} = g3
  Wd.W{+w23, +w22, +w21, +w20, +w19, +w18, +w17, +w16} = g2
  Wd.W{+w15, +w14, +w13, +w12, +w11, +w10, +w9, +w8} = g1
  Q8{Wd.W{+w7, +w6, +w5, +w4, +w3, +w2, +w1, +w0}, _} = q
  B.M16{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16, w17, w18, w19, w20, w21, w22, w23, w24, w25, w26, w27, w28, w29, w30, w31}

def blk_s3(g3: Wd.W, g2: Wd.W, q: Q8) -> B.M16:
  Q8{g1, r} = q
  blk_s4(g3, g2, g1, pop8(r))

def blk_s2(g3: Wd.W, q: Q8) -> B.M16:
  Q8{g2, r} = q
  blk_s3(g3, g2, pop8(r))

def blk_s1(q: Q8) -> B.M16:
  Q8{g3, r} = q
  blk_s2(g3, pop8(r))

# exactly 32 words, newest first, as the BLAKE2b message block (oldest word first)
def blk32(ws: +List<U32>) -> B.M16:
  blk_s1(pop8(ws))

# k zeros in front of ws (the zero padding of a short final block, newest first)
def zpad(k: Nat, ws: +List<U32>) -> +List<U32>:
  match k:
    case 0n:
      ws
    case 1n+j:
      zpad(j, 0 <> ws)

# x or-ed into the head (partial) word of ws
def or_head(ws: +List<U32>, +x: U32) -> +List<U32>:
  match ws:
    case Con{+a, rest}:
      (a .|. x : U32) <> rest
    case Nil{}:
      x <> Nil{}

# compress the oldest 128 of the n >= 128 pending bytes (not the final block); k = number
# of the newest words kept
def tr_cut(h: B.H8, +t: U32, +n: U32, +ws: +List<U32>, +k: Nat) -> Tr:
  Tr{B.b2_compress(h, blk32(List.drop(&2, U32, ws, k)), (t + 128 : U32), 0), (t + 128 : U32), (n - 128 : U32), List.take(&2, U32, ws, k)}

# compress the oldest block if n >= 128 (call only when more input is arriving)
def tr_norm_if(full: Bool, h: B.H8, +t: U32, +n: U32, ws: +List<U32>) -> Tr:
  match full:
    case True{}:
      tr_cut(h, t, n, ws, U32.to_nat((((n + 3 : U32) >> 2n) - 32 : U32)))
    case False{}:
      Tr{h, t, n, ws}

# absorb byte b at n pending bytes, no compression; r = n mod 4
def tr_byte_go(h: B.H8, +t: U32, +n: U32, ws: +List<U32>, +b: U32, +r: U32) -> Tr:
  match r:
    case 0:
      Tr{h, t, (n + 1 : U32), b <> ws}
    case 1:
      Tr{h, t, (n + 1 : U32), or_head(ws, (b << 8n : U32))}
    case 2:
      Tr{h, t, (n + 1 : U32), or_head(ws, (b << 16n : U32))}
    case _:
      Tr{h, t, (n + 1 : U32), or_head(ws, (b << 24n : U32))}

def tr_byte_raw(tr: Tr, +b: U32) -> Tr:
  Tr{h, +t, +n, ws} = tr
  tr_byte_go(h, t, n, ws, b, (n .&. 3 : U32))

def tr_norm(tr: Tr) -> Tr:
  Tr{h, +t, +n, ws} = tr
  tr_norm_if(U32.is_ge(n, 128), h, t, n, ws)

# absorb one byte (compressing a full block first)
def tr_byte(tr: Tr, +b: U32) -> Tr:
  tr_byte_raw(tr_norm(tr), b)

# absorb the 4 little-endian bytes of w, no compression (only right after tr_byte, at most
# 16 words per item); r = n mod 4
def tr_word_go(h: B.H8, +t: U32, +n: U32, ws: +List<U32>, +w: U32, +r: U32) -> Tr:
  match r:
    case 0:
      Tr{h, t, (n + 4 : U32), w <> ws}
    case 1:
      Tr{h, t, (n + 4 : U32), (w >> 24n : U32) <> or_head(ws, (w << 8n : U32))}
    case 2:
      Tr{h, t, (n + 4 : U32), (w >> 16n : U32) <> or_head(ws, (w << 16n : U32))}
    case _:
      Tr{h, t, (n + 4 : U32), (w >> 8n : U32) <> or_head(ws, (w << 24n : U32))}

def tr_word(tr: Tr, +w: U32) -> Tr:
  Tr{h, +t, +n, ws} = tr
  tr_word_go(h, t, n, ws, w, (n .&. 3 : U32))

# absorb the 32 little-endian bytes of W (as tr_word: only after tr_byte)
def tr_w(tr: Tr, w: Wd.W) -> Tr:
  Wd.W{+a, +b, +c, +d, +e, +f, +g, +h} = w
  tr_word(tr_word(tr_word(tr_word(tr_word(tr_word(tr_word(tr_word(tr, a), b), c), d), e), f), g), h)

def tr_bytes(bs: +List<U32>, tr: Tr) -> Tr:
  match bs:
    case Nil{}:
      tr
    case Con{+b, rest}:
      tr_bytes(rest, tr_byte(tr, b))

# BLAKE2b finalization of a copy of the state: the 64 output bytes as an H8 (n <= 128:
# called right after tr_byte)
def tr_final(tr: Tr) -> B.H8:
  Tr{h, +t, +n, ws} = tr
  B.b2_compress(h, blk32(zpad(U32.to_nat((32 - ((n + 3 : U32) >> 2n) : U32)), ws)), (t + n : U32), 1)

# Challenge255: Fp::from_uniform_bytes of the 64 bytes (low 32 bytes = lo)
def challenge(o: B.H8) -> Fp.Fp:
  B.H8{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7} = o
  Fp.from_wide(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}, Wd.W{b0, b1, b2, b3, b4, b5, b6, b7})

# --- verifier state -------------------------------------------------------------

def aff_x(a: V.Aff) -> Fq.Fq:
  V.Aff{+x, _} = a
  x

def aff_y(a: V.Aff) -> Fq.Fq:
  V.Aff{_, +y} = a
  y

# items: the proof, as 32-byte items (points compressed, scalars canonical);
# ivals: the instance values, per proof then per column, each column padded to its length
type Proof is Data:
  Proof{items: +List<It>, ivals: +List<Fp.Fp>}

# A proof item. Items the transcript will read as points are decompressed ahead of the
# transcript, all at once in a parallel map (`pre_items`); IP carries the result of
# VD.decompress(w) (ok = 0: not a valid encoding). IS items are read as scalars, or, if a
# malformed proof makes the transcript read one as a point, decompressed then.
type It is Data:
  IS{w: Wd.W}
  IP{w: Wd.W, ok: U32, p: V.Pt}

def it_w(+i: It) -> Wd.W:
  match i:
    case IS{+w}:
      w
    case IP{+w, _, _}:
      w

def mk_ip(+w: Wd.W, m: Maybe<&2, V.Pt>) -> It:
  match m:
    case None{}:
      IP{w, 0, V.identity()}
    case Some{+p}:
      IP{w, 1, p}

def dec_item(+w: Wd.W) -> It:
  mk_ip(w, VD.decompress(w))

def dec_it(+w: Wd.W, d: VD.Dec) -> It:
  VD.Dec{+ok, +p} = d
  mk_ip(w, VD.mk_maybe(ok, p))

# two points in lockstep (F2.decompress2: per lane, what VD.decompress returns)
def dec_two_fin(+w1: Wd.W, +w2: Wd.W, d: F2.D2) -> +List<It>:
  F2.D2{+a, +b} = d
  dec_it(w1, a) <> dec_it(w2, b) <> Nil{}

def dec_two(+w1: Wd.W, +w2: Wd.W) -> +List<It>:
  dec_two_fin(w1, w2, F2.decompress2(w1, w2))

def dec_par(+fuel: Nat, +cnt: Nat, +ws: +List<Wd.W>) -> +List<It>:
  match fuel cnt ws:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+w, _}:
      dec_item(w) <> Nil{}
    case _ 2n Con{+w1, Con{+w2, _}}:
      dec_two(w1, w2)
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = dec_par(f, h, List.take(&2, Wd.W, ws, h)) dec_par(f, Nat.sub(cnt, h), List.drop(&2, Wd.W, ws, h))
      List.append(&2, It, a, b)
    case _ _ _:
      Nil{}

def scal_items(ws: +List<Wd.W>) -> +List<It>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{+w, t}:
      IS{w} <> scal_items(t)

# Item kinds of a post-NU6.3 Orchard proof with np actions, in transcript order:
# points 22np+9, scalars 49np+45, point 1, scalars 5, points 23, then scalars.
def pre_items(+np: Nat, +ws: +List<Wd.W>) -> +List<It>:
  +a = Nat.add(Nat.mul(22n, np), 9n)
  +b = Nat.add(Nat.mul(49n, np), 45n)
  +p1 = List.take(&2, Wd.W, ws, a)
  +r1 = List.drop(&2, Wd.W, ws, a)
  +s1 = List.take(&2, Wd.W, r1, b)
  +r2 = List.drop(&2, Wd.W, r1, b)
  +p2 = List.take(&2, Wd.W, r2, 1n)
  +r3 = List.drop(&2, Wd.W, r2, 1n)
  +s2 = List.take(&2, Wd.W, r3, 5n)
  +r4 = List.drop(&2, Wd.W, r3, 5n)
  +p3 = List.take(&2, Wd.W, r4, 23n)
  +r5 = List.drop(&2, Wd.W, r4, 23n)
  +la = List.length(&2, Wd.W, p1)
  +lb = List.length(&2, Wd.W, p2)
  +pts = List.append(&2, Wd.W, p1, List.append(&2, Wd.W, p2, p3))
  +ds = dec_par(16n, List.length(&2, Wd.W, pts), pts)
  +d1 = List.take(&2, It, ds, la)
  +d2 = List.take(&2, It, List.drop(&2, It, ds, la), lb)
  +d3 = List.drop(&2, It, ds, Nat.add(la, lb))
  List.append(&2, It, d1, List.append(&2, It, scal_items(s1), List.append(&2, It, d2, List.append(&2, It, scal_items(s2), List.append(&2, It, d3, scal_items(r5))))))

type Log is Data:
  Log{name: String, val: Wd.W}

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

def lgw(st: St, name: String, +v: Wd.W) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr, pr, ok, Log{name, v} <> log}

def lgf(st: St, name: String, +v: Fp.Fp) -> St:
  lgw(st, name, Fp.to_words(v))

# x coordinate of a point (identity logs as zero)
def lgp(st: St, name: String, +p: V.Pt) -> St:
  lgw(st, name, Wd.clear_top_bit(V.encode(p)))

def check(st: St, +good: Bool) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr, pr, (ok .&. b2u(good) : U32), log}

# common_point: [1] || x || y (affine Fq coordinates); the identity cannot be absorbed
# Affine form without an inversion when z = 1 (every point decompressed from the proof).
def aff_z(one: Bool, p: V.Pt) -> V.Aff:
  match one:
    case True{}:
      V.Pt{x, y, _} = p
      V.Aff{x, y}
    case False{}:
      V.to_aff(p)

def aff_fast(+p: V.Pt) -> V.Aff:
  V.Pt{_, _, +z} = p
  aff_z(Fq.is_eq(z, Fq.one()), p)

def ab_point(st: St, +p: V.Pt) -> St:
  St{tr, pr, +ok, +log} = st
  +a = aff_fast(p)
  +bad = V.is_identity(p)
  St{tr_w(tr_w(tr_byte(tr, 1), Fq.to_words(aff_x(a))), Fq.to_words(aff_y(a))), pr, (ok .&. (1 - b2u(bad)) : U32), log}

# common_scalar: [2] || repr
def ab_scalar(st: St, +s: Fp.Fp) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr_w(tr_byte(tr, 2), Fp.to_words(s)), pr, ok, log}

type SF is Data:
  SF{v: Fp.Fp, st: St}

def sf_v(r: SF) -> Fp.Fp:
  SF{+v, _} = r
  v

def sf_st(r: SF) -> St:
  SF{_, +st} = r
  st

# squeeze_challenge: absorb [0], hash a copy, Challenge255 -> Fp
def squeeze(st: St) -> SF:
  St{tr, pr, +ok, +log} = st
  +tr1 = tr_byte(tr, 0)
  SF{challenge(tr_final(tr1)), St{tr1, pr, ok, log}}

# read_scalar: next item, which must be a canonical encoding (< p)
def rd_scalar_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SF:
  Proof{items, +ivals} = pr
  match items:
    case Nil{}:
      SF{Fp.zero(), St{tr, Proof{Nil{}, ivals}, 0, log}}
    case Con{+it, rest}:
      +w = it_w(it)
      +good = Wd.is_lt(w, Fp.modulus())
      SF{Fp.from_words(w), St{tr_w(tr_byte(tr, 2), w), Proof{rest, ivals}, (ok .&. b2u(good) : U32), log}}

def rd_scalar(st: St) -> SF:
  St{tr, pr, +ok, +log} = st
  rd_scalar_go(tr, pr, ok, log)

# the next instance value (an input, not part of the proof stream)
def rd_ival_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SF:
  Proof{+items, ivals} = pr
  match ivals:
    case Nil{}:
      SF{Fp.zero(), St{tr, Proof{items, Nil{}}, 0, log}}
    case Con{+v, rest}:
      SF{v, St{tr, Proof{items, rest}, ok, log}}

def rd_ival(st: St) -> SF:
  St{tr, pr, +ok, +log} = st
  rd_ival_go(tr, pr, ok, log)

type SP is Data:
  SP{p: V.Pt, st: St}

def sp_p(r: SP) -> V.Pt:
  SP{+p, _} = r
  p

def sp_st(r: SP) -> St:
  SP{_, +st} = r
  st

def rd_point_dec(m: Maybe<&2, V.Pt>, st: St) -> SP:
  match m:
    case None{}:
      SP{V.identity(), check(st, False{})}
    case Some{+p}:
      SP{p, ab_point(st, p)}

def rd_point_pre(+good: U32, +p: V.Pt, st: St) -> SP:
  match good:
    case 0:
      SP{V.identity(), check(st, False{})}
    case _:
      SP{p, ab_point(st, p)}

# read_point: next item is a compressed Vesta point (pasta from_bytes: canonical x, on curve)
def rd_point_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SP:
  Proof{items, +ivals} = pr
  match items:
    case Nil{}:
      SP{V.identity(), St{tr, Proof{Nil{}, ivals}, 0, log}}
    case Con{IS{+w}, rest}:
      rd_point_dec(VD.decompress(w), St{tr, Proof{rest, ivals}, ok, log})
    case Con{IP{_, +good, +p}, rest}:
      rd_point_pre(good, p, St{tr, Proof{rest, ivals}, ok, log})

def rd_point(st: St) -> SP:
  St{tr, pr, +ok, +log} = st
  rd_point_go(tr, pr, ok, log)

# --- bulk reads and indexed access (keeps the generated verifier's live set small) ---

type SL is Data:
  SL{vs: +List<Fp.Fp>, st: St}

def sl_v(r: SL) -> +List<Fp.Fp>:
  SL{+vs, _} = r
  vs

def sl_st(r: SL) -> St:
  SL{_, +st} = r
  st

def rd_scalars_go(n: Nat, st: St, acc: +List<Fp.Fp>) -> SL:
  match n:
    case 0n:
      SL{List.reverse(&2, Fp.Fp, acc), st}
    case 1n+k:
      +r = rd_scalar(st)
      rd_scalars_go(k, sf_st(r), sf_v(r) <> acc)

# read_n_scalars
def rd_scalars(st: St, n: Nat) -> SL:
  rd_scalars_go(n, st, Nil{})

type PL is Data:
  PL{ps: +List<V.Pt>, st: St}

def pl_v(r: PL) -> +List<V.Pt>:
  PL{+ps, _} = r
  ps

def pl_st(r: PL) -> St:
  PL{_, +st} = r
  st

def rd_points_go(n: Nat, st: St, acc: +List<V.Pt>) -> PL:
  match n:
    case 0n:
      PL{List.reverse(&2, V.Pt, acc), st}
    case 1n+k:
      +r = rd_point(st)
      rd_points_go(k, sp_st(r), sp_p(r) <> acc)

# read_n_points
def rd_points(st: St, n: Nat) -> PL:
  rd_points_go(n, st, Nil{})

def fat(i: Nat, xs: +List<Fp.Fp>) -> Fp.Fp:
  match i xs:
    case 0n Con{+h, _}:
      h
    case 1n+k Con{_, t}:
      fat(k, t)
    case _ Nil{}:
      Fp.zero()

def pat(i: Nat, xs: +List<V.Pt>) -> V.Pt:
  match i xs:
    case 0n Con{+h, _}:
      h
    case 1n+k Con{_, t}:
      pat(k, t)
    case _ Nil{}:
      V.identity()

# --- a runtime MSM accumulator (halo2's commitment::MSM "other" terms) ------------

# A term on a fixed base (VK fixed/permutation commitments, W, U), by index; batch mode
# merges these across proofs, so each fixed base appears once in the batch MSM.
type FX is Data:
  FX{i: U32, s: Fp.Fp}

type MS is Data:
  MS{ps: +List<V.Pt>, ss: +List<Fp.Fp>, fx: +List<FX>}

def ms_empty() -> MS:
  MS{Nil{}, Nil{}, Nil{}}

def ms_ps(m: MS) -> +List<V.Pt>:
  MS{+ps, _, _} = m
  ps

def ms_ss(m: MS) -> +List<Fp.Fp>:
  MS{_, +ss, _} = m
  ss

def ms_fx(m: MS) -> +List<FX>:
  MS{_, _, +fx} = m
  fx

def ms_push(m: MS, +s: Fp.Fp, +p: V.Pt) -> MS:
  MS{+ps, +ss, +fx} = m
  MS{p <> ps, s <> ss, fx}

def ms_fix(m: MS, +s: Fp.Fp, +i: U32) -> MS:
  MS{+ps, +ss, +fx} = m
  MS{ps, ss, FX{i, s} <> fx}

def scale_list(xs: +List<Fp.Fp>, +u: Fp.Fp) -> +List<Fp.Fp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Fp.mul(h, u) <> scale_list(t, u)

def scale_fx(xs: +List<FX>, +u: Fp.Fp) -> +List<FX>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{FX{+i, +s}, t}:
      FX{i, Fp.mul(s, u)} <> scale_fx(t, u)

def ms_scale(m: MS, +f: Fp.Fp) -> MS:
  MS{+ps, +ss, +fx} = m
  MS{ps, scale_list(ss, f), scale_fx(fx, f)}

def ms_cat(a: MS, b: MS) -> MS:
  MS{+ap, +as, +af} = a
  MS{+bp, +bs, +bf} = b
  MS{List.append(&2, V.Pt, ap, bp), List.append(&2, Fp.Fp, as, bs), List.append(&2, FX, af, bf)}

# --- IPA helpers ------------------------------------------------------------------

# The IPA s-vector for challenges given top-first (the first IPA round's u first), in front of
# tail: s = s(rest) ++ s(rest) * u, built right to left so every cell is allocated once (no
# appends) with one multiplication per cell. s_i = c * prod of the u_j selected by the bits of i,
# the first round's u on the top bit, as halo2's compute_s; only the order of the products
# differs, and Fp.mul returns the canonical reduced value, so every s_i is the same.
def s_build(+us: +List<Fp.Fp>, +c: Fp.Fp, +tail: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match us:
    case Nil{}:
      c <> tail
    case Con{+u, +rest}:
      s_build(rest, c, s_build(rest, Fp.mul(c, u), tail))

# compute_s(u, init) with the u_j given last-first (as halo2 iterates u.rev())
def compute_s(+us_rev: +List<Fp.Fp>, +init: Fp.Fp) -> +List<Fp.Fp>:
  s_build(List.reverse(&2, Fp.Fp, us_rev), init, Nil{})

def sub_head(xs: +List<Fp.Fp>, +v: Fp.Fp) -> +List<Fp.Fp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Fp.sub(h, v) <> t

def words_list(xs: +List<Fp.Fp>) -> +List<Wd.W>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Fp.to_words(h) <> words_list(t)

def log_list(xs: +List<Fp.Fp>, st: St) -> St:
  match xs:
    case Nil{}:
      st
    case Con{+h, t}:
      log_list(t, lgf(st, "msm_g", h))

# --- output -------------------------------------------------------------------------

def log_line(l: Log) -> String:
  Log{+n, +v} = l
  n ++ " " ++ Wd.hex(v)

def print_log(xs: +List<Log>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{+l, rest}:
      do IO<Unit>:
        IO.print(log_line(l))
        print_log(rest)

# --- boxed values for generated code ------------------------------------------------
# Bend's native backend flattens Data values into registers (an Fp is 16 words, a Vesta
# point 48) and caps a call frame's live registers at 247. A recursive type is laid out as a
# single heap pointer, so the generated verifier keeps every field element and point boxed.

type BF is Data:
  BF0{v: Fp.Fp}
  BF1{v: Fp.Fp, n: BF}

type BP is Data:
  BP0{p: V.Pt}
  BP1{p: V.Pt, n: BP}

def ub(b: BF) -> Fp.Fp:
  match b:
    case BF0{+v}:
      v
    case BF1{+v, _}:
      v

def upt(b: BP) -> V.Pt:
  match b:
    case BP0{+p}:
      p
    case BP1{+p, _}:
      p

def bx(+v: Fp.Fp) -> BF:
  BF0{v}

def bpt(+p: V.Pt) -> BP:
  BP0{p}

def bmul(a: BF, b: BF) -> BF:
  BF0{Fp.mul(ub(a), ub(b))}

def badd(a: BF, b: BF) -> BF:
  BF0{Fp.add(ub(a), ub(b))}

def bsub(a: BF, b: BF) -> BF:
  BF0{Fp.sub(ub(a), ub(b))}

def bneg(a: BF) -> BF:
  BF0{Fp.neg(ub(a))}

def binv(a: BF) -> BF:
  BF0{Fp.inv(ub(a))}

# Inverses of xs in one field inversion (Montgomery's trick); a zero maps to zero, as
# Fp.inv(0) = 0^(p-2) = 0 does, so binvs(xs)[i] == Fp.inv(xs[i]) for every input.
def nz1(xs: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      Fp.sel(Bool.to_u32(Fp.is_zero(x)), Fp.one(), x) <> nz1(t)

def z0(xs: +List<Fp.Fp>, ivs: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match xs ivs:
    case Con{+x, xt} Con{+i, it}:
      Fp.sel(Bool.to_u32(Fp.is_zero(x)), Fp.zero(), i) <> z0(xt, it)
    case _ _:
      Nil{}

def binvs(+xs: +List<Fp.Fp>) -> +List<Fp.Fp>:
  z0(xs, Fp.batch_inv(nz1(xs)))

def bsqrn(n: Nat, a: BF) -> BF:
  BF0{Fp.sqr_n(n, ub(a))}

def bsmul(p: BP, s: BF) -> BP:
  BP0{G.mul(upt(p), Fp.to_words(ub(s)))}

def bpadd(p: BP, q: BP) -> BP:
  BP0{V.add(upt(p), upt(q))}

def bfat(i: Nat, xs: +List<Fp.Fp>) -> BF:
  BF0{fat(i, xs)}

def bpat(i: Nat, xs: +List<V.Pt>) -> BP:
  BP0{pat(i, xs)}

def blgf(st: St, name: String, +v: BF) -> St:
  lgf(st, name, ub(v))

def blgp(st: St, name: String, +p: BP) -> St:
  lgp(st, name, upt(p))

def bab_scalar(st: St, +v: BF) -> St:
  ab_scalar(st, ub(v))

def bab_point(st: St, +p: BP) -> St:
  ab_point(st, upt(p))

def bms_push(m: MS, +s: BF, +p: BP) -> MS:
  ms_push(m, ub(s), upt(p))

def bms_fix(m: MS, +s: BF, +i: U32) -> MS:
  ms_fix(m, ub(s), i)

def bms_scale(m: MS, +f: BF) -> MS:
  ms_scale(m, ub(f))

def bis_identity(p: BP) -> Bool:
  V.is_identity(upt(p))

def rd_ivals_go(n: Nat, st: St, acc: +List<Fp.Fp>) -> SL:
  match n:
    case 0n:
      SL{List.reverse(&2, Fp.Fp, acc), st}
    case 1n+k:
      +r = rd_ival(st)
      rd_ivals_go(k, sf_st(r), sf_v(r) <> acc)

def rd_ivals(st: St, n: Nat) -> SL:
  rd_ivals_go(n, st, Nil{})

# --- per-proof groups (bundles with a runtime number of actions) -------------------

type PLL is Data:
  PLL{gs: +List<+List<V.Pt>>, st: St}

def pll_v(r: PLL) -> +List<+List<V.Pt>>:
  PLL{+gs, _} = r
  gs

def pll_st(r: PLL) -> St:
  PLL{_, +st} = r
  st

def rd_groups_go(n: Nat, +k: Nat, st: St, acc: +List<+List<V.Pt>>) -> PLL:
  match n:
    case 0n:
      PLL{List.reverse(&2, +List<V.Pt>, acc), st}
    case 1n+m:
      +r = rd_points(st, k)
      rd_groups_go(m, k, pl_st(r), pl_v(r) <> acc)

# n proofs, each contributing k points in a row
def rd_groups(st: St, +n: Nat, +k: Nat) -> PLL:
  rd_groups_go(n, k, st, Nil{})

type SLL is Data:
  SLL{gs: +List<+List<Fp.Fp>>, st: St}

def sll_v(r: SLL) -> +List<+List<Fp.Fp>>:
  SLL{+gs, _} = r
  gs

def sll_st(r: SLL) -> St:
  SLL{_, +st} = r
  st

def rd_sgroups_go(n: Nat, +k: Nat, st: St, acc: +List<+List<Fp.Fp>>) -> SLL:
  match n:
    case 0n:
      SLL{List.reverse(&2, +List<Fp.Fp>, acc), st}
    case 1n+m:
      +r = rd_scalars(st, k)
      rd_sgroups_go(m, k, sl_st(r), sl_v(r) <> acc)

def rd_sgroups(st: St, +n: Nat, +k: Nat) -> SLL:
  rd_sgroups_go(n, k, st, Nil{})

# sum_j vals_j * G_lagrange_j + acc (GLV scalar multiplications)
def lag_sum(vals: +List<Fp.Fp>, gl: +List<V.Pt>, +acc: V.Pt) -> V.Pt:
  match vals gl:
    case Con{+v, vr} Con{+g, gr}:
      lag_sum(vr, gr, V.add(acc, G.mul(g, Fp.to_words(v))))
    case _ _:
      acc

# Every product inst_j * G_lag_j of every proof as one wide balanced parallel map (a narrow
# early fork would pin the later MSM forks to few cores), then per-proof sums.
type GV is Data:
  GV{g: V.Pt, v: Fp.Fp}

def gv_mul(t: GV) -> V.Pt:
  GV{+g, +v} = t
  G.mul(g, Fp.to_words(v))

def pmap(+fuel: Nat, +cnt: Nat, +ts: +List<GV>) -> +List<V.Pt>:
  match fuel cnt ts:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+t, _}:
      gv_mul(t) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = pmap(f, h, List.take(&2, GV, ts, h)) pmap(f, Nat.sub(cnt, h), List.drop(&2, GV, ts, h))
      List.append(&2, V.Pt, a, b)
    case _ _ _:
      Nil{}

def zip_gv(vs: +List<Fp.Fp>, gl: +List<V.Pt>, out: +List<GV>) -> +List<GV>:
  match vs gl:
    case Con{+v, vr} Con{+g, gr}:
      zip_gv(vr, gr, GV{g, v} <> out)
    case _ _:
      out

def all_terms(xs: +List<+List<Fp.Fp>>, +gl: +List<V.Pt>) -> +List<GV>:
  match xs:
    case Con{+v, t}:
      List.append(&2, GV, List.reverse(&2, GV, zip_gv(v, gl, Nil{})), all_terms(t, gl))
    case Nil{}:
      Nil{}

def sum_n(k: Nat, ps: +List<V.Pt>, +acc: V.Pt) -> V.Pt:
  match k ps:
    case 1n+m Con{+p, t}:
      sum_n(m, t, V.add(acc, p))
    case _ _:
      acc

def per_proof(n: Nat, +ni: Nat, +ps: +List<V.Pt>, +w: V.Pt) -> +List<V.Pt>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      sum_n(ni, ps, w) <> per_proof(m, ni, List.drop(&2, V.Pt, ps, ni), w)

def comms_wide(+n: Nat, +ni: Nat, +xs: +List<+List<Fp.Fp>>, +gl: +List<V.Pt>, +w: V.Pt) -> +List<V.Pt>:
  +ts = all_terms(xs, gl)
  per_proof(n, ni, pmap(20n, List.length(&2, GV, ts), ts), w)

# The same commitments from fixed-base tables of G_lag_0 .. G_lag_(t-1) (window width c):
# one mixed addition per non-zero signed digit, no doublings. Used when there is a table
# for every instance value (ni <= t); otherwise the GLV path above.
def comm_fb(+c: Nat, +tabs: +List<FB.Tab>, +vs: +List<Fp.Fp>, +w: V.Pt) -> V.Pt:
  FB.msm_add(c, tabs, words_list(vs), w)

def comms_fb(+fuel: Nat, +cnt: Nat, +c: Nat, +tabs: +List<FB.Tab>, +xs: +List<+List<Fp.Fp>>, +w: V.Pt) -> +List<V.Pt>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+v, _}:
      comm_fb(c, tabs, v, w) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = comms_fb(f, h, c, tabs, List.take(&2, +List<Fp.Fp>, xs, h), w) comms_fb(f, Nat.sub(cnt, h), c, tabs, List.drop(&2, +List<Fp.Fp>, xs, h), w)
      List.append(&2, V.Pt, a, b)
    case _ _ _:
      Nil{}

type IVS is Data:
  IVS{vs: +List<+List<Fp.Fp>>, st: St}

def ivs_v(r: IVS) -> +List<+List<Fp.Fp>>:
  IVS{+vs, _} = r
  vs

def ivs_st(r: IVS) -> St:
  IVS{_, +st} = r
  st

# Instance values are read in order (they feed nothing in the transcript here).
def ivals_go(n: Nat, +ni: Nat, st: St, acc: +List<+List<Fp.Fp>>) -> IVS:
  match n:
    case 0n:
      IVS{List.reverse(&2, +List<Fp.Fp>, acc), st}
    case 1n+m:
      +r = rd_ivals(st, ni)
      ivals_go(m, ni, sl_st(r), sl_v(r) <> acc)

# instance commitments, one per proof (single instance column): sum inst_j G_lag_j + 1*W
def inst_comms(st: St, +n: Nat, +ni: Nat, +gl: +List<V.Pt>, +w: V.Pt) -> PL:
  +r = ivals_go(n, ni, st, Nil{})
  PL{comms_wide(n, ni, ivs_v(r), gl, w), ivs_st(r)}

# Fixed-base table width for the instance commitments (batch mode).
def fb_c() -> Nat:
  8n

# perf5: the instance commitments of one bundle, sharing work across its actions.
# Every Orchard action's instance column is [anchor, cv_net x, cv_net y, nf_old, rk x, rk y, cmx,
# enable_spend, enable_output, disable_cross_address]: the anchor is the bundle's (equal in every
# action) and the last three are 0 or 1. So W + anchor*G_lag_0 is computed once per bundle, a value
# 0 adds nothing and a value 1 adds the table's 1*G_lag_j entry (exactly what mul_add does for
# s = 1), and only the other values pay a full fixed-base multiplication. Nothing is assumed: an
# action whose first value is not the shared anchor, or any value other than 0 and 1, takes the
# general path, so every commitment is the same group element as comm_fb's for any input.

def head_fp(xs: +List<Fp.Fp>) -> Fp.Fp:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      Fp.zero()

def head_vs(xs: +List<+List<Fp.Fp>>) -> +List<Fp.Fp>:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      Nil{}

# the commitments in affine form (z = 1, one shared inversion), so the transcript's
# common_point needs no inversion per commitment; the identity stays the identity
def aps_pts(xs: +List<BA.AP>) -> +List<V.Pt>:
  match xs:
    case Con{+a, t}:
      BA.ap_to_pt(a) <> aps_pts(t)
    case Nil{}:
      Nil{}

# The same with the flat table (FB.make_flat): P_j is base j of the table. Every rule above holds
# unchanged; only the table lookups differ.
def fa_one_r(r: Array<U32> & BA.AP, +acc: V.Pt) -> Array<U32> & V.Pt:
  (a, +p) = r
  (a, FB.add_d(acc, p))

# acc + v * P_b
def fa_one(o: Bool, a: Array<U32>, +c: Nat, +b: U32, +v: Fp.Fp, +acc: V.Pt) -> Array<U32> & V.Pt:
  match o:
    case True{}:
      fa_one_r(FB.first_f(a, c, b), acc)
    case False{}:
      FB.mul_add_f(a, c, b, Fp.to_words(v), acc)

def fa_zero(z: Bool, a: Array<U32>, +c: Nat, +b: U32, +v: Fp.Fp, +acc: V.Pt) -> Array<U32> & V.Pt:
  match z:
    case True{}:
      (a, acc)
    case False{}:
      fa_one(Fp.is_eq(v, Fp.one()), a, c, b, v, acc)

# r = (table, acc): acc + sum_k vs_k P_(b+k)
def fa_msm(vs: +List<Fp.Fp>, +c: Nat, +b: U32, r: Array<U32> & V.Pt) -> V.Pt:
  match vs:
    case Con{+v, vt}:
      (a, +acc) = r
      fa_msm(vt, c, (b + 1 : U32), fa_zero(Fp.is_zero(v), a, c, b, v, acc))
    case Nil{}:
      (a, +acc) = r
      acc

# one action: from the shared base when its anchor matches, otherwise from W
def fa_act(same: Bool, a: Array<U32>, +c: Nat, +vs: +List<Fp.Fp>, +base: V.Pt, +w: V.Pt) -> V.Pt:
  match same:
    case True{}:
      fa_msm(List.drop(&2, Fp.Fp, vs, 1n), c, 1, (a, base))
    case False{}:
      fa_msm(vs, c, 0, (a, w))

def fa_sh(+fuel: Nat, +cnt: Nat, +c: Nat, +xs: +List<+List<Fp.Fp>>, +anchor: Fp.Fp, +base: V.Pt, +w: V.Pt, p: Array<U32> & Array<U32>) -> +List<V.Pt>:
  match fuel cnt xs:
    case _ 1n Con{+v, _}:
      (a1, a2) = p
      fa_act(Fp.is_eq(head_fp(v), anchor), a1, c, v, base, w) <> Nil{}
    case 1n+f 1n+1n+_ _:
      (a1, a2) = p
      +h = Nat.div(cnt, 2n)
      x y = fa_sh(f, h, c, List.take(&2, +List<Fp.Fp>, xs, h), anchor, base, w, Array.fork(U32, a1)) fa_sh(f, Nat.sub(cnt, h), c, List.drop(&2, +List<Fp.Fp>, xs, h), anchor, base, w, Array.fork(U32, a2))
      List.append(&2, V.Pt, x, y)
    case _ _ _:
      (a1, a2) = p
      Nil{}

def fa_shared_r(r: Array<U32> & V.Pt, +n: Nat, +c: Nat, +xs: +List<+List<Fp.Fp>>, +anchor: Fp.Fp, +w: V.Pt) -> +List<V.Pt>:
  (a, +base) = r
  aps_pts(BA.normalize(fa_sh(20n, n, c, xs, anchor, base, w, Array.fork(U32, a))))

def comms_shared(+n: Nat, +c: Nat, a: Array<U32>, +xs: +List<+List<Fp.Fp>>, +w: V.Pt) -> +List<V.Pt>:
  +anchor = head_fp(head_vs(xs))
  fa_shared_r(FB.mul_add_f(a, c, 0, Fp.to_words(anchor), w), n, c, xs, anchor, w)

def comms_sel(glv: Bool, +n: Nat, +ni: Nat, +xs: +List<+List<Fp.Fp>>, +gl: +List<V.Pt>, a: Array<U32>, +w: V.Pt) -> +List<V.Pt>:
  match glv:
    case True{}:
      comms_wide(n, ni, xs, gl, w)
    case False{}:
      comms_shared(n, fb_c(), a, xs, w)

# r = (table, its base count; 0 when there is no table)
def comms_any_r(r: Array<U32> & U32, +n: Nat, +ni: Nat, +xs: +List<+List<Fp.Fp>>, +gl: +List<V.Pt>, +w: V.Pt) -> +List<V.Pt>:
  (a, +nb) = r
  comms_sel(Bool.or(U32.is_eq(nb, 0), U32.is_lt(nb, U32.from_nat(ni))), n, ni, xs, gl, a, w)

def comms_any(+n: Nat, +ni: Nat, +xs: +List<+List<Fp.Fp>>, +gl: +List<V.Pt>, a: Array<U32>, +w: V.Pt) -> +List<V.Pt>:
  comms_any_r(a[1], n, ni, xs, gl, w)

# inst_comms, with the flat fixed-base table when given (one base per instance value)
def inst_comms_fb(st: St, +n: Nat, +ni: Nat, +gl: +List<V.Pt>, a: Array<U32>, +w: V.Pt) -> PL:
  +r = ivals_go(n, ni, st, Nil{})
  PL{comms_any(n, ni, ivs_v(r), gl, a, w), ivs_st(r)}

def ab_points(ps: +List<V.Pt>, st: St) -> St:
  match ps:
    case Nil{}:
      st
    case Con{+p, rest}:
      ab_points(rest, ab_point(st, p))

type HS is Data:
  HS{h: BF, st: St}

def hs_h(r: HS) -> BF:
  HS{+h, _} = r
  h

def hs_st(r: HS) -> St:
  HS{_, +st} = r
  st

def rev_pts(xs: +List<V.Pt>) -> +List<V.Pt>:
  List.reverse(&2, V.Pt, xs)

def rev_pll(xs: +List<+List<V.Pt>>) -> +List<+List<V.Pt>>:
  List.reverse(&2, +List<V.Pt>, xs)

def rev_sll(xs: +List<+List<Fp.Fp>>) -> +List<+List<Fp.Fp>>:
  List.reverse(&2, +List<Fp.Fp>, xs)

def nat_of(+n: U32) -> Nat:
  U32.to_nat(n)
