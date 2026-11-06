import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../ring/expr.bend as X
import ./model.bend as M
import ./lemmas.bend as G
import ./LAWS.bend as Laws
import ./certs/m15.bend as C_m15
import ./certs/negsq.bend as C_negsq
import ./certs/add_chord_x.bend as C_add_chord_x
import ./certs/add_chord_y.bend as C_add_chord_y
import ./certs/add_chord_z.bend as C_add_chord_z
import ./certs/aff_chord_x.bend as C_aff_chord_x
import ./certs/aff_chord_y.bend as C_aff_chord_y
import ./certs/chord_on.bend as C_chord_on
import ./certs/add_tan_x.bend as C_add_tan_x
import ./certs/add_tan_y.bend as C_add_tan_y
import ./certs/add_tan_z.bend as C_add_tan_z
import ./certs/add_neg_x.bend as C_add_neg_x
import ./certs/add_neg_z.bend as C_add_neg_z
import ./certs/add_neg_y.bend as C_add_neg_y
import ./certs/dbl_tan_x.bend as C_dbl_tan_x
import ./certs/dbl_tan_y.bend as C_dbl_tan_y
import ./certs/dbl_tan_z.bend as C_dbl_tan_z
import ./certs/tan_on.bend as C_tan_on
import ./certs/add_idl_x.bend as C_add_idl_x
import ./certs/add_idl_y.bend as C_add_idl_y
import ./certs/add_idl_z.bend as C_add_idl_z
import ./certs/add_idr_x.bend as C_add_idr_x
import ./certs/add_idr_y.bend as C_add_idr_y
import ./certs/add_idr_z.bend as C_add_idr_z
import ./certs/dbl_id_x.bend as C_dbl_id_x
import ./certs/dbl_id_y.bend as C_dbl_id_y
import ./certs/dbl_id_z.bend as C_dbl_id_z
import ./certs/aff_eq_x.bend as C_aff_eq_x
import ./certs/aff_eq_y.bend as C_aff_eq_y
import ./certs/aff_eq_z.bend as C_aff_eq_z
import ./certs/dbl_on.bend as C_dbl_on

# Each law: rewrite the projective inputs to (Z x, Z y, Z) (G.rep), then the generated
# identity lem_<name> (certs/<name>.bend, proven by ring/cert.bend's cert_ok2).

# --- chord -----------------------------------------------------------------------------

