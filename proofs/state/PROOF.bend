# Proofs of LAWS.bend.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../node/state/sinsemilla.bend as S
import ../merkle/merkle.bend as M
import ./refine.bend as R
import ./LAWS.bend as L
import ../merkle/LAWS.bend as ML
import ../merkle/PROOF.bend as MP

def succ(n: Nat) -> Nat:
  1n+n

def add0(n: Nat) -> {Nat.add(n, 0n) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, succ, Nat.add(p, 0n), p, add0(p))

def add_succ(a: Nat, +b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, succ, Nat.add(p, 1n+b), 1n+Nat.add(p, b), add_succ(p, b))

# ---- closures for congruence --------------------------------------------------------

def none_c(rest: +List<Maybe<&2, Wd.W>>) -> +List<Maybe<&2, Wd.W>>:
  None{} <> rest

def spa_c(+ws: +List<Wd.W>, +g: S.Gens, f: +List<Maybe<&2, Wd.W>>) -> +List<Maybe<&2, Wd.W>>:
  R.spush_all(ws, f, g)

def some_crh_c(+g: S.Gens, +l: Nat, +a: Wd.W, z: Wd.W) -> Maybe<&2, Wd.W>:
  Some{S.crh(g, U32.from_nat(l), a, z)}

def froot_c(+g: S.Gens, +es: +List<Wd.W>, +lv: +List<Maybe<&2, Wd.W>>, +l: Nat, a: Maybe<&2, Wd.W>) -> Wd.W:
  S.froot(lv, l, a, g, es)

def fr0_c(+g: S.Gens, +es: +List<Wd.W>, lv: +List<Maybe<&2, Wd.W>>) -> Wd.W:
  S.froot(lv, 0n, None{}, g, es)

def nth_c(+es: +List<Wd.W>, n: Nat) -> Wd.W:
  S.nth(es, n)

def interp_c(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, t: M.HT) -> Wd.W:
  R.interp(g, es, ls, t)

def crh_l(+g: S.Gens, +j: Nat, +s: Wd.W, a: Wd.W) -> Wd.W:
  S.crh(g, U32.from_nat(j), a, s)

def crh_r(+g: S.Gens, +j: Nat, +s: Wd.W, a: Wd.W) -> Wd.W:
  S.crh(g, U32.from_nat(j), s, a)

# ---- push ---------------------------------------------------------------------------

def push_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, lv: +List<Maybe<&2, M.HT>>, +l: Nat, +c: M.HT) -> {S.push(R.imap(g, es, ls, lv), l, R.interp(g, es, ls, c), g) == R.imap(g, es, ls, M.push(lv, l, c)) : +List<Maybe<&2, Wd.W>>}:
  match lv:
    case Nil{}:
      {==}
    case Con{+m, +rest}:
      match m:
        case None{}:
          {==}
        case Some{+left}:
          Equal.cong(+List<Maybe<&2, Wd.W>>, +List<Maybe<&2, Wd.W>>, none_c,
            S.push(R.imap(g, es, ls, rest), 1n+l, R.interp(g, es, ls, M.Hn{l, left, c}), g),
            R.imap(g, es, ls, M.push(rest, 1n+l, M.Hn{l, left, c})),
            push_ref(g, es, ls, rest, 1n+l, M.Hn{l, left, c}))

