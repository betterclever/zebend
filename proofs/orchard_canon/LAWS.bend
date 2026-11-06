import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./gates_model.bend as G

# Per-row soundness of Orchard's decomposition and canonicity gates, stated about the generated
# gate polynomials (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend).
# Fp = Z/p, p = 1 + pp. Hypotheses, all explicit: nzd<k> (no zero divisors among canonical
# elements, true for prime p; one copy per product the proof splits), l1 / lc<c> (the small
# constants used are below p), the selector is invertible, the cells named l<cell> are
# canonical, and every listed polynomial of the gate vanishes on the row. Large constants are
# parameters (values in gates_model.bend). Names in quotes are halo2's gate names
# (../orchard/names/names.txt); cells are the gate's queried evaluations.

# Gate 20 "Canonicity checks".
# a8 = alpha_2 (the MSB part), a7 = alpha_1, a24 = z_84_alpha; MSB = 1 forces alpha_1 = 0 and the
# high parts of alpha_0 to vanish (the cross-row canonicity argument is not covered).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a20: advice column 6, rotation -1
#   a22: advice column 6, rotation +1
#   a24: advice column 8, rotation -1
law gate_20:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for nzd2: F.NZD(pp)
  for nzd3: F.NZD(pp)
  for nzd4: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +lc3: L.Le(3n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t120: Nat
  for +t130: Nat
  for +t252: Nat
  for +tP: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +a20: Nat
  for +a22: Nat
  for +a24: Nat
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for +la8: L.Le(a8, pp)
  for +la18: L.Le(a18, pp)
  for +la22: L.Le(a22, pp)
  for +la24: L.Le(a24, pp)
  for h0: {G.gate_20_0(pp, sel, a7, a8) == 0n : Nat}
  for h1: {G.gate_20_1(pp, sel, t120, a8, a18, a24) == 0n : Nat}
  for h2: {G.gate_20_2(pp, sel, a8, a18, a19) == 0n : Nat}
  for h3: {G.gate_20_3(pp, sel, a8, a22) == 0n : Nat}
  for h4: {G.gate_20_4(pp, sel, a7) == 0n : Nat}
  for h5: {G.gate_20_5(pp, sel, a8) == 0n : Nat}
  for h6: {G.gate_20_6(pp, sel, a7, a8, a24) == 0n : Nat}
  for h7: {G.gate_20_7(pp, sel, t130, t252, tP, a6, a20, a24) == 0n : Nat}
  ({a8 == 1n : Nat} -> {a7 == 0n : Nat}) & ({a8 == 1n : Nat} -> {a18 == F.fmul(1n+pp, a24, t120) : Nat}) & ({a8 == 1n : Nat} -> Either<&1, &1, {F.fadd(1n+pp, a19, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a18, 8n))) == 0n : Nat}, {F.fadd(1n+pp, a19, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a18, 8n))) == 1n : Nat}>) & ({a8 == 1n : Nat} -> {a22 == 0n : Nat}) & L.Le(a7, 3n) & Either<&1, &1, {a8 == 0n : Nat}, {a8 == 1n : Nat}> & {a24 == F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 4n)) : Nat} & {a6 == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a20, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a24, t252))), t130), F.fsub(1n+pp, 0n, tP)) : Nat}