def Laws.add_chord_x(bp, l1, b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di, hc, r1, r2, on1, on2, hd):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx1, (ly1, (lX2, (lY2, (lZ2, (lzi2, (lx2, (ly2, (ldi, _)))))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.px(M.addb(bp, M.b3(bp, b), p, q)) == T.fmul(bp, M.chord_x(bp, x1, y1, x2, y2, di), M.pz(M.addb(bp, M.b3(bp, b), p, q))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x1), T.fmul(bp, Z1, y1), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x2), T.fmul(bp, Z2, y2), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x1, y1, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x2, y2, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_chord_x.lem_add_chord_x(bp, l1, b, x1, y1, x2, y2, Z1, Z2, di, zi1, zi2, lb, lx1, ly1, lx2, ly2, lZ1, lZ2, ldi, lzi1, lzi2, on1, on2, hd))

def Laws.add_chord_y(bp, l1, b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di, hc, r1, r2, on1, on2, hd):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx1, (ly1, (lX2, (lY2, (lZ2, (lzi2, (lx2, (ly2, (ldi, _)))))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.py(M.addb(bp, M.b3(bp, b), p, q)) == T.fmul(bp, M.chord_y(bp, x1, y1, x2, y2, di), M.pz(M.addb(bp, M.b3(bp, b), p, q))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x1), T.fmul(bp, Z1, y1), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x2), T.fmul(bp, Z2, y2), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x1, y1, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x2, y2, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_chord_y.lem_add_chord_y(bp, l1, b, x1, y1, x2, y2, Z1, Z2, di, zi1, zi2, lb, lx1, ly1, lx2, ly2, lZ1, lZ2, ldi, lzi1, lzi2, on1, on2, hd))

def Laws.add_chord_nz(bp, l1, b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di, hc, r1, r2, on1, on2, hd, not2):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx1, (ly1, (lX2, (lY2, (lZ2, (lzi2, (lx2, (ly2, (ldi, _)))))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  +ny = T.fneg(bp, y2)
  +on2n = Equal.trans(Nat, T.fmul(bp, ny, ny), T.fmul(bp, y2, y2), T.fadd(bp, T.fmul(bp, x2, T.fmul(bp, x2, x2)), b), C_negsq.lem_negsq(bp, l1, y2, ly2), on2)
  +onp = C_chord_on.lem_chord_on(bp, l1, b, x1, y1, x2, ny, Z1, Z2, di, zi1, zi2, lb, lx1, ly1, lx2, G.fneg_le(bp, y2), lZ1, lZ2, ldi, lzi1, lzi2, on1, on2n, hd)
  +lcx = G.fsub_le(bp, T.fsub(bp, T.fmul(bp, M.chord_l(bp, y1, ny, di), M.chord_l(bp, y1, ny, di)), x1), x2)
  ynz = G.y_nz(bp, b, M.chord_x(bp, x1, y1, x2, ny, di), M.chord_y(bp, x1, y1, x2, ny, di), lcx, onp, not2)
  +w = T.fmul(bp, T.fmul(bp, T.fmul(bp, zi1, zi1), T.fmul(bp, zi2, zi2)), T.fmul(bp, di, T.fmul(bp, di, di)))
  +hw = C_add_chord_z.lem_add_chord_z(bp, l1, b, x1, y1, x2, y2, Z1, Z2, di, zi1, zi2, lb, lx1, ly1, lx2, ly2, lZ1, lZ2, ldi, lzi1, lzi2, on1, on2, hd, hz1, hz2)
  +ps = {M.Pt{T.fmul(bp, Z1, x1), T.fmul(bp, Z1, y1), Z1} : M.Pt}
  +qs = {M.Pt{T.fmul(bp, Z2, x2), T.fmul(bp, Z2, y2), Z2} : M.Pt}
  nz = G.mul_nz(bp, M.pz(M.addb(bp, M.b3(bp, b), ps, qs)), w, M.chord_y(bp, x1, y1, x2, ny, di), hw, ynz)
  G.tr2(p => q => {M.pz(M.addb(bp, M.b3(bp, b), p, q)) != 0n : Nat}, M.Pt{X1, Y1, Z1}, ps, M.Pt{X2, Y2, Z2}, qs, G.rep(bp, l1, X1, Y1, Z1, zi1, x1, y1, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x2, y2, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), nz)

# --- tangent ----------------------------------------------------------------------------

def Laws.add_tan_x(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti, hc, r1, r2, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, (lti, _)))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.px(M.addb(bp, M.b3(bp, b), p, q)) == T.fmul(bp, M.tan_x(bp, x, ti), M.pz(M.addb(bp, M.b3(bp, b), p, q))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, y), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, y, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_tan_x.lem_add_tan_x(bp, l1, b, x, y, Z1, Z2, ti, zi1, zi2, lb, lx, ly, lZ1, lZ2, lti, lzi1, lzi2, on, ht))

def Laws.add_tan_y(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti, hc, r1, r2, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, (lti, _)))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.py(M.addb(bp, M.b3(bp, b), p, q)) == T.fmul(bp, M.tan_y(bp, x, y, ti), M.pz(M.addb(bp, M.b3(bp, b), p, q))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, y), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, y, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_tan_y.lem_add_tan_y(bp, l1, b, x, y, Z1, Z2, ti, zi1, zi2, lb, lx, ly, lZ1, lZ2, lti, lzi1, lzi2, on, ht))

def Laws.add_tan_nz(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti, hc, r1, r2, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, (lti, _)))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  +ps = {M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1} : M.Pt}
  +qs = {M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, y), Z2} : M.Pt}
  +w = T.fmul(bp, T.fmul(bp, T.fmul(bp, zi1, zi1), T.fmul(bp, zi2, zi2)), T.fmul(bp, ti, T.fmul(bp, ti, ti)))
  nz = G.inv_nz(bp, M.pz(M.addb(bp, M.b3(bp, b), ps, qs)), w, C_add_tan_z.lem_add_tan_z(bp, l1, b, x, y, Z1, Z2, ti, zi1, zi2, lb, lx, ly, lZ1, lZ2, lti, lzi1, lzi2, on, ht, hz1, hz2))
  G.tr2(p => q => {M.pz(M.addb(bp, M.b3(bp, b), p, q)) != 0n : Nat}, M.Pt{X1, Y1, Z1}, ps, M.Pt{X2, Y2, Z2}, qs, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, y, lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), nz)

