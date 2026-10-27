# halo2/constraints: Orchard's full constraint system, and an under-constraint checker

Goal: make the class of bug behind Zcash's May 2026 Orchard soundness bug detectable. In
that bug, the variable-base scalar multiplication's base cells were never copy-constrained
to `g_d` (see BlockSec's analysis; the fix shipped in NU6.2).

**Disclosure rule.** This directory holds the tool, generic tests, and results for the
**pre-NU6.2** circuit (the already-public bug). Detailed results for the live circuits
(NU6.2, NU6.3/Ironwood) are kept outside the repository, pending review. Only their
summary counts appear below.

## 1. Extraction (`extract/`, `vendor/halo2_proofs/src/plonk/zebend_cs.rs`)

`extract <prenu62|nu62|nu63> OUT.json` builds one honest Action witness and synthesizes the
real `orchard::circuit::Circuit` once, through a recording `Assignment` backend. It uses
orchard 0.16 (the vendored copy in `halo2/oracle`), halo2_gadgets 0.6.0 and
halo2_proofs 0.4.0 (a pristine copy plus the `zebend_cs` module). The recording backend
makes the same calls keygen makes. The dump records:

- every gate and lookup, uncompressed (selectors as selectors), and as compressed in the VK;
- every selector enable, with its row and the region that enabled it;
- every copy constraint (cycles are their union-find classes);
- every fixed cell (with constants and table fills);
- every region, in synthesis order, with its name;
- every advice cell, with its row, column, owning region, namespaced annotation and honest value.

| Check | prenu62 | nu62 | nu63 |
|---|---|---|---|
| honest witness accepted by halo2's `MockProver` | yes | yes | yes |
| VK rebuilt from the dump's fixed cells, selectors and copies equals `VerifyingKey::build`'s, pinned form byte for byte (`vk_match`) | yes | yes | yes |
| negative control: rebuilt with one copy dropped, the VK differs | yes | yes | yes |
| VK gates vs `halo2/gen/orchard_cs.bend` at 3 random points (`tools/crosscheck.py`) | 579/579 | 579/579 | 579/579 |
| fixed commitments, permutation commitments and `transcript_repr` equal those hard-coded in `halo2/verifier`'s verifier for that era (`tools/vkbind.py`) | `orchard_dyn_prenu62` 29+15+1 equal | `orchard_dyn_nu62` equal | `orchard_dyn_fast` equal |
| re-extraction byte-identical (deterministic) | yes | yes | yes |

Those verifiers accept the sampled mainnet bundles of their era (`halo2/verifier/README.md`). So
the dumps are the deployed circuits: dump → same VK → same digest absorbed by the verifier
that agrees with mainnet. The cross pairs are negative controls:
- prenu62's VK vs `orchard_dyn_nu62`: the 29 fixed commitments are equal, but the 15 permutation commitments and the digest differ;
- nu62's VK vs `orchard_dyn_fast`: everything differs.

**Pre-NU6.2 vs NU6.2:**
- gates, lookups, queries and permutation columns are identical;
- the copy constraints differ by exactly two: `anchor x_p to base` and `anchor y_p to base` (row 2 of `variable-base scalar mul`), each copy-linked to the `gd_old` witness cell.

All three versions have 55 gates (193 polynomials) and 3 lookups. The pre-NU6.2 dump is
`out/prenu62.json`, and its VK digest is `out/prenu62.json.vk.json`.

```sh
cd extract && cargo run --release -- prenu62 ../out/prenu62.json   # also writes .vk.json; exits 1 unless mock_ok && vk_match
python3 tools/crosscheck.py out/prenu62.json [more dumps]
python3 tools/vkbind.py out/prenu62.json.vk.json ../verifier/orchard_dyn_prenu62.bend
```

## 2. The checker (`tools/anchor.py`)

The checker linearises every active equation at the honest witness, using exact partial
derivatives over Fp. An active equation is a gate polynomial on a row where its selector is
enabled, or a lookup input on such a row. Cells joined by copy constraints count as one
variable. It runs three passes:

1. **Per region (the gadget view).**
   - **Region inputs:** cells whose copy class reaches a fixed cell, an instance cell the circuit *reads*, or a cell assigned by an *earlier* region. An instance cell that a value is only *exposed* to does not count, because a public output must not explain away a lost input link.
   - **Free cells:** a cell is free if it has a non-zero component in the kernel of the region's Jacobian with respect to its other cells. It can then move while the inputs are fixed and every equation of the region still holds.
   - **`free-used`:** a free cell that some equation of the region reads. This is the bug signature: a gadget input tied only to itself.
2. **Global, declared-anchored.**
   - **Anchors:** instance and fixed cells, plus the Action statement's declared private witnesses: `g_d`, `pk_d`, `v`, `rho`, `psi`, `cm_old`, `ak`, `nk`, the Merkle siblings, and `v_net`'s magnitude and sign.
   - **What it tells:** a per-region flag that is determined here was only waiting for a later region's check.
3. **Global, full** (instance and fixed anchors only). Plus **instance binding**: which instance rows no copy constraint reaches.

Run: `python3 tools/anchor.py DUMP OUTDIR` (≈3 s). Then `tools/summarize.py`. `tools/queried.py` checks globally free cells: is each one queried by any active gate, and is its coefficient zero for *random* advice values too (a structural don't-care)?

### Acceptance test: passes

| `variable-base scalar mul` region (`[ivk] g_d_old`) | kernel dim | free-used cells | `x_p`/`y_p` flagged |
|---|---|---|---|
| pre-NU6.2 | 3 | 1,045, including `x_p`, `y_p` on all 129 rows | **yes** |
| NU6.2 | 1 | 0 | no |
| NU6.3 | 1 | 0 | no |

In NU6.2/NU6.3 the remaining dimension is the `α` cell of row 0. That cell is a structural
don't-care: its operands are copies of the same base cell, so every equation's coefficient
on it is identically zero.

### Every other flag, pre-NU6.2 (`results/prenu62/`)

The table below gives `[regions, kernel dim, free-used cells]` per region type. Every count
is identical in NU6.2 and NU6.3.

| Region | kernel dim | free-used | Triage |
|---|---|---|---|
| `load private` ×8 | 8 | 0 | intended: declared private witnesses (`v_old`, `v_new`, `nk`, `rho_old`, `psi_old`, `psi_new`, `v_net` magnitude and sign) |
| `witness point` (`cm_old`), `witness non-identity point` ×5 (`g_d_old`, `ak`, `pk_d_old`, `g_d_new`, `pk_d_new`) | 1 + 4 | 2 + 8 | intended: declared witness points; the on-curve gate leaves a 1-dimensional curve |
| `swap` ×32 | 32 | 64 | intended: the Merkle sibling (`witness b`) and the swapped output it feeds |
| `witness message piece` ×116 | 116 | 0 | analysis scope: a piece witnessed here and checked by later decomposition gates; determined in pass 2 |
| `hash_to_point` ×35 | 70 | 0 | intended: the `dummy x_p`/`dummy lambda2` cells of each Sinsemilla hash; structural don't-cares (`queried.py`: zero coefficient for random advice) |
| `Witness element` ×19 | 15 | 215 | analysis scope: running-sum decompositions (lookup range checks) of a value witnessed here and tied to its source by a later canonicity / decomposition gate; all determined in pass 2 |
| `s = alpha + k_254 ⋅ 2^130` | 1 | 0 | analysis scope: witnessed here, checked by the following overflow-check region |
| **`variable-base scalar mul`** | **3** | **1,045** | **suspicious, and the known bug: the unanchored base** |

**Pass 2** (all three versions): 71 free cells, none read by any equation at the honest
witness. All 71 are structural don't-cares (`queried.py`): 70 Sinsemilla dummies and the
`α` cell. **Pass 3:** its kernel dimension is also 71, in all three versions. **Instance
binding:** row 9 (`disableCrossAddress`) is unbound in prenu62 and nu62. That is by design
(orchard documents it); NU6.3 binds it.

**Live circuits, summary only:** NU6.2 and NU6.3: 289 free-used cells in per-region pass, all by
design or analysis gaps (details withheld pending review); pass-2 free cells: 71, all
structural don't-cares.

### Why the per-region view is needed

Pass 2 and pass 3 do **not** distinguish pre-NU6.2 from NU6.2: kernel dimensions 71 and 71.
Orchard decomposes almost every private value into lookup-checked words or bits, so the
whole witness is locally rigid. In the pre-NU6.2 circuit, a different base is not a
continuous deformation of an honest witness. It is a different discrete solution (the
attacker picks another `nk`), and a global dimension count cannot see that. The bug is a
lost relation *between* declared witnesses (`pk_d = [ivk] g_d`). Only the gadget view, which
asks whether the gadget's input reads are tied to the gadget's inputs, exposes it.

### What the checker does NOT see

- **Finite ambiguity:** a boolean's two roots, a square root's sign, a lookup's choice of row. These are isolated solutions and look anchored. A missing link that leaves only *discrete* freedom (bits, windows) is invisible.
- **Constraints a later region imposes:** these show up as per-region flags, and pass 2 resolves them. The declared-witness list is the analyst's input; a wrong list makes pass 2 wrong.
- **Degenerate honest points:** these could produce spurious kernel vectors (none were seen; every flag was triaged).
- **The permutation and lookup arguments themselves** are assumed sound.

## 3. Mutation testing (`tools/mutate.py`)

One mutant per removable thing in the pre-NU6.2 dump:
- every copy constraint deleted (2,960: 2,076 self-copies, which are no-ops, and 884 real links);
- every selector enable deleted (4,326);
- every lookup argument deleted (3).

The checker re-runs on each mutant. A mutant is **flagged** if, relative to the unmutated dump, any of these appears:
- **R:** a new free-used cell in a touched region;
- **D:** a larger kernel in a touched region;
- **G:** a new free-and-used cell in pass 2;
- **F:** a larger kernel or a new free-and-used cell in pass 3;
- **I:** a new unbound instance row.

**Relaxed mode** (`--relaxed`) also drops every finite-domain equation:
- lookup inputs;
- every gate instance that is a non-linear polynomial in a single linear form of the advice. Detection is numerical (parallel but unequal gradients at two random points): booleanity, window and range checks, `sign² = 1`, swap bits.

Bits and words then count as free, so a lost *linear* link from them shows up. Relaxed mode over-approximates "the link is necessary": it can flag a copy that only discrete constraints make redundant. Its flags raise recall at **unestablished precision**.

| Mutants (pre-NU6.2) | first run | normal (current) | relaxed | normal or relaxed |
|---|---|---|---|---|
| real copy links (884) | 330 (37%) | 345 (39%) | 870 | **884 (100%)** |
| selector enables (4,326) | 3,408 | 3,427 | 3,521 | 3,522 |
| lookups (3) | 3 | 3 | 0 | 3 |

- **First run vs normal (current):** the first run counted any instance-linked cell as an anchor. The current normal mode differs in two ways:
  - **Directional instance anchoring:** only instance cells the circuit *reads* (`assign_advice_from_instance`) are anchors; cells only *exposed* to an instance (`constrain_instance`) are not.
  - **Criterion D** is added.
- **The 8 real-copy survivors of the first run:**
  - **What they were:** the input copies of three complete additions whose outputs are public. Examples: `rk = [α] SpendAuthG + ak` with the `ak` link deleted, and the two additions of the value commitment.
  - **Why they survived:** the public output pinned the gadget, so the lost input link went unnoticed. That is a real checker hole of the same kind as the May 2026 bug: a lost relation hidden by a rigid global view.
  - **Status:** all 8 are flagged now.
- **Before vs after on real copy links:** **330/884 → 345/884** in normal mode; **884/884** with relaxed mode (first-order; precision not established).
- **Self-copies:** a copy of a cell onto itself, which the fixed-base mul gadgets emit. Deleting one is a no-op mutant and is excluded from recall.

**Surviving enables** (804, `results/prenu62/enable_survivors_by_gate.txt`). Every one is an enable of the range-check lookup: 600 running-sum words (`Witness element`) and 204 short range checks.
- Without its lookup, a word is still determined linearly by its running sum. No freedom appears; only its **range** is lost.
- Range, canonicity and table-tag properties (C1, C2, C5) are **outside what anchoring can see**. This is a checker hole, not redundancy.

Known redundant constraints:
- **`pk_d_old`'s on-curve gate:** the point is copy-linked to the already computed `[ivk] g_d`. It is not flagged in normal mode. Relaxed mode flags it, through criterion F. With the finite-domain equations dropped, the full pass is no longer rigid, so removing the gate adds a kernel dimension.
- **The NU6.2 anchors:** the hi and lo halves both `copy_advice` the same row-2 cells, so each anchor copy has a parallel twin. Deleting one is redundant; deleting both re-creates the bug and is flagged (`tools/pairmut.py`).

Live circuits, summary only: mutation runs on NU6.2 (7,293 mutants, normal and relaxed) were triaged privately. All results are by design or analysis gaps (details withheld pending review).

**Not done: per-copy SMT decision.** The coordinator asked for an SMT decision of each copy: can the two cells differ once the link is removed, with lookups encoded as table membership? This is not done.
- The pip build of cvc5 1.4.2 has no finite-field solver: "not configured with --cocoa".
- z3 has no finite-field theory, and a mod-p integer encoding of these gates over a 255-bit prime is not expected to terminate.
- So the "necessary vs redundant" status of relaxed-only flags stays **UNKNOWN** and is not claimed either way.

```sh
python3 tools/mutate.py out/prenu62.json results/prenu62 --workers 16              # ≈ 22 min on the M5 Max
python3 tools/mutate.py out/prenu62.json results/prenu62 --workers 12 --relaxed    # ≈ 15 min
python3 tools/combine.py out/prenu62.json results/prenu62/mutants_prenu62.jsonl results/prenu62/mutants_prenu62_relaxed.jsonl
python3 tools/survivors.py out/prenu62.json results/prenu62/mutants_prenu62.jsonl
```

## Layout

| Path | What |
|---|---|
| `extract/` | the extractor (Rust) |
| `vendor/halo2_proofs/` | halo2_proofs 0.4.0 + `src/plonk/zebend_cs.rs`; `permutation.rs`'s `commitments()` un-gated |
| `tools/` | `anchor.py`, `mutate.py`, `combine.py`, `survivors.py`, `pairmut.py`, `crosscheck.py`, `vkbind.py`, `mulfacts.py`, `queried.py`, `summarize.py`, `cslib.py` |
| `out/` | the pre-NU6.2 dump + VK digest |
| `results/prenu62/` | the pre-NU6.2 analysis and mutation results (`v1_instance_anchor/`: the first run, before directional instance anchoring) |

Theorem about the fix: `proofs/orchard_mul/`.