# NON-VACUITY: every hypothesis of gate_20 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 5, a7 = 3, a8 = 0, a18 = 9, a19 = 1, a20 = 6, a22 = 7, a24 = 3.
law gate_20_satisfiable:
  F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & L.Le(1n, 10n) & L.Le(3n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(3n, 10n) & L.Le(0n, 10n) & L.Le(9n, 10n) & L.Le(7n, 10n) & L.Le(3n, 10n) & {G.gate_20_0(10n, 1n, 3n, 0n) == 0n : Nat} & {G.gate_20_1(10n, 1n, 1n, 0n, 9n, 3n) == 0n : Nat} & {G.gate_20_2(10n, 1n, 0n, 9n, 1n) == 0n : Nat} & {G.gate_20_3(10n, 1n, 0n, 7n) == 0n : Nat} & {G.gate_20_4(10n, 1n, 3n) == 0n : Nat} & {G.gate_20_5(10n, 1n, 0n) == 0n : Nat} & {G.gate_20_6(10n, 1n, 3n, 0n, 3n) == 0n : Nat} & {G.gate_20_7(10n, 1n, 1n, 4n, 1n, 5n, 6n, 3n) == 0n : Nat}

# Gate 27 "Decomposition check".
# Sinsemilla MessagePiece decomposition (first Sinsemilla chip).
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a2: advice column 2, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a12: advice column 2, rotation +1
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
#   a16: advice column 0, rotation +1
#   a17: advice column 1, rotation +1
law gate_27:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t240: Nat
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a4: Nat
  for +a12: Nat
  for +a13: Nat
  for +a14: Nat
  for +a16: Nat
  for +a17: Nat
  for +la0: L.Le(a0, pp)
  for +la3: L.Le(a3, pp)
  for +la4: L.Le(a4, pp)
  for +la14: L.Le(a14, pp)
  for +la17: L.Le(a17, pp)
  for h0: {G.gate_27_0(pp, sel, a0, a14, a16) == 0n : Nat}
  for h1: {G.gate_27_1(pp, sel, t240, a1, a3, a12, a16, a17) == 0n : Nat}
  for h2: {G.gate_27_2(pp, sel, a2, a4, a13) == 0n : Nat}
  for h3: {G.gate_27_3(pp, sel, a12, a13, a17) == 0n : Nat}
  {a0 == F.fadd(1n+pp, F.fmul(1n+pp, a16, 1024n), a14) : Nat} & {F.fadd(1n+pp, a16, F.fmul(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a1, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a17, 1024n))), F.fmul(1n+pp, a12, 1024n)), t240)) == a3 : Nat} & {F.fadd(1n+pp, a13, F.fmul(1n+pp, a2, 32n)) == a4 : Nat} & {a17 == F.fadd(1n+pp, a12, F.fmul(1n+pp, a13, 32n)) : Nat}

# NON-VACUITY: every hypothesis of gate_27 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 9, a1 = 9, a2 = 0, a3 = 10, a4 = 0, a12 = 1, a13 = 0, a14 = 8, a16 = 1, a17 = 1.
law gate_27_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(9n, 10n) & L.Le(10n, 10n) & L.Le(0n, 10n) & L.Le(8n, 10n) & L.Le(1n, 10n) & {G.gate_27_0(10n, 1n, 9n, 8n, 1n) == 0n : Nat} & {G.gate_27_1(10n, 1n, 1n, 9n, 10n, 1n, 1n, 1n) == 0n : Nat} & {G.gate_27_2(10n, 1n, 0n, 0n, 0n) == 0n : Nat} & {G.gate_27_3(10n, 1n, 1n, 0n, 1n) == 0n : Nat}

# Gate 31 "Decomposition check".
# Sinsemilla MessagePiece decomposition (second Sinsemilla chip).
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a15: advice column 5, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
law gate_31:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t240: Nat
  for +a5: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a15: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +la5: L.Le(a5, pp)
  for +la8: L.Le(a8, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la22: L.Le(a22, pp)
  for h0: {G.gate_31_0(pp, sel, a5, a10, a15) == 0n : Nat}
  for h1: {G.gate_31_1(pp, sel, t240, a6, a8, a15, a18, a22) == 0n : Nat}
  for h2: {G.gate_31_2(pp, sel, a7, a9, a19) == 0n : Nat}
  for h3: {G.gate_31_3(pp, sel, a18, a19, a22) == 0n : Nat}
  {a5 == F.fadd(1n+pp, F.fmul(1n+pp, a15, 1024n), a10) : Nat} & {F.fadd(1n+pp, a15, F.fmul(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a6, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a22, 1024n))), F.fmul(1n+pp, a18, 1024n)), t240)) == a8 : Nat} & {F.fadd(1n+pp, a19, F.fmul(1n+pp, a7, 32n)) == a9 : Nat} & {a22 == F.fadd(1n+pp, a18, F.fmul(1n+pp, a19, 32n)) : Nat}