# --- P + (-P) ---------------------------------------------------------------------------

def Laws.add_neg_x(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, hc, r1, r2, on):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, _))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.px(M.addb(bp, M.b3(bp, b), p, q)) == 0n : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, T.fneg(bp, y)), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, T.fneg(bp, y), lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_neg_x.lem_add_neg_x(bp, l1, b, x, y, Z1, Z2, b, zi1, zi2, lb, lx, ly, lZ1, lZ2, lb, lzi1, lzi2, on))

def Laws.add_neg_z(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, hc, r1, r2, on):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, _))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  G.tr2(p => q => {M.pz(M.addb(bp, M.b3(bp, b), p, q)) == 0n : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, M.Pt{X2, Y2, Z2}, M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, T.fneg(bp, y)), Z2}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, T.fneg(bp, y), lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), C_add_neg_z.lem_add_neg_z(bp, l1, b, x, y, Z1, Z2, b, zi1, zi2, lb, lx, ly, lZ1, lZ2, lb, lzi1, lzi2, on))

def Laws.add_neg_y_nz(bp, l1, b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti, hc, r1, r2, on, ht, not2):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lX2, (lY2, (lZ2, (lzi2, (lx, (ly, (lti, _)))))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  (hz2, (hx2, hy2)) = r2
  +ps = {M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1} : M.Pt}
  +qs = {M.Pt{T.fmul(bp, Z2, x), T.fmul(bp, Z2, T.fneg(bp, y)), Z2} : M.Pt}
  +w = T.fmul(bp, T.fmul(bp, T.fmul(bp, zi1, zi1), T.fmul(bp, zi2, zi2)), T.fmul(bp, ti, T.fmul(bp, ti, ti)))
  +ont = C_tan_on.lem_tan_on(bp, l1, b, x, y, Z1, Z2, ti, zi1, zi2, lb, lx, ly, lZ1, lZ2, lti, lzi1, lzi2, on, ht)
  +ltx = G.fsub_le(bp, T.fsub(bp, T.fmul(bp, M.tan_l(bp, x, ti), M.tan_l(bp, x, ti)), x), x)
  ynz = G.y_nz(bp, b, M.tan_x(bp, x, ti), M.tan_y(bp, x, y, ti), ltx, ont, not2)
  +hw = C_add_neg_y.lem_add_neg_y(bp, l1, b, x, y, Z1, Z2, ti, zi1, zi2, lb, lx, ly, lZ1, lZ2, lti, lzi1, lzi2, on, ht, hz1, hz2)
  nz = G.mul_nz(bp, M.py(M.addb(bp, M.b3(bp, b), ps, qs)), w, M.tan_y(bp, x, y, ti), hw, ynz)
  G.tr2(p => q => {M.py(M.addb(bp, M.b3(bp, b), p, q)) != 0n : Nat}, M.Pt{X1, Y1, Z1}, ps, M.Pt{X2, Y2, Z2}, qs, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), G.rep(bp, l1, X2, Y2, Z2, zi2, x, T.fneg(bp, y), lX2, lY2, lZ2, lzi2, hz2, hx2, hy2), nz)

# --- the identity -----------------------------------------------------------------------

