# Usage: fz <mode> <chunk> <count>
#   chunk: <count> records of u32 LE length || bytes (a slice of an oracle .cases file).
#   mode: cs | hdr | frame | tx | block | bundle   the hardened parsers in lib/
#         cs_old | frame_old                 zcash/p2p's current readers, for comparison
# Prints one verdict line per record in the oracle's .expect format.
import Base
import ../../zcash/p2p/bytes.bend as B
import ../../zcash/p2p/msg.bend as M
import ./lib/hb.bend as H
import ./lib/cs.bend as CS
import ./lib/frame.bend as F
import ./lib/txv.bend as T
import ./lib/blk.bend as K
import ./lib/bundle.bend as BU

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def flag(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def v_cs(+n: U32, m: Maybe<&2, H.V>) -> String:
  match m:
    case None{}:
      "0"
    case Some{r}:
      H.V{+v, +s} = r
      "1 " ++ U32.show(v) ++ " " ++ U32.show((n - H.rem(s) : U32))

def v_cs_old(c: B.Compact) -> String:
  B.Compact{+v, +w} = c
  "1 " ++ U32.show(v) ++ " " ++ U32.show(w)

def cmd_name(+c: +List<U32>) -> String:
  match c:
    case Nil{}:
      "-"
    case Con{_, _}:
      B.to_string(c)

def v_frame(f: F.Frame) -> String:
  match f:
    case F.FBad{}:
      "0"
    case F.FMore{}:
      "2"
    case F.FGot{c, +len, _}:
      "1 " ++ cmd_name(c) ++ " " ++ U32.show(len)

def clean_c(ok: Bool, +c: Char) -> Char:
  match ok:
    case True{}:
      c
    case False{}:
      '?'

# Non-printable characters (the old parser accepts them) shown as '?' to keep one line per case.
def clean(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      SCon{clean_c(U32.is_le(32, Char.to_u32(c)) && U32.is_le(Char.to_u32(c), 126), c), clean(t)}

def old_name(+s: String) -> String:
  match s:
    case SNil{}:
      "-"
    case SCon{_, _}:
      clean(s)

def v_frame_old(p: M.Parsed) -> String:
  match p:
    case M.NeedMore{_}:
      "2"
    case M.Bad{_}:
      "0"
    case M.Got{m, _}:
      M.Msg{c, +pl} = m
      "1 " ++ old_name(c) ++ " " ++ U32.show(B.length(pl))

def v_block(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}:
      "0"
    case Some{n}:
      "1 " ++ U32.show(n)

type Mode is Data:
  MCs{}
  MCsOld{}
  MHdr{}
  MFrame{}
  MFrameOld{}
  MTx{}
  MBlock{}
  MBundle{}
  MNone{}

def v_bundle(ok: Bool, +xs: +List<U32>) -> String:
  match ok:
    case True{}:
      "1 " ++ U32.show(BU.np_of(xs))
    case False{}:
      "0"

def verdict(md: Mode, +xs: +List<U32>) -> String:
  match md:
    case MCs{}:
      v_cs(H.length(xs), CS.read(H.start(xs)))
    case MCsOld{}:
      v_cs_old(B.read_compact(xs))
    case MHdr{}:
      flag(K.header_ok(xs))
    case MFrame{}:
      v_frame(F.parse(xs))
    case MFrameOld{}:
      v_frame_old(M.parse(xs))
    case MTx{}:
      flag(T.valid(xs))
    case MBlock{}:
      v_block(K.parse_capped(xs))
    case MBundle{}:
      v_bundle(BU.valid(xs), xs)
    case MNone{}:
      "?"

def run(n: Nat, +md: Mode, +xs: +List<U32>) -> String:
  match n:
    case 0n:
      ""
    case 1n+m:
      +len = H.le32(xs)
      +rest = H.drop(xs, 4)
      verdict(md, H.take(rest, len)) ++ "\n" ++ run(m, md, H.drop(rest, len))

type Args is Type:
  Args{mode: String, path: String, count: String}

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{m, Con{p, Con{c, _}}}}:
      Args{m, p, c}
    case _:
      Args{"", "", "0"}

def count_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      0
    case Some{n}:
      n

def pick(b: Bool, +m: Mode, +rest: Mode) -> Mode:
  match b:
    case True{}:
      m
    case False{}:
      rest

def mode_sel(+s: String) -> Mode:
  pick(String.eq(s, "cs"), MCs{}, pick(String.eq(s, "cs_old"), MCsOld{},
  pick(String.eq(s, "hdr"), MHdr{}, pick(String.eq(s, "frame"), MFrame{},
  pick(String.eq(s, "frame_old"), MFrameOld{}, pick(String.eq(s, "tx"), MTx{},
  pick(String.eq(s, "block"), MBlock{}, pick(String.eq(s, "bundle"), MBundle{}, MNone{}))))))))

def go(a: Args) -> IO(Unit):
  Args{md, p, c} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 8000000)
    IO.print(run(U32.to_nat(count_of(U32.read(c))), mode_sel(md), bytes_of(r)))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args_of(args))