# NON-VACUITY: every hypothesis of gate_31 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 0, a6 = 0, a7 = 2, a8 = 0, a9 = 9, a10 = 0, a15 = 0, a18 = 1, a19 = 0, a22 = 1.
law gate_31_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(9n, 10n) & L.Le(0n, 10n) & L.Le(1n, 10n) & {G.gate_31_0(10n, 1n, 0n, 0n, 0n) == 0n : Nat} & {G.gate_31_1(10n, 1n, 1n, 0n, 0n, 0n, 1n, 1n) == 0n : Nat} & {G.gate_31_2(10n, 1n, 2n, 9n, 0n) == 0n : Nat} & {G.gate_31_3(10n, 1n, 1n, 0n, 1n) == 0n : Nat}

# Gate 32 "CommitIvk canonicity check".
# a4 = b_1, a14 = d_1: the high bits whose value 1 forces the canonicity conditions.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a2: advice column 2, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a12: advice column 2, rotation +1
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
#   a16: advice column 0, rotation +1
#   a17: advice column 1, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
law gate_32:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t130: Nat
  for +t140: Nat
  for +t245: Nat
  for +t250: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a4: Nat
  for +a5: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a12: Nat
  for +a13: Nat
  for +a14: Nat
  for +a16: Nat
  for +a17: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +la0: L.Le(a0, pp)
  for +la2: L.Le(a2, pp)
  for +la3: L.Le(a3, pp)
  for +la4: L.Le(a4, pp)
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for +la8: L.Le(a8, pp)
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +la14: L.Le(a14, pp)
  for +la16: L.Le(a16, pp)
  for +la18: L.Le(a18, pp)
  for +la19: L.Le(a19, pp)
  for +la22: L.Le(a22, pp)
  for h0: {G.gate_32_0(pp, sel, a4) == 0n : Nat}
  for h1: {G.gate_32_1(pp, sel, a14) == 0n : Nat}
  for h2: {G.gate_32_2(pp, sel, a2, a3, a4, a5) == 0n : Nat}
  for h3: {G.gate_32_3(pp, sel, a12, a13, a14) == 0n : Nat}
  for h4: {G.gate_32_4(pp, sel, t250, t254, a0, a1, a3, a4) == 0n : Nat}
  for h5: {G.gate_32_5(pp, sel, t245, t254, a5, a13, a14, a16, a17) == 0n : Nat}
  for h6: {G.gate_32_6(pp, sel, a3, a4) == 0n : Nat}
  for h7: {G.gate_32_7(pp, sel, a4, a6) == 0n : Nat}
  for h8: {G.gate_32_8(pp, sel, t130, tP, a1, a7) == 0n : Nat}
  for h9: {G.gate_32_9(pp, sel, a4, a8) == 0n : Nat}
  for h10: {G.gate_32_10(pp, sel, a13, a14) == 0n : Nat}
  for h11: {G.gate_32_11(pp, sel, a14, a22) == 0n : Nat}
  for h12: {G.gate_32_12(pp, sel, t140, tP, a5, a17, a18) == 0n : Nat}
  for h13: {G.gate_32_13(pp, sel, a14, a19) == 0n : Nat}
  Either<&1, &1, {a4 == 0n : Nat}, {a4 == 1n : Nat}> & Either<&1, &1, {a14 == 0n : Nat}, {a14 == 1n : Nat}> & {a2 == F.fadd(1n+pp, F.fadd(1n+pp, a3, F.fmul(1n+pp, a4, 16n)), F.fmul(1n+pp, a5, 32n)) : Nat} & {a12 == F.fadd(1n+pp, a13, F.fmul(1n+pp, a14, 512n)) : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, a1, F.fmul(1n+pp, a3, t250)), F.fmul(1n+pp, a4, t254)) == a0 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a5, F.fmul(1n+pp, a17, 32n)), F.fmul(1n+pp, a13, t245)), F.fmul(1n+pp, a14, t254)) == a16 : Nat} & ({a4 == 1n : Nat} -> {a3 == 0n : Nat}) & ({a4 == 1n : Nat} -> {a6 == 0n : Nat}) & {F.fadd(1n+pp, a1, t130) == F.fadd(1n+pp, tP, a7) : Nat} & ({a4 == 1n : Nat} -> {a8 == 0n : Nat}) & ({a14 == 1n : Nat} -> {a13 == 0n : Nat}) & ({a14 == 1n : Nat} -> {a22 == 0n : Nat}) & {F.fadd(1n+pp, F.fadd(1n+pp, a5, F.fmul(1n+pp, a17, 32n)), t140) == F.fadd(1n+pp, tP, a18) : Nat} & ({a14 == 1n : Nat} -> {a19 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_32 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 1, a1 = 0, a2 = 1, a3 = 1, a4 = 0, a5 = 0, a6 = 0, a7 = 0, a8 = 8, a12 = 0, a13 = 0, a14 = 0, a16 = 10, a17 = 1, a18 = 10, a19 = 0, a22 = 5.
law gate_32_satisfiable:
  F.NZD(10n) & F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(8n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(10n, 10n) & L.Le(10n, 10n) & L.Le(0n, 10n) & L.Le(5n, 10n) & {G.gate_32_0(10n, 1n, 0n) == 0n : Nat} & {G.gate_32_1(10n, 1n, 0n) == 0n : Nat} & {G.gate_32_2(10n, 1n, 1n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_32_3(10n, 1n, 0n, 0n, 0n) == 0n : Nat} & {G.gate_32_4(10n, 1n, 1n, 5n, 1n, 0n, 1n, 0n) == 0n : Nat} & {G.gate_32_5(10n, 1n, 10n, 5n, 0n, 0n, 0n, 10n, 1n) == 0n : Nat} & {G.gate_32_6(10n, 1n, 1n, 0n) == 0n : Nat} & {G.gate_32_7(10n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_32_8(10n, 1n, 1n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_32_9(10n, 1n, 0n, 8n) == 0n : Nat} & {G.gate_32_10(10n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_32_11(10n, 1n, 0n, 5n) == 0n : Nat} & {G.gate_32_12(10n, 1n, 1n, 1n, 0n, 1n, 10n) == 0n : Nat} & {G.gate_32_13(10n, 1n, 0n, 0n) == 0n : Nat}

# Gate 33 "NoteCommit MessagePiece b" (also gate 44: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_33:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +la6: L.Le(a6, pp)
  for +la8: L.Le(a8, pp)
  for +la18: L.Le(a18, pp)
  for h0: {G.gate_33_0(pp, sel, a8) == 0n : Nat}
  for h1: {G.gate_33_1(pp, sel, a18) == 0n : Nat}
  for h2: {G.gate_33_2(pp, sel, a6, a7, a8, a18, a19) == 0n : Nat}
  Either<&1, &1, {a8 == 0n : Nat}, {a8 == 1n : Nat}> & Either<&1, &1, {a18 == 0n : Nat}, {a18 == 1n : Nat}> & {a6 == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 16n)), F.fmul(1n+pp, a18, 32n)), F.fmul(1n+pp, a19, 64n)) : Nat}

# NON-VACUITY: every hypothesis of gate_33 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 4, a7 = 2, a8 = 0, a18 = 0, a19 = 10.
law gate_33_satisfiable:
  F.NZD(10n) & F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(4n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & {G.gate_33_0(10n, 1n, 0n) == 0n : Nat} & {G.gate_33_1(10n, 1n, 0n) == 0n : Nat} & {G.gate_33_2(10n, 1n, 4n, 2n, 0n, 0n, 10n) == 0n : Nat}

# Gate 34 "NoteCommit MessagePiece d" (also gate 45: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_34:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for +la8: L.Le(a8, pp)
  for h0: {G.gate_34_0(pp, sel, a7) == 0n : Nat}
  for h1: {G.gate_34_1(pp, sel, a8) == 0n : Nat}
  for h2: {G.gate_34_2(pp, sel, a6, a7, a8, a18, a19) == 0n : Nat}
  Either<&1, &1, {a7 == 0n : Nat}, {a7 == 1n : Nat}> & Either<&1, &1, {a8 == 0n : Nat}, {a8 == 1n : Nat}> & {a6 == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 2n)), F.fmul(1n+pp, a18, 4n)), F.fmul(1n+pp, a19, 1024n)) : Nat}

