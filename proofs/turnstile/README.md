# turnstile: Zcash's value pools, proven in Bend

A small executable model of Zcash's chain value pools (transparent, Sprout,
Sapling, Orchard, Ironwood) and the rules that guard them, with **nine laws
mechanically proven** about the very function the demo runs.

```
$ bend PROOF.bend
ALL PROOFS CHECK

$ bend PROOF.bend --verdict        # re-checked by BendTT's kernel (proven sound in Lean 4)
ALL PROOFS CHECK
```

No `@unsafe`, no `?TODO`, no foreign code. `bend LAWS.bend` on its own reports
`9 TODOs found`: the laws are open claims until PROOF.bend fills them.

## Why this matters

ZIP 2005 is candid that a discrete-log-breaking (e.g. quantum) adversary can
forge shielded value in any current pool, Ironwood included, and that until
those protocols are switched off *"the only constraint on such attacks is the
ZIP 209 turnstile mechanism."* The turnstile is what stops forged value from
leaving the pool it was forged in. These laws state, and prove, that the
turnstile and the NU6.3 / NU7 pool rules do what they claim, for every
possible state and transaction.

## The laws (`LAWS.bend`)

| Law | Says | Grounded in |
|---|---|---|
| `turnstile` | An accepted tx moves **every** pool by exactly `in − out`: `out + new == old + in`, over `Nat`, so no pool ever goes negative. | ZIP 209 |
| `no_counterfeit_exit` | If a tx withdraws more from Ironwood than the pool holds (plus what it deposits), `apply` returns `None`. | ZIP 209, ZIP 2005 § effects of DL-breaking attacks |
| `conservation` | `total_after + burned == total_before + issued`. | value balance, ZIP 235 |
| `orchard_withdraw_only` | From NU6.3 on, Orchard shrinks by exactly what leaves it; nothing enters. | ZIP 258 (NU6.3) |
| `sprout_frozen` | Under NU7, Sprout never changes. | ZIP 2003 (v4 txs disabled) |
| `sprout_never_grows` | In every era, Sprout only shrinks. | ZIP 211 |
| `ironwood_dormant_before_nu63` | Before NU6.3, Ironwood cannot move. | ZIP 258 |
| `chain_conservation` | Conservation over any accepted **sequence** of transactions (induction). | |
| `chain_orchard_shrinks` | After NU6.3, over any accepted history, `∃k. k + orchard_end == orchard_start`. | ZIP 258 |

## Files

| File | |
|---|---|
| `pools.bend` | The model: `Era`, `Flow`, `Pools`, `Tx`, `apply`, `apply_all`. |
| `LAWS.bend` | The nine claims (human-readable; the part to audit). |
| `PROOF.bend` | Their proofs (inversion lemmas, accounting, inductions). |
| `lemmas.bend` | General `Nat` / `Bool` / `Maybe` lemmas (commutativity, associativity, cancellation, discrimination). |
| `main.bend` | Scripted history NU6.2 → NU6.3 → NU7 (below). `turnstile-demo` is its native binary. |
| `pools.c` | The emitted C (one file: CPU program and GPU kernel). |
| `pools.mjs`, `node-demo.mjs` | The model as an ES module, called from plain Node. |

## Run

```sh
bend PROOF.bend              # check every law
bend PROOF.bend --verdict    # recheck with the Lean-proven kernel (needs Lean v4.34.0 via elan)
bend main.bend               # run the history
bend main.bend -o pools.c    # emit C
bend pools.bend -o pools.mjs && node node-demo.mjs
```

## Demo output (`bend main.bend`)

Starting balances are **illustrative round numbers, not live chain data**: no
public pool-balance API was reachable when this was built.

```
[NU6.2] accepted  shield 100 ZEC: transparent -> Orchard
[NU6.2] REJECTED  deposit into Ironwood before it activates (ZIP 258)
[NU6.3] REJECTED  deposit into Orchard after NU6.3: Orchard is withdraw-only (ZIP 258)
[NU6.3] accepted  migrate 1,000,000 ZEC: Orchard -> Ironwood (ZIP 318)
[NU6.3] REJECTED  COUNTERFEIT: forged Ironwood notes try to exit 1,000,001 ZEC (pool holds 1,000,000)
[NU6.3] accepted  unshield 250,000 ZEC: Ironwood -> transparent
[NU7  ] REJECTED  withdraw from Sprout after NU7: v4 transactions are gone (ZIP 2003)
[NU7  ] accepted  coinbase: issue 0.5208333 ZEC; burn 60 zat of fees (ZIP 235)
[NU7  ] REJECTED  unbalanced: claims 1 ZEC of issuance it has no right to

Supply check (laws `conservation` / `chain_conservation`):
  start total + issued - burned = 16525000.5208327
  end total                     = 16525000.5208327
```

```
$ node node-demo.mjs
unshield 40 ZEC from an Ironwood pool holding 40 ZEC -> accepted, ironwood now 0 ZEC
unshield 41 ZEC from an Ironwood pool holding 40 ZEC -> REJECTED (turnstile)
```

## Limitations

- **A model, not consensus code.** It abstracts a transaction to per-pool
  flows plus issuance and burn; it does not parse transactions, check proofs
  or signatures, or model the coinbase/funding-stream split, ZIP 317 fee rules,
  or the exact 60% burn ratio of ZIP 235 (burning is only *allowed* from NU7).
- Fees are not a separate field: at block granularity a fee is value moving
  from a spending pool into the miner's coinbase output, i.e. ordinary flows.
- `PreNU63` covers Canopy..NU6.2; Sprout inflows are forbidden there (ZIP 211).
- Units are 10 zatoshi, because Bend's runtime `Nat` stops at 2^48−1 and the
  21M ZEC supply is 2.1×10^15 zatoshi. Every law is unit-independent.
- The laws are proven about Bend's semantics of these definitions. As Bend's
  own README notes, the parser/translation into the kernel and the backends are
  not themselves proven.