def Laws.add_id_l(bp, l1, b, Y1, X2, Y2, Z2, hc):
  (lb, (lY1, (lX2, (lY2, (lZ2, _))))) = hc
  +l0 = {(bp, {==}) : L.Le(0n, bp)}
  G.pt_ext(M.addb(bp, M.b3(bp, b), M.Pt{0n, Y1, 0n}, M.Pt{X2, Y2, Z2}), M.Pt{T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), X2), T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), Y2), T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), Z2)}, C_add_idl_x.lem_add_idl_x(bp, l1, b, 0n, Y1, X2, Y2, Z2, lb, l0, lY1, lX2, lY2, lZ2, {==}), C_add_idl_y.lem_add_idl_y(bp, l1, b, 0n, Y1, X2, Y2, Z2, lb, l0, lY1, lX2, lY2, lZ2, {==}), C_add_idl_z.lem_add_idl_z(bp, l1, b, 0n, Y1, X2, Y2, Z2, lb, l0, lY1, lX2, lY2, lZ2, {==}))

def Laws.add_id_r(bp, l1, b, X1, Y1, Z1, Y2, hc):
  (lb, (lX1, (lY1, (lZ1, (lY2, _))))) = hc
  +l0 = {(bp, {==}) : L.Le(0n, bp)}
  G.pt_ext(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{0n, Y2, 0n}), M.Pt{T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), X1), T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), Y1), T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), Z1)}, C_add_idr_x.lem_add_idr_x(bp, l1, b, 0n, Y2, X1, Y1, Z1, lb, l0, lY2, lX1, lY1, lZ1, {==}), C_add_idr_y.lem_add_idr_y(bp, l1, b, 0n, Y2, X1, Y1, Z1, lb, l0, lY2, lX1, lY1, lZ1, {==}), C_add_idr_z.lem_add_idr_z(bp, l1, b, 0n, Y2, X1, Y1, Z1, lb, l0, lY2, lX1, lY1, lZ1, {==}))

# --- add_aff ----------------------------------------------------------------------------

def Laws.aff_is_add(bp, l1, b, X1, Y1, Z1, x2, y2, hc):
  (lb, (lX1, (lY1, (lZ1, (lx2, (ly2, _)))))) = hc
  G.pt_ext(M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}), M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{x2, y2, 1n}), C_aff_eq_x.lem_aff_eq_x(bp, l1, b, X1, Y1, Z1, x2, y2, 1n, lb, lX1, lY1, lZ1, lx2, ly2, l1, {==}), C_aff_eq_y.lem_aff_eq_y(bp, l1, b, X1, Y1, Z1, x2, y2, 1n, lb, lX1, lY1, lZ1, lx2, ly2, l1, {==}), C_aff_eq_z.lem_aff_eq_z(bp, l1, b, X1, Y1, Z1, x2, y2, 1n, lb, lX1, lY1, lZ1, lx2, ly2, l1, {==}))

def Laws.aff_chord_x(bp, l1, b, X1, Y1, Z1, zi1, x1, y1, x2, y2, di, hc, r1, on1, on2, hd):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx1, (ly1, (lx2, (ly2, (ldi, _)))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  G.tr1(p => {M.px(M.add_affb(bp, M.b3(bp, b), p, M.Aff{x2, y2})) == T.fmul(bp, M.chord_x(bp, x1, y1, x2, y2, di), M.pz(M.add_affb(bp, M.b3(bp, b), p, M.Aff{x2, y2}))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x1), T.fmul(bp, Z1, y1), Z1}, G.rep(bp, l1, X1, Y1, Z1, zi1, x1, y1, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), C_aff_chord_x.lem_aff_chord_x(bp, l1, b, x1, y1, x2, y2, Z1, Z1, di, zi1, zi1, lb, lx1, ly1, lx2, ly2, lZ1, lZ1, ldi, lzi1, lzi1, on1, on2, hd))

def Laws.aff_chord_y(bp, l1, b, X1, Y1, Z1, zi1, x1, y1, x2, y2, di, hc, r1, on1, on2, hd):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx1, (ly1, (lx2, (ly2, (ldi, _)))))))))) = hc
  (hz1, (hx1, hy1)) = r1
  G.tr1(p => {M.py(M.add_affb(bp, M.b3(bp, b), p, M.Aff{x2, y2})) == T.fmul(bp, M.chord_y(bp, x1, y1, x2, y2, di), M.pz(M.add_affb(bp, M.b3(bp, b), p, M.Aff{x2, y2}))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x1), T.fmul(bp, Z1, y1), Z1}, G.rep(bp, l1, X1, Y1, Z1, zi1, x1, y1, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), C_aff_chord_y.lem_aff_chord_y(bp, l1, b, x1, y1, x2, y2, Z1, Z1, di, zi1, zi1, lb, lx1, ly1, lx2, ly2, lZ1, lZ1, ldi, lzi1, lzi1, on1, on2, hd))

