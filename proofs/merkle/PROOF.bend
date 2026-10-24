import Base
import ./merkle.bend as M
import ./lemmas.bend as L
import ./LAWS.bend as Laws

def fst2(-A: Data, -B: Data, +x: Sigma<&2, &2, A, _ => B>) -> A:
  (a, b) = x
  a

def snd2(-A: Data, -B: Data, +x: Sigma<&2, &2, A, _ => B>) -> B:
  (a, b) = x
  b

# Pushing the leaves of a perfect subtree of height k onto levels that are empty
# below k carries exactly that subtree's root into level k.
law carry:
  for +k: Nat
  for +t: M.Tr
  for +pf: M.Perf(k, t)
  for -rest: List<&2, Maybe<&2, M.HT>>
  {M.push_all(M.tleaves(t), List.append(&2, Maybe<&2, M.HT>, M.nones(k), rest)) == List.append(&2, Maybe<&2, M.HT>, M.nones(k), M.push(rest, k, M.troot(k, t))) : List<&2, Maybe<&2, M.HT>>}

def carry(k, t, pf, rest):
  match k t:
    case 0n M.TL{x}:
      {==}
    case 0n M.TN{a, b}:
      match pf:
    case 1n+j M.TL{x}:
      match pf:
    case 1n+j M.TN{a, b}:
      +pa = fst2(M.Perf(j, a), M.Perf(j, b), pf)
      +pb = snd2(M.Perf(j, a), M.Perf(j, b), pf)
      %L.push_all_append(M.tleaves(a), M.tleaves(b), List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), rest)) : {_ == List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), M.push(rest, 1n+j, M.Hn{j, M.troot(j, a), M.troot(j, b)})) : List<&2, Maybe<&2, M.HT>>}
      %L.nones_shift(j, rest) : {M.push_all(M.tleaves(b), M.push_all(M.tleaves(a), _)) == List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), M.push(rest, 1n+j, M.Hn{j, M.troot(j, a), M.troot(j, b)})) : List<&2, Maybe<&2, M.HT>>}
      %Equal.sym(List<&2, Maybe<&2, M.HT>>, M.push_all(M.tleaves(a), List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> rest)), List.append(&2, Maybe<&2, M.HT>, M.nones(j), M.push(None{} <> rest, j, M.troot(j, a))), carry(j, a, pa, None{} <> rest)) : {M.push_all(M.tleaves(b), _) == List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), M.push(rest, 1n+j, M.Hn{j, M.troot(j, a), M.troot(j, b)})) : List<&2, Maybe<&2, M.HT>>}
      %Equal.sym(List<&2, Maybe<&2, M.HT>>, M.push_all(M.tleaves(b), List.append(&2, Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, a)} <> rest)), List.append(&2, Maybe<&2, M.HT>, M.nones(j), M.push(Some{M.troot(j, a)} <> rest, j, M.troot(j, b))), carry(j, b, pb, Some{M.troot(j, a)} <> rest)) : {_ == List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), M.push(rest, 1n+j, M.Hn{j, M.troot(j, a), M.troot(j, b)})) : List<&2, Maybe<&2, M.HT>>}
      L.nones_shift(j, M.push(rest, 1n+j, M.Hn{j, M.troot(j, a), M.troot(j, b)}))

# A well-formed, not-full partial tree of height k leaves fr(p, k) on levels 0..k-1
# and carries nothing above them.
law shape:
  for +k: Nat
  for +p: M.PT
  for +w: M.WF(p, k)
  for +nf: M.NotB(M.IsFull(p))
  for -rest: List<&2, Maybe<&2, M.HT>>
  {M.push_all(M.pleaves(p), List.append(&2, Maybe<&2, M.HT>, M.nones(k), rest)) == List.append(&2, Maybe<&2, M.HT>, M.fr(p, k), rest) : List<&2, Maybe<&2, M.HT>>}