def push_all_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, xs: +List<M.HT>, +lv: +List<Maybe<&2, M.HT>>) -> {R.spush_all(R.imapl(g, es, ls, xs), R.imap(g, es, ls, lv), g) == R.imap(g, es, ls, M.push_all(xs, lv)) : +List<Maybe<&2, Wd.W>>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      Equal.trans(+List<Maybe<&2, Wd.W>>,
        R.spush_all(R.imapl(g, es, ls, rest), S.push(R.imap(g, es, ls, lv), 0n, R.interp(g, es, ls, x), g), g),
        R.spush_all(R.imapl(g, es, ls, rest), R.imap(g, es, ls, M.push(lv, 0n, x)), g),
        R.imap(g, es, ls, M.push_all(rest, M.push(lv, 0n, x))),
        Equal.cong(+List<Maybe<&2, Wd.W>>, +List<Maybe<&2, Wd.W>>, spa_c(R.imapl(g, es, ls, rest), g),
          S.push(R.imap(g, es, ls, lv), 0n, R.interp(g, es, ls, x), g), R.imap(g, es, ls, M.push(lv, 0n, x)),
          push_ref(g, es, ls, lv, 0n, x)),
        push_all_ref(g, es, ls, rest, M.push(lv, 0n, x)))

# ---- lengths --------------------------------------------------------------------------

def lenpush(lv: +List<Maybe<&2, M.HT>>, +l: Nat, +c: M.HT) -> {List.length(&2, Maybe<&2, M.HT>, M.push(lv, l, c)) == List.length(&2, Maybe<&2, M.HT>, lv) : Nat}:
  match lv:
    case Nil{}:
      {==}
    case Con{+m, +rest}:
      match m:
        case None{}:
          {==}
        case Some{+left}:
          Equal.cong(Nat, Nat, succ, List.length(&2, Maybe<&2, M.HT>, M.push(rest, 1n+l, M.Hn{l, left, c})), List.length(&2, Maybe<&2, M.HT>, rest), lenpush(rest, 1n+l, M.Hn{l, left, c}))

def lenpushall(xs: +List<M.HT>, +lv: +List<Maybe<&2, M.HT>>) -> {List.length(&2, Maybe<&2, M.HT>, M.push_all(xs, lv)) == List.length(&2, Maybe<&2, M.HT>, lv) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +rest}:
      Equal.trans(Nat, List.length(&2, Maybe<&2, M.HT>, M.push_all(rest, M.push(lv, 0n, x))), List.length(&2, Maybe<&2, M.HT>, M.push(lv, 0n, x)), List.length(&2, Maybe<&2, M.HT>, lv),
        lenpushall(rest, M.push(lv, 0n, x)), lenpush(lv, 0n, x))

# ---- fstep / froot ------------------------------------------------------------------------

def dflt(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, acc: Maybe<&2, M.HT>, +l: Nat) -> {Maybe.default(&2, Wd.W, R.imaybe(g, es, ls, acc), S.nth(es, l)) == R.interp(g, es, ls, Maybe.default(&2, M.HT, acc, M.Em{l})) : Wd.W}:
  match acc:
    case Some{_}:
      {==}
    case None{}:
      {==}

def fright_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, acc: Maybe<&2, M.HT>, +l: Nat) -> {S.fright(R.imaybe(g, es, ls, acc), l, g, es) == R.imaybe(g, es, ls, M.fright(acc, l)) : Maybe<&2, Wd.W>}:
  match acc:
    case Some{_}:
      {==}
    case None{}:
      {==}

def fstep_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, m: Maybe<&2, M.HT>, +acc: Maybe<&2, M.HT>, +l: Nat) -> {S.fstep(R.imaybe(g, es, ls, m), R.imaybe(g, es, ls, acc), l, g, es) == R.imaybe(g, es, ls, M.fstep(m, acc, l)) : Maybe<&2, Wd.W>}:
  match m:
    case Some{+left}:
      Equal.cong(Wd.W, Maybe<&2, Wd.W>, some_crh_c(g, l, R.interp(g, es, ls, left)),
        Maybe.default(&2, Wd.W, R.imaybe(g, es, ls, acc), S.nth(es, l)),
        R.interp(g, es, ls, Maybe.default(&2, M.HT, acc, M.Em{l})),
        dflt(g, es, ls, acc, l))
    case None{}:
      fright_ref(g, es, ls, acc, l)

def fr_nil(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, +l: Nat, acc: Maybe<&2, M.HT>, h: {Nat.add(l, 0n) == 32n : Nat}) -> {S.froot(Nil{}, l, R.imaybe(g, es, ls, acc), g, es) == R.interp(g, es, ls, M.froot(Nil{}, l, acc)) : Wd.W}:
  match acc:
    case Some{_}:
      {==}
    case None{}:
      +eq_l = Equal.trans(Nat, l, Nat.add(l, 0n), 32n, Equal.sym(Nat, Nat.add(l, 0n), l, add0(l)), h)
      Equal.cong(Nat, Wd.W, nth_c(es), 32n, l, Equal.sym(Nat, l, 32n, eq_l))

def froot_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, lv: +List<Maybe<&2, M.HT>>, +l: Nat, +acc: Maybe<&2, M.HT>) -> {Nat.add(l, List.length(&2, Maybe<&2, M.HT>, lv)) == 32n : Nat} -> {S.froot(R.imap(g, es, ls, lv), l, R.imaybe(g, es, ls, acc), g, es) == R.interp(g, es, ls, M.froot(lv, l, acc)) : Wd.W}:
  match lv:
    case Nil{}:
      h => fr_nil(g, es, ls, l, acc, h)
    case Con{+m, +rest}:
      h =>
        +n = List.length(&2, Maybe<&2, M.HT>, rest)
        +h2 = Equal.trans(Nat, 1n+Nat.add(l, n), Nat.add(l, 1n+n), 32n, Equal.sym(Nat, Nat.add(l, 1n+n), 1n+Nat.add(l, n), add_succ(l, n)), h)
        Equal.trans(Wd.W,
          S.froot(R.imap(g, es, ls, rest), 1n+l, S.fstep(R.imaybe(g, es, ls, m), R.imaybe(g, es, ls, acc), l, g, es), g, es),
          S.froot(R.imap(g, es, ls, rest), 1n+l, R.imaybe(g, es, ls, M.fstep(m, acc, l)), g, es),
          R.interp(g, es, ls, M.froot(rest, 1n+l, M.fstep(m, acc, l))),
          Equal.cong(Maybe<&2, Wd.W>, Wd.W, froot_c(g, es, R.imap(g, es, ls, rest), 1n+l),
            S.fstep(R.imaybe(g, es, ls, m), R.imaybe(g, es, ls, acc), l, g, es), R.imaybe(g, es, ls, M.fstep(m, acc, l)),
            fstep_ref(g, es, ls, m, acc, l)),
          froot_ref(g, es, ls, rest, 1n+l, M.fstep(m, acc, l), h2))

