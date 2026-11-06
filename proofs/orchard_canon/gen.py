"""Emit gates_model.bend, LAWS.bend and PROOF.bend for proofs/orchard_canon: the decomposition
and canonicity gates of Orchard (base-field scalar canonicity, Sinsemilla message-piece
decompositions, CommitIvk and NoteCommit canonicity), one law per gate plus a non-vacuity
law. The shapes and the proof method are in ../orchard/lawgen.py. Gate and constraint names:
../orchard/names/names.txt.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "orchard"))
import lawgen as LG
Gt = LG.Gate

GATES = [
    Gt(20, "Canonicity checks", range(8), impl={"a8"},
       note="a8 = alpha_2 (the MSB part), a7 = alpha_1, a24 = z_84_alpha; MSB = 1 forces alpha_1 = 0 and the\nhigh parts of alpha_0 to vanish (the cross-row canonicity argument is not covered)."),
    Gt(27, "Decomposition check", range(4), note="Sinsemilla MessagePiece decomposition (first Sinsemilla chip)."),
    Gt(31, "Decomposition check", range(4), note="Sinsemilla MessagePiece decomposition (second Sinsemilla chip)."),
    Gt(32, "CommitIvk canonicity check", range(14), impl={"a4", "a14"},
       note="a4 = b_1, a14 = d_1: the high bits whose value 1 forces the canonicity conditions."),
    Gt(33, "NoteCommit MessagePiece b", range(3), same_as=[44]),
    Gt(34, "NoteCommit MessagePiece d", range(3), same_as=[45]),
    Gt(35, "NoteCommit MessagePiece e", range(1), same_as=[46]),
    Gt(36, "NoteCommit MessagePiece g", range(2), same_as=[47]),
    Gt(37, "NoteCommit MessagePiece h", range(2), same_as=[48]),
    Gt(38, "NoteCommit input g_d", range(5), impl={"a18"}, same_as=[49], note="a18 = b_1."),
    Gt(39, "NoteCommit input pk_d", range(4), impl={"a18"}, same_as=[50], note="a18 = d_0."),
    Gt(40, "NoteCommit input value", range(1), same_as=[51]),
    Gt(41, "NoteCommit input rho", range(4), impl={"a18"}, same_as=[52], note="a18 = g_0."),
    Gt(42, "NoteCommit input psi", range(5), impl={"a18"}, same_as=[53], note="a18 = h_1."),
    Gt(43, "y coordinate checks", range(7), impl={"a9"}, same_as=[54], note="a9 = k_3."),
]

HEADER = [
    "# Per-row soundness of Orchard's decomposition and canonicity gates, stated about the generated",
    "# gate polynomials (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend).",
    "# Fp = Z/p, p = 1 + pp. Hypotheses, all explicit: nzd<k> (no zero divisors among canonical",
    "# elements, true for prime p; one copy per product the proof splits), l1 / lc<c> (the small",
    "# constants used are below p), the selector is invertible, the cells named l<cell> are",
    "# canonical, and every listed polynomial of the gate vanishes on the row. Large constants are",
    "# parameters (values in gates_model.bend). Names in quotes are halo2's gate names",
    "# (../orchard/names/names.txt); cells are the gate's queried evaluations.",
]

if __name__ == "__main__":
    only = [int(x) for a in sys.argv[1:] for x in a.split()]
    LG.emit("orchard_canon", [g for g in GATES if not only or g.g in only], HEADER)
