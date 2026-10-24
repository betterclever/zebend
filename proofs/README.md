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
