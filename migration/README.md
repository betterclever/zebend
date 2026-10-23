# Proven ZIP 318 migration planner (Bend 2)

A planner for moving funds from the *Orchard* pool to the quantum-recoverable
*Ironwood* pool, written in [Bend 2](https://github.com/HigherOrderCO/Bend),
whose privacy and accounting properties are **mathematical proofs checked by
the compiler**, not tests.

```
$ bend PROOF.bend
ALL PROOFS CHECK
$ bend PROOF.bend --verdict        # recheck with BendTT's Lean-proven kernel
ALL PROOFS CHECK
```

## The laws (`LAWS.bend`)

| Law | Statement | Why it matters for Zcash |
|---|---|---|
| **conservation** | `total(denominate(ds)) == amount(ds)` for every amount | Splitting an amount into denominations never creates or loses a zatoshi. |
| **exact_migration** | the plan's denominated outputs sum to exactly the requested amount | What you asked to migrate is what lands in Ironwood. |
| **canonical** | every migration output of every plan is `m × 10^k` with `m ∈ {1, 2, 5}` | ZIP 318 migrates in canonical denominations so that transfers from different wallets look alike. An odd amount (say 3.14159265 ZEC) moved in one piece is a fingerprint that links the Orchard spend to the Ironwood output. |
| **no_transparent** | no output of any plan, change included, is transparent | A transparent output publishes the amount and the address. The migration's privacy depends on never leaving the shielded pools. |
| **balanced** | `inputs == outputs + change + fee` for every plan | Mirrors the consensus value-balance rule: a plan that would be rejected (or burn funds) cannot be produced. |
| **fee_is_zip317** | `fee == 5000 × max(2, max(spends, outputs))` | The ZIP 317 conventional fee, so the transaction relays, and the fee does not become a distinguishing feature. |

Each law quantifies over **all** inputs: every list of notes and every amount.
The `None` case ("notes too small") holds vacuously. The proofs in `PROOF.bend`
reason about what `plan` actually computes, splitting on whether the notes
cover amount + fee. Separately, the `Plan` type in `planner.bend` carries the
same four invariants as erased proof fields, so a `Plan` value violating them
cannot be constructed anywhere in the program. Erased fields cost nothing at
runtime.

## How it is built

- Amounts are little-endian decimal digit lists. `denominate` handles each
  digit independently (e.g. `8 → 1 + 2 + 5`, `9 → 2 + 2 + 5`), at most 3 pieces
  per digit, which makes the conservation proof a structural induction.
- The proof chain is `mul_distrib`, then `put_total`, then `conservation_at`,
  over hand-proven `Nat` lemmas (`add_assoc`, `add_succ_r`, `sub_add`, …).
- `split(need, have)` computes the change with native `Nat.sub` and carries an
  *erased* proof `change + need == have`, so the proof costs nothing at runtime.

## Run

```sh
bend PROOF.bend                 # check every law
bend main.bend                  # demo: three migrations
bend main.bend -o migrate       # native binary
bend main.bend -o planner.c     # the emitted C (one file, CPU + GPU)
bend main.bend -o planner.mjs   # ES module; see node_demo.mjs
node node_demo.mjs
```

Demo output (`demo.txt`):

```
migrate 314159265 zat:
  spend 400000000 zat from 1 Orchard note(s)
  14 denominated outputs:
    Ironwood  5 zat
    Ironwood  10 zat
    Ironwood  50 zat
    Ironwood  200 zat
    Ironwood  2000 zat
    Ironwood  2000 zat
    Ironwood  5000 zat
    Ironwood  50000 zat
    Ironwood  100000 zat
    Ironwood  2000000 zat
    Ironwood  2000000 zat
    Ironwood  10000000 zat
    Ironwood  100000000 zat
    Ironwood  200000000 zat
  change   Ironwood  85765735 zat
  fee      75000 zat (ZIP 317)
```

## Limitations (honest scope)

- **A model of the planner, not a transaction builder.** It decides *what* to
  send; building and signing the actual v6 transaction (librustzcash / PCZT) is
  out of scope.
- **One transaction.** Real ZIP 318 runs in two phases (note preparation, then
  pre-signed transfers) with Poisson-scheduled broadcasts and shared anchor
  cohorts. Timing privacy is not modelled.
- **The change amount is not denominated.** It goes to the wallet's own Ironwood
  internal address, but its odd amount is a residual fingerprint. A real
  migration would denominate or hold it back.
- **The pool of the *spent* notes is not checked.** The planner accepts any
  notes as inputs. A law that inputs are Orchard-only is a natural next one.
- **Laws are about Bend semantics.** Bend's compiler is young and "99%
  AI-written" (its own README). `--verdict` re-checks the proofs with a
  Lean-proven kernel, but the translation to native code is trusted.
- Runtime `Nat` is a native immediate below 2^48 (~2.8M ZEC), which covers any
  single note but not the whole 21M ZEC supply in one value.