# ---- paths ------------------------------------------------------------------------------------

def path_ref(+g: S.Gens, +es: +List<Wd.W>, +ls: +List<Wd.W>, +k: Nat, +x: M.HT, ds: Word(k), ss: +List<M.HT>) -> {R.srecompute(g, es, k, R.interp(g, es, ls, x), ds, R.imapl(g, es, ls, ss)) == R.interp(g, es, ls, M.recompute(k, x, ds, ss)) : Wd.W}:
  match k:
    case 0n:
      {==}
    case 1n+j:
      match ds:
        case WCon{d, +dr}:
          match d:
            case False{}:
              match ss:
                case Con{+s, +sr}:
                  Equal.cong(Wd.W, Wd.W, crh_l(g, j, R.interp(g, es, ls, s)),
                    R.srecompute(g, es, j, R.interp(g, es, ls, x), dr, R.imapl(g, es, ls, sr)),
                    R.interp(g, es, ls, M.recompute(j, x, dr, sr)),
                    path_ref(g, es, ls, j, x, dr, sr))
                case Nil{}:
                  {==}
            case True{}:
              match ss:
                case Con{+s, +sr}:
                  Equal.cong(Wd.W, Wd.W, crh_r(g, j, R.interp(g, es, ls, s)),
                    R.srecompute(g, es, j, R.interp(g, es, ls, x), dr, R.imapl(g, es, ls, sr)),
                    R.interp(g, es, ls, M.recompute(j, x, dr, sr)),
                    path_ref(g, es, ls, j, x, dr, sr))
                case Nil{}:
                  {==}

# ---- the laws ------------------------------------------------------------------------------------

def L.push_refines(g, es, ls, lv, l, c):
  push_ref(g, es, ls, lv, l, c)

def L.froot_refines(g, es, ls, lv, l, acc, h):
  froot_ref(g, es, ls, lv, l, acc, h)

def L.frontier_root_running(g, es, ls, p, w, nf):
  +xs : +List<M.HT> = M.pleaves(p)
  +lv0 : +List<Maybe<&2, M.HT>> = M.nones(32n)
  Equal.trans(Wd.W,
    S.froot(R.spush_all(R.imapl(g, es, ls, xs), R.imap(g, es, ls, lv0), g), 0n, None{}, g, es),
    S.froot(R.imap(g, es, ls, M.push_all(xs, lv0)), 0n, None{}, g, es),
    R.interp(g, es, ls, M.proot(p, 32n)),
    Equal.cong(+List<Maybe<&2, Wd.W>>, Wd.W, fr0_c(g, es), R.spush_all(R.imapl(g, es, ls, xs), R.imap(g, es, ls, lv0), g), R.imap(g, es, ls, M.push_all(xs, lv0)), push_all_ref(g, es, ls, xs, lv0)),
    Equal.trans(Wd.W,
      S.froot(R.imap(g, es, ls, M.push_all(xs, lv0)), 0n, None{}, g, es),
      R.interp(g, es, ls, M.froot(M.push_all(xs, lv0), 0n, None{})),
      R.interp(g, es, ls, M.proot(p, 32n)),
      froot_ref(g, es, ls, M.push_all(xs, lv0), 0n, None{}, lenpushall(xs, lv0)),
      Equal.cong(M.HT, Wd.W, interp_c(g, es, ls), M.froot(M.push_all(xs, lv0), 0n, None{}), M.proot(p, 32n), ML.frontier_root(32n, p, w, nf))))

def L.path_refines(g, es, ls, k, x, ds, ss):
  path_ref(g, es, ls, k, x, ds, ss)

def L.path_sound_running(g, es, ls, k, t, pf, ds):
  Equal.trans(Wd.W,
    R.srecompute(g, es, k, R.interp(g, es, ls, M.leaf_at(k, t, ds)), ds, R.imapl(g, es, ls, M.auth(k, t, ds))),
    R.interp(g, es, ls, M.recompute(k, M.leaf_at(k, t, ds), ds, M.auth(k, t, ds))),
    R.interp(g, es, ls, M.troot(k, t)),
    path_ref(g, es, ls, k, M.leaf_at(k, t, ds), ds, M.auth(k, t, ds)),
    Equal.cong(M.HT, Wd.W, interp_c(g, es, ls), M.recompute(k, M.leaf_at(k, t, ds), ds, M.auth(k, t, ds)), M.troot(k, t), ML.path_sound(k, t, pf, ds)))
