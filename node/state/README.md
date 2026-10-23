# Zebend `state/`: Zcash's shielded state, rebuilt in Bend

This component recomputes the **real mainnet Ironwood note commitment tree** in Bend 2,
using Sinsemilla on Pallas, and matches the **chain's own root** at every checkpoint up
to the tip. It also builds the Ironwood **nullifier set** and catches a replayed nullifier
(a double spend). The set's insertion law is **proven**.

## Results (Apple M5 Max, Bend 2.0.38; machine shared with other jobs)

Data: every Ironwood output from activation (block 3,428,143, ZIP 258) to block
3,528,268: **100,126 blocks, 838,662 leaves**, streamed from `zec.rocks` lightwalletd.
At every 20,000-block chunk our leaf count equals the chain-reported
`ironwoodCommitmentTreeSize`.

| Height | Leaves | Chain root (`GetTreeState`) | Bend, CPU threads | Bend, Metal GPU |
|---|---|---|---|---|
| 3,428,200 | 725 | `f0b2f0c2…df4c3a` | MATCH (0.1 s) | MATCH (1.6 s, includes Metal start-up) |
| 3,448,142 | 58,122 | `444015c1…9cd102` | MATCH (8.8 s) | MATCH (1.3 s) |
| 3,468,142 | 131,132 | `a8f52421…4cfe935` | MATCH (13.6 s) | MATCH (4.4 s) |
| 3,488,142 | 398,133 | `c712f3e3…cb4ee236` | MATCH (26.7 s) | MATCH (11.7 s) |
| 3,508,142 | 693,785 | `a3f94f08…eb79a115` | MATCH (51.9 s) | MATCH (18.8 s) |
| **3,528,268 (tip)** | **838,662** | `5ae9f773…69c0db529` | **MATCH (68.1 s)** | **MATCH (22.5 s)** |

Each row is an independent full rebuild of the depth-32 tree from the first *n* leaves.
For comparison, the Rust `orchard` crate's sequential frontier (one thread) takes 45 s
for all 838,662 leaves.

Incremental frontier (a node's view: append one leaf at a time, single thread): all 838,662
leaves appended in **360 s**, with the root checked at the same 6 heights: **6/6 MATCH**.
Rust's `orchard` frontier does the same in 45 s, so Bend is about 8× slower per core.

Nullifier set: all 838,662 Ironwood nullifiers ingested in 4.9 s. **0 duplicates**
(as consensus requires). Replaying a real nullifier is **REJECTED (double spend)**.

## What is real, tested, proven

| Piece | Status |
|---|---|
| Leaves, nullifiers, chain roots | **real mainnet** data via lightwalletd `GetBlockRange` / `GetTreeState` |
| SinsemillaHashToPoint, incomplete addition ⸭ with ⊥, Extract_P, MerkleCRH^Orchard, empty roots, tree, frontier | **implemented in Bend** (`sinsemilla.bend`). Pallas arithmetic from `../../halo2/lib` |
| Tree roots | **match the chain** at 6 heights (CPU and GPU) |
| MerkleCRH, empty roots | **match the oracle**: 16/16 vectors, 33/33 empty roots (`t/crh_test.bend`) |
| Sinsemilla generators Q and S[0..1024] | **exported** by the Rust oracle (`sinsemilla` crate). Bend checks all 1025 are on the curve but does not re-derive them via hash-to-curve |
| `get(ins(k, t, v), k) == v :: get(t, k)` for every trie, key and value | **proven** (`LAWS.bend`/`PROOF.bend`, `ALL PROOFS CHECK` with `--verdict`) |
| Duplicate detection at runtime | **tested** on mainnet + one injected replay |

"Matches" means differential testing against ground truth. It is not a proof that the
hash code is correct; only the nullifier-set law is proven.

## How it works

- `MerkleCRH^Orchard(l, left, right) = SinsemillaHash("z.cash:Orchard-MerkleCRH",
  I2LEBSP_10(l) ‖ I2LEBSP_255(left) ‖ I2LEBSP_255(right))`. That's 520 bits, so 52 chunks
  of 10 bits, each selecting one of 1024 S generators via a balanced lookup tree.
- Incomplete addition: `acc ⸭ S` and `(acc ⸭ S) ⸭ acc` return ⊥ if an operand is the
  identity or the two share an x coordinate. Consensus (`MerkleHashOrchard::combine`)
  maps ⊥ (and the identity) to 0, and so does `extract`.
- `subroot` hashes both halves of every node in parallel: `a b = f(l) f(r)` on CPU
  threads, or `subroot!` on the Metal GPU. Empty subtrees short-circuit to precomputed
  empty roots, and `lift` pairs the result with empty roots up to depth 32.
- `push` / `froot` are the incremental frontier a node keeps between blocks: one pending
  left sibling per level, amortised O(1) hashes per appended leaf.
- `nfset.bend`: a binary trie on 16 key bits with a bucket at every node, so no malformed
  shapes exist and the law needs no side condition.

## Run

```sh
./run.sh        # oracle sync (~100 s) + all Bend checks
```
Or step by step: `oracle/` (`cargo run --release -- consts | sync | trees … | roots`),
`gen_consts.py`, `gen_inputs.py`, then `bend t/crh_test.bend`,
`bend tree_main.bend -o tree_main && ./tree_main out/cmx.bin {gpu|tree|frontier}`,
`bend nf_main.bend -o nf_main && ./nf_main out/nf.bin`, `bend PROOF.bend --verdict`.

## Gaps

- Ironwood only. The Orchard tree is the same code with different leaves and wasn't run.
- Q and S come from the oracle (on-curve checked) instead of Bend hash-to-curve.
- The nullifier law covers the trie structure. Bucket membership compares 256-bit words
  with `Wd.is_eq` and is tested, not proven. The key is 16 bits of the nullifier.
- Leaves are read in one `File.read_bytes` (27 MB as a byte list), which is fine at this size.
