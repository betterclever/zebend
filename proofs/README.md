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

`merkle.bend` copies node/state's frontier (`push`, `fstep`, `fright`, `froot`) with one
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

Scope: the theorems are about the frontier *algorithm* as written in node/state, with the
hash abstracted. They do not prove Sinsemilla itself, or that node/state's Bend file is
byte-identical to this copy (it is a copy, not an import, because node/state's version
is hard-wired to its curve types).

## field/: the arithmetic under the Pasta field

| Law | Statement |
|---|---|
| `raw_roundtrip` | About `halo2/lib/fp.bend` itself (imported): for **every** 256-bit input `w`, `Fp.unraw(Fp.raw(w)) == w`. The 16-bit limb layer every field operation enters and leaves through is lossless. |
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
| `post_agrees` | `E.timespan(Post, neg, mag) == D.timespan(neg, mag)`: the model equals the running verifier's code in `node/headers/diff.bend` |
| `pre_awt_double` | `AWT(Pre) == 2 · AWT(Post)` |

**Real data:** `check_era.bend` (era-aware expected nBits, reusing `diff.bend`'s target
arithmetic) over every mainnet height 29..3,528,279: pre-Blossom 653,571/653,571 and
post-Blossom 2,874,680/2,874,680 nBits equal the headers, 0 mismatches (`check_all.log`).
Heights 1–28 lack a full 28-header window and are not checked.

## parse/: encode/decode round-trips about `node/p2p/bytes.bend` (9 laws)

| Law | Statement |
|---|---|
| `le32_roundtrip` | for all `x: U32`, `B.get_le32(B.le32(x)) == x` |
| `le16_roundtrip` | for all `x < 65536`, `B.get_le16(B.le16(x)) == x` |
| `compact_roundtrip` | `read_compact(compact(n) ++ rest) == Compact{n, length(compact(n))}` |
| `noncanonical_accepted` | `read_compact([253, 5, 0]) == Compact{5, 3}` |
| `noncanonical_differs` | `compact(5) == [5]` |
| `canon_rejects_example` | the canonical decoder `canon.bend` rejects `[253, 5, 0]` |
| `canon_accepts` | the canonical decoder accepts `compact(n) ++ rest` with the same result |
| `canon_sound` | if the canonical decoder accepts `(v, w)` then the first `w` bytes are exactly `compact(v)` |
| `header_split_concat` | `concat(split(k, bs)) == take(bs, k·1487)` for `node/headers/main.bend`'s `split` |

The 32-bit round-trip is proved bit by bit: `gen_bits.py` asks Bend for the normalised goal
and emits per-bit lemmas into `bits.bend` (~100 KB, imports the real `bytes.bend`).

**Finding:** `node/p2p`'s CompactSize decoder accepts non-canonical encodings
(`[0xfd, 5, 0]` decodes to 5); zcashd rejects them. The laws above prove both the bug and
a canonical decoder that fixes it.

## state/: the Merkle theorems transferred to the running `node/state` code (5 laws)

`refine.bend` interprets `merkle/`'s symbolic tree into real Sinsemilla values
(`interp`: leaves → `S.nth(ls, x)`, empty roots → `S.nth(es, k)`, nodes →
`S.crh(g, k, a, b)`), with no change to `node/state`.

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

Target: `field3/fp64.bend`'s `mul` (CIOS Montgomery over 4×64-bit limbs via
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
