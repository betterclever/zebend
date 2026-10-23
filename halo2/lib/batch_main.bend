# Batch MSM check / benchmark: ./batch_main <batch_K.bin> <c> <cdepth>
# Reads K halo2-shaped final-MSM instances (written by perf/: `batchvec K`), merges
# them in parallel, evaluates one fixed-base MSM over G plus one Pippenger MSM, and
# compares with the expected point from halo2's best_multiexp.
import Base
import ./words.bend as Wd
import ./fp.bend as S
import ./vesta.bend as V
import ./fixed.bend as FX
import ./batch.bend as BT

def words(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}:
      words(rest, (b0 .|. (b1 << 8n) .|. (b2 << 16n) .|. (b3 << 24n) : U32) <> acc)
    case _:
      acc

def rev(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Con{h, t}:
      rev(t, h <> acc)
    case Nil{}:
      acc

type WR is Data:
  WR{w: Wd.W, rest: +List<U32>}

def w8(ws: +List<U32>) -> WR:
  match ws:
    case Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, rest}}}}}}}}:
      WR{Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}, rest}
    case _:
      WR{Wd.zero(), Nil{}}

def wr_w(r: WR) -> Wd.W:
  WR{w, _} = r
  w

def wr_rest(r: WR) -> +List<U32>:
  WR{_, rest} = r
  rest

def pt_of(+w: Wd.W) -> V.Pt:
  Maybe.default(&2, V.Pt, V.decompress(w), V.identity())

type PR is Data:
  PR{ps: +List<V.Pt>, rest: +List<U32>}

def pts_cons(p: V.Pt, r: PR) -> PR:
  PR{ps, rest} = r
  PR{p <> ps, rest}

def pts(n: Nat, ws: +List<U32>) -> PR:
  match n ws:
    case 1n+k Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, rest}}}}}}}}:
      pts_cons(pt_of(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}), pts(k, rest))
    case _ _:
      PR{Nil{}, ws}

type SR is Data:
  SR{ss: +List<S.Fp>, rest: +List<U32>}

def scs_cons(s: S.Fp, r: SR) -> SR:
  SR{ss, rest} = r
  SR{s <> ss, rest}

def scs(n: Nat, ws: +List<U32>) -> SR:
  match n ws:
    case 1n+k Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, rest}}}}}}}}:
      scs_cons(S.from_words(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}), scs(k, rest))
    case _ _:
      SR{Nil{}, ws}

# Per-proof terms: n x (point, scalar).
type VR is Data:
  VR{ps: +List<V.Pt>, ss: +List<S.Fp>, rest: +List<U32>}

def vt_cons(p: V.Pt, s: S.Fp, r: VR) -> VR:
  VR{ps, ss, rest} = r
  VR{p <> ps, s <> ss, rest}

def vts(n: Nat, ws: +List<U32>) -> VR:
  match n ws:
    case 1n+k Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, Con{b0, Con{b1, Con{b2, Con{b3, Con{b4, Con{b5, Con{b6, Con{b7, rest}}}}}}}}}}}}}}}}:
      vt_cons(pt_of(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}), S.from_words(Wd.W{b0, b1, b2, b3, b4, b5, b6, b7}), vts(k, rest))
    case _ _:
      VR{Nil{}, Nil{}, ws}

# One instance parsed from `start`, plus what follows it.
type I1 is Data:
  I1{i: BT.Inst, start: +List<U32>, rest: +List<U32>}

def inst_v(+r: S.Fp, g: +List<S.Fp>, f: +List<S.Fp>, +start: +List<U32>, v: VR) -> I1:
  VR{vp, vs, rest} = v
  I1{BT.Inst{r, g, f, vp, vs}, start, rest}

def inst_f(+r: S.Fp, g: +List<S.Fp>, +nv: Nat, +start: +List<U32>, f: SR) -> I1:
  SR{fs, rest} = f
  inst_v(r, g, fs, start, vts(nv, rest))

def inst_g(+r: S.Fp, +nf: Nat, +nv: Nat, +start: +List<U32>, g: SR) -> I1:
  SR{gs, rest} = g
  inst_f(r, gs, nv, start, scs(nf, rest))

def one_inst(+ng: Nat, +nf: Nat, +nv: Nat, +ws: +List<U32>) -> I1:
  match ws:
    case Con{a0, Con{a1, Con{a2, Con{a3, Con{a4, Con{a5, Con{a6, Con{a7, rest}}}}}}}}:
      inst_g(S.from_words(Wd.W{a0, a1, a2, a3, a4, a5, a6, a7}), nf, nv, ws, scs(ng, rest))
    case _:
      I1{BT.Inst{S.zero(), Nil{}, Nil{}, Nil{}, Nil{}}, ws, Nil{}}

type IR is Data:
  IR{xs: +List<BT.Inst>, rest: +List<U32>}

# Parses n instances; `cur` is the next instance, already parsed (one look-ahead).
def insts(n: Nat, +ng: Nat, +nf: Nat, +nv: Nat, cur: I1, acc: +List<BT.Inst>) -> IR:
  match n cur:
    case 1n+k I1{i, _, rest}:
      insts(k, ng, nf, nv, one_inst(ng, nf, nv, rest), i <> acc)
    case _ I1{_, start, _}:
      IR{acc, start}