def shape(k, p, w, nf, rest):
  match k p:
    case _ M.PE{}:
      {==}
    case _ M.PF{t}:
      match nf:
    case 0n M.PLo{q}:
      match w:
    case 0n M.PB{t, q}:
      match w:
    case 1n+j M.PLo{q}:
      match q:
        case M.PE{}:
          Empty.absurd({M.push_all(Nil{}, List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), rest)) == List.append(&2, Maybe<&2, M.HT>, M.fr(M.PLo{M.PE{}}, 1n+j), rest) : List<&2, Maybe<&2, M.HT>>}, snd2(M.WF(M.PE{}, j), M.NotB(M.IsEmpty(M.PE{})), w))
        case M.PF{t}:
          +pt = fst2(M.WF(M.PF{t}, j), M.NotB(M.IsEmpty(M.PF{t})), w)
          %L.nones_shift(j, rest) : {M.push_all(M.tleaves(t), _) == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, t)} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
          %L.snoc(Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, t)}, rest) : {M.push_all(M.tleaves(t), List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> rest)) == _ : List<&2, Maybe<&2, M.HT>>}
          carry(j, t, pt, None{} <> rest)
        case M.PLo{q2}:
          +wq = fst2(M.WF(M.PLo{q2}, j), M.NotB(M.IsEmpty(M.PLo{q2})), w)
          %L.nones_shift(j, rest) : {M.push_all(M.pleaves(q2), _) == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.fr(M.PLo{q2}, j), None{} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
          %L.snoc(Maybe<&2, M.HT>, M.fr(M.PLo{q2}, j), None{}, rest) : {M.push_all(M.pleaves(q2), List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> rest)) == _ : List<&2, Maybe<&2, M.HT>>}
          shape(j, M.PLo{q2}, wq, Unit{}, None{} <> rest)
        case M.PB{t2, q2}:
          +wq = fst2(M.WF(M.PB{t2, q2}, j), M.NotB(M.IsEmpty(M.PB{t2, q2})), w)
          %L.nones_shift(j, rest) : {M.push_all(M.pleaves(M.PB{t2, q2}), _) == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.fr(M.PB{t2, q2}, j), None{} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
          %L.snoc(Maybe<&2, M.HT>, M.fr(M.PB{t2, q2}, j), None{}, rest) : {M.push_all(M.pleaves(M.PB{t2, q2}), List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> rest)) == _ : List<&2, Maybe<&2, M.HT>>}
          shape(j, M.PB{t2, q2}, wq, Unit{}, None{} <> rest)
    case 1n+j M.PB{t, q}:
      +pt = fst2(M.Perf(j, t), Sigma<&2, &2, M.WF(q, j), _ => M.NotB(M.IsFull(q))>, w)
      +wr = snd2(M.Perf(j, t), Sigma<&2, &2, M.WF(q, j), _ => M.NotB(M.IsFull(q))>, w)
      +wq = fst2(M.WF(q, j), M.NotB(M.IsFull(q)), wr)
      +nq = snd2(M.WF(q, j), M.NotB(M.IsFull(q)), wr)
      %L.push_all_append(M.tleaves(t), M.pleaves(q), List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), rest)) : {_ == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
      %L.nones_shift(j, rest) : {M.push_all(M.pleaves(q), M.push_all(M.tleaves(t), _)) == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
      %Equal.sym(List<&2, Maybe<&2, M.HT>>, M.push_all(M.tleaves(t), List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> rest)), List.append(&2, Maybe<&2, M.HT>, M.nones(j), M.push(None{} <> rest, j, M.troot(j, t))), carry(j, t, pt, None{} <> rest)) : {M.push_all(M.pleaves(q), _) == List.append(&2, Maybe<&2, M.HT>, List.append(&2, Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)} <> Nil{}), rest) : List<&2, Maybe<&2, M.HT>>}
      %L.snoc(Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)}, rest) : {M.push_all(M.pleaves(q), List.append(&2, Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, t)} <> rest)) == _ : List<&2, Maybe<&2, M.HT>>}
      shape(j, q, wq, nq, Some{M.troot(j, t)} <> rest)

