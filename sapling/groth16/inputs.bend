# Sapling public inputs from a description's raw fields, as sapling-crypto computes them
# (check_spend / check_output) after zcash_primitives parsed the fields:
#   spend:  cv (not small order), anchor (canonical Fr), nf, rk (a Jubjub point, not small
#           order) -> [rk.u, rk.v, cv.u, cv.v, anchor, nf bits 0..253, nf bits 254..255]
#   output: cv (not small order), cmu (canonical Fr), epk (a Jubjub point, not small order)
#           -> [cv.u, cv.v, epk.u, epk.v, cmu]
# Jubjub decoding (ZIP 216), affine coordinates and the small-order test come from
# ../jubjub (the Sapling workstream's tested Jubjub; imported read-only).
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as R
import ../jubjub/consts.bend as K
import ../jubjub/jubjub.bend as J

# ok = 0: the fields are rejected (parsing or a consensus check before the proof).
type In is Data:
  In{ok: U32, ws: +List<U32>}

def wl(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  [a, b, c, d, e, f, g, h]

def aff_ws(a: K.Aff) -> +List<U32>:
  K.Aff{u, v} = a
  List.append(&2, U32, wl(R.to_words(u)), wl(R.to_words(v)))

def pt_ws(p: J.Pt) -> +List<U32>:
  aff_ws(J.to_aff(p))

def canon(+w: Wd.W) -> Bool:
  Wd.is_lt(w, R.modulus())

def not_small(+p: J.Pt) -> Bool:
  Bool.not(J.is_small_order(p))

# multipack: nf bits 0..253 and 254..255 as two field elements (Fr::CAPACITY = 254)
def nf_lo(w: Wd.W) -> Wd.W:
  Wd.W{a, b, c, d, e, f, g, h} = w
  Wd.W{a, b, c, d, e, f, g, (h .&. 1073741823 : U32)}

def nf_hi(w: Wd.W) -> Wd.W:
  Wd.W{_, _, _, _, _, _, _, h} = w
  Wd.W{(h >> 30n : U32), 0, 0, 0, 0, 0, 0, 0}

def rejected() -> In:
  In{0, Nil{}}

def sp_fin(ok: Bool, +rk: J.Pt, +cv: J.Pt, +anchor: Wd.W, +nf: Wd.W) -> In:
  match ok:
    case True{}:
      In{1, List.append(&2, U32, pt_ws(rk), List.append(&2, U32, pt_ws(cv), List.append(&2, U32, wl(anchor), List.append(&2, U32, wl(nf_lo(nf)), wl(nf_hi(nf))))))}
    case False{}:
      rejected()

def sp_pts(rk: Maybe<&2, J.Pt>, cv: Maybe<&2, J.Pt>, +anchor: Wd.W, +nf: Wd.W) -> In:
  match rk cv:
    case Some{+r} Some{+c}:
      sp_fin(Bool.and(Bool.and(not_small(r), not_small(c)), canon(anchor)), r, c, anchor, nf)
    case _ _:
      rejected()

def spend(+cv: Wd.W, +anchor: Wd.W, +nf: Wd.W, +rk: Wd.W) -> In:
  sp_pts(J.decompress(rk), J.decompress(cv), anchor, nf)

def out_fin(ok: Bool, +cv: J.Pt, +epk: J.Pt, +cmu: Wd.W) -> In:
  match ok:
    case True{}:
      In{1, List.append(&2, U32, pt_ws(cv), List.append(&2, U32, pt_ws(epk), wl(cmu)))}
    case False{}:
      rejected()

def out_pts(cv: Maybe<&2, J.Pt>, epk: Maybe<&2, J.Pt>, +cmu: Wd.W) -> In:
  match cv epk:
    case Some{+c} Some{+e}:
      out_fin(Bool.and(Bool.and(not_small(c), not_small(e)), canon(cmu)), c, e, cmu)
    case _ _:
      rejected()

def output(+cv: Wd.W, +cmu: Wd.W, +epk: Wd.W) -> In:
  out_pts(J.decompress(cv), J.decompress(epk), cmu)
