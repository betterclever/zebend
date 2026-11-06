"""Emit gates_model.bend, LAWS.bend and PROOF.bend for proofs/orchard_ecc: the per-row facts of
Orchard's ECC-chip gates (field addition, short range-check bitshift, point witnessing,
variable-base mul loop booleanity and secant/gradient lines, overflow check, fixed-base window
range checks and coordinates, short fixed-base sign handling), one law per gate plus a
non-vacuity law. Shapes and proof method: ../orchard/lawgen.py. The hand-written ECC laws
(complete and incomplete addition, the LSB check, the short-mul sign) are in ECC.bend and
PROOF_ECC.bend, about the same gates_model.bend.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "orchard"))
import lawgen as LG
Gt = LG.Gate

GATES = [
    Gt(1, "Field element addition: c = a + b", range(1)),
    Gt(2, "Short lookup bitshift", range(1),
       note="a11 = word, a10 = inv_two_pow_s (constrained to 2^-s elsewhere), a9 = shifted word."),
    Gt(3, "witness point", range(2), split_sel=True, either={0, 1},
       note="halo2 writes q_point * x * on_curve and q_point * y * on_curve: the cell is part of the\nproduct, so each constraint gives x == 0 (resp. y == 0) or the curve equation y^2 - x^3 == 5."),
    Gt(4, "witness non-identity point", range(1), note="a1 = y, a0 = x: y^2 - x^3 == 5."),
    Gt(5, "incomplete addition", range(2), note="Kept as the raw polynomials; their meaning is incomplete_add in ECC.bend."),
    Gt(6, "complete addition", range(12), note="Kept as the raw polynomials; their meaning is the cadd_* laws in ECC.bend."),
    Gt(7, "q_mul_1 == 1 checks", range(1), note="init y_a, hi half (inv2 = 1/2 mod p)."),
    Gt(10, "q_mul_1 == 1 checks", range(1), note="init y_a, lo half."),
    Gt(8, "q_mul_2 == 1 checks", [2, 4, 5], note="Incomplete-addition loop, hi half: bool_check, secant_line, gradient_2. x_p_check /\ny_p_check are ../orchard_mul's base_anchored."),
    Gt(9, "q_mul_3 == 1 checks", [0, 2, 3], note="Last loop row, hi half: bool_check, secant_line, gradient_2."),
    Gt(11, "q_mul_2 == 1 checks", [2, 4, 5], note="Incomplete-addition loop, lo half."),
    Gt(12, "q_mul_3 == 1 checks", [0, 2, 3], note="Last loop row, lo half."),
    Gt(14, "overflow checks", range(5), impl={"a23"}, either={4},
       note="Constraints in order: s_check, recovery, lo_zero, s_minus_lo_130_check, canonicity. a23 = k_254, the\nbit whose value 1 forces the lo_zero and s_minus_lo_130 conditions; a22 is an inverse witness."),
    Gt(15, "LSB check", range(3), note="bool_check; lsb_x / lsb_y are kept raw here, their meaning is lsb_check in ECC.bend."),
    Gt(16, "range check", range(1), note="Fixed-base running sum: each 3-bit window a4 - 8 * a14 is at most 7."),
    Gt(17, "Running sum coordinates check", range(3),
       note="check x: x is the Lagrange interpolation of the window (fixed coefficients f0, f3..f9);\ncheck y: u^2 == y + z (f2 = z); on-curve."),
    Gt(18, "Full-width fixed-base scalar mul", range(4), note="As gate 17 for a window a4, plus the window range check a4 <= 7."),
    Gt(19, "Short fixed-base mul gate", range(4), either={2},
       note="a5 = last window bit, a4 = sign, a1 / a3 = the y-coordinate before / after the sign: sign^2 == 1,\na3 == +/- a1, a3 == sign * a1 (sign = +/-1 itself is short_sign in ECC.bend)."),
]

HEADER = [
    "# Per-row soundness of Orchard's ECC-chip gates, stated about the generated gate polynomials",
    "# (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend). Fp = Z/p,",
    "# p = 1 + pp. Hypotheses, all explicit: nzd<k> (no zero divisors among canonical elements,",
    "# true for prime p; one copy per product the proof splits), l1 / lc<c> (the small constants",
    "# used are below p), the selector is invertible, the cells named l<cell> are canonical, and",
    "# every listed polynomial of the gate vanishes on the row. Large constants are parameters",
    "# (values in gates_model.bend). Names in quotes are halo2's gate names",
    "# (../orchard/names/names.txt); cells are the gate's queried evaluations.",
]

# Gates whose polynomials are only emitted into gates_model.bend (for ECC.bend), with no
# generated law: their raw form says nothing a reader can use; the hand-written laws do.
MODEL_ONLY = {5, 6, 15}

if __name__ == "__main__":
    only = [int(x) for a in sys.argv[1:] for x in a.split()]
    LG.emit("orchard_ecc", [g for g in GATES if not only or g.g in only], HEADER, model_only=MODEL_ONLY)