# NON-VACUITY: every hypothesis of gate_34 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 5, a7 = 1, a8 = 1, a18 = 3, a19 = 1.
law gate_34_satisfiable:
  F.NZD(10n) & F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & {G.gate_34_0(10n, 1n, 1n) == 0n : Nat} & {G.gate_34_1(10n, 1n, 1n) == 0n : Nat} & {G.gate_34_2(10n, 1n, 5n, 1n, 1n, 3n, 1n) == 0n : Nat}

# Gate 35 "NoteCommit MessagePiece e" (also gate 46: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
law gate_35:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +la6: L.Le(a6, pp)
  for h0: {G.gate_35_0(pp, sel, a6, a7, a8) == 0n : Nat}
  {a6 == F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 64n)) : Nat}

# NON-VACUITY: every hypothesis of gate_35 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 5, a7 = 2, a8 = 4.
law gate_35_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & {G.gate_35_0(10n, 1n, 5n, 2n, 4n) == 0n : Nat}

# Gate 36 "NoteCommit MessagePiece g" (also gate 47: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a18: advice column 7, rotation +1
#   a22: advice column 6, rotation +1
law gate_36:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a18: Nat
  for +a22: Nat
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for h0: {G.gate_36_0(pp, sel, a7) == 0n : Nat}
  for h1: {G.gate_36_1(pp, sel, a6, a7, a18, a22) == 0n : Nat}
  Either<&1, &1, {a7 == 0n : Nat}, {a7 == 1n : Nat}> & {a6 == F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a22, 2n)), F.fmul(1n+pp, a18, 1024n)) : Nat}

