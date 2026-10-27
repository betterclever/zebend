# node/rules: non-cryptographic consensus rules, in Bend

`bin/rules <window.bin> <ctx.bin>` (source `rules.bend`) re-parses every block of a window
(zcash/wire gate + `node/bend/parse.bend`) and decides every rule below in Bend. The
driver `../rules.py` only looks up what Bend needs and the block does not contain (spent
outputs from the UTXO store or earlier txs of the window, the previous 11 block times, the
value pools before the window), writes `ctx.bin`, and compares the printed verdict lines.

```sh
python3 test_rules.py            # every real block in ../bend/data: all rules PASS
python3 tamper_rules.py          # 16 tampered blocks: each fails exactly the intended rule
python3 window_test.py 3522461 3522490   # rules.validate(mode=full) + hooks above the checkpoint
```

## Interface

- `window.bin`: blockdelta's format (u32 height | 1487-byte header | u32 length | block).
- `ctx.bin` (u32 LE): 6 × (lo, hi) pools before the window (sprout, sapling, orchard, ironwood,
  lockbox, transparent; 64-bit two's complement); then per block `L | height | nt | nt × time |`
  per spent transparent input in block order (coinbase input excluded) `value lo | value hi |
  height | from-coinbase | script length | scriptPubKey`.
- Output per block: `fail <h> <rule> [tx <i>]` per violation; `skip <h> …` for rules not
  modelled at that height (NU7 issuance); `fees <h> <zat> sigops <n> txs <n>`;
  `pools <h> <sprout> <sapling> <orchard> <ironwood> <lockbox> <transparent>` (after the
  block, zatoshis); `verdict <h> VALID|INVALID`.
- `rules.validate(blocks, st, raw_by_height, log, mode="full"|"audit") -> extra meta`:
  `full` raises `rules.RuleFail` (a `store.StateError`, so sync.py reports it as FAIL and does
  not commit) on any rule or hook FAIL; `audit` (for checkpointed blocks, to track pools from
  genesis) returns disagreements instead and runs no hooks. Returns `{"rules": {...},
  "pools": {...}, "pools@<last>": {...}}`; if the store has no `pools` (not tracked from
  genesis) the turnstile is reported **SKIPPED** and no pools are returned.
- Hooks: see `../hooks/README`.

## Rules and their status

Sources: Zebra at the pinned commit 7a839a6 (`zebra-consensus/src/{block,transaction}/check.rs`,
`transaction.rs`, `block.rs`, `zebra-state/src/service/check/utxo.rs`, `zebra-chain`
`parameters/{constants,network_upgrade,network}.rs`, `subsidy/check.rs`,
`subsidy/constants/mainnet.rs`, `transparent/serialize.rs`) and zcashd where Zebra checkpoints
(pre-Canopy rules). NU7 heights/branch id from Zebra main 1e03ee7 (NU7 3,543,405, 0x77190ad9).

"real" = passes on real mainnet blocks (64 sampled blocks of every era + 30 contiguous blocks
3,522,461–3,522,490 above the last checkpoint, spent outputs from the real chain via
lightwalletd). "tamper" = a tampered block fails exactly this rule.

| Rule (name printed) | Mirrors | Status |
|---|---|---|
| first tx is the only coinbase; no null prevout elsewhere (`coinbase_first`) | Zebra `coinbase_is_first` | real + tamper (2nd coinbase) |
| coinbase scriptSig 2..100 bytes (`coinbase_script_length`) | Zebra `parse_coinbase_height`, zcashd | real |
| BIP34 height prefix, canonical CScriptNum (`coinbase_height`) | Zebra `parse_coinbase_height` | real + tamper |
| coinbase: no JoinSplits / Sapling spends / enableSpends (`coinbase_shielded_spend`) | Zebra `coinbase_tx_no_prevout_joinsplit_spend` | real |
| coinbase: no Orchard component from NU6.3 (`coinbase_orchard_nu63`) | Zebra `coinbase_orchard_component_empty` | real |
| coinbase: no Sapling outputs before Heartwood (`coinbase_sapling_output_pre_heartwood`) | zcashd | real |
| coinbase nExpiryHeight == height from NU5 (`coinbase_expiry`) | Zebra `coinbase_expiry_height` | real |
| founders' reward / funding streams / NU6.1 lockbox disbursement outputs (`issuance_required_outputs`) | Zebra `subsidy_is_valid`, via `zcash/consensus/issuance` (`cb_main.expected/matched`) | real + tamper (ZCG 1 zat short) |
| miner fees: coinbase out − shielded vb + deferred ≤ subsidy + fees, == from NU6 (ZIP 236) (`miner_fees`) | Zebra `miner_fees_are_valid` | real + tamper (overpay 1 zat) |
| lockbox (deferred) share 12% from NU6 to 4,406,400, −78,750 ZEC at 3,146,400 | Zebra `funding_stream_values`, mainnet.rs | real (via miner_fees) |
| tx version / version group per upgrade; v4 retired at NU7 (`tx_version`) | Zebra `verify_v{4,5,6}_transaction_network_upgrade`, zcashd pre-Sapling | real + tamper (v3 in Sapling era) |
| v5/v6 consensus branch id == height's (`branch_id`) | Zebra `consensus_branch_id` | real + tamper |
| has inputs and outputs (`inputs_outputs`) | Zebra `has_inputs_and_outputs` | real |
| Orchard / Ironwood: some flag set when actions present (`orchard_flags`, `ironwood_flags`) | Zebra `has_enough_*_flags` | real |
| NU6.3: Orchard valueBalance ≥ 0 (`orchard_value_balance_nu63`) | Zebra `orchard_value_balance_non_negative` | real |
| no Orchard actions in [3,363,426, 3,364,600) (`orchard_disabled`) | Zebra `is_orchard_temporarily_disabled` | implemented, untested (no block in range sampled) |
| JoinSplit: not both vpub nonzero (`joinsplit_vpub`); vpub_old = 0 from Canopy (`sprout_vpub_old_canopy`) | Zebra `joinsplit_has_vpub_zero`, `disabled_add_to_sprout_pool` | real |
| duplicate outpoints and nullifiers anywhere in the block, per pool (`duplicate_spend`) | Zebra `spend_conflicts` + state | real + tamper (input, nullifier) |
| expiry ≤ 499,999,999 (`expiry_max`); not mined after expiry (`expired`) | Zebra `non_coinbase_expiry_height` | real + tamper |
| lock time, against height / the block's own time, unless all sequences final (`lock_time`) | Zebra `lock_time_has_passed` (block time, as Zebra does for blocks) | real + tamper |
| pre-Sapling tx size ≤ 100,000 (`tx_size`) | zcashd | real |
| fee ≥ 0 per non-coinbase tx (`value_balance`) | Zebra `remaining_transaction_value` | real + tamper |
| total transparent output ≤ MAX_MONEY (`output_total_range`) (per-amount ranges: wire validator) | zcashd CheckTransaction | real |
| coinbase maturity 100 (`coinbase_maturity`); coinbase spend with transparent outputs (`coinbase_spend_transparent_outputs`) | Zebra `transparent_coinbase_spend`, mainnet `DisallowCoinbaseSpend` | real + tamper (both) |
| block sigops ≤ 20,000: legacy + P2SH accurate count (`sigops`) | Zebra block.rs `MAX_BLOCK_SIGOPS`, zcashd GetP2SHSigOpCount | real + tamper; the count itself is **not** compared with Zebra's |
| block time > median-time-past of 11 (`mtp`) | zcashd ContextualCheckBlockHeader / Zebra state | real |
| ZIP 209 turnstile: no pool negative (sprout, sapling, orchard, ironwood, lockbox, transparent) (`turnstile_*`) | Zebra chain value pools | tamper (Sapling pool 0); pools from genesis correct on blocks 0–2 (transparent 187,500 zat); **SKIPPED** in a sync that did not track pools from genesis |
| NU7 (≥ 3,543,405): branch id and v4 retirement | Zebra main | implemented, untested (not active yet) |

**Not done / pending:**
- NU7 issuance (ZIP 218 subsidy ÷3, ZIP 235/237 NSM fee burning): issuance, miner-fee and
  lockbox rules print `skip <h> …` from NU7 instead of a verdict. NU7 Sprout-spend retirement
  and ZIP 218 shielded action limits: not implemented.
- Sapling/Orchard/Ironwood canonical proof sizes and Orchard flag bits: enforced by the wire
  validator (`zcash/wire/txv.bend`), not here.
- Anchors, nullifier-set and UTXO membership: lookups the store does in sync.py's commit (a
  missing spent output makes `rules.build_ctx` raise as well).
