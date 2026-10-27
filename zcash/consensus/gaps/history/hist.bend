# zcash/consensus/gaps/history: the ZIP 221 chain history tree (a Merkle mountain range), in Bend.
#
# Mirrors zcash_history 0.6.0 (the crate Zebra uses) exactly:
#  - node data V1 (Heartwood, Canopy), V2 (NU5 .. NU6.2: + Orchard root/count),
#    V3 (NU6.3, NU7: + Ironwood root/count); node_data.rs write()
#  - a leaf per block: start == end fields; subtree_commitment = block hash
#  - combine(l, r): subtree_commitment = BLAKE2b-256("ZcashHistory" || branch LE,
#    ser(l) || ser(r)); start fields from l, end fields from r, work and counts summed
#  - append: merge equal-sized peaks right to left (tree.rs append_leaf)
#  - root: peaks folded left to right, combine(combine(p0, p1), p2) ...; the history root
#    is BLAKE2b-256("ZcashHistory" || branch, ser(root node))  (version.rs hash())
#
# Each peak keeps, next to it, its "bag": the left fold of all peaks up to and including it.
# An append only changes the rightmost peaks, so only their bags are recomputed and the
# root of every block costs O(1) combines amortized instead of O(log n).
#
# Bytes are U32 values 0..255 (as in zcash/block). 256-bit numbers (targets, work) are
# little-endian byte lists.
import Base
import ../../../block/blake2b.bend as B
import ../../../block/bytes.bend as Y
import ../../../wire/hb.bend as H

