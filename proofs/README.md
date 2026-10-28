# Proofs

Theorems that turn some of Zebend's "tested" claims into machine-checked ones. Each
directory follows Bend's convention: `LAWS.bend` states the claims, `PROOF.bend` proves
them. Every directory prints `ALL PROOFS CHECK` under both `bend PROOF.bend` and
`bend PROOF.bend --verdict` (the recheck by Bend's Lean-proven kernel), with no `@unsafe`,
no foreign code and no open goals.

```sh
cd merkle && bend PROOF.bend --verdict   # likewise field/, gadget/
```

## merkle/: the incremental note-commitment tree

`merkle.bend` copies zcash/state's frontier (`push`, `fstep`, `fright`, `froot`) with one
change: the node hash `crh(g, l, a, b)` becomes the free constructor `Hn{l, a, b}` and the
empty-subtree roots `nth(es, l)` become `Em{l}`. Equal free terms stay equal under every
interpretation, so these theorems hold for any hash, Sinsemilla included.

| Law | Statement |
|---|---|
| `frontier_root` | For every well-formed tree `p` of height `D` filled from the left and not completely full, pushing its leaves one at a time into an empty `D`-level frontier and taking `froot` gives exactly the tree's root: `froot(push_all(pleaves(p), nones(D)), 0, None) == proot(p, D)`. |
| `path_sound` | For every perfect tree of height `k` and every position (a `Word(k)` of direction bits), the authentication path recomputes the root. |
| `path_binding` | If **any** claimed leaf `x` with **any** sibling list recomputes a perfect tree's root, then `x` is the tree's leaf at that position. For a real hash this is the contrapositive of collision resistance: a forged path that verifies exhibits a collision. |

Supporting lemmas (`carry`, `shape`, `fold` in `PROOF.bend`; list and Nat lemmas in
`lemmas.bend`) describe exactly what the frontier holds after each subtree.

Scope: the theorems are about the frontier *algorithm* as written in zcash/state, with the
hash abstracted. They do not prove Sinsemilla itself, or that zcash/state's Bend file is
byte-identical to this copy (it is a copy, not an import, because zcash/state's version
is hard-wired to its curve types).

## field/: the arithmetic under the Pasta field

| Law | Statement |
|---|---|
| `raw_roundtrip` | About `zcash/halo2/lib/fp.bend` itself (imported): for **every** 256-bit input `w`, `Fp.unraw(Fp.raw(w)) == w`. The 16-bit limb layer every field operation enters and leaves through is lossless. |
| `adc_ok` | Bend's `Word.adc` (which every `U32` `+` and `-` uses) is binary addition with carry, at every width `n`: `to_nat(sum) + carry_out·2ⁿ == to_nat(a) + to_nat(b) + carry_in`. |
| `u32_add_ok` | Corollary for `U32`: computed `x + y` plus the dropped carry times 2³² is the true sum, so a `U32` addition whose true sum is below 2³² is exact. |

`limbs.bend` and `wordadd.bend` are generated (`gen_limbs.py`, `gen_wordadd.py`): the limb
proof takes a `U32` apart into its 32 bits (Bend's `U32` is an inductive 32-bit vector,
so this is possible) and closes each bit with a two-case lemma; the addition proof is an
induction over the bits whose eight full-adder cases share one algebraic lemma.
`natlemmas.bend` is the Nat algebra (associativity, commutativity, doubling).

### Where Montgomery multiplication correctness stops

The goal was `val(Fp.mul(a, b)) ≡ val(a)·val(b)·R⁻¹ (mod p)` with the result below `p`,
where `val(x) = Σ limbᵢ·2¹⁶ⁱ`. It is **not proven**. What exists is the foundation
(`adc_ok`, `u32_add_ok`, `raw_roundtrip`); what is missing, in order:

1. **Mask and shift semantics on values:** `to_nat(x .&. 65535) = to_nat(x) mod 2¹⁶` and
   `to_nat(x >> 16) = to_nat(x) div 2¹⁶`. The bit-level technique of `limbs.bend` decomposes
   `x`, but `Word.to_nat` then gets stuck on 32 symbolic bits, so this needs an inductive
   "low m bits / high bits" lemma over `Word`, plus `mod`/`div` lemmas Base doesn't have
   (`Nat.mod` is defined through `divmod`, with no laws).
2. **`U32.mul` semantics:** `Word.mul` is shift-and-add; it needs its own induction on top
   of `adc_ok`, giving `to_nat(x·y) = to_nat(x)·to_nat(y) mod 2³²`, and the bound
   `(2¹⁶−1)² + 2·(2¹⁶−1) < 2³²` showing every limb product-plus-carry in `mul` is exact.
3. **The limb chain:** `Fp.add` is about 50 straight-line steps and `Fp.mul` about 1,700.
   Each step needs a no-overflow side condition (an `is_lt` proof). These proofs would have
   to be generated, the way `gen_field.py` generates the code.
4. **Modular reduction:** the final conditional subtraction of `p` (a `Word.sub` borrow
   chain plus `sel`) and the Montgomery identity itself (REDC correctness), both pure Nat
   number theory.

Step 1 is the next concrete lemma to prove. `Fp.add` correctness then needs steps 1, 3
and 4 without multiplication, and is the natural first target after that.

## gadget/: soundness of the boolean-constraint gate

| Law | Statement |
|---|---|
| `bool_gate_sound` | In ℤ/p with canonical elements (`b < p`), if `b·(1−b) = 0` then `b = 0` or `b = 1`. |

The gate is the most common constraint in PLONKish circuits (Orchard's included), and an
under-constrained version of a gate like this is the class of bug that let a circuit
accept an invalid witness. **Assumption, stated as a hypothesis:** ℤ/p has no zero
divisors (`NoZeroDivisors(p)`), which holds exactly when p is prime. Proving that Pallas'
p is prime is not attempted. Field multiplication is modelled as `(x·y) mod p` on Nats;
this is a model of the gate's algebra, not a check of Orchard's generated gate code.

## Timings (M5 Max)

| Directory | `bend PROOF.bend` | `--verdict` |
|---|---|---|
| merkle | 0.07 s | 0.10 s |
| field | 0.15 s | 0.41 s |
| gadget | 0.06 s | 0.07 s |
| prims | 0.2 s | 1 s |
| orchard | 0.1 s | 1 s |
| opt_gates | 11 s | 43 s |
| msm_chunk | 0.1 s | 0.2 s |
| msm_bucket | 0.1 s | 0.2 s |

`--verdict` is fast because Bend caches its compiled Lean kernel (`~/.bend/bendtt/`); it
still rejects unsound proofs (an `@unsafe` "proof" fails it).

## difficulty/: pre- and post-Blossom difficulty adjustment (8 laws)

`era.bend` makes the averaging-window timespan, damping and clamp era-parametric
(`Pre` below height 653,600, `Post` from it; AWT 2550 s / 1275 s, MIN 2142 / 1071,
MAX 3366 / 1683). For all `e`, `neg`, `mag`:

| Law | Statement |
|---|---|
| `timespan_ge_min` | ∃k. `MIN_TS(e) + k == timespan(e, neg, mag)` |
| `timespan_le_max` | ∃k. `timespan(e, neg, mag) + k == MAX_TS(e)` |
| `on_schedule` | `timespan(e, False, AWT(e)) == AWT(e)` |
| `clamp_ge_min`, `clamp_le_max` | the clamp's output lies in `[MIN_TS(e), MAX_TS(e)]` |
| `clamp_id` | inside the bounds, the clamp is the identity |
| `post_agrees` | `E.timespan(Post, neg, mag) == D.timespan(neg, mag)`: the model equals the running verifier's code in `zcash/headers/diff.bend` |
| `pre_awt_double` | `AWT(Pre) == 2 · AWT(Post)` |

**Real data:** `check_era.bend` (era-aware expected nBits, reusing `diff.bend`'s target
arithmetic) over every mainnet height 29..3,528,279: pre-Blossom 653,571/653,571 and
post-Blossom 2,874,680/2,874,680 nBits equal the headers, 0 mismatches (`check_all.log`).
Heights 1–28 lack a full 28-header window and are not checked.

## parse/: encode/decode round-trips about `zcash/p2p/bytes.bend` (11 laws)

| Law | Statement |
|---|---|
| `le32_roundtrip` | for all `x: U32`, `B.get_le32(B.le32(x)) == x` |
| `le16_roundtrip` | for all `x < 65536`, `B.get_le16(B.le16(x)) == x` |
| `compact_roundtrip` | for `n ≤ 0x02000000`, `read_compact(compact(n) ++ rest) == Compact{n, length(compact(n))}` |
| `noncanonical_rejected` | `read_compact([253, 5, 0]) == Compact{0, 0}` (width 0 = malformed) |
| `ff_rejected` | the `0xff` (u64) form is rejected |
| `over_cap_rejected` | `0xfe` with a value over `0x02000000` is rejected |
| `noncanonical_differs` | `compact(5) == [5]` |
| `canon_rejects_example` | the canonical decoder `canon.bend` rejects `[253, 5, 0]` |
| `canon_accepts` | for `n ≤ 0x02000000`, the canonical decoder accepts `compact(n) ++ rest` with the same result |
| `canon_sound` | if the canonical decoder accepts `(v, w)` then the first `w` bytes are exactly `compact(v)` |
| `header_split_concat` | `concat(split(k, bs)) == take(bs, k·1487)` for `zcash/headers/main.bend`'s `split` |

The 32-bit round-trip is proved bit by bit: `gen_bits.py` asks Bend for the normalised goal
and emits per-bit lemmas into `bits.bend` (~100 KB, imports the real `bytes.bend`).

**Finding (fixed):** `zcash/p2p`'s CompactSize decoder used to accept non-canonical
encodings (`[0xfd, 5, 0]` decoded to 5), which zcashd rejects. The decoder now in
`bytes.bend` (merged from `tools/harden/lib/cs.bend`) is canonical and capped at
`MAX_COMPACT_SIZE`; `noncanonical_rejected` proves the old counterexample is refused, and
`compact_roundtrip` proves every in-range canonical encoding still decodes.

## state/: the Merkle theorems transferred to the running `zcash/state` code (5 laws)

`refine.bend` interprets `merkle/`'s symbolic tree into real Sinsemilla values
(`interp`: leaves → `S.nth(ls, x)`, empty roots → `S.nth(es, k)`, nodes →
`S.crh(g, k, a, b)`), with no change to `zcash/state`.

| Law | Statement |
|---|---|
| `push_refines` | `S.push` on interpreted values equals interpreting `merkle/`'s push |
| `froot_refines` | `S.froot` equals interpreting `merkle/`'s frontier root (hypothesis: `l + length(levels) == 32`) |
| `frontier_root_running` | for a well-formed, non-full depth-32 tree `p`, pushing its leaves into `S.frontier_new()` and calling `S.froot` gives `interp(M.proot(p, 32))` |
| `path_refines` | `srecompute` equals interpreting `merkle/`'s path recompute |
| `path_sound_running` | an honest authentication path recomputes, with the real Sinsemilla, to the tree's root |

**Not transferred:** `path_binding`. With a real hash it only reduces to "a forged path
implies a Sinsemilla collision"; collision resistance is an assumption, not a theorem.
**Real data:** the frontier re-run over all 838,662 mainnet Ironwood notes gives 6/6 roots MATCH.

## fieldmul/: field multiplication correctness (2 laws; the chain stops early)

Target: `crypto/field3/fp64.bend`'s `mul` (CIOS Montgomery over 4×64-bit limbs via
`U32.mac64`, then a masked conditional subtraction). Proven so far:

| Law | Statement |
|---|---|
| `divmod_spec` | for all `a`, `b ≥ 1`: `(a div b)·b + (a mod b) == a` |
| `mod_bound` | for all `a`, `b ≥ 1`: ∃k. `(a mod b) + k == b − 1` |

Base defines `Nat.div`/`Nat.mod` through an accumulator loop (`Nat.divmod.go`) and states
no laws about it; these are proved by an invariant on that loop. Every limb identity of
`mac64` (defined with `Nat.div` by powers of two) needs them.

**Why the chain stops here:** Bend's checker evaluates Nat in unary. `2^12` checks by
evaluation; `2^16` overflows the machine stack. So no fact about Pallas' p (~2^254),
R = 2^256 or the Montgomery constant can be established by computation; everything must
be symbolic, and there is no ring-normalisation tactic. Still missing, in order:
`to_nat(from_nat n) == n mod 2^32`, `mac64`'s word decomposition, symbolic
normalisation over ~60 `mac64` steps, the Montgomery constant fact
(`p · p' ≡ −1 mod 2^64`), and bit-mask select lemmas for the final subtraction.
Field multiplication stays **tested** (116/116 against `pasta_curves`), not proven.

## prims/: the fork's U32 arithmetic and widening primitives (7 laws)

Target: Bend's `U32.mul` / `U32.add` / `U32.from_nat` and the primitives the bend-fork
branch `u64-rot` adds for 64-bit and multi-limb arithmetic (`bend2/base.bend`). `K` is
`Nat.mul(65536n, 65536n)` (= 2^32, written as the fork writes it); `A = U32.to_nat(a)` etc.

| Law | Statement |
|---|---|
| `u32_mul_lo` | `U32.to_nat(U32.mul(a, b)) == (A * B) mod K` |
| `u32_add_lo` | `U32.to_nat(U32.add(a, b)) == (A + B) mod K` |
| `u32_from_nat` | `U32.to_nat(U32.from_nat(y)) == y mod K`, for every Nat `y` |
| `mul_hi_split` | `U32.to_nat(U32.mul(a, b)) + U32.to_nat(U32.from_nat((A * B) div K)) * K == A * B` |
| `add_hi_split` | `U32.to_nat(U32.add(a, b)) + U32.to_nat(U32.from_nat((A + B) div K)) * K == A + B` |
| `mac_hi_split` | `U32.to_nat(((a * b + c) + d : U32)) + U32.to_nat(U32.from_nat(((A * B + C) + D) div K)) * K == (A * B + C) + D` |
| `lane64_split` | `lane(0, x) + lane(1, x) * K == x mod 2^64`, where `lane(k, x)` is `U32.lane64`'s body with `k` = `0`, `1` |

`U32.mul` is Bend's own shift-and-add `Word.mul`; `wmul.bend` proves it is multiplication
mod 2^n for **every** width n (`word_mul_mod`), by an invariant on `Word.mul.go` and a
congruence-mod-P library (`cong.bend`). `words.bend` proves the value bound
`Word.to_nat(n, w) <= 2^n - 1`, `Word.inc`'s carry identity and `2^32 == 65536 * 65536`;
`hi.bend` proves that the high digit of any `x <= M^2 - 1` is below `M` (so
`U32.from_nat` of it does not wrap), and the bounds `A*B`, `A+B`, `A*B + C + D <= M^2 - 1`.
`u32_from_nat` is the lemma `fieldmul/` lists as missing.

**What the hi laws are about.** By definition, `U32.mul_hi(a, b)` is
`U32.from_nat(Nat.div(A*B, K))`, `U32.add_hi` and `U32.mac_hi` likewise, and
`U32.lane64(k, x)` is `U32.from_nat(Nat.div(Nat.mod(x, Nat.pow(2n, 64n)), Nat.pow(2n, Nat.mul(32n, U32.to_nat(k)))))`.
Laws 4–7 are stated about those defining expressions, copied verbatim, not about the
names: the checker cannot unfold `U32.mul_hi(a, b)` to its body. Comparing an unfolded
body with any separately written copy of it makes the checker reduce the closed term
`Nat.mul(65536n, 65536n)` in unary, 2^32 steps, and it overflows the stack (minimal
repro: `law t: for +a: U32, for +b: U32, {U32.add_hi(a, b) == U32.from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n))) : U32}`
with proof `{==}`; moving the constant into a 0-ary def does not help). The same
limitation is why every proof here first rewrites `K` to `1 + mask(32)` and applies
lemmas proven for a variable modulus `1 + bp`; a proof that lets the checker compare
two copies of a closed 2^32 term crashes it. Since `U32.add64(k, …)` is by definition
`U32.lane64(k, word(al, ah) + word(bl, bh))` and `U32.rotr64(k, …)` is `U32.lane64(k, r)`
for its rotation formula `r`, `lane64_split` (for every `x`) covers both of them: their two
lanes recombine to the 64-bit result mod 2^64.

**Not proven:** `U32.mac64` (word k of a 128-bit multiply-accumulate; needs a four-digit
split of a value below 2^128, and the same unfolding step), `U32.xor64` (needs a
`Word.xor` lemma), and that `rotr64`'s formula is a rotation (that is its definition).
Run with `prims/chk.sh FILE [--verdict]`: it raises the JS stack so the checker can
expand `65536n` (2^16) once, in `words.bend`'s `e16`.

## orchard/: soundness of Orchard circuit gadgets on the generated gates (7 laws)

Target: the exact gate polynomials of the generated Orchard circuit
(`zcash/halo2/gen/orchard_cs.bend`). `gates.py` parses that file, decodes its Montgomery-form
constants, and `--check` evaluates its parsed trees on the real proof evaluations of
`zcash/halo2/vectors/orchard_verify.txt`: **386/386** gate values equal the generated code's
(193 polynomials × 2 proofs). `--emit` writes `gates_model.bend`: the selected gates over
`F.fadd/fsub/fmul` (Nat mod p, `fieldmodel.bend`), with the gate's selector factor
(checked identical for every polynomial of a gate) as a variable `sel`. Gate and
constraint names come from the `orchard` crate (`names/names.txt`).

Hypotheses (explicit in every law): p = 1 + pp with **`NZD(pp)`**: no zero divisors among
canonical elements (true exactly when p is prime; Pallas' p is, which is not proven here);
`1 <= pp`; every queried evaluation canonical (`Le(v, pp)`, i.e. `v < p`); the selector is
**invertible**, `fmul(si, sel) == 1` (in Fp: the gate is active on this row, `sel != 0`);
the gate polynomial(s) evaluate to 0. `a<k>` is the k-th queried advice evaluation.

| Law | Gate / constraint | Conclusion |
|---|---|---|
| `value_balance` | 0 "Orchard circuit checks": "v_old - v_new = magnitude * sign" | `a0 == a1 + a2·a3` (needs no `NZD`) |
| `anchor_or_zero` | 0: "Either v_old = 0, or root = anchor" | `a0 == 0` or `a4 == a5` |
| `spend_disabled_zero` | 0: "v_old = 0 or enable_spend = 1" | `a0 == 0` or `a6 == 1` |
| `output_disabled_zero` | 0: "v_new = 0 or enable_output = 1" | `a1 == 0` or `a7 == 1` |
| `last_window_bit` | 19 "Short fixed-base mul gate": "last_window_check" | `a5 == 0` or `a5 == 1` |
| `decompose_bit` | 13 "Decompose scalar for complete bits of variable-base mul": "bool_check" and "y_switch" together | `a10 == 2·a11 + 0` and `a9 + a21 == 0`, or `a10 == 2·a11 + 1` and `a9 == a21` |
| `cond_swap` | 26 "a' = b ⋅ swap + a ⋅ (1-swap)": "a check", "b check", "swap is bool" together | `a4 == 0`, `a2 == a0`, `a3 == a1`; or `a4 == 1`, `a2 == a1`, `a3 == a0` |

(`+`, `·`, `2·` above are `F.fadd`/`F.fmul` in Fp.) The laws are about the generated code
after `gates.py`'s translation; that translation is checked by the 386/386 evaluation, not
proven. Each law is about one gate on one row; what a gadget means across rows (e.g. a
whole running-sum decomposition) is not covered.

**The selector is invertible rather than just non-zero** because Bend can use a function
hypothesis (`NZD`) at most once: a law that strips the selector of three constraints and
then splits a product could not use `NZD` four times. Stripping with an inverse needs no
`NZD` (`evals.bend`'s `strip_inv`), so each law uses it at most once.

**Finding: `gadget/`'s `bool_gate_sound` is vacuous.** Its hypothesis `NoZeroDivisors(p)`
quantifies over all Nats, and x = p, y = 1 is a zero divisor (p·1 mod p = 0), so the
hypothesis is false for every p ≥ 1. `orchard/gadget_vacuous.bend` proves this
(`nzd_unsatisfiable: NoZeroDivisors(1 + pp) -> Empty`). `orchard/`'s `NZD` quantifies only
over canonical elements, which a prime p satisfies, and `orchard/`'s `last_window_bit` /
`E.boolean` is the non-vacuous version of that law, on a real Orchard gate.

## opt_gates/: the optimised generated verifier computes what the original computes (56 laws)

`research/perf4/v/opt_gates.py` (perf4 lever F: CSE, constant folding, a+(−b) → a−b, dead
code, inversion batching) is checked by translation validation, for every function it
rewrites, in `orchard_bt` (batch verifier) and `orchard_ba` (single verifier). `gen.py` checks
mechanically that the original and optimised bodies run the same non-arithmetic statements in
the same order. Each law states that every value passed to those statements is equal in Z/p,
for every p ≥ 2, every input and every constant. A once-proven normaliser (`sound.bend`'s
`nf_sound`: each rewrite rule preserves value) discharges the laws. In `ba` this covers all
215 `"expr"` values (the 193 gate polynomials and the permutation and lookup expressions)
individually.

**Trusted, not proven:** that `binvs` (Montgomery's batch inversion) returns pointwise inverses,
and, in `bt`, the removal of the log lines. Details: `opt_gates/README.md`.

## msm_chunk/: chunking and merging preserve the MSM (8 laws)

This is a model, with Nat points, of `msm_par.mpar`/`msm_auto` and `bt.groups`/`leaf`/`join`/
`check`, with the same control structure. Laws:

* `msm_split`: any split point splits the MSM;
* `mpar_ok`, `msm_auto_ok`: the chunked MSM equals the MSM for every fuel, chunk count and length;
* `groups_ok`, with its non-vacuity law `aligned_sat`;
* `shared_base`: s₁·P + s₂·P = (s₁+s₂)·P, base by base, through `vadd`;
* `merge_ok`, with `merge_sat`: for any tree of weighted proofs, the merged check value equals
  Σₖ rₖ·(own MSM + shared-base MSM).

`fx_dense` is not covered.

## msm_bucket/: the signed-digit bucket MSM computes Σ kᵢ·Pᵢ (18 laws)

This is a model of `msm_ba.msm9`: carry-free signed digits, bucket fill, pairwise rounds,
running-sum reduction over the reversed buckets, and windows combined by halving and doubling.
Points are free generators p (for P) and n (for −P).

* `window_ok`: one window equals Σᵢ dᵢⱼ·Pᵢ;
* `msm9_ok`: the result is Σᵢ posvᵢ·Pᵢ + negvᵢ·(−Pᵢ);
* `recode`: posv + H == negv + k';
* hypotheses discharged or shown satisfiable: `win_sat`, `points_sat`, and `fuel_c4..16` for
  every window width the code accepts.

Not modelled: bit extraction of the windows, the curve formulas (taken to be group addition),
and `Array.swap`.
