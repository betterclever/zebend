# Vector runner for the Jubjub layer: reads N fixed-size records of 32-byte values from a
# binary file and prints one result line per record (compared by t/vectors.py with the
# Rust oracle's expected values).
#   vec_main fr  FILE N   records (a, b) in Fr: "a+b a-b a*b a^2 inv(a) sqrt(a)|none"
#   vec_main fs  FILE N   records (lo, hi): Fs.from_wide(lo || hi) (64-byte LE reduction)
#   vec_main dec FILE N   records (e): decompress -> re-encoding, or "none"
#   vec_main add FILE N   records (P, Q): "P+Q 2P [8]P small_order(P)"
#   vec_main mul FILE N   records (P, k): "[k]P"
#   vec_main mh  FILE N   records (level, l, r): MerkleCRH^Sapling(level, l, r) (Pedersen hash)
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as F
import ../jubjub/fs.bend as S
import ../jubjub/jubjub.bend as J
import ../jubjub/fr_sqrt.bend as FQ
import ../tree/pedersen.bend as PH

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

def words_go(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_go(rest, w4(a, b, c, d) <> acc)
    case _:
      List.reverse(&2, U32, acc)

def ws_go(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_go(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      List.reverse(&2, Wd.W, acc)

def sq_str(m: Maybe<&2, F.Fr>) -> String:
  match m:
    case Some{r}:
      Wd.hex(F.to_words(r))
    case None{}:
      "none"

def fr_line(+a: F.Fr, +b: F.Fr) -> String:
  +sq = sq_str(FQ.sqrt(a))
  Wd.hex(F.to_words(F.add(a, b))) ++ " " ++ Wd.hex(F.to_words(F.sub(a, b))) ++ " " ++ Wd.hex(F.to_words(F.mul(a, b))) ++ " " ++ Wd.hex(F.to_words(F.sqr(a))) ++ " " ++ Wd.hex(F.to_words(F.inv(a))) ++ " " ++ sq

def b01(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def dec_line(m: Maybe<&2, J.Pt>) -> String:
  match m:
    case Some{p}:
      Wd.hex(J.encode(p))
    case None{}:
      "none"

def add_line(m: Maybe<&2, J.Pt>, n: Maybe<&2, J.Pt>) -> String:
  match m n:
    case Some{+p} Some{q}:
      Wd.hex(J.encode(J.add(p, q))) ++ " " ++ Wd.hex(J.encode(J.double(p))) ++ " " ++ Wd.hex(J.encode(J.mul_by_cofactor(p))) ++ " " ++ b01(J.is_small_order(p))
    case _ _:
      "none"

def mul_line(m: Maybe<&2, J.Pt>, +k: Wd.W) -> String:
  match m:
    case Some{p}:
      Wd.hex(J.encode(J.scalar_mul(p, k)))
    case None{}:
      "none"

def lv(w: Wd.W) -> U32:
  Wd.W{a, _, _, _, _, _, _, _} = w
  a

type SR is Data:
  SR{s: String, r: +List<Wd.W>}

# One record's line, given the op; returns the rest of the values.
def fsa_line(+a: S.Fs, +b: S.Fs) -> String:
  Wd.hex(S.to_words(S.add(a, b))) ++ " " ++ Wd.hex(S.to_words(S.mul(a, b))) ++ " " ++ Wd.hex(S.to_words(S.neg(a))) ++ " " ++ Wd.hex(S.to_words(S.inv(a)))

def one7b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, Con{c, rest}}:
      SR{fsa_line(S.from_words(a), S.from_words(c)), rest}
    case _ _:
      SR{"?", Nil{}}

def one7(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one7b(String.eq(op, "fsa"), op, xs, g)

def one6b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{l, Con{a, Con{b, rest}}}:
      SR{Wd.hex(PH.merkle(g, lv(l), a, b)), rest}
    case _ _:
      one7(op, xs, g)

def one6(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one6b(String.eq(op, "mh"), op, xs, g)

def one5b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, Con{k, rest}}:
      SR{mul_line(J.decompress(a), k), rest}
    case _ _:
      one6(op, xs, g)

def one5(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one5b(String.eq(op, "mul"), op, xs, g)

def one4b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, Con{b, rest}}:
      SR{add_line(J.decompress(a), J.decompress(b)), rest}
    case _ _:
      one5(op, xs, g)

def one4(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one4b(String.eq(op, "add"), op, xs, g)

def one3b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, rest}:
      SR{dec_line(J.decompress(a)), rest}
    case _ _:
      one4(op, xs, g)

def one3(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one3b(String.eq(op, "dec"), op, xs, g)

def one2b(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, Con{b, rest}}:
      SR{Wd.hex(S.to_words(S.from_wide(a, b))), rest}
    case _ _:
      one3(op, xs, g)

def one2(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one2b(String.eq(op, "fs"), op, xs, g)

def one1(b: Bool, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  match b xs:
    case True{} Con{a, Con{b, rest}}:
      SR{fr_line(F.from_words(a), F.from_words(b)), rest}
    case _ _:
      one2(op, xs, g)

def one(+op: String, xs: +List<Wd.W>, +g: PH.Tab) -> SR:
  one1(String.eq(op, "fr"), op, xs, g)

def sr_s(sr: SR) -> String:
  SR{s, _} = sr
  s

def sr_r(sr: SR) -> +List<Wd.W>:
  SR{_, r} = sr
  r

def run(n: Nat, +op: String, xs: +List<Wd.W>, +g: PH.Tab) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      +sr = one(op, xs, g)
      do IO<Unit>:
        IO.print(sr_s(sr))
        run(k, op, sr_r(sr), g)

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def rec_size_dec(d: Bool, +n: Nat) -> Nat:
  match d:
    case True{}:
      32n
    case False{}:
      n

def rec_size(+op: String) -> Nat:
  Nat.add(Nat.add(64n, Nat.mul(32n, b2n(String.eq(op, "mh")))), Nat.mul(0n, 0n))

def got(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> +List<Wd.W>:
  (_, res) = r
  match res:
    case Done{bs}:
      ws_go(words_go(bs, Nil{}), Nil{})
    case Fail{_}:
      Nil{}

def num(s: String) -> Nat:
  U32.to_nat(Maybe.default(&2, U32, U32.read(s), 0))

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{op, Con{path, Con{n, _}}}}:
      +k = num(n)
      +o = op
      do IO<Unit>:
        fl : File <- IO.try(File, File.open(path, "r"))
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, 0, U32.from_nat(Nat.mul(k, rec_size_dec(String.eq(o, "dec"), rec_size(o)))))
        run(k, o, got(r), PH.tab())
    case _:
      IO.print("usage: vec_main fr|fs|dec|add|mul|mh FILE N")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
