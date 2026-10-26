# Test driver: secp_t FILE. The file's first byte selects the mode:
#   1: field records a(32) b(32)  -> "mul sqr add sub neg inv sqrtcand" (hex, big-endian)
#   2: scalar records a(32) b(32) -> "inv(a) a*b" mod n (hex)
#   3: ECDSA records pklen(1) pk r(32) s(32) msg(32) -> "v <0|1> d <x||y hex | none>"
import Base
import ../../util.bend as U
import ../fe.bend as F
import ../sc.bend as S
import ../gtab.bend as G
import ../ec.bend as E

def fe_line(+a: F.Fe, +b: F.Fe) -> String:
  U.hex(F.to_be(F.mul(a, b))) ++ " " ++ U.hex(F.to_be(F.sqr(a))) ++ " " ++ U.hex(F.to_be(F.add(a, b))) ++ " "
    ++ U.hex(F.to_be(E.sub(a, b))) ++ " " ++ U.hex(F.to_be(E.neg(a))) ++ " " ++ U.hex(F.to_be(E.inv(a))) ++ " "
    ++ U.hex(F.to_be(E.sqrt_cand(a))) ++ "\n"

def sc_from_mont(+a: S.Sc) -> S.Sc:
  S.mul(a, S.Sc{1, 0, 0, 0, 0, 0, 0, 0})

def sc_line(+a: S.Sc, +b: S.Sc) -> String:
  +am = S.mul(a, S.r2())
  +bm = S.mul(b, S.r2())
  U.hex(S.to_be(sc_from_mont(E.sc_inv_mont(am)))) ++ " " ++ U.hex(S.to_be(sc_from_mont(S.mul(am, bm)))) ++ "\n"

def dec_str(m: Maybe<&2, G.Af>) -> String:
  match m:
    case Some{p}:
      G.Af{x, y} = p
      U.hex(F.to_be(x)) ++ U.hex(F.to_be(y))
    case None{}:
      "none"

def ver_m(m: Maybe<&2, G.Af>, +r: S.Sc, +s: S.Sc, +msg: +List<U32>) -> String:
  match m:
    case Some{q}:
      Bool.pick(String, E.verify(q, r, s, msg), "1", "0")
    case None{}:
      "0"

# r, s >= n parse as 0, as in libsecp256k1's DER parser
def ovf0(+x: S.Sc) -> S.Sc:
  Bool.pick(S.Sc, S.is_lt_n(x), x, S.zero())

def ec_line(+pk: +List<U32>, +rest: +List<U32>) -> String:
  +r = ovf0(S.from_be(U.at(rest, 0n, 32n)))
  +s = ovf0(S.from_be(U.at(rest, 32n, 32n)))
  "v " ++ ver_m(E.decode(pk), r, s, U.at(rest, 64n, 32n)) ++ " d " ++ dec_str(E.decode(pk)) ++ "\n"

type Step is Data:
  Step{line: String, rest: +List<U32>}

def one_ec(+xs: +List<U32>) -> Step:
  +n = U32.to_nat(U.head0(xs))
  +body = U.drop(xs, 1n)
  Step{ec_line(U.take(body, n), U.drop(body, n)), U.drop(body, (n + 96n : Nat))}

def one_23(is2: Bool, +xs: +List<U32>) -> Step:
  match is2:
    case True{}:
      Step{sc_line(S.from_be(xs), S.from_be(U.drop(xs, 32n))), U.drop(xs, 64n)}
    case False{}:
      one_ec(xs)

def one(is1: Bool, +mode: U32, +xs: +List<U32>) -> Step:
  match is1:
    case True{}:
      Step{fe_line(F.from_be(xs), F.from_be(U.drop(xs, 32n))), U.drop(xs, 64n)}
    case False{}:
      one_23(U32.is_eq(mode, 2), xs)

def st_line(s: Step) -> String:
  Step{l, _} = s
  l

def st_rest(s: Step) -> +List<U32>:
  Step{_, r} = s
  r

def go(fuel: Nat, +mode: U32, +xs: +List<U32>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+p:
      +st = one(U32.is_eq(mode, 1), mode, xs)
      +rest = st_rest(st)
      st_line(st) ++ Bool.pick(String, U.is_empty(rest), "", go(p, mode, rest))

def path1(xs: List<String>) -> String:
  match xs:
    case Con{_, Con{a, _}}:
      a
    case _:
      ""

def run(+bs: +List<U32>) -> String:
  match bs:
    case Con{mode, rest}:
      go(U32.to_nat((U.len(rest) / 64 : U32)), mode, rest)
    case Nil{}:
      "empty\n"

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(path1(args), "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 50000000)
    IO.print(run(U.bytes_of(r)))