# Epoch index: 0 pre-Heartwood, 1 Heartwood, 2 Canopy, 3 NU5, 4 NU6, 5 NU6.1, 6 NU6.2,
# 7 NU6.3, 8 NU7.  Activation heights: zebra-chain parameters/constants.rs.
# net: 0 = Mainnet, 1 = Testnet.
def ifu(c: Bool, +a: U32, +b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

# k -> table[k-1] for k in 1..8, else 2^32-1.
def tab8(+e: U32, +a: U32, +b: U32, +c: U32, +d: U32, +f: U32, +g: U32, +h: U32, +i: U32, +o: U32) -> U32:
  ifu(U32.is_eq(e, 1), a, ifu(U32.is_eq(e, 2), b, ifu(U32.is_eq(e, 3), c, ifu(U32.is_eq(e, 4), d,
    ifu(U32.is_eq(e, 5), f, ifu(U32.is_eq(e, 6), g, ifu(U32.is_eq(e, 7), h, ifu(U32.is_eq(e, 8), i, o))))))))

# Consensus branch ids: zebra-chain parameters/network_upgrade.rs CONSENSUS_BRANCH_IDS.
def branch(+e: U32) -> U32:
  tab8(e, 4122551051, 3925833126, 3268858036, 3370586197, 1307332080, 1412952880, 933566043, 1998129881, 0)

def zeros(+n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      0 <> zeros(p)

# ---------------------------------------------------------------- epochs

def add_go(xs: +List<U32>, ys: +List<U32>, +c: U32) -> +List<U32>:
  match xs ys:
    case Con{+a, s} Con{+b, t}:
      +v = (a + b + c : U32)
      (v .&. 255 : U32) <> add_go(s, t, (v >> 8n : U32))
    case _ _:
      Nil{}

def add(+xs: +List<U32>, +ys: +List<U32>) -> +List<U32>:
  add_go(xs, ys, 0)

# The expanded target of compact nBits as 33 LE bytes: mantissa (23 bits) * 256^(e-3).
# (Every Heartwood-onward nBits has 3 <= e <= 32 and a clear sign bit.)
def tbyte(+i: U32, +e: U32, +m: U32) -> U32:
  ifu(U32.is_eq(i, (e - 3 : U32)), (m .&. 255 : U32), ifu(U32.is_eq(i, (e - 2 : U32)), ((m >> 8n) .&. 255 : U32),
    ifu(U32.is_eq(i, (e - 1 : U32)), ((m >> 16n) .&. 255 : U32), 0)))

def target_go(fuel: Nat, +i: U32, +e: U32, +m: U32) -> +List<U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      tbyte(i, e, m) <> target_go(p, (i + 1 : U32), e, m)

def target(+bits: U32) -> +List<U32>:
  target_go(33n, 0, (bits >> 24n : U32), (bits .&. 8388607 : U32))

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def ilog2_8(+b: U32) -> U32:
  (b2u(U32.is_le(2, b)) + b2u(U32.is_le(4, b)) + b2u(U32.is_le(8, b)) + b2u(U32.is_le(16, b))
    + b2u(U32.is_le(32, b)) + b2u(U32.is_le(64, b)) + b2u(U32.is_le(128, b)) : U32)

def top_sel(nz: Bool, +i: U32, +b: U32, +acc: U32) -> U32:
  match nz:
    case True{}:
      ((i << 3n) + ilog2_8(b) : U32)
    case False{}:
      acc

# Index of the highest set bit (xs != 0).
def topbit_go(xs: +List<U32>, +i: U32, +acc: U32) -> U32:
  match xs:
    case Con{+b, t}:
      topbit_go(t, (i + 1 : U32), top_sel(U32.is_ne(b, 0), i, b, acc))
    case Nil{}:
      acc

def pow2_go(fuel: Nat, +i: U32, +p: U32) -> +List<U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+k:
      (b2u(U32.is_eq(i, (p >> 3n : U32))) << U32.to_nat((p .&. 7 : U32)) : U32) <> pow2_go(k, (i + 1 : U32), p)

def sub_go(xs: +List<U32>, ys: +List<U32>, +bw: U32) -> +List<U32>:
  match xs ys:
    case Con{+a, s} Con{+b, t}:
      +v = (a - b - bw : U32)
      (v .&. 255 : U32) <> sub_go(s, t, (v >> 31n : U32))
    case _ _:
      Nil{}

def ge_sel(eq: Bool, +a: U32, +b: U32, r: Bool) -> Bool:
  match eq:
    case True{}:
      r
    case False{}:
      U32.is_gt(a, b)

# br: consensus branch id; ver: 1, 2 or 3; cm: subtree commitment; st/et: times;
# sb/eb: nBits; ssr/esr: Sapling roots; wk: subtree total work (32 bytes LE);
# sh/eh: heights; stx: Sapling tx count; sor/eor, otx: Orchard; sir/eir, itx: Ironwood.
type ND is Data:
  ND{br: U32, ver: U32, cm: +List<U32>, st: U32, et: U32, sb: U32, eb: U32, ssr: +List<U32>, esr: +List<U32>, wk: +List<U32>, sh: U32, eh: U32, stx: U32, sor: +List<U32>, eor: +List<U32>, otx: U32, sir: +List<U32>, eir: +List<U32>, itx: U32}

# A peak and its bag (left fold of the peaks up to it).
type E is Data:
  E{pk: ND, bag: ND}

def leaves(n: ND) -> U32:
  ND{_, _, _, _, _, _, _, _, _, _, +sh, +eh, _, _, _, _, _, _, _} = n
  (eh - sh + 1 : U32)

def e_pk(e: E) -> ND:
  E{+pk, _} = e
  pk

# Does the rightmost peak have as many leaves as cur?
def same(+cur: ND, ps: +List<E>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{e, _}:
      U32.is_eq(leaves(e_pk(e)), leaves(cur))

# xs >= ys (same length, little-endian): higher bytes decide.
def ge_go(xs: +List<U32>, ys: +List<U32>, r: Bool) -> Bool:
  match xs ys:
    case Con{+a, s} Con{+b, t}:
      ge_go(s, t, ge_sel(U32.is_eq(a, b), a, b, r))
    case _ _:
      r

def ge(+xs: +List<U32>, +ys: +List<U32>) -> Bool:
  ge_go(xs, ys, True{})

# 2x + c (c in {0, 1}), dropping the carry out of the top byte.
def shl1(xs: +List<U32>, +c: U32) -> +List<U32>:
  match xs:
    case Con{+a, s}:
      (((a << 1n) .|. c) .&. 255 : U32) <> shl1(s, (a >> 7n : U32))
    case Nil{}:
      Nil{}

def sel_l(b: Bool, +x: +List<U32>, +y: +List<U32>) -> +List<U32>:
  match b:
    case True{}:
      x
    case False{}:
      y

def act(+net: U32, +e: U32) -> U32:
  ifu(U32.is_eq(net, 0),
    tab8(e, 903000, 1046400, 1687104, 2726400, 3146400, 3364600, 3428143, 3543405, 4294967295),
    tab8(e, 903800, 1028500, 1842420, 2976000, 3536500, 4052000, 4134000, 4465026, 4294967295))

# The epoch of height h: how many activation heights are <= h.
def epoch(+net: U32, +h: U32) -> U32:
  (b2u(U32.is_le(act(net, 1), h)) + b2u(U32.is_le(act(net, 2), h)) + b2u(U32.is_le(act(net, 3), h))
    + b2u(U32.is_le(act(net, 4), h)) + b2u(U32.is_le(act(net, 5), h)) + b2u(U32.is_le(act(net, 6), h))
    + b2u(U32.is_le(act(net, 7), h)) + b2u(U32.is_le(act(net, 8), h)) : U32)

# Node data version: zebra-chain history_tree.rs (PreOrchard / OrchardOnward / IronwoodOnward).
def version(+e: U32) -> U32:
  (b2u(U32.is_le(1, e)) + b2u(U32.is_le(3, e)) + b2u(U32.is_le(7, e)) : U32)

# ---------------------------------------------------------------- 256-bit arithmetic (LE bytes)

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  Y.append(a, b)

def commit_sel(c: Bool, +hroot: +List<U32>, +auth: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      B.hash32(B.P.ZcashBlockCommit(), cat(hroot, cat(auth, zeros(32n))))
    case False{}:
      hroot

def commit(+e: U32, +hroot: +List<U32>, +auth: +List<U32>) -> +List<U32>:
  commit_sel(U32.is_le(3, e), hroot, auth)

# Restoring long division of 2^256 by d, from the step where the partial remainder first
# reaches d's bit length (all earlier quotient bits are 0).
def div_go(fuel: Nat, +r: +List<U32>, +d: +List<U32>, +q: +List<U32>) -> +List<U32>:
  match fuel:
    case 0n:
      q
    case 1n+k:
      +g = ge(r, d)
      div_go(k, shl1(sel_l(g, sub_go(r, d, 0), r), 0), d, shl1(q, b2u(g)))

# work(nBits) = floor(2^256 / (target + 1)), as 32 LE bytes (protocol spec section 7.7.5;
# zebra-chain work/difficulty.rs: (!t / (t + 1)) + 1, the same value).
def work(+bits: U32) -> +List<U32>:
  +d = add(target(bits), 1 <> zeros(32n))
  +p = topbit_go(d, 0, 0)
  Y.take(div_go(U32.to_nat((257 - p : U32)), pow2_go(33n, 0, p), d, zeros(32n)), 32n)

# ---------------------------------------------------------------- node data

# A leaf (zebra-chain primitives/zcash_history.rs block_to_history_node). Roots and counts
# the version does not commit to are kept but never serialized.
def leaf(+e: U32, +hash: +List<U32>, +time: U32, +bits: U32, +sap: +List<U32>, +orch: +List<U32>, +iw: +List<U32>, +h: U32, +stx: U32, +otx: U32, +itx: U32) -> ND:
  ND{branch(e), version(e), hash, time, time, bits, bits, sap, sap, work(bits), h, h, stx, orch, orch, otx, iw, iw, itx}

# ---------------------------------------------------------------- the MMR

type St is Data:
  St{net: U32, last: U32, ep: U32, ps: +List<E>}

type R is Data:
  R{line: String, st: St}

def nil_e(ps: +List<E>) -> Bool:
  match ps:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def pers(+br: U32) -> B.P4:
  # "ZcashHistory" || branch id (LE)
  B.P4{1935762266, 1936279656, 2037542772, br}

def ser_v3_sel(c: Bool, +sir: +List<U32>, +eir: +List<U32>, +itx: U32) -> +List<U32>:
  match c:
    case True{}:
      cat(sir, cat(eir, Y.compact(itx)))
    case False{}:
      Nil{}

def ser_v3(+ver: U32, +sir: +List<U32>, +eir: +List<U32>, +itx: U32) -> +List<U32>:
  ser_v3_sel(U32.is_le(3, ver), sir, eir, itx)

def ser_v2_sel(c: Bool, +sor: +List<U32>, +eor: +List<U32>, +otx: U32, +rest: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      cat(sor, cat(eor, cat(Y.compact(otx), rest)))
    case False{}:
      Nil{}

def ser_v2(+ver: U32, +sor: +List<U32>, +eor: +List<U32>, +otx: U32, +rest: +List<U32>) -> +List<U32>:
  ser_v2_sel(U32.is_le(2, ver), sor, eor, otx, rest)

# zcash_history node_data.rs write(): V1 fields, then V2's, then V3's.
def ser(n: ND) -> +List<U32>:
  ND{_, +ver, +cm, +st, +et, +sb, +eb, +ssr, +esr, +wk, +sh, +eh, +stx, +sor, +eor, +otx, +sir, +eir, +itx} = n
  cat(cm, cat(Y.le32(st), cat(Y.le32(et), cat(Y.le32(sb), cat(Y.le32(eb), cat(ssr, cat(esr, cat(wk,
    cat(Y.compact(sh), cat(Y.compact(eh), cat(Y.compact(stx), ser_v2(ver, sor, eor, otx, ser_v3(ver, sir, eir, itx)))))))))))))

def nd_br(n: ND) -> U32:
  ND{+br, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = n
  br

# version.rs hash(): the history root of a tree whose root node is n.
def node_hash(+n: ND) -> +List<U32>:
  B.hash32(pers(nd_br(n)), ser(n))

def e_bag(e: E) -> ND:
  E{_, +bag} = e
  bag

# The history root (32 zero bytes for an empty tree, which never reaches a check).
def root(+ps: +List<E>) -> +List<U32>:
  match ps:
    case Nil{}:
      zeros(32n)
    case Con{e, _}:
      node_hash(e_bag(e))

def hexs(+xs: +List<U32>) -> String:
  Y.hex(xs)

def verdict(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

def check_line(+h: U32, +field: +List<U32>, +computed: +List<U32>, +hroot: +List<U32>) -> String:
  "hist " ++ U32.show(h) ++ " " ++ verdict(Y.is_eq(field, computed)) ++ " " ++ hexs(field) ++ " " ++ hexs(computed) ++ " root " ++ hexs(hroot)

# The header check of block h against the tree of blocks up to h-1 (the state s).
# have_auth: whether auth is the block's real hashAuthDataRoot (only seed mode lacks it).
def check_auth(c: Bool, +e: U32, +h: U32, +field: +List<U32>, +auth: +List<U32>, +ps: +List<E>) -> String:
  match c:
    case True{}:
      check_line(h, field, commit(e, root(ps), auth), root(ps))
    case False{}:
      "hist " ++ U32.show(h) ++ " UNCHECKED no-authroot root " ++ hexs(root(ps))

def check_hist(nohist: Bool, +e: U32, +h: U32, +field: +List<U32>, +auth: +List<U32>, have_auth: Bool, +ps: +List<E>) -> String:
  match nohist:
    case True{}:
      "hist " ++ U32.show(h) ++ " SKIP no-history"
    case False{}:
      check_auth(Bool.or(have_auth, U32.is_lt(e, 3)), e, h, field, auth, ps)

def check_hw(hw: Bool, +e: U32, +h: U32, +field: +List<U32>, +auth: +List<U32>, have_auth: Bool, +last: U32, +ps: +List<E>) -> String:
  match hw:
    case True{}:
      # Heartwood activation block: hashLightClientRoot is [0; 32] (ZIP 221).
      check_line(h, field, zeros(32n), zeros(32n))
    case False{}:
      check_hist(Bool.or(nil_e(ps), U32.is_ne(last, (h - 1 : U32))), e, h, field, auth, have_auth, ps)

def check_pre(pre: Bool, +net: U32, +e: U32, +h: U32, +field: +List<U32>, +auth: +List<U32>, have_auth: Bool, +last: U32, +ps: +List<E>) -> String:
  match pre:
    case True{}:
      "hist " ++ U32.show(h) ++ " n/a"
    case False{}:
      check_hw(U32.is_eq(h, act(net, 1)), e, h, field, auth, have_auth, last, ps)

def check(+s: St, +h: U32, +field: +List<U32>, +auth: +List<U32>, have_auth: Bool) -> String:
  St{+net, +last, _, +ps} = s
  +e = epoch(net, h)
  check_pre(U32.is_eq(e, 0), net, e, h, field, auth, have_auth, last, ps)

def combine_h(+h: +List<U32>, l: ND, r: ND) -> ND:
  ND{+br, +ver, _, +st, _, +sb, _, +ssr, _, +lw, +sh, _, +ls, +sor, _, +lo, +sir, _, +li} = l
  ND{_, _, _, _, +et, _, +eb, _, +esr, +rw, _, +eh, +rs, _, +eor, +ro, _, +eir, +ri} = r
  ND{br, ver, h, st, et, sb, eb, ssr, esr, add(lw, rw), sh, eh, (ls + rs : U32), sor, eor, (lo + ro : U32), sir, eir, (li + ri : U32)}

# zcash_history version.rs combine().
def combine(+l: ND, +r: ND) -> ND:
  combine_h(B.hash32(pers(nd_br(l)), cat(ser(l), ser(r))), l, r)

def push(+cur: ND, +ps: +List<E>) -> +List<E>:
  match ps:
    case Nil{}:
      E{cur, cur} <> Nil{}
    case Con{e, t}:
      E{cur, combine(e_bag(e), cur)} <> (e <> t)

# Peaks are kept rightmost first. A new leaf merges with every peak of its size.
def merge(+ps: +List<E>, eq: Bool, +cur: ND) -> +List<E>:
  match ps eq:
    case Con{e, t} True{}:
      +c2 = combine(e_pk(e), cur)
      merge(t, same(c2, t), c2)
    case _ _:
      push(cur, ps)

def append(+ps: +List<E>, +lf: ND) -> +List<E>:
  merge(ps, same(lf, ps), lf)

def update_new(fresh: Bool, +net: U32, +h: U32, +e: U32, +lf: ND) -> St:
  match fresh:
    case True{}:
      St{net, h, e, push(lf, Nil{})}
    case False{}:
      St{net, h, e, Nil{}}

def update_sel(cont: Bool, +net: U32, +h: U32, +e: U32, +ps: +List<E>, +lf: ND) -> St:
  match cont:
    case True{}:
      St{net, h, e, append(ps, lf)}
    case False{}:
      update_new(Bool.and(U32.is_ne(e, 0), U32.is_eq(h, act(net, e))), net, h, e, lf)

# Add block h's leaf: append within an epoch, a fresh tree at an activation height,
# nothing without history.
def update(+s: St, +h: U32, +lf: ND) -> St:
  St{+net, +last, +ep, +ps} = s
  +e = epoch(net, h)
  update_sel(Bool.and(Bool.and(Bool.not(nil_e(ps)), U32.is_eq(last, (h - 1 : U32))), U32.is_eq(ep, e)), net, h, e, ps, lf)

def step_sel(pre: Bool, +line: String, +s: St, +net: U32, +e: U32, +h: U32, +lf: ND) -> R:
  match pre:
    case True{}:
      R{line, St{net, h, 0, Nil{}}}
    case False{}:
      R{line, update(s, h, lf)}

def step(+s: St, +h: U32, +field: +List<U32>, +auth: +List<U32>, have_auth: Bool, +hash: +List<U32>, +time: U32, +bits: U32,
         +sap: +List<U32>, +orch: +List<U32>, +iw: +List<U32>, +stx: U32, +otx: U32, +itx: U32) -> R:
  St{+net, _, _, _} = s
  +e = epoch(net, h)
  step_sel(U32.is_eq(e, 0), check(s, h, field, auth, have_auth), s, net, e, h, leaf(e, hash, time, bits, sap, orch, iw, h, stx, otx, itx))

# Rebuild bags from peaks given leftmost first.
def from_peaks(xs: +List<ND>, +acc: +List<E>) -> +List<E>:
  match xs:
    case Nil{}:
      acc
    case Con{p, t}:
      from_peaks(t, push(p, acc))

def peaks_lr(ps: +List<E>, +acc: +List<ND>) -> +List<ND>:
  match ps:
    case Nil{}:
      acc
    case Con{e, t}:
      peaks_lr(t, e_pk(e) <> acc)

def npeaks(ps: +List<E>) -> U32:
  match ps:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + npeaks(t) : U32)

# ---------------------------------------------------------------- state (binary, deterministic)
#
# "ZHT1" | u32 net | u32 last height | u32 epoch | u32 n | n peaks, leftmost first, each:
#   u32 br | u32 ver | cm 32 | u32 st | u32 et | u32 sb | u32 eb | ssr 32 | esr 32 | work 32 |
#   u32 sh | u32 eh | u32 stx | sor 32 | eor 32 | u32 otx | sir 32 | eir 32 | u32 itx
# (300 bytes per peak). An empty tree has n = 0.

def nd_bytes(n: ND) -> +List<U32>:
  ND{+br, +ver, +cm, +st, +et, +sb, +eb, +ssr, +esr, +wk, +sh, +eh, +stx, +sor, +eor, +otx, +sir, +eir, +itx} = n
  cat(Y.le32(br), cat(Y.le32(ver), cat(cm, cat(Y.le32(st), cat(Y.le32(et), cat(Y.le32(sb), cat(Y.le32(eb), cat(ssr, cat(esr, cat(wk,
    cat(Y.le32(sh), cat(Y.le32(eh), cat(Y.le32(stx), cat(sor, cat(eor, cat(Y.le32(otx), cat(sir, cat(eir, Y.le32(itx)))))))))))))))))))

def nds_bytes(xs: +List<ND>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{n, t}:
      cat(nd_bytes(n), nds_bytes(t))

def state_bytes(s: St) -> +List<U32>:
  St{+net, +last, +ep, +ps} = s
  cat([90, 72, 84, 49], cat(Y.le32(net), cat(Y.le32(last), cat(Y.le32(ep), cat(Y.le32(npeaks(ps)), nds_bytes(peaks_lr(ps, Nil{})))))))

def u32o(+xs: +List<U32>, +o: U32) -> U32:
  H.le32(H.drop(xs, o))

def b32o(+xs: +List<U32>, +o: U32) -> +List<U32>:
  H.take(H.drop(xs, o), 32)

def nd_of(+x: +List<U32>) -> ND:
  ND{u32o(x, 0), u32o(x, 4), b32o(x, 8), u32o(x, 40), u32o(x, 44), u32o(x, 48), u32o(x, 52), b32o(x, 56), b32o(x, 88), b32o(x, 120),
     u32o(x, 152), u32o(x, 156), u32o(x, 160), b32o(x, 164), b32o(x, 196), u32o(x, 228), b32o(x, 232), b32o(x, 264), u32o(x, 296)}

def nds_of(n: Nat, +xs: +List<U32>) -> +List<ND>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      nd_of(H.take(xs, 300)) <> nds_of(k, H.drop(xs, 300))

def state_ok(ok: Bool, +net: U32, +xs: +List<U32>) -> St:
  match ok:
    case True{}:
      St{u32o(xs, 4), u32o(xs, 8), u32o(xs, 12), from_peaks(nds_of(U32.to_nat(u32o(xs, 16)), H.drop(xs, 20)), Nil{})}
    case False{}:
      St{net, 0, 0, Nil{}}

# Parse a state file; anything without the magic is the empty state on network net.
def state_of(+net: U32, +xs: +List<U32>) -> St:
  state_ok(U32.is_eq(u32o(xs, 0), 827607130), net, xs)

# ---------------------------------------------------------------- one block

def r_line(r: R) -> String:
  R{+l, _} = r
  l

def r_st(r: R) -> St:
  R{_, +s} = r
  s

# ---------------------------------------------------------------- root carry-over
#
# A side root of 32 zero bytes means "unchanged": the block's final root is taken from the
# tree's last leaf (the end root of the rightmost bag). If the block did add notes to that
# pool, the carried root is wrong and the header check fails, so this never weakens a MATCH.
def is_zero32(xs: +List<U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+a, t}:
      Bool.and(U32.is_eq(a, 0), is_zero32(t))

def end_root(+k: U32, n: ND) -> +List<U32>:
  ND{_, _, _, _, _, _, _, _, +esr, _, _, _, _, _, +eor, _, _, +eir, _} = n
  sel_l(U32.is_eq(k, 0), esr, sel_l(U32.is_eq(k, 1), eor, eir))

def last_root(+k: U32, ps: +List<E>) -> +List<U32>:
  match ps:
    case Nil{}:
      zeros(32n)
    case Con{e, _}:
      end_root(k, e_bag(e))

def st_ps(s: St) -> +List<E>:
  St{_, _, _, +ps} = s
  ps

def carry(+s: St, +k: U32, +r: +List<U32>) -> +List<U32>:
  sel_l(is_zero32(r), last_root(k, st_ps(s)), r)
