# fixedbase: fixed-base scalars, sparse to dense, and the comb tables (9 laws)

`BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict`: ALL PROOFS CHECK (< 1 s, no `@unsafe`).

Points and scalars follow `msm_chunk/` and `msm_bucket/`: an identity between sums of
multiples of points that holds in the free model holds in every abelian group.

## bt.fx_dense: the sparse-to-dense step

`model.bend` copies `research/perf4/v/bt.bend`'s `fx_sum`, `fx_dense_go`, `fx_dense` over
msm_chunk's (Nat, +) model (a point is a Nat, scalars are Nats; `Fp.sel(Bool.to_u32(c), a, b)`
is "if c then a else b"; the U32 base index is a Nat, which `(i + 1 : U32)` never wraps below
46). A proof's fixed-base terms are a sparse list `FX{i, s}` (s on fixed base i); fx_dense turns
them into one summed scalar per base, which msm_chunk's `merge_ok` takes as given.

| Law | Statement |
|---|---|
| `fx_dense_sparse` | For every list of bases fs and every list of terms: `msm(fs, fx_dense_go(len fs, 0, xs)) == Σ s·fs[i]` over the terms (a term past the last base contributes nothing). |
| `fx_dense_46` | The same for `fx_dense` itself, when there are 46 bases. |
| `fx_merged` | With the G scalars in front, as `bt.leaf` builds `gx = gss ++ fx_dense(fx)` against `gs ++ fixed`: the G part plus the fixed terms. |
| `fx_46_sat` | Non-vacuity: a list of 46 bases exists. |

Proof (`fxlemmas.bend`): `fx_sum` is linear in its accumulator, so the dense vector of a
list of terms is the sum of the dense vectors of single terms, and one term s on base j
lands as s·fs[j] (the `Nat.is_eq` tests are discharged by three small lemmas).

## lib/fixb.bend: comb tables

`comb.bend` copies `research/perf4/lib/fixb.bend`'s `tbuild`, `tget`, `child`, `head_ap`,
`pow2`, `mults`, `dbl_n`, `wbases`, `window`, `step`, `add_d` and `walk`, over the free
commutative monoid on {P, −P} (`SP{a, b}` is a P + b(−P); point addition is +,
`BA.signed_pt` swaps). Substitutions:

* `BA.normalize` (projective to affine, batch inversion) is the identity on group elements;
  `BA.ANone` is the identity point, and `add_d(acc, ANone)` is acc + 0;
* `tget`'s index i = m − 1 is given by its bits, most significant first, and the parameter
  order is (d, t, bits). **Assumed, not proven:** that `(U32.shrn(i, k) .&. 1)` is bit k of i
  (prims/ does not prove shift and mask semantics);
* `fixb.table` builds the windows with `wpar`, a parallel split; here they are the plain
  per-base map `windows`. That `wpar` computes that map (given enough fuel) is not proven.

| Law | Statement |
|---|---|
| `comb_entry` | For every window base B and every d-bit index bs: the table built from [B, 2B, .., 2^d B] returns (1 + value(bs))·B at bs. |
| `comb_walk` | `walk` over the tables of any bases B_j adds Σ_j ±m_j·B_j to the accumulator, when each digit is 0 or its bits are those of m_j − 1 (`DigOk`). |
| `comb_bases` | `wbases(n, c, P)[j] == 2^(c·j)·P`. |
| `comb_mul` | Together: the comb multiplication over `wbases(n, c, P)` is acc + Σ_j ±m_j·2^(c·j)·P, the Σ digitᵢ·2^(w·i)·G of the specification. |
| `comb_sat` | Non-vacuity: digits meeting `DigOk` for c = 2. |

That the digits recode the scalar (`msm_ba.recode`, with carries) is not covered here
(`msm_bucket/` proves the carry-free recoding msm9 uses), nor are `GT.msm`'s fixed-base tables.

## Reproduce

```sh
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict
```