# --- double -----------------------------------------------------------------------------

def Laws.dbl_tan_x(bp, l1, b, X1, Y1, Z1, zi1, x, y, ti, hc, r1, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx, (ly, (lti, _)))))))) = hc
  (hz1, (hx1, hy1)) = r1
  G.tr1(p => {M.px(M.doubleb(bp, M.b3(bp, b), p)) == T.fmul(bp, M.tan_x(bp, x, ti), M.pz(M.doubleb(bp, M.b3(bp, b), p))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), C_dbl_tan_x.lem_dbl_tan_x(bp, l1, b, x, y, Z1, Z1, ti, zi1, zi1, lb, lx, ly, lZ1, lZ1, lti, lzi1, lzi1, on, ht))

def Laws.dbl_tan_y(bp, l1, b, X1, Y1, Z1, zi1, x, y, ti, hc, r1, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx, (ly, (lti, _)))))))) = hc
  (hz1, (hx1, hy1)) = r1
  G.tr1(p => {M.py(M.doubleb(bp, M.b3(bp, b), p)) == T.fmul(bp, M.tan_y(bp, x, y, ti), M.pz(M.doubleb(bp, M.b3(bp, b), p))) : Nat}, M.Pt{X1, Y1, Z1}, M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1}, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), C_dbl_tan_y.lem_dbl_tan_y(bp, l1, b, x, y, Z1, Z1, ti, zi1, zi1, lb, lx, ly, lZ1, lZ1, lti, lzi1, lzi1, on, ht))

def Laws.dbl_tan_nz(bp, l1, b, X1, Y1, Z1, zi1, x, y, ti, hc, r1, on, ht):
  (lb, (lX1, (lY1, (lZ1, (lzi1, (lx, (ly, (lti, _)))))))) = hc
  (hz1, (hx1, hy1)) = r1
  +ps = {M.Pt{T.fmul(bp, Z1, x), T.fmul(bp, Z1, y), Z1} : M.Pt}
  +w = T.fmul(bp, T.fmul(bp, T.fmul(bp, zi1, zi1), T.fmul(bp, zi1, zi1)), T.fmul(bp, ti, T.fmul(bp, ti, ti)))
  nz = G.inv_nz(bp, M.pz(M.doubleb(bp, M.b3(bp, b), ps)), w, C_dbl_tan_z.lem_dbl_tan_z(bp, l1, b, x, y, Z1, Z1, ti, zi1, zi1, lb, lx, ly, lZ1, lZ1, lti, lzi1, lzi1, on, ht, hz1))
  G.tr1(p => {M.pz(M.doubleb(bp, M.b3(bp, b), p)) != 0n : Nat}, M.Pt{X1, Y1, Z1}, ps, G.rep(bp, l1, X1, Y1, Z1, zi1, x, y, lX1, lY1, lZ1, lzi1, hz1, hx1, hy1), nz)

def Laws.dbl_id(bp, l1, b, Y, hc):
  (lb, (lY, _)) = hc
  +l0 = {(bp, {==}) : L.Le(0n, bp)}
  G.pt_ext(M.doubleb(bp, M.b3(bp, b), M.Pt{0n, Y, 0n}), M.Pt{0n, T.fmul(bp, T.fmul(bp, Y, Y), T.fmul(bp, Y, Y)), 0n}, C_dbl_id_x.lem_dbl_id_x(bp, l1, b, 0n, Y, 0n, 0n, 0n, lb, l0, lY, l0, l0, l0, {==}), C_dbl_id_y.lem_dbl_id_y(bp, l1, b, 0n, Y, 0n, 0n, 0n, lb, l0, lY, l0, l0, l0, {==}), C_dbl_id_z.lem_dbl_id_z(bp, l1, b, 0n, Y, 0n, 0n, 0n, lb, l0, lY, l0, l0, l0, {==}))