# NON-VACUITY: every hypothesis of gate_36 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 2, a7 = 0, a18 = 0, a22 = 1.
law gate_36_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(2n, 10n) & L.Le(0n, 10n) & {G.gate_36_0(10n, 1n, 0n) == 0n : Nat} & {G.gate_36_1(10n, 1n, 2n, 0n, 0n, 1n) == 0n : Nat}

# Gate 37 "NoteCommit MessagePiece h" (also gate 48: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
law gate_37:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +la6: L.Le(a6, pp)
  for +la8: L.Le(a8, pp)
  for h0: {G.gate_37_0(pp, sel, a8) == 0n : Nat}
  for h1: {G.gate_37_1(pp, sel, a6, a7, a8) == 0n : Nat}
  Either<&1, &1, {a8 == 0n : Nat}, {a8 == 1n : Nat}> & {a6 == F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 32n)) : Nat}

# NON-VACUITY: every hypothesis of gate_37 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 7, a7 = 7, a8 = 0.
law gate_37_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(7n, 10n) & L.Le(0n, 10n) & {G.gate_37_0(10n, 1n, 0n) == 0n : Nat} & {G.gate_37_1(10n, 1n, 7n, 7n, 0n) == 0n : Nat}

# Gate 38 "NoteCommit input g_d" (also gate 49: the same polynomials, checked by gen.py).
# a18 = b_1.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_38:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t130: Nat
  for +t250: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a18: Nat
  for +a19: Nat
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la19: L.Le(a19, pp)
  for h0: {G.gate_38_0(pp, sel, t250, t254, a6, a7, a8, a18) == 0n : Nat}
  for h1: {G.gate_38_1(pp, sel, t130, tP, a8, a19) == 0n : Nat}
  for h2: {G.gate_38_2(pp, sel, a7, a18) == 0n : Nat}
  for h3: {G.gate_38_3(pp, sel, a9, a18) == 0n : Nat}
  for h4: {G.gate_38_4(pp, sel, a10, a18) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, a8, F.fmul(1n+pp, a7, t250)), F.fmul(1n+pp, a18, t254)) == a6 : Nat} & {F.fadd(1n+pp, a8, t130) == F.fadd(1n+pp, tP, a19) : Nat} & ({a18 == 1n : Nat} -> {a7 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a9 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a10 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_38 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 7, a7 = 7, a8 = 0, a9 = 9, a10 = 8, a18 = 0, a19 = 0.
law gate_38_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(7n, 10n) & L.Le(7n, 10n) & L.Le(9n, 10n) & L.Le(8n, 10n) & L.Le(0n, 10n) & {G.gate_38_0(10n, 1n, 1n, 5n, 7n, 7n, 0n, 0n) == 0n : Nat} & {G.gate_38_1(10n, 1n, 1n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_38_2(10n, 1n, 7n, 0n) == 0n : Nat} & {G.gate_38_3(10n, 1n, 9n, 0n) == 0n : Nat} & {G.gate_38_4(10n, 1n, 8n, 0n) == 0n : Nat}

# Gate 39 "NoteCommit input pk_d" (also gate 50: the same polynomials, checked by gen.py).
# a18 = d_0.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_39:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t140: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a18: Nat
  for +a19: Nat
  for +la6: L.Le(a6, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la19: L.Le(a19, pp)
  for h0: {G.gate_39_0(pp, sel, t254, a6, a7, a8, a18) == 0n : Nat}
  for h1: {G.gate_39_1(pp, sel, t140, tP, a7, a8, a19) == 0n : Nat}
  for h2: {G.gate_39_2(pp, sel, a9, a18) == 0n : Nat}
  for h3: {G.gate_39_3(pp, sel, a10, a18) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 16n)), F.fmul(1n+pp, a18, t254)) == a6 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 16n)), t140) == F.fadd(1n+pp, tP, a19) : Nat} & ({a18 == 1n : Nat} -> {a9 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a10 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_39 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 0, a7 = 10, a8 = 3, a9 = 0, a10 = 0, a18 = 6, a19 = 3.
law gate_39_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(3n, 10n) & {G.gate_39_0(10n, 1n, 5n, 0n, 10n, 3n, 6n) == 0n : Nat} & {G.gate_39_1(10n, 1n, 1n, 1n, 10n, 3n, 3n) == 0n : Nat} & {G.gate_39_2(10n, 1n, 0n, 6n) == 0n : Nat} & {G.gate_39_3(10n, 1n, 0n, 6n) == 0n : Nat}

# Gate 40 "NoteCommit input value" (also gate 51: the same polynomials, checked by gen.py).
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
law gate_40:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t58: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +la6: L.Le(a6, pp)
  for h0: {G.gate_40_0(pp, sel, t58, a6, a7, a8, a9) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 256n)), F.fmul(1n+pp, a9, t58)) == a6 : Nat}

