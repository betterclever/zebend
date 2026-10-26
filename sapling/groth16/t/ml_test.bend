# ml_test <vk_spend> <vk_output> <vk_sprout> <set.bin> <n>: for the first n records prints
# the oracle `dump` values: acc (IC0 + sum input_i IC_i), the 3-term Miller loop and its final
# exponentiation (records whose proof decodes). t/ml_test.py diffs them with the bls12_381 crate.
import Base
import ../fq.bend as F
import ../fq12.bend as T
import ../g1.bend as G1
import ../g2.bend as G2
import ../pairing.bend as PR
import ../groth16.bend as V
import ../io.bend as IO2
import ./show.bend as Sh

def rlen(+kind: U32) -> Nat:
  match kind:
    case 0:
      106n
    case 1:
      90n
    case _:
      122n

def pick(+kind: U32, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> V.PVK:
  match kind:
    case 0:
      vs
    case 1:
      vo
    case _:
      vj

def b2u(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def show_dec(d: V.Dec, +ins: +List<U32>, +v: V.PVK) -> IO(Unit):
  V.Dec{+ok, +a, +b, +c} = d
  +accp = V.msm(V.pvk_tabs(v), ins)
  +acc = G1.to_aff(accp)
  +ml = PR.miller(V.pvk_gs(v), V.pvk_ds(v), PR.mk_ps(b, a, acc, c, 1, (1 - b2u(G1.is_identity(accp)) : U32), 1))
  do IO<Unit>:
    IO.print("acc " ++ Sh.g1a(acc))
    IO.print("ml " ++ Sh.fq12(ml))
    IO.print("fe " ++ Sh.fq12(PR.final_exp(ml)))

def go(fuel: Nat, +ws: +List<U32>, +vs: V.PVK, +vo: V.PVK, +vj: V.PVK) -> IO(Unit):
  match fuel ws:
    case 1n+k Con{+kind, _}:
      +r = List.drop(&2, U32, ws, 2n)
      do IO<Unit>:
        show_dec(V.decode(List.take(&2, U32, r, 48n)), List.drop(&2, U32, r, 48n), pick(kind, vs, vo, vj))
        go(k, List.drop(&2, U32, ws, rlen(kind)), vs, vo, vj)
    case _ _:
      IO.pure(Unit, Unit{})

def pnat(s: String, +acc: Nat) -> Nat:
  match s:
    case SCon{+c, t}:
      pnat(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((Char.to_u32(c) - 48 : U32))))
    case SNil{}:
      acc

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{sp, Con{op, Con{jp, Con{p, Con{n, _}}}}}}:
      do IO<Unit>:
        sb : List<&2, U32> <- IO2.read_all(sp)
        ob : List<&2, U32> <- IO2.read_all(op)
        jb : List<&2, U32> <- IO2.read_all(jp)
        bs : List<&2, U32> <- IO2.read_all(p)
        go(pnat(n, 0n), IO2.pack4(bs), V.prepare_vk(IO2.pack4(sb)), V.prepare_vk(IO2.pack4(ob)), V.prepare_vk(IO2.pack4(jb)))
    case _:
      IO.print("usage: ml_test <vk_spend> <vk_output> <vk_sprout> <set.bin> <n>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
