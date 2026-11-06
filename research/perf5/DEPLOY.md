# Deploying perf4 into the node

Two binaries change. Both read the same arguments and print the same verdict lines as the
perf3 builds they replace, so no driver or hook code needs to change.

| Node path | Replace with | Built from | Used by |
|---|---|---|---|
| `node/follow/bin/halo2_batch` | `research/perf4/v/batch_main` | `v/batch_main.bend` | `node/follow/zebend_follow.py` `halo2_check` and the orchard hook `node/hooks/orchard` (both call `node/follow/bin/halo2_batch PARAMS bundle...`) |
| `node/follow/bin/halo2_one` (optional) | `research/perf4/v/bundle_ba` | `v/bundle_ba.bend` | the same two callers, to pinpoint a bundle when a batch is rejected |

Leave `node/follow/bin/halo2_two` alone. It is the second, independent build that must agree
before a bundle is declared invalid.

Bend builds are not byte-reproducible: two builds of the same source give different binaries.
`research/perf4/v/batch_main` and `v/bundle_ba` are the exact binaries every check below ran on.
If you rebuild, run `t/verify_all.sh` again, and ideally `t/full.py`.

## Steps

```sh
cd /Users/betterclever/projects/zecathon/zebend

# 1. build (or use the binaries already in research/perf4/v/). Needs the fork's zebend worktree
#    (bend-fork-zebend >= 3fbef653, for File.read_words); bun peaks near 8 GB on batch_main.
(cd research/perf4 && ./build.sh v/batch_main.bend v/batch_main && ./build.sh v/bundle_ba.bend v/bundle_ba)

# 2. check them before the swap
research/perf4/t/verify_all.sh            # every line PASS / 42/42 / 10/10 / 8/8 / MATCH

# 3. swap, keeping the old ones
cp node/follow/bin/halo2_batch node/follow/bin/halo2_batch.perf3
cp node/follow/bin/halo2_one   node/follow/bin/halo2_one.perf3
cp research/perf4/v/batch_main node/follow/bin/halo2_batch
cp research/perf4/v/bundle_ba  node/follow/bin/halo2_one      # optional

# rollback
cp node/follow/bin/halo2_batch.perf3 node/follow/bin/halo2_batch
cp node/follow/bin/halo2_one.perf3   node/follow/bin/halo2_one
```

The orchard hook (`node/hooks/orchard`) reads `node/follow/bin/` directly, so it picks up the
swap with no edit. Do not put a `params_g.bin.gtab` file next to
`zcash/halo2/verifier/data/params_g.bin`: the fixed-base G table is optional, was measured as
no faster (README, "What did not work"), and without the file the binary simply prints
`gtab 0`.

## Output, unchanged where it is parsed

```
verified <K> unreadable_or_missing <0|n>
batch K <K> result <0|1>              <- the line both callers parse
batch_ms <ms> per_bundle_ms <ms> warm 1
gtab <0|1> read_ms <ms> proofs_ms <ms> final_ms <ms>     <- new, informational
```

The verdict rule is unchanged: `result 1` only if every proof's transcript checks pass, the
merged MSM is the identity, `verified K == K` (the 9c0b0ec guard) and no bundle is empty or
unreadable. `halo2_one` prints `result 0|1` (and the full trace with `-v`) as before.

## Behaviour differences to know

- **Files are read with `File.read_words`, eight or more at a time** (groups of 64 on forked
  IO actions). A path that cannot be opened ends the process with no verdict line, as in
  perf3. A read error after a successful open now does the same, where perf3 counted that
  bundle as `unreadable_or_missing`. Both callers already treat "no verdict" as a verifier
  error (retried, never "invalid"). An empty file still gives np = 0 and rejects the batch.
- **Batch weights:** r_i = the low 128 bits of BLAKE2b(256-bit OS seed ‖ i), with the seed
  from 8 `IO.random_u32` calls. perf3 made 4 `IO.random_u32` calls per bundle. The weights
  stay unpredictable to the prover.
- **Memory:** less than perf3 (`/usr/bin/time -l`, max RSS): 512 bundles 163 MB (perf3
  603 MB); 3,840 bundles 620 MB (perf3 3.7 GB).
- **Threads:** the binary uses every core by default, as before (`+RTS --threads N -RTS` still
  works).

## What was verified on these exact binaries

See `README.md` § Exactness: 42-bundle honest/tampered batches; the single verifier on all
three circuit sets; 42/42 `-v` traces identical to perf3; MSM equal to `best_multiexp`; the
10,048-bundle sample; the full 392,806-bundle run (`t/full_final.log`).