# NON-VACUITY: every hypothesis of gate_40 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 4, a7 = 6, a8 = 3, a9 = 0.
law gate_40_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(4n, 10n) & {G.gate_40_0(10n, 1n, 3n, 4n, 6n, 3n, 0n) == 0n : Nat}

# Gate 41 "NoteCommit input rho" (also gate 52: the same polynomials, checked by gen.py).
# a18 = g_0.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_41:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t140: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a18: Nat
  for +a19: Nat
  for +la6: L.Le(a6, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la19: L.Le(a19, pp)
  for h0: {G.gate_41_0(pp, sel, t254, a6, a7, a8, a18) == 0n : Nat}
  for h1: {G.gate_41_1(pp, sel, t140, tP, a7, a8, a19) == 0n : Nat}
  for h2: {G.gate_41_2(pp, sel, a9, a18) == 0n : Nat}
  for h3: {G.gate_41_3(pp, sel, a10, a18) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 16n)), F.fmul(1n+pp, a18, t254)) == a6 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 16n)), t140) == F.fadd(1n+pp, tP, a19) : Nat} & ({a18 == 1n : Nat} -> {a9 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a10 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_41 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 5, a7 = 2, a8 = 10, a9 = 0, a10 = 0, a18 = 6, a19 = 8.
law gate_41_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(5n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & L.Le(8n, 10n) & {G.gate_41_0(10n, 1n, 5n, 5n, 2n, 10n, 6n) == 0n : Nat} & {G.gate_41_1(10n, 1n, 1n, 1n, 2n, 10n, 8n) == 0n : Nat} & {G.gate_41_2(10n, 1n, 0n, 6n) == 0n : Nat} & {G.gate_41_3(10n, 1n, 0n, 6n) == 0n : Nat}

# Gate 42 "NoteCommit input psi" (also gate 53: the same polynomials, checked by gen.py).
# a18 = h_1.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
law gate_42:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t130: Nat
  for +t249: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +la6: L.Le(a6, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la19: L.Le(a19, pp)
  for +la22: L.Le(a22, pp)
  for h0: {G.gate_42_0(pp, sel, t249, t254, a6, a7, a8, a18, a22) == 0n : Nat}
  for h1: {G.gate_42_1(pp, sel, t130, tP, a7, a8, a19) == 0n : Nat}
  for h2: {G.gate_42_2(pp, sel, a18, a22) == 0n : Nat}
  for h3: {G.gate_42_3(pp, sel, a9, a18) == 0n : Nat}
  for h4: {G.gate_42_4(pp, sel, a10, a18) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 512n)), F.fmul(1n+pp, a22, t249)), F.fmul(1n+pp, a18, t254)) == a6 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, a7, F.fmul(1n+pp, a8, 512n)), t130) == F.fadd(1n+pp, tP, a19) : Nat} & ({a18 == 1n : Nat} -> {a22 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a9 == 0n : Nat}) & ({a18 == 1n : Nat} -> {a10 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_42 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 7, a7 = 0, a8 = 2, a9 = 8, a10 = 1, a18 = 0, a19 = 1, a22 = 1.
law gate_42_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(7n, 10n) & L.Le(8n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & {G.gate_42_0(10n, 1n, 6n, 5n, 7n, 0n, 2n, 0n, 1n) == 0n : Nat} & {G.gate_42_1(10n, 1n, 1n, 1n, 0n, 2n, 1n) == 0n : Nat} & {G.gate_42_2(10n, 1n, 0n, 1n) == 0n : Nat} & {G.gate_42_3(10n, 1n, 8n, 0n) == 0n : Nat} & {G.gate_42_4(10n, 1n, 1n, 0n) == 0n : Nat}

# Gate 43 "y coordinate checks" (also gate 54: the same polynomials, checked by gen.py).
# a9 = k_3.
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a15: advice column 5, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
law gate_43:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t130: Nat
  for +t250: Nat
  for +t254: Nat
  for +tP: Nat
  for +ltP: L.Le(tP, pp)
  for +a5: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a15: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +la5: L.Le(a5, pp)
  for +la8: L.Le(a8, pp)
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la15: L.Le(a15, pp)
  for +la18: L.Le(a18, pp)
  for +la19: L.Le(a19, pp)
  for h0: {G.gate_43_0(pp, sel, a9) == 0n : Nat}
  for h1: {G.gate_43_1(pp, sel, a6, a7, a15, a22) == 0n : Nat}
  for h2: {G.gate_43_2(pp, sel, t250, t254, a5, a8, a9, a15) == 0n : Nat}
  for h3: {G.gate_43_3(pp, sel, t130, tP, a15, a19) == 0n : Nat}
  for h4: {G.gate_43_4(pp, sel, a8, a9) == 0n : Nat}
  for h5: {G.gate_43_5(pp, sel, a9, a18) == 0n : Nat}
  for h6: {G.gate_43_6(pp, sel, a9, a10) == 0n : Nat}
  Either<&1, &1, {a9 == 0n : Nat}, {a9 == 1n : Nat}> & {a15 == F.fadd(1n+pp, F.fadd(1n+pp, a6, F.fmul(1n+pp, a7, 2n)), F.fmul(1n+pp, a22, 1024n)) : Nat} & {a5 == F.fadd(1n+pp, F.fadd(1n+pp, a15, F.fmul(1n+pp, a8, t250)), F.fmul(1n+pp, a9, t254)) : Nat} & {F.fadd(1n+pp, a15, t130) == F.fadd(1n+pp, tP, a19) : Nat} & ({a9 == 1n : Nat} -> {a8 == 0n : Nat}) & ({a9 == 1n : Nat} -> {a18 == 0n : Nat}) & ({a9 == 1n : Nat} -> {a10 == 0n : Nat})

# NON-VACUITY: every hypothesis of gate_43 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 8, a6 = 5, a7 = 10, a8 = 0, a9 = 1, a10 = 0, a15 = 3, a18 = 0, a19 = 3, a22 = 0.
law gate_43_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & L.Le(8n, 10n) & L.Le(0n, 10n) & L.Le(1n, 10n) & L.Le(0n, 10n) & L.Le(3n, 10n) & L.Le(0n, 10n) & L.Le(3n, 10n) & {G.gate_43_0(10n, 1n, 1n) == 0n : Nat} & {G.gate_43_1(10n, 1n, 5n, 10n, 3n, 0n) == 0n : Nat} & {G.gate_43_2(10n, 1n, 1n, 5n, 8n, 0n, 1n, 3n) == 0n : Nat} & {G.gate_43_3(10n, 1n, 1n, 1n, 3n, 3n) == 0n : Nat} & {G.gate_43_4(10n, 1n, 0n, 1n) == 0n : Nat} & {G.gate_43_5(10n, 1n, 1n, 0n) == 0n : Nat} & {G.gate_43_6(10n, 1n, 1n, 0n) == 0n : Nat}