# Folding froot over that frontier reaches level k carrying the subtree's root
# (or nothing, for the empty tree).
law fold:
  for +k: Nat
  for +p: M.PT
  for +w: M.WF(p, k)
  for +nf: M.NotB(M.IsFull(p))
  for -rest: List<&2, Maybe<&2, M.HT>>
  {M.froot(List.append(&2, Maybe<&2, M.HT>, M.fr(p, k), rest), 0n, None{}) == M.froot(rest, k, M.pacc(k, p)) : M.HT}

def fold(k, p, w, nf, rest):
  match k p:
    case 0n M.PE{}:
      {==}
    case 1n+j M.PE{}:
      %L.add_zero(1n+j) : {M.froot(List.append(&2, Maybe<&2, M.HT>, M.nones(1n+j), rest), 0n, None{}) == M.froot(rest, _, None{}) : M.HT}
      L.froot_nones(1n+j, 0n, rest)
    case _ M.PF{t}:
      match nf:
    case 0n M.PLo{q}:
      match w:
    case 0n M.PB{t, q}:
      match w:
    case 1n+j M.PLo{q}:
      match q:
        case M.PE{}:
          Empty.absurd({M.froot(List.append(&2, Maybe<&2, M.HT>, M.fr(M.PLo{M.PE{}}, 1n+j), rest), 0n, None{}) == M.froot(rest, 1n+j, M.pacc(1n+j, M.PLo{M.PE{}})) : M.HT}, snd2(M.WF(M.PE{}, j), M.NotB(M.IsEmpty(M.PE{})), w))
        case M.PF{t}:
          %L.snoc(Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, t)}, rest) : {M.froot(_, 0n, None{}) == M.froot(rest, 1n+j, Some{M.Hn{j, M.troot(j, t), M.Em{j}}}) : M.HT}
          %L.add_zero(j) : {M.froot(List.append(&2, Maybe<&2, M.HT>, M.nones(j), Some{M.troot(j, t)} <> rest), 0n, None{}) == M.froot(rest, 1n+_, Some{M.Hn{_, M.troot(j, t), M.Em{_}}}) : M.HT}
          L.froot_nones(j, 0n, Some{M.troot(j, t)} <> rest)
        case M.PLo{q2}:
          +wq = fst2(M.WF(M.PLo{q2}, j), M.NotB(M.IsEmpty(M.PLo{q2})), w)
          %L.snoc(Maybe<&2, M.HT>, M.fr(M.PLo{q2}, j), None{}, rest) : {M.froot(_, 0n, None{}) == M.froot(rest, 1n+j, Some{M.Hn{j, M.proot(M.PLo{q2}, j), M.Em{j}}}) : M.HT}
          fold(j, M.PLo{q2}, wq, Unit{}, None{} <> rest)
        case M.PB{t2, q2}:
          +wq = fst2(M.WF(M.PB{t2, q2}, j), M.NotB(M.IsEmpty(M.PB{t2, q2})), w)
          %L.snoc(Maybe<&2, M.HT>, M.fr(M.PB{t2, q2}, j), None{}, rest) : {M.froot(_, 0n, None{}) == M.froot(rest, 1n+j, Some{M.Hn{j, M.proot(M.PB{t2, q2}, j), M.Em{j}}}) : M.HT}
          fold(j, M.PB{t2, q2}, wq, Unit{}, None{} <> rest)
    case 1n+j M.PB{t, q}:
      +wr = snd2(M.Perf(j, t), Sigma<&2, &2, M.WF(q, j), _ => M.NotB(M.IsFull(q))>, w)
      +wq = fst2(M.WF(q, j), M.NotB(M.IsFull(q)), wr)
      +nq = snd2(M.WF(q, j), M.NotB(M.IsFull(q)), wr)
      %L.snoc(Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)}, rest) : {M.froot(_, 0n, None{}) == M.froot(rest, 1n+j, Some{M.Hn{j, M.troot(j, t), M.proot(q, j)}}) : M.HT}
      %L.acc_default(j, q) : {M.froot(List.append(&2, Maybe<&2, M.HT>, M.fr(q, j), Some{M.troot(j, t)} <> rest), 0n, None{}) == M.froot(rest, 1n+j, Some{M.Hn{j, M.troot(j, t), _}}) : M.HT}
      fold(j, q, wq, nq, Some{M.troot(j, t)} <> rest)

