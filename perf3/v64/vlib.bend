# Halo 2 verifier runtime (hand-written), on H1's Pasta library (../lib) and the generated
# BLAKE2b compression function (b2.bend). Generated verifiers import this as `L`.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../field3/fp64.bend as Fp
import ../../field3/fq64.bend as Fq
import ../../field3/lib64/vesta.bend as V
import ../lib_64/glv_vesta.bend as G
import ../../decomp/vesta_dec.bend as VD
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

# h: chaining value; t: bytes compressed so far; n: pending bytes; buf: pending bytes, newest first
type Tr is Data:
  Tr{h: B.H8, t: U32, n: U32, buf: +List<U32>}

# BLAKE2b-512, personalization "Halo2-Transcript", no key
def tr_init() -> Tr:
  Tr{B.H8{4072524104, 1779033703, 2227873595, 3144134277, 4271175723, 1013904242, 1595750129, 2773480762, 2917565137, 1359893119, 725511199, 2600822924, 2486033443, 1842869401, 1879920408, 798008427}, 0, 0, Nil{}}

# BLAKE2b compresses a full buffer only once more input arrives (the last block is final)
def tr_byte_if(full: Bool, h: B.H8, +t: U32, +n: U32, buf: +List<U32>, +b: U32) -> Tr:
  match full:
    case True{}:
      Tr{B.b2_compress(h, block(List.reverse(&2, U32, buf)), (t + 128 : U32), 0), (t + 128 : U32), 1, b <> Nil{}}
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

# BLAKE2b finalization of a copy of the state: the 64 output bytes as an H8
def tr_final(tr: Tr) -> B.H8:
  Tr{h, +t, +n, +buf} = tr
  B.b2_compress(h, block(List.reverse(&2, U32, buf)), (t + n : U32), 1)

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
  Proof{items: +List<Wd.W>, ivals: +List<Fp.Fp>}

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
  St{tr_bytes(1 <> bytes_of_w(Fq.to_words(aff_x(a)), bytes_of_w(Fq.to_words(aff_y(a)), Nil{})), tr), pr, (ok .&. (1 - b2u(bad)) : U32), log}

# common_scalar: [2] || repr
def ab_scalar(st: St, +s: Fp.Fp) -> St:
  St{tr, pr, +ok, +log} = st
  St{tr_bytes(2 <> bytes_of_w(Fp.to_words(s), Nil{}), tr), pr, ok, log}

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
    case Con{+w, rest}:
      +good = Wd.is_lt(w, Fp.modulus())
      SF{Fp.from_words(w), St{tr_bytes(2 <> bytes_of_w(w, Nil{}), tr), Proof{rest, ivals}, (ok .&. b2u(good) : U32), log}}

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

# read_point: next item is a compressed Vesta point (pasta from_bytes: canonical x, on curve)
def rd_point_go(tr: Tr, pr: Proof, +ok: U32, log: +List<Log>) -> SP:
  Proof{items, +ivals} = pr
  match items:
    case Nil{}:
      SP{V.identity(), St{tr, Proof{Nil{}, ivals}, 0, log}}
    case Con{+w, rest}:
      rd_point_dec(VD.decompress(w), St{tr, Proof{rest, ivals}, ok, log})

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

type MS is Data:
  MS{ps: +List<V.Pt>, ss: +List<Fp.Fp>}

def ms_empty() -> MS:
  MS{Nil{}, Nil{}}

def ms_ps(m: MS) -> +List<V.Pt>:
  MS{+ps, _} = m
  ps

def ms_ss(m: MS) -> +List<Fp.Fp>:
  MS{_, +ss} = m
  ss

def ms_push(m: MS, +s: Fp.Fp, +p: V.Pt) -> MS:
  MS{+ps, +ss} = m
  MS{p <> ps, s <> ss}

def scale_list(xs: +List<Fp.Fp>, +u: Fp.Fp) -> +List<Fp.Fp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Fp.mul(h, u) <> scale_list(t, u)

def ms_scale(m: MS, +f: Fp.Fp) -> MS:
  MS{+ps, +ss} = m
  MS{ps, scale_list(ss, f)}

def ms_cat(a: MS, b: MS) -> MS:
  MS{+ap, +as} = a
  MS{+bp, +bs} = b
  MS{List.append(&2, V.Pt, ap, bp), List.append(&2, Fp.Fp, as, bs)}

# --- IPA helpers ------------------------------------------------------------------

def s_go(us: +List<Fp.Fp>, +acc: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match us:
    case Nil{}:
      acc
    case Con{+u, rest}:
      s_go(rest, List.append(&2, Fp.Fp, acc, scale_list(acc, u)))

# compute_s(u, init) with the u_j given last-first (as halo2 iterates u.rev())
def compute_s(us_rev: +List<Fp.Fp>, +init: Fp.Fp) -> +List<Fp.Fp>:
  s_go(us_rev, init <> Nil{})

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
