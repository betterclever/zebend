# Interpreting proofs/merkle's free symbolic trees with node/state's REAL hash:
#   Hn{k, a, b}  ->  S.crh(g, k, a, b)        (Sinsemilla MerkleCRH, node/state/sinsemilla.bend)
#   Em{k}        ->  S.nth(es, k)             (node/state's table of empty roots)
#   Lf{i}        ->  i-th leaf word
# LAWS.bend shows node/state's own frontier functions (S.push, S.fstep, S.froot), the
# code that matched mainnet, commute with this interpretation, so proofs/merkle's
# theorems transfer to the running code.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../node/state/sinsemilla.bend as S
import ../merkle/merkle.bend as M

def interp(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, t: M.HT) -> Wd.W:
  match t:
    case M.Lf{x}:
      S.nth(ls, x)
    case M.Em{k}:
      S.nth(es, k)
    case M.Hn{k, a, b}:
      S.crh(g, U32.from_nat(k), interp(g, es, ls, a), interp(g, es, ls, b))

def imaybe(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, m: Maybe<&2, M.HT>) -> Maybe<&2, Wd.W>:
  match m:
    case Some{t}:
      Some{interp(g, es, ls, t)}
    case None{}:
      None{}

def imap(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, lv: +List<Maybe<&2, M.HT>>) -> +List<Maybe<&2, Wd.W>>:
  match lv:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      imaybe(g, es, ls, m) <> imap(g, es, ls, rest)

def imapl(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, xs: +List<M.HT>) -> +List<Wd.W>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, rest}:
      interp(g, es, ls, x) <> imapl(g, es, ls, rest)

# Appending words one at a time with node/state's S.push (what tree_main's frontier
# mode does between checkpoints).
def spush_all(ws: +List<Wd.W>, f: +List<Maybe<&2, Wd.W>>, +g: S.Gens) -> +List<Maybe<&2, Wd.W>>:
  match ws:
    case Nil{}:
      f
    case Con{w, rest}:
      spush_all(rest, S.push(f, 0n, w, g), g)

# Recomputing a root from a leaf and its authentication path with the real hash
# (mirrors M.recompute; Em{0n} fallbacks map to S.nth(es, 0n)).
def srecompute(+g: S.Gens, +es: +List<Wd.W>, +k: Nat, x: Wd.W, ds: Word(k), ss: +List<Wd.W>) -> Wd.W:
  match k:
    case 0n:
      x
    case 1n+j:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              match ss:
                case Con{s, sr}:
                  S.crh(g, U32.from_nat(j), srecompute(g, es, j, x, dr, sr), s)
                case Nil{}:
                  S.nth(es, 0n)
            case True{}:
              match ss:
                case Con{s, sr}:
                  S.crh(g, U32.from_nat(j), s, srecompute(g, es, j, x, dr, sr))
                case Nil{}:
                  S.nth(es, 0n)
