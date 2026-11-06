"""Emit gates_model.bend, LAWS.bend and PROOF.bend for proofs/orchard_hash: the equations of
Orchard's Poseidon gates (full rounds, partial rounds, pad-and-add) and Sinsemilla gates
(initial y_Q, the round's secant line and y check), plus MerkleCRH's second conditional swap,
one law per gate plus a non-vacuity law. Shapes and proof method: ../orchard/lawgen.py.
The MDS entries are taken from the generated gates as they are (whose polynomials equal the
deployed verifying keys'); this script does not recompute them from the Poseidon spec.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "orchard"))
import lawgen as LG
Gt = LG.Gate

GATES = [
    Gt(21, "full round", range(3), note="Poseidon full round: the next state (a22, a18, a19) is MDS * (state + round constants)^5, with\nstate a6, a7, a8 and round constants f4, f5, f6; the MDS entries are the parameters c<hex>."),
    Gt(22, "partial rounds", range(4), note="Two Poseidon partial rounds per row (halo2_poseidon's pow5 chip): a5 is the first S-box output,\nthe last three equations equate the second half-round with the inverse-MDS image of the next state."),
    Gt(23, "pad-and-add", range(3), note="Poseidon absorption: next state = state + message."),
    Gt(24, "Initial y_Q", range(1), note="Sinsemilla (first chip): 2 * y_Q (fixed f0) from the first row's x_A, x_P, lambda_1, lambda_2."),
    Gt(25, "Sinsemilla gate", range(2), note="Sinsemilla round (first chip): secant line and y check; f10 is the q_s2 / q_s3 tag."),
    Gt(28, "Initial y_Q", range(1), note="Sinsemilla (second chip)."),
    Gt(29, "Sinsemilla gate", range(2), note="Sinsemilla round (second chip)."),
    Gt(30, "a' = b ⋅ swap + a ⋅ (1-swap)", range(3), note="The second conditional-swap instance (../orchard's cond_swap is gate 26)."),
]

HEADER = [
    "# The equations of Orchard's Poseidon and Sinsemilla gates, stated about the generated gate",
    "# polynomials (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend). These",
    "# gates are algebraic identities: each law turns 'the polynomial vanishes' into the equation",
    "# X == Y the chip intends, with an invertible selector and canonical cells. Fp = Z/p,",
    "# p = 1 + pp; large constants (MDS entries, 2^k) are parameters listed in gates_model.bend.",
]

if __name__ == "__main__":
    only = [int(x) for a in sys.argv[1:] for x in a.split()]
    LG.emit("orchard_hash", [g for g in GATES if not only or g.g in only], HEADER)
