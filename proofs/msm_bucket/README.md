# msm_bucket: the signed-digit bucket method computes the MSM

`research/perf4/lib/msm_ba.bend`'s `msm9` is the MSM every chunk runs. It is a carry-free
signed-digit Pippenger:

1. Each scalar is offset, k' = k + H, and cut into c-bit windows uⱼ.
2. Each window gives a signed digit uⱼ − 2^(c−1) as a magnitude and a sign (`sd_u`, `digit9`).
3. Per window, each point goes, negated if the sign is negative, into the bucket of its
   magnitude (`put`, `fill9`).
4. Buckets are summed by rounds of pairwise additions (`rounds`, `rbucket`).
5. A running sum from the highest bucket down gives Σ_d d·B_d (`reduce`, `add_b`).
6. The windows are combined by a halving tree with h·c doublings (`wrange9`, `dbl_n`).

This directory proves that this algorithm, as the code structures it, computes Σᵢ kᵢ·Pᵢ.

`BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict`: ALL PROOFS CHECK (< 1 s, no `@unsafe`).

## The model and its link to the code

`model.bend` copies `sd_u`/`digit9`, `signed_pt`, `put`, `fill9`, `rbucket`/`rebuild`, `small`,
`rounds` (fuel 32), `add_b`, `reduce`, `window_sum9` (including its `List.reverse`), `dbl_n`,
`wrange9` (fuel 9, `cnt >> 1` as `Nat.div(cnt, 2)`) and `msm9`. The substitutions:

* **Points.** An input point is `AP{p, n}`: two free generators, p for P and n for −P. `ap_neg`
  (via `signed_pt`) picks n. After that the algorithm only adds points. Point addition
  (`psum`'s affine and complete additions, `VL.add`, `VL.double`) becomes `+` on Nats, and the
  identity (`ANone`, `V.identity()`) becomes 0. Mapping p ↦ P and n ↦ −P is a monoid
  homomorphism into the curve group that commutes with every step. So an identity proven for
  all Nat values of the p's and n's, with coefficients independent of them, holds on the curve.
* **Scalars.** A scalar is given by its windows `us_i = [u_i0, u_i1, …]`. In the code these are
  `bits9(add9(k, hconst(c)), j·c, c)`. The bit extraction, `add9` and `hconst` are **not**
  modelled.
* **Buckets.** The bucket array (`Array<+List<AP>>` of `empty(c−1)`, written with `Array.swap`,
  read by `flat`) becomes a list of `half = 2^(c−1)` bucket lists in index order.
* **Rounds.** The batch inversion inside `rounds` (one inverse per round, for the affine
  additions) is dropped: it computes the same sums. The pair cases of `psum` (equal x, a none
  operand) are all "add the two points".
* **Points at infinity.** `put` skips a point that is `ANone`. In the model that point is 0,
  and adding it changes nothing.

Window width c = 1 + cm, half = 2^cm, B = 2^c.

## Laws (`LAWS.bend`)

| Law | Statement |
|---|---|
| `window_ok` | **One window.** If every window value is at most 2·half (`Win`) and there are at most 2^rf points, then `window_sum(half, rf, ps, us, j)`, i.e. fill, rounds with fuel rf, reduction over the reversed buckets, equals Σᵢ mᵢⱼ·(nᵢ if the digit is negative else pᵢ). Here (mᵢⱼ, sign) is the signed digit of uᵢⱼ. |
| `msm9_ok` | **The MSM.** Under `Win(2^cm, us)`, at most 2^32 points, and `Fuel(9, False, cnt)` (wrange9's 9 levels split cnt windows down to single windows), `msm9(cm, ps, us, cnt)` equals Σᵢ (posvᵢ·pᵢ + negvᵢ·nᵢ). Here posvᵢ = Σⱼ Bʲ·(positive part of digit ij) and negvᵢ = Σⱼ Bʲ·(negative part). |
| `recode` | **The digits.** For every window list u (any values), posv + H == negv + k', where k' = Σⱼ Bʲ·uⱼ and H = Σⱼ Bʲ·half (the code's `hconst`). |
| `win_sat`, `points_sat` | Non-vacuity: all-zero windows satisfy `Win` (any number of points and windows), and a point list of length 1 is at most 2^rf points, for every rf. |
| `fuel_c4` … `fuel_c16` | Non-vacuity, and the hypothesis discharged for the code. For every window width c = 4..16 that `msm9` accepts, `Fuel(9, False, windows9(c))` holds. windows9(c) = (257 + c − 1)/c = 65, 52, 43, 37, 33, 29, 26, 24, 22, 20, 19, 18, 17. |

**Putting them together** (on paper, one line). The code computes the windows of k' = k + H, so
`recode` gives posvᵢ − negvᵢ = k'ᵢ − H = kᵢ. With nᵢ = −Pᵢ, `msm9_ok` gives
Σᵢ (posvᵢ − negvᵢ)·Pᵢ = Σᵢ kᵢ·Pᵢ. The hypotheses hold in the code:

* windows are c-bit values, so u < 2^c = 2·half;
* a chunk has far fewer than 2^32 points;
* `fuel_c*` covers every c the code uses.

The bound k' < 2^(c·windows9(c)) (k < 2^255, so the top window does not overflow) is about the
bit extraction and is not modelled.

## How it is proven

* `red.bend`: `reduce` has the closed form `acc + len·run + W(bs)`. W over a reversed list is
  Σ_d d·B_d in index order (`W_go`, by induction on `List.reverse.go`'s accumulator). A round
  keeps each bucket's sum and halves its size. Bucket sizes at most 2^f mean that `rounds(f)`
  ends with at most one point per bucket, so the heads are the bucket sums (`rounds_ok`).
* `fill.bend`: inserting x into bucket k adds (k+1)·x. Digit magnitudes are at most half, so
  every point lands in a bucket. No bucket gets more points than there are. That gives
  `window_ok`.
* `win.bend`: `dbl_n(n, p) = 2ⁿ·p`, 2^(h·c) = (2^c)^h, the Horner split of the window sum, and
  h + (cnt − h) = cnt for h = cnt/2. Together these give `wrange_ok`.
* `digit.bend`: the positive and negative parts of `sd_u`, the meaning of `Nat.is_ge`,
  `recode`, and the regrouping of Σⱼ Bʲ·(window j) into per-point coefficients (`spec_coef`).
* `acu.bend`: a small proven normaliser for sums of Nats (associativity, commutativity), used
  for rearrangements.

## Not covered

* The scalar side below the windows: `add9`, `hconst`, `bits9`/`wpick9_n` (U32 bit extraction)
  and the `k < 2^255` bound.
* The curve arithmetic: `psum`/`add_aff`/`norm_one`, batch-affine additions with one batched
  inversion per round, and `normalize`. These are taken to be group addition and are tested
  against `best_multiexp`, not proven.
* That `Array.swap` on the bucket tree behaves like the list update used here.
* `msm` (the older `wrange`/`recode` path with carries) and `msm_fa`. Only `msm9`, which
  `msm_par` and the verifier use, is modelled.

## Files and reproduce

| File | What |
|---|---|
| `model.bend` | the model of `msm9` and the specification |
| `acu.bend` | proven sum normaliser |
| `red.bend`, `fill.bend`, `win.bend`, `digit.bend` | the proofs, in pipeline order |
| `LAWS.bend`, `PROOF.bend` | laws and their proofs |

```sh
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict
```