def Laws.dbl_on_curve(bp, l1, b, X1, Y1, Z1, hc, on1):
  (lb, (lX1, (lY1, (lZ1, _)))) = hc
  C_dbl_on.lem_dbl_on(bp, l1, b, X1, Y1, Z1, X1, Y1, Z1, lb, lX1, lY1, lZ1, lX1, lY1, lZ1, on1)

# --- chord and tangent ------------------------------------------------------------------

def Laws.aadd_is_chord(bp, x1, y1, x2, y2, inv):
  {==}

def Laws.chord_on_curve(bp, l1, b, x1, y1, x2, y2, di, hc, on1, on2, hd):
  (lb, (lx1, (ly1, (lx2, (ly2, (ldi, _)))))) = hc
  C_chord_on.lem_chord_on(bp, l1, b, x1, y1, x2, y2, b, b, di, b, b, lb, lx1, ly1, lx2, ly2, lb, lb, ldi, lb, lb, on1, on2, hd)

def Laws.tan_on_curve(bp, l1, b, x, y, ti, hc, on, ht):
  (lb, (lx, (ly, (lti, _)))) = hc
  C_tan_on.lem_tan_on(bp, l1, b, x, y, b, b, ti, b, b, lb, lx, ly, lb, lb, lti, lb, lb, on, ht)

# --- mul15 ------------------------------------------------------------------------------

def Laws.add_is_b5(bp, l1, X1, Y1, Z1, X2, Y2, Z2):
  +p = {M.Pt{X1, Y1, Z1} : M.Pt}
  +q = {M.Pt{X2, Y2, Z2} : M.Pt}
  +k = M.b3(bp, Nat.mod(5n, 1n+bp))
  +t2 = M.add_t2(bp, p, q)
  +ya = M.add_y3a(bp, p, q)
  +e1 = C_m15.lem_m15(bp, l1, t2, G.fmul_le(bp, Z1, Z2))
  +e2 = C_m15.lem_m15(bp, l1, ya, G.fsub_le(bp, T.fmul(bp, T.fadd(bp, X1, Z1), T.fadd(bp, X2, Z2)), T.fadd(bp, T.fmul(bp, X1, X2), T.fmul(bp, Z1, Z2))))
  Equal.trans(M.Pt, M.addh(bp, p, q, M.m15(bp, t2), M.m15(bp, ya)), M.addh(bp, p, q, T.fmul(bp, k, t2), M.m15(bp, ya)), M.addh(bp, p, q, T.fmul(bp, k, t2), T.fmul(bp, k, ya)), Equal.cong(Nat, M.Pt, w => M.addh(bp, p, q, w, M.m15(bp, ya)), M.m15(bp, t2), T.fmul(bp, k, t2), e1), Equal.cong(Nat, M.Pt, w => M.addh(bp, p, q, T.fmul(bp, k, t2), w), M.m15(bp, ya), T.fmul(bp, k, ya), e2))

def Laws.aff_is_b5(bp, l1, X1, Y1, Z1, x2, y2, lz):
  +p = {M.Pt{X1, Y1, Z1} : M.Pt}
  +q = {M.Aff{x2, y2} : M.Aff}
  +k = M.b3(bp, Nat.mod(5n, 1n+bp))
  +t2 = M.aff_t2(p)
  +ya = M.aff_y3a(bp, p, q)
  +e1 = C_m15.lem_m15(bp, l1, t2, lz)
  +e2 = C_m15.lem_m15(bp, l1, ya, G.fadd_le(bp, T.fmul(bp, x2, Z1), X1))
  Equal.trans(M.Pt, M.add_affh(bp, p, q, M.m15(bp, t2), M.m15(bp, ya)), M.add_affh(bp, p, q, T.fmul(bp, k, t2), M.m15(bp, ya)), M.add_affh(bp, p, q, T.fmul(bp, k, t2), T.fmul(bp, k, ya)), Equal.cong(Nat, M.Pt, w => M.add_affh(bp, p, q, w, M.m15(bp, ya)), M.m15(bp, t2), T.fmul(bp, k, t2), e1), Equal.cong(Nat, M.Pt, w => M.add_affh(bp, p, q, T.fmul(bp, k, t2), w), M.m15(bp, ya), T.fmul(bp, k, ya), e2))

