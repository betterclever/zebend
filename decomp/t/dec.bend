# Decompression: decomp (table sqrt) vs field3, on 2^16 random encodings per curve (half with
# a non-canonical x range), plus decompress_ct agreement; then 1e4 decompression attempts
# (x = 7 + i, sign = i & 1, as rust/ bench) timed for both. One thread for the timings.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../field3/fp64.bend as Fp
import ../../field3/fq64.bend as Fq
import ../../field3/lib64/pallas.bend as P
import ../../field3/lib64/vesta.bend as V
import ../pallas_dec.bend as PD
import ../vesta_dec.bend as VD

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

# Random encodings: the low 255 bits uniform below 2^254 (or 2^255 when s is odd: x >= p is
# then common), sign bit from s.
def rw(+s: U32) -> Wd.W:
  +s1 = xs(s)
  +s2 = xs(s1)
  +s3 = xs(s2)
  +s4 = xs(s3)
  +s5 = xs(s4)
  +s6 = xs(s5)
  +s7 = xs(s6)
  +s8 = xs(s7)
  +top = (s8 .&. (1073741823 + ((s .&. 1 : U32) << 30n)) : U32)
  Wd.W{s1, s2, s3, s4, s5, s6, s7, (top .|. ((s .&. 2 : U32) << 30n) : U32)}

def next8(+s: U32) -> U32:
  xs(xs(xs(xs(xs(xs(xs(xs(s))))))))

type D is Data:
  D{bad: U32, ok: U32}

def dadd(a: D, b: D) -> D:
  D{+x, +y} = a
  D{+u, +v} = b
  D{(x + u : U32), (y + v : U32)}

def p_same(+a: P.Pt, +b: P.Pt) -> Bool:
  P.Pt{+ax, +ay, +az} = a
  P.Pt{+bx, +by, +bz} = b
  Bool.and(Fp.is_eq(ax, bx), Bool.and(Fp.is_eq(ay, by), Fp.is_eq(az, bz)))

def v_same(+a: V.Pt, +b: V.Pt) -> Bool:
  V.Pt{+ax, +ay, +az} = a
  V.Pt{+bx, +by, +bz} = b
  Bool.and(Fq.is_eq(ax, bx), Bool.and(Fq.is_eq(ay, by), Fq.is_eq(az, bz)))

# 0 if new == old and the fixed-work form agrees.
def p_both(+a: P.Pt, +b: P.Pt, c: PD.Dec) -> D:
  PD.Dec{+cok, +cp} = c
  D{Bool.to_u32(Bool.not(Bool.and(p_same(a, b), Bool.and(U32.is_eq(cok, 1), p_same(a, cp))))), 1}

def p_none(c: PD.Dec) -> D:
  PD.Dec{+cok, _} = c
  D{Bool.to_u32(Bool.not(U32.is_eq(cok, 0))), 0}

def p_cmp(m: Maybe<&2, P.Pt>, o: Maybe<&2, P.Pt>, c: PD.Dec) -> D:
  match m o:
    case Some{+a} Some{+b}:
      p_both(a, b, c)
    case None{} None{}:
      p_none(c)
    case _ _:
      D{1, 0}

def v_both(+a: V.Pt, +b: V.Pt, c: VD.Dec) -> D:
  VD.Dec{+cok, +cp} = c
  D{Bool.to_u32(Bool.not(Bool.and(v_same(a, b), Bool.and(U32.is_eq(cok, 1), v_same(a, cp))))), 1}

def v_none(c: VD.Dec) -> D:
  VD.Dec{+cok, _} = c
  D{Bool.to_u32(Bool.not(U32.is_eq(cok, 0))), 0}

def v_cmp(m: Maybe<&2, V.Pt>, o: Maybe<&2, V.Pt>, c: VD.Dec) -> D:
  match m o:
    case Some{+a} Some{+b}:
      v_both(a, b, c)
    case None{} None{}:
      v_none(c)
    case _ _:
      D{1, 0}

def one(+w: Wd.W) -> D:
  dadd(p_cmp(PD.decompress(w), P.decompress(w), PD.decompress_ct(w)), v_cmp(VD.decompress(w), V.decompress(w), VD.decompress_ct(w)))

