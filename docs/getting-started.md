# Getting started

## Requirements

- **Apple Silicon Mac.** Everything is developed and measured on an M5 Max (macOS 27). The Bend
  programs compile to C and run anywhere, but the scripts assume macOS and the GPU paths need Metal.
- **Bend 2.** Install the official compiler (`~/.bend/bin/bend`, 2.0.38 or later). Many components
  also need Zebend's local Bend fork, which adds 64-bit multiply primitives (`U32.mul_hi`, `mac64`),
  fast file-to-array I/O and Metal fixes. The fork is not published yet; see [bend.md](bend.md).
- **Python 3** (3.12 or later) for the node's orchestration.
- **Rust** only to rebuild the reference oracles that Zebend is tested against.
- **Disk.** About 15 GB for the node's state; more while syncing from genesis.

## Build

Each component has a `build.sh` next to its sources. Heavy builds go through `tools/heavy.sh`, a
machine-wide lock that also kills jobs above a memory or time limit:

```sh
export BEND_NO_TELEMETRY=1
cd research/perf4 && ../../tools/heavy.sh ./build.sh v/batch_main.bend v/batch_main
```

The node's binaries live in `node/bin/` and `node/follow/bin/`. Compiled binaries are not tracked
in git; the README of each source directory gives its build command.

## Run the node

The supervisor starts and watches every service: `sync` (block validation with push pickup), `rpc`,
`mempool` and `follow` (an independent live monitor).

```sh
nohup python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
python3 node/ops/supervise.py status node/ops/zebend.json
tail -f node/logs/sync.log
```

Each block produces lines like:

```
anchors: Ironwood 2/2 PASS; Sapling 0/0 PASS; Orchard 1/1 PASS; Sprout 0/0 PASS
full validation 3532675..3532676: every consensus rule PASS (turnstile checked); hooks: {...}
history (ZIP 221): 2 MATCH
```

Stop with `kill -TERM` on the supervisor; every service stops at a committed window and resumes
from it.

## Start from a snapshot

A snapshot is the node's state at a pinned height, checked by a digest computed in Bend:

```sh
cd node/snapshot
python3 consume.py work/fast/g3532588.zsnap NEWSTATE   # refuses a digest that is not in pinned.json
```

Import verifies the digest and every tree root, and checks the roots at the snapshot height against
the chain's own block commitments. The node then validates from the snapshot height to the tip.
[node/snapshot/README.md](../node/snapshot/README.md) covers producing and confirming snapshots.

## Use the RPC

`rpc.py` speaks a zcashd-compatible subset on port 18233, enough for lightwalletd:

```sh
python3 node/rpccli.py --port 18233 getblockchaininfo
python3 node/rpccli.py --port 18233 getrawmempool
```

## Check one transaction end to end

```sh
./node/validate/zebend validate                 # header, block, tx, Halo 2 proof, state: all in Bend
./node/validate/zebend validate --tamper proof  # also: header ciphertext signature note doublespend
```

## Run the tests

```sh
./tools/harden/ci.sh
```

CI runs every proof directory, the differential suites against the official crates, the
fuzzers and the resource-limit probes.