- Header rules (PoW, difficulty, links, merkle, block size): blockdelta / equihash.
- Coinbase outputs decryptable with the zero ovk (ZIP 212/213): needs note decryption; pending.
- The 2-hour future-time rule (non-deterministic): not checked.

## Results

- Real blocks: **94/94** (64 sampled blocks of every era + 30 contiguous above the checkpoint, each as its own window) pass every rule (`test_rules.py`; 371
  txs, 1,444 inputs with spent outputs from lightwalletd), and the 30-block window
  3,522,461–3,522,490 above the last checkpoint passes `rules.validate(mode="full")`
  (232 txs).
- Tampered: **16/16** cases fail exactly the intended rule(s) (`tamper_rules.py`): coinbase
  overpay by 1 zat → `miner_fees`; output +10,000 ZEC → `value_balance` (+ `miner_fees`, as
  the block's fees fall); immature coinbase spend → `coinbase_maturity` (+ the shielding rule:
  the tx has transparent outputs); mature coinbase spend with transparent outputs →
  `coinbase_spend_transparent_outputs`; expiry h−1 → `expired`; lock h+10 with a non-final
  sequence → `lock_time`; NU6.2 branch id at NU6.3 → `branch_id`; v3 tx in a Sapling-era block →
  `tx_version`; repeated input / nullifier → `duplicate_spend`; Sapling pool 0 →
  `turnstile_sapling` (and no failure with large pools); 1,001 × OP_CHECKMULTISIG →
  `sigops`; ZCG output 1 zat short (miner +1) → `issuance_required_outputs`; BIP34 height
  off by one → `coinbase_height`; a second coinbase → `coinbase_first`.
- Hooks on 3,522,461–3,522,490: orchard **PASS 99/99 txs** (sigs + Halo 2, follow's
  binaries); transparent **SKIPPED (component pending)** 134 txs; sapling **SKIPPED** 6 txs.
  A flipped proof bit in an Ironwood bundle → `hook orchard: FAIL Halo 2 ironwood rejected`.
- Speed (one process, M5 Max): 3–30 ms per typical block including process start;
  30 contiguous NU6.3 blocks in 0.32 s (11 ms/block) with ctx building, 1.55 s with the
  orchard hook; the 1.96 MB sandblasting block 1,750,000: 1.3 s.