# Edge encodings: x = 0 with either sign, x = p - 1, x = p, p + 1, 2^255 - 1 (non-canonical).
def edges(+i: U32) -> Wd.W:
  match i:
    case 0:
      Wd.W{0, 0, 0, 0, 0, 0, 0, 0}
    case 1:
      Wd.W{0, 0, 0, 0, 0, 0, 0, 2147483648}
    case 2:
      Wd.W{0, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 3:
      Wd.W{1, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 4:
      Wd.W{2, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 5:
      Wd.W{0, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}
    case 6:
      Wd.W{1, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}
    case 7:
      Wd.W{4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 2147483647}
    case _:
      Wd.W{5, 0, 0, 0, 0, 0, 0, 2147483648}

def edge_run(n: Nat, +i: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      edge_run(k, (i + 1 : U32), dadd(a, one(edges(i))))

def run(n: Nat, +s: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      run(k, next8(s), dadd(a, one(rw(s))))

def par(+d: Nat, +seed: U32, +n: Nat) -> D:
  match d:
    case 0n:
      run(n, (seed * 2654435761 + 99 : U32), D{0, 0})
    case 1n+p:
      a b = par(p, (seed * 2 : U32), n) par(p, (seed * 2 + 1 : U32), n)
      dadd(a, b)

def enc(+i: U32) -> Wd.W:
  Wd.W{(7 + i : U32), 0, 0, 0, 0, 0, 0, ((i .&. 1 : U32) << 31n : U32)}

def some_p(m: Maybe<&2, P.Pt>) -> U32:
  match m:
    case Some{_}:
      1
    case None{}:
      0

def some_v(m: Maybe<&2, V.Pt>) -> U32:
  match m:
    case Some{_}:
      1
    case None{}:
      0

def b_vo(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      b_vo(k, (i + 1 : U32), (acc + some_v(V.decompress(enc(i))) : U32))

def b_vn(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      b_vn(k, (i + 1 : U32), (acc + some_v(VD.decompress(enc(i))) : U32))

def b_po(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      b_po(k, (i + 1 : U32), (acc + some_p(P.decompress(enc(i))) : U32))

def b_pn(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      b_pn(k, (i + 1 : U32), (acc + some_p(PD.decompress(enc(i))) : U32))

def dok(c: VD.Dec) -> U32:
  VD.Dec{ok, _} = c
  ok

def b_vc(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      b_vc(k, (i + 1 : U32), (acc + dok(VD.decompress_ct(enc(i))) : U32))

def show(+tag: String, a: D) -> String:
  D{+b, +o} = a
  tag ++ ": mismatches " ++ U32.show(b) ++ ", valid " ++ U32.show(o)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show("edges (9 per curve)", edge_run(9n, 0, D{0, 0})))
    IO.print(show("random 2^16 per curve", par(6n, 5, 1024n)))
    t0 : Nat <- IO.now()
    +a : U32 = b_vo(10000n, 0, 0)
    t1 : Nat <- IO.now()
    IO.print("Vesta field3 decompress 1e4: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms, valid " ++ U32.show(a))
    t2 : Nat <- IO.now()
    +b : U32 = b_vn(10000n, 0, 0)
    t3 : Nat <- IO.now()
    IO.print("Vesta decomp decompress 1e4: " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms, valid " ++ U32.show(b))
    t4 : Nat <- IO.now()
    +c : U32 = b_po(10000n, 0, 0)
    t5 : Nat <- IO.now()
    IO.print("Pallas field3 decompress 1e4: " ++ Nat.show(Nat.sub(t5, t4)) ++ " ms, valid " ++ U32.show(c))
    t6 : Nat <- IO.now()
    +d : U32 = b_pn(10000n, 0, 0)
    t7 : Nat <- IO.now()
    IO.print("Pallas decomp decompress 1e4: " ++ Nat.show(Nat.sub(t7, t6)) ++ " ms, valid " ++ U32.show(d))
    t8 : Nat <- IO.now()
    +e : U32 = b_vc(10000n, 0, 0)
    t9 : Nat <- IO.now()
    IO.print("Vesta decompress_ct 1e4: " ++ Nat.show(Nat.sub(t9, t8)) ++ " ms, valid " ++ U32.show(e))
