# Verification

Zebend's claims come in two kinds, and every README in the repository keeps them apart:

- **Tested:** differential testing against the official Rust implementation, on real mainnet data
  where it exists. This shows agreement on the data checked, not correctness in general.
- **Proven:** a Bend law that `bend PROOF.bend --verdict` accepts with no `@unsafe`. See
  [proofs.md](proofs.md).

## On mainnet data

| Component | Data | Result |
|---|---|---|
| Halo 2 (Orchard/Ironwood) | every bundle since NU6.3: 392,806 bundles, 1,155,249 actions | 392,806 / 392,806 verdicts equal `halo2_proofs` |
| Halo 2, all circuit versions | 60 honest and tampered bundles (pre-NU6.2, NU6.2, NU6.3) | 60 / 60 agree |
| RedPallas | 1,283,411 signatures | all valid; tampered ones pinpointed exactly |
| Groth16 (Sapling, Sprout) | 61,168 proofs from 419,201 to 3,529,205, plus a tampered copy of each | 0 disagreements in 391,453 comparisons |
| RedJubjub | 230,769 signatures | invalid sets equal Rust's |
| Transparent | 131,146 inputs across all 11 eras; 23,301 tampered; 604,719 fuzz cases | 0 disagreements with `zcash_script` |
| Headers | all 3,528,279 headers from height 1 | every Equihash, target, link and difficulty check passes |
| Sapling tree | all 73,989,124 leaves | 1,128 / 1,128 subtree roots, 13 / 13 full roots equal the chain |
| Orchard tree | all 50,478,033 leaves | 770 / 770 subtree roots, 6 / 6 full roots equal the chain |
| ZIP 221 | 784,104 Heartwood and Canopy headers plus every activation window | 0 mismatches |
| NU7 | real testnet NU7 blocks | 23,036 / 23,036 valid; 82,648 / 82,648 difficulty checks |
| Live node | every block since it reached the tip | every rule PASS, every hook PASS, ZIP 221 MATCH |
| Zebend vs Zakura | 141 consecutive live blocks | both nodes agree on every block |

## Robustness

- **Fuzzing:** 803,000 differential cases against the Rust parsers; every mismatch found was fixed.
- **Tampering:** every component has tamper tests that must fail at the expected check.
- **Replays:** every block from the last checkpoint to the tip, replayed with all checks on a copy
  of the genesis state: 10,033 blocks, 0 failures.
- **Faults:** crash and reorg tests, including SIGKILL at several points during a reorg.

## Continuous integration

`tools/harden/ci.sh` runs every proof directory, the differential suites, the fuzzers and the
resource-limit probes.