def Laws.dbl_is_b5(bp, l1, X1, Y1, Z1):
  +p = {M.Pt{X1, Y1, Z1} : M.Pt}
  +k = M.b3(bp, Nat.mod(5n, 1n+bp))
  +t2 = M.dbl_t2(bp, p)
  Equal.cong(Nat, M.Pt, w => M.doubleh(bp, p, w), M.m15(bp, t2), T.fmul(bp, k, t2), C_m15.lem_m15(bp, l1, t2, G.fmul_le(bp, Z1, Z1)))

# --- y^2 = x^3 + 5 over Z/7 -----------------------------------------------------------------

def not2_le(+j: Nat, +e: Nat, he: {Nat.add(7n+j, e) == 6n : Nat}) -> Empty:
  L.succ_ne_zero(Nat.add(j, e), L.succ_inj(1n+Nat.add(j, e), 0n, L.succ_inj(2n+Nat.add(j, e), 1n, L.succ_inj(3n+Nat.add(j, e), 2n, L.succ_inj(4n+Nat.add(j, e), 3n, L.succ_inj(5n+Nat.add(j, e), 4n, L.succ_inj(6n+Nat.add(j, e), 5n, he)))))))

def not2_7(+t: Nat, l: L.Le(t, 6n), h: {T.fadd(6n, T.fmul(6n, t, T.fmul(6n, t, t)), 5n) == 0n : Nat}) -> Empty:
  match t:
    case 0n:
      L.succ_ne_zero(4n, h)
    case 1n+t1:
      match t1:
        case 0n:
          L.succ_ne_zero(5n, h)
        case 1n+t2:
          match t2:
            case 0n:
              L.succ_ne_zero(5n, h)
            case 1n+t3:
              match t3:
                case 0n:
                  L.succ_ne_zero(3n, h)
                case 1n+t4:
                  match t4:
                    case 0n:
                      L.succ_ne_zero(5n, h)
                    case 1n+t5:
                      match t5:
                        case 0n:
                          L.succ_ne_zero(3n, h)
                        case 1n+t6:
                          match t6:
                            case 0n:
                              L.succ_ne_zero(3n, h)
                            case 1n+j:
                              (+e, he) = l
                              not2_le(j, e, he)

def Laws.not2_7():
  t => l => h => not2_7(t, l, h)

def Laws.chord_sat():
  ((5n, {==}), (((1n, {==}), ((3n, {==}), ((4n, {==}), ((5n, {==}), ((5n, {==}), ((3n, {==}), ((4n, {==}), ((1n, {==}), ((4n, {==}), ((5n, {==}), ((5n, {==}), ((1n, {==}), ((4n, {==}), ((2n, {==}), Unit{})))))))))))))), (({==}, ({==}, {==})), (({==}, ({==}, {==})), ({==}, ({==}, {==}))))))

def Laws.tan_sat():
  (((1n, {==}), ((3n, {==}), ((4n, {==}), ((5n, {==}), ((5n, {==}), ((3n, {==}), ((4n, {==}), ((5n, {==}), ((5n, {==}), ((3n, {==}), ((4n, {==}), ((4n, {==}), Unit{})))))))))))), (({==}, ({==}, {==})), ({==}, {==})))

def Laws.neg_sat():
  (((1n, {==}), ((3n, {==}), ((4n, {==}), ((5n, {==}), ((5n, {==}), ((3n, {==}), ((1n, {==}), ((5n, {==}), ((5n, {==}), ((3n, {==}), ((4n, {==}), ((4n, {==}), Unit{})))))))))))), ({==}, ({==}, {==})))

def Laws.on_curve_sat():
  {==}