def Laws.frontier_root(D, p, w, nf):
  %L.append_nil(Maybe<&2, M.HT>, M.nones(D)) : {M.froot(M.push_all(M.pleaves(p), _), 0n, None{}) == M.proot(p, D) : M.HT}
  %Equal.sym(List<&2, Maybe<&2, M.HT>>, M.push_all(M.pleaves(p), List.append(&2, Maybe<&2, M.HT>, M.nones(D), Nil{})), List.append(&2, Maybe<&2, M.HT>, M.fr(p, D), Nil{}), shape(D, p, w, nf, Nil{})) : {M.froot(_, 0n, None{}) == M.proot(p, D) : M.HT}
  %L.acc_default(D, p) : {M.froot(List.append(&2, Maybe<&2, M.HT>, M.fr(p, D), Nil{}), 0n, None{}) == _ : M.HT}
  fold(D, p, w, nf, Nil{})

def Laws.path_sound(k, t, pf, ds):
  match k t:
    case 0n M.TL{x}:
      {==}
    case 0n M.TN{a, b}:
      match pf:
    case 1n+j M.TL{x}:
      match pf:
    case 1n+j M.TN{l, r}:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              %Laws.path_sound(j, l, fst2(M.Perf(j, l), M.Perf(j, r), pf), dr) : {M.recompute(1n+j, M.leaf_at(j, l, dr), WCon{False{}, dr}, M.troot(j, r) <> M.auth(j, l, dr)) == M.Hn{j, _, M.troot(j, r)} : M.HT}
              {==}
            case True{}:
              %Laws.path_sound(j, r, snd2(M.Perf(j, l), M.Perf(j, r), pf), dr) : {M.recompute(1n+j, M.leaf_at(j, r, dr), WCon{True{}, dr}, M.troot(j, l) <> M.auth(j, r, dr)) == M.Hn{j, M.troot(j, l), _} : M.HT}
              {==}

law em_not_hn:
  for -k: Nat
  for -h: M.HT
  for e: {M.Em{k} == h : M.HT}
  for ih: M.IsHn(h)
  Empty

def em_not_hn(k, h, e, ih):
  %Equal.sym(M.HT, M.Em{k}, h, e) : M.IsHn(_)
  ih

def Laws.path_binding(k, t, pf, ds, x, ss, e):
  match k t:
    case 0n M.TL{y}:
      e
    case 0n M.TN{a, b}:
      match pf:
    case 1n+j M.TL{y}:
      match pf:
    case 1n+j M.TN{l, r}:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              match ss:
                case Con{s, sr}:
                  Laws.path_binding(j, l, fst2(M.Perf(j, l), M.Perf(j, r), pf), dr, x, sr, Equal.cong(M.HT, M.HT, M.hn_l, M.Hn{j, M.recompute(j, x, dr, sr), s}, M.Hn{j, M.troot(j, l), M.troot(j, r)}, e))
                case Nil{}:
                  Empty.absurd({x == M.leaf_at(j, l, dr) : M.HT}, em_not_hn(0n, M.Hn{j, M.troot(j, l), M.troot(j, r)}, e, Unit{}))
            case True{}:
              match ss:
                case Con{s, sr}:
                  Laws.path_binding(j, r, snd2(M.Perf(j, l), M.Perf(j, r), pf), dr, x, sr, Equal.cong(M.HT, M.HT, M.hn_r, M.Hn{j, s, M.recompute(j, x, dr, sr)}, M.Hn{j, M.troot(j, l), M.troot(j, r)}, e))
                case Nil{}:
                  Empty.absurd({x == M.leaf_at(j, r, dr) : M.HT}, em_not_hn(0n, M.Hn{j, M.troot(j, l), M.troot(j, r)}, e, Unit{}))
