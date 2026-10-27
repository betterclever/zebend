# Checks the Bend Sinsemilla / MerkleCRH against the oracle's vectors.
import Base
import ../../halo2/lib/words.bend as Wd
import ../consts.bend as C
import ../sinsemilla.bend as S

def cmp_list(+g: S.Gens, xs: +List<C.CrhVec>, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{v, t}:
      C.CrhVec{level, left, right, out} = v
      cmp_list(g, t, Nat.add(acc, S.b2n(Wd.is_eq(S.crh(g, level, left, right), out))))

def cmp_ws(xs: +List<Wd.W>, ys: +List<Wd.W>, acc: Nat) -> Nat:
  match xs ys:
    case Con{a, s} Con{b, t}:
      cmp_ws(s, t, Nat.add(acc, S.b2n(Wd.is_eq(a, b))))
    case _ _:
      acc

def main() -> IO(Unit):
  +g = S.gens()
  do IO<Unit>:
    IO.print("S generators on curve: " ++ Nat.show(S.count_on_curve(C.s_list(), 0n)) ++ " / 1024")
    IO.print("Q on curve: " ++ Nat.show(S.b2n(S.on_curve(S.aff_of(C.q())))))
    IO.print("empty roots matching oracle: " ++ Nat.show(cmp_ws(S.empties(g), C.empty_roots_oracle(), 0n)) ++ " / 33")
    IO.print("MerkleCRH vectors matching oracle: " ++ Nat.show(cmp_list(g, C.crh_vectors(), 0n)) ++ " / 16")
