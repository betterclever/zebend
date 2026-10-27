# Halo 2 oracle vectors (H0)

Ground truth from the official verifier (orchard 0.16, halo2_proofs 0.4, both vendored in
`../oracle/vendor` with recording hooks), for a real **Ironwood (NU6.3, post-NU6.3 circuit)**
Orchard-protocol bundle with **2 actions = 2 circuit instances in one proof**.

Regenerate: `cd ../oracle && cargo run --release` (≈2 s on the M5 Max; seeded, so deterministic).

| File | Content |
|---|---|
| `proof.bin` | the 7264-byte Halo 2 proof exactly as carried in the transaction |
| `instances.txt` | `instance[proof][column][row] hex`: 2 proofs × 1 column × 10 rows |
| `orchard_verify.txt` | 5487 records, every step of a successful verification (ends `result ACCEPT`) |
| `orchard_tampered.txt` | same with proof byte 3632 flipped: diverges at record 164, ends `result REJECT` |
| `params_vk.txt` | k, n, ω, ω⁻¹, δ, ζ, blinding factors, degrees, column counts, `transcript_repr`, `params.w`, `params.u`, 29 fixed commitments, 15 permutation commitments, every query `(column rotation)`, permutation columns `(kind column query_index)` (kind 0 advice, 1 fixed, 2 instance), gate/lookup shapes |
| `params_g.bin` | the 2^11 IPA generators G, 32-byte compressed Vesta points |
| `params_g_lagrange.bin` | the Lagrange-basis generators, used to commit to instance columns |

Every value is `name hex`, where hex is 32 bytes canonical little-endian (field elements) or
compressed Vesta points (x LE, sign of y in bit 255). Integers in `params_vk.txt` are u32 LE hex,
except the query/column lines, which are decimal. `phase` and `result` records are plain text.

## Sizes (Orchard post-NU6.3 circuit)

k = 11 (n = 2048), 10 advice / 29 fixed / 1 instance columns, 25 advice / 29 fixed / 1 instance
queries, 15 permutation columns (cs_degree 9, so chunks of 7: 3 permutation product sets),
3 lookups (input widths 1, 3, 3), 55 gates with 193 polynomials, blinding factors 5, quotient degree 8 (8 h-commitments).
Final MSM: 2173 terms (2048 G + w + u + 123 merged commitment terms).

## Transcript (BLAKE2b, recorded as `tx.*`)

- One running BLAKE2b-512 state, personalization `Halo2-Transcript`, never reset.
- Absorb point: `0x01 ‖ x ‖ y` with x, y the **affine coordinates** in Fq, 32 bytes LE each
  (NOT the compressed form). Absorb scalar: `0x02 ‖ repr` (32 bytes LE). Recorded as
  `tx.absorb_point` (compressed, for readability) and `tx.absorb_scalar`.
- Proof reads (`read_point`: 32-byte compressed; `read_scalar`: 32-byte canonical) absorb what they read.
- Squeeze: absorb `0x00`, then finalize a **clone** of the state (64 bytes, `tx.squeeze_hash64`);
  the challenge is that 512-bit little-endian integer reduced mod p (`tx.challenge`). The running
  state keeps the `0x00`.

## Verification order (one bundle = `num_proofs` = 2 circuits)

1. Instance commitments: `Σ_j instance[j]·G_lagrange[j]` per (proof, column), with no blinding term.
2. `vk_hash`: absorb scalar `transcript_repr`. Then absorb each instance commitment (point).
3. Read advice commitments: 10 per proof → squeeze **θ**.
4. Read lookup permuted commitments: (input, table) per lookup per proof → squeeze **β**, **γ**.
5. Read permutation product commitments: 3 per proof. Then lookup product commitments: 1 per lookup per proof.
6. Read vanishing random commitment → squeeze **y** → read 8 h-commitments → squeeze **x**.
7. Read scalars: instance evals (1 per proof), advice evals (25 per proof), fixed evals (29),
   vanishing random eval (1), permutation common evals (15), per proof the permutation sets
   (eval, next, last for every set except the last, which has eval, next), then per proof per
   lookup (product, product_next, permuted_input, permuted_input_inv, permuted_table).
8. Lagrange evals for rotations −(bf+1) … 0: `l_r = ω^r · (xⁿ−1)·(1/n) / (x − ω^r)` (halo2's
   `barycentric_weight` = 1/n). l_last = rotation −6, l_blind = sum of rotations −5…−1, l_0 = rotation 0.
9. Expressions, **per proof**: gate polys (193; `../gen/orchard_cs.bend: gate_polys`), permutation
   terms (7), lookup terms (5 per lookup). The h numerator folds all of them, proof 0 then proof 1,
   as `acc·y + v`; `expected_h_eval = numerator / (xⁿ − 1)`. The h commitment is
   `Σ_i xⁿⁱ · H_i`. This check is only enforced through the opening argument.
10. Multiopen (`phase multiopen`): squeeze **x1**, **x2**. Queries in this order: per proof
    (instance, advice, permutation sets at x / ωx, then sets except the last at ω^(−6)x, lookups at
    x, x, x, ω⁻¹x, ωx), then fixed, permutation common, vanishing (h MSM at x, random at x).
    Grouping (`construct_intermediate_sets`): commitments are keyed by **source identity, not
    value**; point indices and set indices are numbered by first appearance; each commitment's
    evals are ordered by its sorted point indices. Recorded: `point_set[s][i]` and
    `commitment_map[c].{set_index,commitment,eval[]}`. Accumulation with powers of x1 walks the
    commitment map **in reverse**. Read q′ → squeeze **x3** → read one u per point set →
    `msm_eval` (Lagrange-interpolate each set at x3, divide by Π(x3 − point), fold with x2) →
    squeeze **x4** → `v`.
11. IPA (`phase ipa`): G₀ scalar −= v; read S → squeeze **ξ**, add ξ·S; squeeze **z**; 11 rounds:
    read L, R, squeeze u_j, add u_j⁻¹·L + u_j·R; read c, f; `b = Π_j (1 + u_{k−1−j}·x3^(2^j))`;
    U scalar += −c·b·z; W scalar += −f; G scalars += s(u, −c), the standard IPA s-vector.
12. Accept iff the final MSM (`final_msm.scalar[i]`, `final_msm.base[i]`) is the identity.
    Equal points are merged (scalars added), so compare sums, not term lists.

## Codegen

`../gen/orchard_cs.bend` (imports `../../../research/gpu-scan/zcrypto.bend` as `Z`; Fp in Montgomery form)
has the metadata and `gate_polys(a, f, i)` / `lookup_<l>_inputs` / `lookup_<l>_tables`. It is
printed from an SSA IR that is evaluated in Rust against this dump on every oracle run (392
values: all gate polys and all lookup product terms, both proofs). `../gen/orchard_cs_selftest.bend`
runs the generated gates in Bend on proof 0's evaluations: **193 / 193 match halo2**.

## Toy circuit (for fast iteration)

`toy_*` files are the same dump / export for `../oracle/src/toy.rs`: c = a·b (custom gate),
a ∈ [0, 8) (lookup), c copied to the public input (permutation), k = 5, **one proof** (a = 5, b = 7,
public input 35). Proof 1472 bytes, 328 records. `../gen/toy_cs.bend` is its codegen;
`../gen/toy_cs_selftest.bend` prints `gate polys matching halo2: 1 / 1`. `toy_tampered.txt` flips
byte 736 and ends `result REJECT`.