def rev_i(xs: +List<BT.Inst>, acc: +List<BT.Inst>) -> +List<BT.Inst>:
  match xs:
    case Con{h, t}:
      rev_i(t, h <> acc)
    case Nil{}:
      acc

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

type Args is Type:
  Args{path: String, c: U32, depth: U32}

def parse_args(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{c, Con{d, _}}}}:
      Args{p, num(c), num(d)}
    case _:
      Args{"", 0, 0}

def verdict(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

type Hdr is Data:
  Hdr{k: U32, ng: U32, nf: U32, nv: U32}

def hdr(ws: +List<U32>) -> Hdr:
  match ws:
    case Con{k, Con{ng, Con{nf, Con{nv, _}}}}:
      Hdr{k, ng, nf, nv}
    case _:
      Hdr{0, 0, 0, 0}

def skip4(ws: +List<U32>) -> +List<U32>:
  match ws:
    case Con{_, Con{_, Con{_, Con{_, rest}}}}:
      rest
    case _:
      Nil{}

def take_pts(k: Nat, xs: +List<V.Pt>) -> +List<V.Pt>:
  match k xs:
    case 1n+j Con{h, t}:
      h <> take_pts(j, t)
    case _ _:
      Nil{}

def drop_pts(k: Nat, xs: +List<V.Pt>) -> +List<V.Pt>:
  match k xs:
    case 1n+j Con{_, t}:
      drop_pts(j, t)
    case _ _:
      xs

def pr_ps(r: PR) -> +List<V.Pt>:
  PR{ps, _} = r
  ps

def pr_rest(r: PR) -> +List<U32>:
  PR{_, rest} = r
  rest

def ir_xs(r: IR) -> +List<BT.Inst>:
  IR{xs, _} = r
  xs

def ir_rest(r: IR) -> +List<U32>:
  IR{_, rest} = r
  rest

def n4(h: Hdr) -> U32:
  Hdr{k, _, _, _} = h
  k

def g4(h: Hdr) -> U32:
  Hdr{_, g, _, _} = h
  g

def f4(h: Hdr) -> U32:
  Hdr{_, _, f, _} = h
  f

def v4(h: Hdr) -> U32:
  Hdr{_, _, _, v} = h
  v

def run(+c: U32, +cd: Nat, +tb: FX.FT, +ng: U32, +fb: +List<V.Pt>, +k: U32, +xs: +List<BT.Inst>) -> V.Pt:
  BT.eval(c, tb, ng, fb, BT.merge(9n, BT.itree(9n, U32.is_lt(k, 2), k, xs)))

def go(a: Args) -> IO(Unit):
  Args{path, +c, +depth} = a
  +cd = U32.to_nat(depth)
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 4294967295)
    t0 : Nat <- IO.now()
    +ws : +List<U32> = rev(words(bytes_of(r), Nil{}), Nil{})
    +h : Hdr = hdr(ws)
    +k : U32 = n4(h)
    +ng : U32 = g4(h)
    +nf : U32 = f4(h)
    +nv : U32 = v4(h)
    +bp : PR = pts(U32.to_nat((ng + nf : U32)), skip4(ws))
    +gb : +List<V.Pt> = take_pts(U32.to_nat(ng), pr_ps(bp))
    +fb : +List<V.Pt> = drop_pts(U32.to_nat(ng), pr_ps(bp))
    +ngn : Nat = U32.to_nat(ng)
    +nfn : Nat = U32.to_nat(nf)
    +nvn : Nat = U32.to_nat(nv)
    +ir : IR = insts(U32.to_nat(k), ngn, nfn, nvn, one_inst(ngn, nfn, nvn, pr_rest(bp)), Nil{})
    +xs : +List<BT.Inst> = rev_i(ir_xs(ir), Nil{})
    +want : Wd.W = wr_w(w8(ir_rest(ir)))
    t1 : Nat <- IO.now()
    +tb : FX.FT = FX.table(c, cd, ng, gb)
    t2 : Nat <- IO.now()
    +got1 : Wd.W = V.encode(run(c, cd, tb, ng, fb, k, xs))
    t3 : Nat <- IO.now()
    +got2 : Wd.W = V.encode(run(c, cd, tb, ng, fb, k, xs))
    t4 : Nat <- IO.now()
    +tp : Nat = t1
    +tt : Nat = t2
    +t3b : Nat = t3
    IO.print("batch K " ++ U32.show(k) ++ " terms " ++ U32.show((k * (ng + nf + nv) : U32)) ++ " parse_ms " ++ Nat.show(Nat.sub(tp, t0)) ++ " table_ms " ++ Nat.show(Nat.sub(tt, tp)) ++ " first_ms " ++ Nat.show(Nat.sub(t3b, tt)) ++ " warm_ms " ++ Nat.show(Nat.sub(t4, t3b)))
    IO.print("got  " ++ Wd.hex(got2) ++ " " ++ verdict(Bool.and(Wd.is_eq(got1, want), Wd.is_eq(got2, want))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(parse_args(args))
