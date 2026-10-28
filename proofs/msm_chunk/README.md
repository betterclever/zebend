# msm_chunk: chunking and merging preserve the MSM

perf4's batch verifier does not run one big MSM. It merges the proofs' fixed and shared bases
(lever A). It splits the per-proof terms into groups of proofs (`bt.groups`), splits each
group's terms into chunks (`msm_par.mpar`), runs the bucket MSM per chunk, and adds the
results. This directory proves that these steps compute the plain MSM.

`BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict`: ALL PROOFS CHECK (< 1 s, no `@unsafe`).

## The model and its link to the code

`model.bend` copies the control structure of `research/perf4/lib/msm_par.bend` (`mpar`,
`pick_cnt`, `msm_auto`) and `v/bt.bend` (`groups`, `small_g`, `all_groups`, `flat_p`/`flat_w`,
`leaf`, `none`, `join`, `vadd`, `scale_words`/`scale_list`, `check`). The same matches, the
same split points (`Nat.div(len·h, cnt)`, `Nat.div(cnt, 2)`), the same `List.take`/`List.drop`
and the same fuel are kept. The only substitutions are:

* points are Nats, point addition (`V.add`, `VL.add`) is `+`, and `k·P` is `k * P`;
* scalars are Nats: `Fp.add` becomes `+`, `Fp.mul` becomes `*`, and `Fp.to_words` is dropped;
* one chunk's bucket MSM `BA.msm9` is replaced by its specification `msm` (Σ sᵢ·Pᵢ over the
  pairs, ending with the shorter list, as `msm_ba.fill` does). `msm9` itself is `msm_bucket/`;
* the accumulator's `ok`, `n` and `bad` fields, which never touch the MSM, are dropped. The
  parallel tree that builds the accumulator is any binary tree (`Tree`).

**Why Nat points suffice.** Every expression here is a sum Σ cᵢ·Pᵢ whose coefficients cᵢ
depend only on the scalars and the list shapes, never on the point values. An identity between
two such sums that holds for every Nat value of every Pᵢ has equal coefficients: set one Pᵢ to
1 and the others to 0. So it holds in every commutative monoid, including the Pallas/Vesta
group.

Scalars: in the code, scalars are elements of F_r, added and multiplied mod r. Here they are
Nats. Since r·P = 0 in the group, (a + b mod r)·P = (a + b)·P and (a·b mod r)·P = (a·b)·P,
so the Nat identities carry over.

## Laws (`LAWS.bend`)

| Law | Statement |
|---|---|
| `msm_split` | For any lists and **any** m: `msm(ps, ss) == msm(take(ps,m), take(ss,m)) + msm(drop(ps,m), drop(ss,m))`. |
| `mpar_ok` | `mpar(fuel, cnt, len, ps, ss) == msm(ps, ss)` for **every** fuel, chunk count and length. There is no hypothesis: whatever the split points, the chunk sums add up. |
| `msm_auto_ok` | `msm_auto(ps, ss) == msm(ps, ss)`. |
| `groups_ok` | If the per-proof lists are `Aligned` (same number of proofs, each proof's point and scalar lists of one length), then `groups(fuel, small, cnt, ps, ss)` equals Σₖ msm(psₖ, ssₖ), for every fuel, flag and count. |
| `aligned_sat` | Non-vacuity: `Aligned(ps, ps)` for every `ps`. |
| `shared_base` | `msm(bases, vadd(a, b)) == msm(bases, a) + msm(bases, b)`. This is s₁·P + s₂·P = (s₁+s₂)·P, base by base, for the summed shared-base scalars. |
| `merge_ok` | **The merged batch check.** Take any tree of weighted proofs, where each proof has its own terms (ops, oss) and its scalars gx on the shared bases G ++ fixed. If each proof's ops and oss have one length (`WF`), then the value `bt.check` tests for the identity, `all_groups(ps, ss) + msm_auto(bases, gx)` on the accumulator `acc(t)`, equals Σₖ rₖ·(msm(opsₖ, ossₖ) + msm(bases, gxₖ)). That is the random linear combination of the per-proof MSMs. |
| `merge_sat` | Non-vacuity: for every tree, giving each proof as many scalars as points satisfies `WF`. |

## Not covered

* `fx_dense`: turning a proof's sparse fixed-base terms `(i, s)` into the dense vector `gx`
  (`fx_sum` per base). The model takes `gx` as given.
* That `BA.msm9` computes `msm`: that is `msm_bucket/`, with its own model.
* `GT.msm`, the fixed-base table path (`check_tab`), which perf4 does not recommend deploying.
* That the Bend code is byte-for-byte this model. It is a hand copy with the substitutions
  listed above.

## Files and reproduce

`model.bend` is the model; `lemmas.bend` has the proofs (split, chunking, flattening, the
accumulator tree); `LAWS.bend` and `PROOF.bend` hold the laws and their proofs.

```sh
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict
```
