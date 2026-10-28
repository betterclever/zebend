# opt_gates: the optimised verifier computes what the generated one computes

`research/perf4/v/opt_gates.py` rewrites the generated Halo 2 verifier, lever F of perf4. It
hoists list reads, folds `x·1`, `x·0`, `x+0`, `x−0` and `−0`, turns `a+(−b)` into `a−b`,
shares common subexpressions with `·` and `+` treated as commutative, drops dead definitions,
and batches field inversions. This directory proves that the rewritten code computes the same
values as the original. It covers every function the script touches, in both generated
verifiers:

| tag | original | optimised | used by |
|---|---|---|---|
| `bt` | `orchard_bt.pre_opt.bend` | `orchard_bt.bend` | `batch_main`, the deployed batch verifier |
| `ba` | `orchard_ba.pre_opt.bend` | `orchard_ba.bend` (`--keep-logs`) | `bundle_ba`, the single verifier |

`orchard_ba_nu62.bend` and `orchard_ba_prenu62.bend` differ from `orchard_ba.bend` only outside
the touched bodies (checked: the bodies are byte-identical). They swap in other constants, and
the laws hold for every value of the constants.

`BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict` prints ALL PROOFS CHECK. That is 56 laws, about
40 s, ~250 MB, with no `@unsafe`.

## The statement

`gen.py` translates each touched function (`pp_expr`, `pp_expr_1..17`, `ex_loop`, `pp_qa`,
`qa_loop`, `verify`, `verify_1`, `verify_2`) of the original file and of the optimised file:

* Every line `+v = L.bmul/badd/bsub/bneg/binv/bfat(...)` becomes a term (`term.bend`'s `T`).
  Terms are built over atoms (the function's parameters, the list reads `L.bfat(n, xs)`, and the
  result of every other call) and over the constants `K<i>()`.
* Every other line is a statement: a transcript call, a point or MSM operation, a log line, a
  `match`, the tail call, the result. It is split into a skeleton (its text with every variable
  replaced by `#`) and the terms of the variables it reads.

`gen.py` then checks the following mechanically, and stops otherwise:

1. The two files are identical outside the touched bodies.
2. `K0()` is the field's one and `K1()` its zero.
3. Each touched body has the same number of statements in both files, with identical skeletons,
   in the same order.

The remaining question is whether the statements receive equal values. Each law
`<tag>_<function>` (split into `_part<k>` when large, so that the kernel's fuel suffices) says:

> In Z/p, for **every** p ≥ 2, **every** value of the atoms and **every** value of the constants
> K2, K3, … (K0 = 1, K1 = 0), each value the original body passes to its statements equals the
> value the optimised body passes in the same position.

Pairs that are the same atom on both sides (e.g. a parameter passed through) are trivially equal
and left out. That leaves 517 obligations over 1,053 statements.

From these laws, the two bodies compute the same thing by induction over the statements. The
same statements run in the same order on equal arguments, so the calls return equal results,
which are again equal atoms. Calls between the touched functions (`pp_expr` → `pp_expr_1` →
…, `verify` → `verify_1` → `verify_2`) are statements like any other, so the argument composes
over the call chain. This last step is a short argument on paper, not a Bend proof.

In `ba` every one of the 215 values logged as `"expr"` is its own obligation. That covers the 193
gate polynomials and the permutation and lookup expressions, one by one. In `bt` the logs are
gone, so the gates are covered through the accumulated `h` that the tail calls pass on.

## How it is proven

`term.bend` defines the meaning `ev` of a term in Z/p (`p = 1 + bp`, canonical Nats), and a
normaliser `nf` whose smart constructors apply exactly the script's rewrite rules:

* `x·1 = 1·x = x`, `x·0 = 0·x = 0`, `x+0 = 0+x = x`, `x−0 = x`, `−0 = 0`;
* `a+(−c) = a−c` and `(−c)+b = b−c`, applied before folding, in the script's order;
* the operands of `+` and `·` sorted by a structural order, which covers the commutative CSE.

`sound.bend` proves `nf_sound` once, for every term: `ev(nf(t)) == ev(t)`. That is one lemma per
rule, on canonical values, built on `prims/natlib.bend`'s `mod` lemmas. From it follows `equiv`:
two term lists with equal normal forms have equal values. Each law is then proved by
`S.equiv(..., {==})`, where the checker computes both normal forms. Sharing (CSE), dead code and
hoisting need no rule, because they do not change a term.

**Check that the method can fail:** a copy of `orchard_bt.bend` with the operands of one
subtraction swapped in `pp_expr_5` (`L.bsub(fat_fe_18, K4())`) makes `bend PROOF.bend` fail on
that law. Reproduce with `OPT_GATES_V=<dir with the four files> OPT_GATES_OUT=<dir> python3 gen.py`.

## What is not covered (trusted steps)

* **Inversion batching (rule 7).** `L.bfat(k, L.binvs([L.ub(x0), ..]))` is read as
  `L.binv(xk)`. That is, `vlib.binvs` is taken to return the pointwise inverses, with 0 ↦ 0,
  as its comment says. It is Montgomery's trick: `Fp.batch_inv` plus the zero masks `nz1`/`z0`.
  It is tested (42/42 `-v` traces byte-identical, 392,806/392,806 verdicts) but **not proven
  here**. The rule touches 19 inversions in 5 groups per file.
* **Log removal in `bt`.** `L.blgf` and `L.log_list` lines are erased from the original as the
  script erases them. The batch verifier never reads `St.log`. That is a reading of `vlib.bend`
  (only `print_log` reads it), not a proof. `ba` keeps the logs, and there they are checked
  statements.
* **The field model.** The laws are about Z/p on canonical Nats. That `Fp.mul`/`add`/`sub`/`neg`
  (Montgomery form, 64-bit limbs) implement Z/p for Pallas' p is tested, not proven (see
  `fieldmul/`). Only ring identities are used, so p need not be prime here.
* **The translator.** `gen.py`'s parsing is not proven. It is line-local and the same for both
  files, and the mutation test above exercises it.

## Files and reproduce

| File | What |
|---|---|
| `term.bend` | terms, `ev` (Z/p), the structural order, the rule-applying normaliser `nf` |
| `sound.bend` | `canon`, the per-rule lemmas, `nf_sound`, `equiv` |
| `gen.py` | translator and statement checker; writes `gen_bt.bend`, `gen_ba.bend`, `LAWS.bend`, `PROOF.bend` |
| `gen_bt.bend`, `gen_ba.bend` | GENERATED: `o_<f>` (original) and `n_<f>` (optimised) obligation lists |

```sh
python3 gen.py        # after any change to research/perf4/v/orchard_b{t,a}*.bend
BEND_NO_TELEMETRY=1 ../../tools/heavy.sh bend PROOF.bend --verdict
```
