# ring: identities in Z/p, checked from certificates

A library, no laws of its own. `curve/` and `batchinv/` use it to prove polynomial identities in
Z/p, modulo hypotheses such as "y² = x³ + b" or "Z·zi = 1", for every p ≥ 2.

| File | What |
|---|---|
| `expr.bend` | expressions `E` (variables, constants, `+ - ·`, negation, and `Pp` = p − 1), their value `ev` in Z/p (opt_gates' `T.fadd` etc.), and their reading `nv` as a Nat polynomial in which x − y is x + (p−1)·y. `ev_nv`: for canonical variables, `ev(t) == nv(t) mod p`. |
| `poly.bend` | a normaliser `nf` for Nat polynomials (sorted monomials, binary coefficients) and its soundness `nf_ok`: `nv(t) == evp(nf(t))` for every expression, p and assignment. |
| `cert.bend` | `cert_ok` / `cert_ok2` / `cert_nv`: if `nv(t1) + Σ cⱼ·nv(bⱼ) + K1·p` and `nv(t2) + Σ cⱼ·nv(aⱼ) + K2·p` are equal Nat polynomials, and the hypotheses `ev(aⱼ) == ev(bⱼ)` hold, then `ev(t1) == ev(t2)` in Z/p. |
| `certgen.py` | finds the certificate (cⱼ, K1, K2) with sympy: division by the hypotheses, Buchberger with cofactors when plain division leaves a remainder, then the Nat lifting. Refuses certificates that need non-integer coefficients. |
| `lemgen.py` | writes `lem_<name>`, the identity stated over Nat-level code (`T.fadd(bp, ..)`) and proven by `cert_nv`. |

Nothing in the Python is trusted: Bend recomputes every normal form and checks every step.
Only ring operations are used, so p need not be prime.

**Checkpoints.** Bend's evaluator copies `+` arguments in full and the kernel has a fixed fuel
per conversion, so a large identity cannot be normalised in one step. `certgen.Emitter` cuts
the expression tree at every node whose normal form has 40 terms or more: it writes the
node's normal form as a literal `N_w`, checks the one operation that produces it from its
children's literals (`N_c`, a closed computation), and proves `nv(N) == evp(N_w)` from the
children's lemmas and `plus_ok` / `pmul_ok` (`N_ok`). Coefficients are binary (`Bn`), so the
checker never builds a large unary Nat.

**Why Nat polynomials.** Z/p's subtraction is (x + (p − y)) mod p. Reading it as x + bp·y
with bp = p − 1 gives a Nat polynomial congruent to the value, so a Z/p identity becomes a
Nat identity up to multiples of p (the K terms). The normaliser then only needs the Nat
semiring laws of `field/natlemmas.bend` and `prims/natlib.bend`; Z/p enters once, in
`ev_nv` and `cert_core`.
