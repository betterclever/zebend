# Halo 2 verifier in Bend: shared contract

Goal: verify real Orchard/Ironwood Halo 2 proofs (halo2_proofs 0.4, as used by orchard 0.16)
in Bend 2, batched on the Metal GPU, checked stage by stage against the official Rust verifier.

Fields and curves (Pasta):
- `Fp` = pallas::Base = vesta::Scalar. The circuit field: witnesses, evaluations, challenges.
  p = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
- `Fq` = vesta::Base = pallas::Scalar. Coordinates of commitments (Vesta points).
  q = 0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001
- Commitments in the proof, the VK and the params are **Vesta** points: y² = x³ + 5 over Fq.

## Directory ownership (do not write outside your own)
- `oracle/`, `gen/`, `vectors/`: Rust oracle + codegen (workstream H0)
- `lib/`: Bend field / curve / MSM library (workstream H1)
- `verifier/`: Bend transcript + verifier algorithm (workstream H2)
- `CONTRACT.md`: owned by the coordinator; propose changes in your report

## Data encoding (everything H0 writes, everything H1/H2 read)
- A field element or a compressed point is 32 bytes = 8 × U32 words, little-endian,
  canonical (not Montgomery). Text vectors use 64-char lowercase hex of the 32 bytes.
- Points: halo2 / pasta 32-byte compressed encoding (x LE, sign of y in the top bit).
  Identity encodes as all zeros.
- Vector files: `vectors/*.txt`, one `name hex` pair per line, so a Bend program or a script
  can read them. Large tables (params G: 2^11 points) also go out as `vectors/*.bin` raw 32-byte records.

## Bend library API (H1 provides; H2 codes against it)
`lib/fp.bend` and `lib/fq.bend` each define a field type with:
`zero one from_u32 add sub neg mul sqr inv pow is_eq from_words(8×U32 canonical) to_words`.
`lib/vesta.bend`: projective `Vesta` + affine form with `identity is_identity add double neg
scalar_mul(Fp) decompress(words) -> Maybe encode(point) -> words`, complete formulas (a = 0, b = 5).
`lib/msm.bend`: `msm(points, scalars) -> Vesta`, parallel (`!`-able), for n up to 4096.
Until H1 lands, H2 may use `../../research/gpu-scan/zcrypto.bend` (its `F` IS Fp in Montgomery form;
convert with to_mont/from_mont) for Fp arithmetic.

## Generated circuit (H0 provides)
`gen/orchard_cs.bend`: constants describing the Orchard VerifyingKey's ConstraintSystem
(column counts, every query (column, rotation), permutation columns, lookups, degree,
blinding factors, k, omega, n) plus a def that evaluates all custom gates' polynomials
from the queried evaluations, combined with powers of y the way halo2 does. Ditto for the
toy circuit H2 uses (`gen/toy_cs.bend`), if H0 gets there; otherwise H2 hand-writes its toy one.
