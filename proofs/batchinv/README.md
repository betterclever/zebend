# batchinv: Montgomery batch inversion returns the inverses (9 laws)

`BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict`: ALL PROOFS CHECK (< 1 s, no `@unsafe`).

## Scope

`model.bend` copies, over the Z/p model (p = 1 + bp, canonical Nats; opt_gates' `T.fmul`,
`T.finv(x) = x^(p−2)`), statement by statement:

* `crypto/field3/fp64.bend`'s `bi_pre`, `bi_back`, `bi_go`, `batch_inv` (fq64.bend's are the
  same text with `Fq` for `Fp`);
* `research/perf4/v/vlib.bend`'s `nz1`, `z0`, `binvs` (zeros replaced by 1, inverted, masked
  back to 0), the inversion batching opt_gates trusts;
* `research/perf4/lib/msm_ba.bend`'s own `prefix`, `back`, `top_or_one`, `batch_inv` (used by
  `normalize` and the bucket rounds).

Substitutions: `Fp.mul` is `T.fmul`, `Fp.one()` is 1, `Fp.inv` is x^(p−2) mod p,
`Fp.is_zero(x)` is `x == 0`, `Fp.sel(Bool.to_u32(c), a, b)` is "if c then a else b". That
`Fp.mul` etc. implement Z/p for Pallas' p is the field-arithmetic assumption (`fieldmul/`).

## Laws

| Law | Statement |
|---|---|
| `bi_inverts` | For every p ≥ 2 and every canonical list xs: if the one inversion the code performs succeeds (`prod · prod^(p−2) == 1`, prod the product the code computes), then `Inv(xs, batch_inv(xs))`: same length, `x·y == 1` and y canonical pointwise. No primality. |
| `bi_finv` | If p is prime in the form of Fermat's little theorem (`Fermat(bp)`) and every input is nonzero, `batch_inv(xs) == [x^(p−2) for x in xs]`. |
| `bi_zero` | What a zero input does (p ≥ 3): the product is 0, `0^(p−2) = 0`, and every output is 0 (same length). The callers never pass a zero (binvs masks zeros; msm_ba passes `z_or_one` and `den`'s 1). |
| `binvs_finv` | `binvs(xs) == [x^(p−2) for x in xs]` for every canonical list, zeros included (0 ↦ 0): exactly how opt_gates reads it. |
| `ba_is_bi` | msm_ba's `batch_inv` computes the same list as fp64's, for every input. |
| `fermat_5`, `bi_inverts_sat`, `bi_finv_sat`, `bi_zero_sat` | Non-vacuity: Fermat holds for p = 5, and each law's other hypotheses hold for concrete lists. |

`Fermat(bp)` is stated for a whole list of nonzero canonical elements at once, "each x has
x·x^(p−2) == 1", because Bend lets a proof use a function hypothesis only once. It holds
exactly when p is prime; that Pallas' and Vesta's p are prime is not proven.

## How

`lemmas.bend`: `pre_ok` describes the reversed prefix products (`Rr`), `back_ok` walks back
with the invariant "inv inverts the current prefix product", each step a ring identity
checked by `ring/cert.bend` (`certs.bend`, from `gen.py`). The field version shows that
x ↦ x^(p−2) is multiplicative, so the product of Fermat-invertible elements is inverted by
its own x^(p−2), and inverses are unique (another ring identity).

## Reproduce

```sh
python3 gen.py          # certs.bend; needs sympy
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict
```
