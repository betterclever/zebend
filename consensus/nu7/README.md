# consensus/nu7: NU7 in Bend (ZIP 259: Mainnet 3,543,405, Testnet 4,465,026, branch 0x77190ad9)

Every NU7 consensus change, written in Bend for both networks. Each one is tested against
Zebra/Zakura code and real Testnet NU7 blocks, and the key laws are proven. The wiring into
the full node, follow and tiphdr is **proposed, not applied**. The diffs are in `wiring/`;
the coordinator applies them with a controlled restart.

## Sources (exact commits)

| Source | Commit | What |
|---|---|---|
| zcash/zips | `2bdf39494320e5e04057ac93b1794031ebfb00b5` (2026-10-21, "nu7_mainnet_activation") | ZIP 259, 218, 235, 237, 207 rev. 2, 214 rev. 3, 2003, 2008 |
| Zebra | `1e03ee753fbc72d70882cdfd3c8bdd58b80f0f97` (2026-10-23) | zebra-chain `parameters/network_upgrade.rs`, `parameters/network/subsidy.rs` (+ `check.rs`, `constants/mainnet.rs`), `block.rs`, `value_balance.rs`; zebra-consensus `block.rs` (ShieldedActionCounts), `transaction.rs` (v4 rejection); zebra-state `service/check/difficulty.rs` |
| Zakura | `52967ff4f4d853fe427a66699ce6f0720db2541e` (2026-10-25) | `crates/zakura-consensus/tests/nu7_diff_dump.rs` (Zakura's own dump of every NU7 quantity) |

The checkouts are in `data/src/` (gitignored).

## What NU7 changes, and where it is implemented

| Rule | Source | Bend |
|---|---|---|
| PoWTargetSpacing 25 s from NU7; PoWAveragingWindow 17 → **102**; AWT = 102·25 = 2550 s; Min/Max timespan 2142/3366; damping 4 and adjust 16%/32% unchanged; MedianBlockSpan 11 unchanged | ZIP 218 § Block target spacing / Averaging window; Zebra `network_upgrade.rs` (POST_NU7_POW_AVERAGING_WINDOW = 102), `difficulty.rs` | `era7.bend` (era = Pre/Post/NU7 by height), `headers/diff7.bend` (17-limb sums: 102 Testnet targets overflow 256 bits) |
| Testnet minimum difficulty: gap > 18 spacings (450 s) from NU7 (it was 6 spacings: 450 s post-Blossom, 900 s pre-Blossom), from height 299,188 | ZIP 218 § Minimum difficulty, ZIP 259 | `era7.MIN_DIFF_GAP`, `diff7.min_diff` |
| Halving(): third era scaled into 25 s blocks; PostNU7HalvingInterval = 5,040,000; third halving moves to **6,132,390** (Mainnet) / 4,497,948 (Testnet) | ZIP 218 § Halving interval; Zebra `halving()` | `nu7.halving_nu7`, `nu7.halving` |
| BlockSubsidy ÷ 3: floor(MaxBlockSubsidy / (2·3·2^Halving)) = 52,083,333 zat now | ZIP 218; Zebra `scheduled_block_subsidy` | `nu7.sub7`, `nu7.subsidy` |
| Revision 2 streams (FS_FPF_ZCG_H3 8%, FS_CCF_H3 12% to the lockbox) end at the ZIP 218 third halving A + 3(H3 − A) = 6,132,390 instead of 4,406,400; values floor(subsidy·n/100) = 4,166,666 / 6,249,999 | ZIP 214 rev. 3; Zebra `nu7_funding_stream_end_height` | `nu7.fs_end7`, `fs_zcg`, `fs_deferred`, `required7` |
| AddressPeriod from NU7 = floor((3(A + I − H1) + h − A) / (3C)): the period that is running at activation gets three times its remaining blocks; later periods last 105,000 blocks | ZIP 207 rev. 2 | `nu7.period_nu7`, `zcg_index` |
| FS_FPF_ZCG_H3 recipient becomes the **P2PKH** t1MkHnkxVjNpNbCrSs3AJ8J7ZSp6NTYiUcG from index N = AddressIndex(A−1)+1 = 12, i.e. from Mainnet height **3,612,390**, paid with the exact P2PKH script | ZIP 2008; Zebra `post_nu6_1_funding_stream_fpf_addresses`, `subsidy/check.rs` | `nu7.zcg_switch`, `zcg_script` |
| Miner fees: the coinbase claims MinerFees = fees − NSMFeeContribution, where NSMFeeContribution = 6q + floor(6r/10) = floor(6·fees/10) over the block's total fees. Total output still == total input (ZIP 236) | ZIP 235 § Consensus Rule Changes; Zebra `nsm_fee_contribution`, `miner_fees_are_valid` | `nu7.contribution64`, `miner_fees` (64-bit); `nsm_contribution_n` (Nat spec) |
| NSM value balance (consensus state, not a pool): seeded with INITIAL_NSM_VALUE_BALANCE (Mainnet 36,858,445,520 zat, Testnet 55,768,414,957) at activation; + contribution − AdditionalBlockSubsidy per block; a block that would make it negative is invalid | ZIP 237 § 4.17; Zebra `nsm_value_balance_change`, `value_balance.rs` | `nu7.nsm_before`, `nsm_after`; 7th pool + `turnstile_nsm` in rules.bend |
| Reissuance: AdditionalBlockSubsidy = ceiling(1375 · NSMValueBalance(h−1) / 10^10) from NSM_REISSUANCE_HEIGHT **8,939,664** (Mainnet; Testnet 7,305,222). BlockSubsidy = scheduled + additional, and funding streams take their share of the total | ZIP 237 § NSM reissuance height, ZIP 259; Zebra `additional_block_subsidy`, `block_subsidy_with_parent_nsm_value_balance` | `nu7.reissue64`, `additional` |
| Shielded action limits per block: Orchard ≤ 330, Ironwood ≤ 330, Sapling spends+outputs ≤ 300, JoinSplits = 0, and Orchard+Ironwood+Sapling+2·JoinSplits ≤ 330 | ZIP 218 § Shielded pool action limits; Zebra `ShieldedActionCounts::exceeded_limit` | `nu7.Cnt`, `limits_ok` (rule `shielded_action_limits`) |
| No v4 transactions, coinbase included; only v5/v6. Sprout can only be spent from v4, so Sprout funds become unspendable (they stay in the issued supply) | ZIP 2003; Zebra `verify_v4_transaction_network_upgrade` | `rules.bend ver_ok` (already present); JoinSplit limit 0 |
| Branch id 0x77190ad9 for v5/v6 txs | ZIP 259 | `rules.bend branch_at` (already present) |

Not consensus, but noted:
- ZIP 218 says nodes SHOULD support rollback of at least 600 blocks after activation. `store.py` keeps 200 blocks of undo data (not changed here).
- Mainnet peers must speak protocol version ≥ 170190. `node/p2p` and `fullnode/net.py` already advertise 170190.
- The ZIP 221 history tree resets at NU7 like at every upgrade; Zebra uses the Ironwood-onward tree.
- Default expiry delta goes from 40 to 120 blocks (a wallet SHOULD).

### Where the original task description differs from the specs
- The averaging window does change, from 17 to 102.
- The halving interval triples, and the third halving moves from 4,406,400 to 6,132,390.
- The funding streams and the 12% lockbox stream are extended to 6,132,390.
- The ZCG recipient switches to a P2PKH address (ZIP 2008).
- Reissuance starts at a fixed **height**, 8,939,664 (ZIP 237's crossover). "February 2031" is only that height converted at 25 s per block.
- Reissuance pays out the whole NSM balance at 1375/10^10 per block, a half-life of one halving. That balance holds the 60% fee contributions plus the 368.58 ZEC left unclaimed before NU6.
- NU7 also adds the ZIP 218 shielded action limits.
- ZIP 233 and ZIP 234 are **not** deployed. Zakura's code still names the mechanism "ZIP 234", with the same values.
- There is no new transaction format, and no new coinbase field: the fee split is a block-level calculation.

## Tests (differential against Zebra/Zakura code, and real Testnet data)

```sh
python3 test/compare_vectors.py      # Bend nu7.bend vs Zebra oracle: subsidy, halving, streams, scripts, fee split, reissuance
python3 test/compare_diff.py         # Bend diff7 vs Zebra AdjustedDifficulty: synthetic chains across NU7, Testnet min-difficulty
python3 test/nu7_rules_mainnet.py    # rules_nu7 (rules.bend + NU7) on Mainnet NU7 heights: 15 cases
python3 test/prenu7_regression.py test_rules|tamper_rules   # fullnode's own suites on the NU7 build
python3 test/parts_check.py          # proposed rules.py: parallel parts predicted exactly (0 reruns)
python3 test/tn_run.py               # all 23,036 real Testnet blocks through bin/tn_check
python3 test/tn_tamper.py 200        # tampered copies of real Testnet NU7 blocks
../../heavy.sh ./bin/equihash7 data/testnet/headers.bin 82676 3758 12 4460000 test   # real Testnet headers
```

Results (Oct 26–27):

| What | Against | Result |
|---|---|---|
| Halving, ScheduledBlockSubsidy, ZCG/Deferred values and ZCG script per height (3,762 Mainnet + 3,755 Testnet heights: activation ±300, every halving/stream/address-period boundary, 3,000 random) | Zebra 1e03ee75 (`oracle/`, built on zebra-chain) | 31,294 values, **0 mismatches** |
| NSMFeeContribution / MinerFees (2,192 fee values per network, 0 … 2.1·10^15) | Zebra | 4,384 cases, **0 mismatches** |
| AdditionalBlockSubsidy + BlockSubsidy with parent balance (around 8,939,664 / 7,305,222) | Zebra | 792 cases, **0 mismatches** |
| Expected nBits on synthetic chains: Mainnet across NU7 (on schedule; hash rate unchanged at 75 s; 8 s blocks), Testnet with 449/450/451/900/901 s gaps, Zakura's chains D/D2 | Zebra `AdjustedDifficulty` (verbatim copy) | 7,411 blocks, 76 of them minimum-difficulty, **0 mismatches** |
| Zebra vs Zakura (oracle/cross.py) | the two implementations | 1,745,265 values, 0 disagreements |
| Real Mainnet headers 3,400,000..3,528,279 and across Blossom (653,000..654,599) through `equihash7` | chain | 128,252/128,252 and 1,572/1,572 difficulty checks pass (unchanged before NU7) |
| **Real Testnet headers 4,460,000..4,542,675** (77,650 after activation, 2 minimum-difficulty blocks, across the 4,497,948 halving) | chain (P2P, links and Equihash checked in Bend) and Zebra oracle | Bend: equihash 82,676/82,676, difficulty **82,648/82,648**. Zebra oracle on the same file: 82,648 checked, 0 mismatches. The same headers checked with pre-NU7 rules: 0/572 pass |
| **Real Testnet blocks**: 23,036 blocks (888 pre-NU7, 22,148 post-NU7) from 4,455,002 to 4,537,095, all blocks with transactions, plus 4,464,826..4,467,026 and 4,497,748..4,498,148 complete | chain: tx versions, branch ids, coinbase funding outputs, miner fees with the 60% NSM contribution, deferred stream, action limits | **23,036/23,036 VALID** (0 disagreements). Bend's fees equal fetch.py's Python fees on 23,036/23,036 blocks (22,226 with fees > 0) |
| Tampered real Testnet NU7 blocks (200 each) | expected rule | miner keeps 100% of fees → `miner_fees` 200/200; ZCG −1 zat and ZCG at the pre-NU7 8% → `issuance_required_outputs`+`miner_fees` 200/200 each; NU6.3 branch id → `branch_id` 200/200; coinbase relabelled v4 → rejected 200/200, but by the wire validator before tx_version (the v4 rule itself is tested on Mainnet below) |
| Mainnet NU7 heights (`nu7_rules_mainnet.py`): real block 3,528,000 relabelled to 3,543,405 / 3,612,389 / 3,612,390 / 3,600,000 / 6,132,390 with the coinbase NU7 requires | ZIPs (expected values from the Zebra oracle) | 15/15 cases: valid blocks VALID with the NSM pool = seed + 60% of fees; a miner taking 100% of fees, a pre-NU7 subsidy, the wrong ZCG script before/after the switch, ZCG 1 zat short, an old subsidy at the third halving, a **real v4 tx** after NU7 (`tx_version`), a negative NSM balance (`turnstile_nsm`), 2,044 Sapling IOs (`shielded_action_limits` at 3,543,405 but not at 3,543,404) |
| Pre-NU7 regression of the NU7 build | fullnode/rules suites | 94/94 real blocks, 16/16 tamper cases, window 3,522,461..90 parallel parts with 0 reruns |

Testnet data: `testnet/fetch.py` fetched it (P2P getheaders/getdata from testnet Zebra peers; spent
outputs from testnet.zec.rocks lightwalletd, raw txs kept in `data/testnet/prevtx/`).
- Header links were checked against lightwalletd's hashes at 82,661 heights.
- 1,284 blocks with transactions near the tip (4,536,934..4,538,xxx) were not downloaded in time (peers timed out). Their headers are verified.
- The Testnet blocks never contain a v4 tx after activation (0 of 104,335 post-NU7 txs).

## Proven laws (`LAWS.bend`, `PROOF.bend`; `bend PROOF.bend --verdict`: ALL PROOFS CHECK, no `@unsafe`)

15 laws. "(spec)" laws are about the Nat form of a formula; its 64-bit runtime form is the
one tested against Zebra above.

| Law | Statement |
|---|---|
| `halving_continuous` | At the activation height the NU7 case of Halving() equals the post-Blossom case, for every network's s, Blossom, A and interval |
| `per_time_le`, `per_time_ge` | For every era: 3 · NU7 subsidy ≤ post-Blossom subsidy ≤ 3 · NU7 subsidy + 2. Issuance per unit time is preserved up to 2 zat per 75 s |
| `transition_era_le` | The era containing activation (x blocks at s, then 3y blocks at floor(s/3)) issues ≤ (x+y)·s |
| `cap_nu7` | K eras of 3n NU7 blocks issue ≤ n·2m, the 75 s bound (21M ZEC for n = 1,680,000, m = 625,000,000) |
| `contribution_exact` (spec) | 6q + floor(6r/10) == floor(6·fees/10) (ZIP 235's claim) |
| `contribution_le`, `fee_split_conserves` (spec) | contribution ≤ fees; contribution + MinerFees == fees |
| `reissue_le` (spec) | ceiling(c·bal/d) ≤ bal for c ≤ d: reissuance never drives the NSM balance negative |
| `nsm_conserves` (spec) | issued' + NSM' == issued + NSM + scheduled subsidy, whatever is reissued or removed |
| `timespan_ge_min`, `timespan_le_max`, `on_schedule` | Bounds and the on-schedule fixed point in all three eras, incl. NU7 |
| `nu7_window_wallclock`, `nu7_timespan_is_pre` | 102 × 25 s == 17 × 150 s; the NU7 timespan function *is* the pre-Blossom one |

## Wiring (proposed; `wiring/`)

None of these files is changed in place. The live genesis sync, the tip instance and follow
keep running the old code until the coordinator applies the diffs.
- `wiring/rules.bend.diff`: `fullnode/rules/rules.bend`. Imports consensus/nu7, adds a 7th pool (NSM, ctx header 56 bytes, `pools` line 7 values), adds per-block action counts, and for h ≥ 3,543,405 uses the NU7 subsidy (+ reissuance), `required7` outputs, the NU7 deferred stream, MinerFees, `shielded_action_limits` and `turnstile_nsm`. It removes the `skip … NU7 pending` line. Pre-NU7 behaviour is unchanged (94/94 + 16/16). The same source, with import paths adjusted, is `rules/rules_nu7.bend` → `bin/rules_nu7`.
- `wiring/rules.py.diff`: `fullnode/rules.py` (against 22b9bb0). POOL_NAMES gets `nsm`; the parse of 7 pools; `RULES_BIN` (env `ZEBEND_RULES_BIN`, default `bin/rules`); `predicted_delta` returns 7 values (NSM: seed at A + floor(6·fees/10)), the NU7 lockbox value (6,249,999 until 6,132,390), and **18,750,000** before NU7. The committed value is 9,375,000, which is wrong, so every part after the first was mispredicted and rerun. The bin/rules rebuild and this rules.py must be switched together, because the ctx format changes.
- `wiring/zebend_follow.py.diff`: follow uses `equihash7` with the first header's height. It keeps 113 headers (DIFF_WINDOW), accepts difficulty checks that all pass and cover ≥ the new headers (the semantics of tiphdr f1f9ee8), and refuses NU7 headers with fewer than 113 stored. Follow's state keeps 29 headers today and grows to 114 within one window, so restart follow before 3,543,405.
- `fullnode/tiphdr.py`: already switched to `equihash7` with 113 context headers by the coordinator (f1f9ee8). `follow/bin/equihash7` is `bin/equihash7` (built from `headers/main7.bend` with the bend-fork).
