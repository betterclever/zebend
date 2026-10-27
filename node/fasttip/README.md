# node/fasttip: validate each new mainnet block right after it is announced

**Status (Oct 28, 2026): built and measured on lab clones; not deployed** (`DEPLOY.md` has the
controlled restart). Nothing under `node/*.py`, `node/bin`, `node/hooks`, `node/follow`,
`node/ops` or `node/state` was modified; no live process was restarted. Every number below is a
measurement (files under `RESULTS`), on a Mac that other jobs kept at load average 30-140
(18 cores), so wall-clock numbers are noisy; the load is given with each run.

## Results (measured)

**Live mainnet, lab instance (APFS clone of node/state, own spool/work), 03:54-04:25 IST
Oct 28, blocks 3,532,888-3,532,917, final code (RUN9 in `results/live_lab_tipsync.log`):**
"announcement" = the first time the lab knew the block existed: a push peer's `inv` (3 blocks),
a `headers` reply to the header poll (4), or follow receiving the block (follow tap, 23).

| blocks | n | announcement -> verdict committed: median | p90 | max |
|---|---|---|---|---|
| all | 30 | **0.48 s** | 2.18 s | 2.98 s |
| < 100 KB | 21 | 0.30 s | 0.61 s | 0.89 s |
| 1-2 MB (3,532,902-911, 915) | 9 | 1.90 s | 2.98 s | 2.98 s (orchard hook 0.54-1.43 s of it) |

Per stage (all 30; `fasttip: block ...` log lines): fetch (inv -> block received; follow tap: follow's receipt -> read) median
0.046 s (inv-fetched blocks: 0.34-1.58 s, one peer round trip), Bend header checks + queue median
0.034 s, hand-off to sync median 0.001 s, validate + commit median 0.22 s (p90 1.5 s, the 2 MB
blocks). Machine load average 32-38 during the run.

**Before vs after on the same blocks** (`tools/compare_live.py`: the live node's own commit time of
each height, from its sync.log, minus the lab's announcement time; 21 blocks, 2 excluded where the
lab's reference came late): live node (`live.py --every 60` + sync.py) **median 90.6 s, p90
199.6 s, max 333.8 s**; fasttip on those 21 blocks **median 0.35 s, p90 2.18 s, max 2.98 s**. (The live node's polls
were slow because most peers refused new connections from this IP: tiphdr.py "no headers from any
peer", download.py minutes per block.)

**Replay benchmark** (real blocks, one at a time, arrival = block in hand; fast includes the Bend
header checks; `pick_to_commit` = sync picks the block up -> commit, i.e. without base's 5 s poll):

| run (load avg at start) | blocks | arrival -> verdict median / p90 / max | pick -> commit median / p90 | digest |
|---|---|---|---|---|
| base 3,532,301-460 (15) | 160 | 4.58 / 4.92 / 5.25 s | 0.238 / 0.418 s | bbfc4f07... |
| fast, same blocks (10) | 160 | **0.080 / 0.147 / 0.683 s** | 0.060 / 0.123 s | bbfc4f07... |
| fast, again (40) | 160 | 0.132 / 0.223 / 1.187 s | 0.098 / 0.183 s | bbfc4f07... |
| base 3,532,781-820 (136) | 40 | 4.88 / 5.87 / 9.74 s | 0.397 / 1.171 s | 652dbdcf... |
| fast (37) | 40 | 0.100 / 0.266 / 0.347 s | 0.078 / 0.175 s | 652dbdcf... |
| fast, hooks as subprocesses (30) | 40 | 0.171 / 0.394 / 1.778 s | 0.140 / 0.330 s | 652dbdcf... |
| fast, hooks + tree pools sequential (29) | 40 | 0.194 / 0.439 / 0.687 s | 0.147 / 0.369 s | 652dbdcf... |
| fast, no rules/trees overlap (33) | 40 | 0.222 / 0.557 / 0.977 s | 0.177 / 0.495 s | 652dbdcf... |
| fast, all three off (30) | 40 | 0.227 / 0.648 / 0.780 s | 0.206 / 0.620 s | 652dbdcf... |

Stage medians, 160-block range, base -> fast (s per block): hooks 0.176 -> 0.048 (in-process:
orchard 0.045, sapling 0.044, transparent 0.023, at the same time); trees 0.036 -> 0.029 (pools in
parallel, overlapped with rules+hooks); bin/rules 0.009 -> 0.013 (now overlapped); blockdelta 0.012
-> 0.010; commit 0.001; Bend header checks (fast only) 0.021. In that range the ZIP 221 history
check was SKIPPED in both runs (the rollback to 3,532,300 is not at a window start, so the lab had
no history state; the 40-block range had it: history 0.013-0.020 s).

**Heavy blocks** (pick -> commit, base -> fast, 160-block range): 3,532,346 (280 KB, one 76-action
Ironwood bundle) 0.91 -> 0.66 s; 3,532,455 (153 KB, 37 tx) 0.66 -> 0.19 s; 3,532,304 0.43 -> 0.21 s;
3,532,434 0.46 -> 0.17 s. Live: ~2 MB blocks 1.1-2.3 s validate + commit. What remains is one
process per transaction: `txx` on the 76-action transaction takes 0.86-0.96 s alone (RedPallas
spend-auth for each action, sighash, Halo 2 instances), halo2_batch on all three bundles 0.14 s.
Batching the RedPallas signatures of a whole block (research/sigbatch already verifies them in one
MSM, ~13k sigs/s on 1 thread) needs a txx build that emits the signature items instead of checking
them one by one: **not done** (a new Bend build; not attempted in this time box).

**Target 0.1 s from announcement: met for small blocks only.** Replay median 0.08-0.13 s from
block-in-hand; live median 0.48 s (0.30 s for blocks < 100 KB) from announcement, because a block
announced by `inv` still needs one round trip to the announcing peer (0.3-1.6 s measured from here)
and validate + commit of a typical block is 0.02-0.25 s at load 30-40. 2 MB blocks take 1-2 s.

## What was slow (profile of the live code, before)

At the tip the live node spends almost nothing validating and almost everything waiting:

1. `live.py` polls every 60 s: `tiphdr.py` (a new P2P session per run) then `download.py` (a new
   process and 4 new P2P connections per run) into the spool. On this IP most peers refuse or drop
   new connections, so one poll often takes minutes (live.log: 6 min for one block at 03:08-03:14).
2. `sync.py` sleeps 5 s whenever the spool is empty, then reads the chunk.
3. Validation of a typical block (replay, 40 blocks 3,532,781-3,532,820, load 30-136) took
   ~0.2-0.4 s, of which the verifier hooks were the largest part: they ran **one after another**,
   each as a new Python interpreter (20 ms `python3 -c pass`, ~50 ms with the hooks' imports) that
   starts its Bend binaries; the note commitment trees ran their pools one after another; bin/rules,
   the trees and the ZIP 221 history ran one after another.

Bend binaries themselves start fast (measured: `hdrchain` on one header 4 ms, `equihash7` on 114
headers 13-17 ms, `blockdelta`/`rules`/`history` on one block 5-8 ms at low load), so keeping Bend
processes alive would save little; the churn that mattered was the Python interpreters and the
serial scheduling.

## What fasttip does

One service, `tipsync.py` (replaces `sync` + `live`): sync.py's own main loop, fed in memory.

**1. Push pickup** (`tipfeed.py`)
- Up to `--peers 3` long-lived P2P connections (node/net.py's `Peer`, the code download.py uses;
  IPv6 first, avoiding follow's/tiphdr's fixed peers) listen for `inv` (MSG_BLOCK) and unsolicited
  `headers`. Zcash has no compact blocks (neither zcashd nor Zebra implements BIP 152
  `cmpctblock`/`sendcmpct`), so there is no cmpct announcement to subscribe to.
- An announced block we do not have is requested (`getdata`) **at once from the announcing peer**.
- When it arrives and its `hashPrevBlock` is our verified tip, its header is checked **in-process,
  once per header batch**, by the same Bend programs and the same acceptance rule as tiphdr.py:
  follow's `equihash7` (Equihash, hash <= target, links, difficulty, with the 113 previous
  headers) and `node/hdr/hdrchain` (Bend SHA-256d of the header + link to our tip), run in
  parallel. On PASS the header goes to `state/hdr/extra.bin` and Bend's hash to `hashes.bin`
  (as tiphdr.py does), and the block goes to an in-memory buffer that sync.py reads
  (`sync.BLOCK_SOURCE`): **no spool round trip, no 5 s sleep** (sync waits on the buffer's
  condition variable).
- A block that does not extend our tip (missed one): `getheaders` to that peer; a header batch
  that extends the tip takes the same path (one Bend run per batch), then its blocks are fetched.
- **follow tap**: zebend_follow.py already listens on its own, better-connected peers and writes
  every block it receives to `node/follow/work/win/<h>/block.bin` before verifying it. tipfeed
  reads such a file (read-only; size stable for 30 ms) and treats it like a block from a peer
  (same Bend checks). No extra peer slot. This is "reusing follow's P2P" without a second
  connection to the same nodes.
- Safety net for missed announcements: `getheaders` over an existing push connection every
  `--hdr-poll 5` s (round-robin; one small message, no new connection).
- **Fallback** = the old live.py cycle (tiphdr.py's header step, then download.py into the
  spool), when kicked (fork / missed block), when there is no push source, or after 10 x
  `--every` without a new header. Its header step runs in-process (`_fetch_headers`: the same
  zebend-p2p client, peer list, Bend checks, acceptance and reorg rules as tiphdr.py) so that the
  header-index lock is held only while appending: with tiphdr.py run under the lock (first lab
  version) three pushed blocks waited 68-125 s behind a stalled tiphdr.py (measured, log
  `03:40:09`). Reorgs: tiphdr.drop_tip, then sync.py's own rollback, unchanged.
- hashlib is used only to name blocks for routing (which getdata a block answers), as
  headers.routing_index and net.py do; the header index only ever receives Bend's hashes.

**2. Less per-block churn, more overlap** (`patches/*.diff`, `inproc.py`)
- `rules.py`: the three hooks run **at the same time** (each still gets exactly its own items,
  written as before) and **alongside bin/rules**; results are evaluated in the old order
  (transparent, sapling, orchard, after bin/rules), and every hook finishes before anything is
  raised, so the verdict and the error raised are the ones the sequential code gives.
- `inproc.py` (`rules.HOOK_RUNNER`): a Python hook (hooks/orchard; the `exec python3 X.py "$@"`
  wrappers hooks/transparent, hooks/sapling) runs inside the long-lived process: its source is
  compiled once and executed per call as `__main__` with its own argv/stdout/print. The hook's
  code and its Bend binaries are unchanged; only the interpreter start is gone. Any other hook
  shape runs as a subprocess, as before.
- `trees.py`: the per-pool Bend tree programs (sapling_frontier, orchard_frontier x2, sprout_js)
  run at the same time; results and errors in the old pool order; per-block dict keys re-ordered
  as the sequential insertion order (they are pickled into the undo data).
- `sync.py`: at the tip (a window of fully validated blocks only), bin/rules + hooks start before
  the trees; the trees, anchors and ZIP 221 history run meanwhile; errors are raised in the old
  order (trees/anchors, then rules/hooks, then history). Plus `BLOCK_SOURCE` and the
  event-driven idle wait. With `BLOCK_SOURCE = None` sync.py reads the spool exactly as before.

**3. Heavy blocks**: the hooks overlap each other and bin/rules (above). See "Heavy blocks" for
what remains (one 76-action Ironwood bundle is checked by one `txx` process).

## Equivalence (same verdicts, same state)

- **State digest** (`tools/digest.py`: every meta row except the wall-clock `secs` inside
  meta "rules", the blk / undo / tx / nf / anchor / utxo rows above the start height, row counts,
  leaf logs): identical for base and fast code on every replay, and for each switch turned off:
  40 blocks 3,532,781-820: `652dbdcf...` for base, fast, and fast with in-process hooks / parallel
  hooks+trees / overlap each turned off and all off (`results/abl_r40.out`); 160 blocks
  3,532,301-460: `bbfc4f07...` for base and fast twice (`results/rng_r160.out`); 20 blocks around
  3,532,346: `097f225e...` both.
  The replays also equal the live node's own committed state on every part except `undo` (the
  undo blob of a window's first block carries the ZIP 221 state, and the live node committed those
  blocks in different windows: 2-4 blocks per poll instead of one).
- **Rejections** (`tools/tamper.py`: one byte of a v6 transaction's authorizing data, which the
  txid does not cover, so the merkle root still matches and the block reaches the rules and hooks;
  block 3,532,820 tx 1):
  | tamper | base (live code) | fast |
  |---|---|---|
  | scriptSig signature byte | `RuleFail: hook transparent: [((3532820, 1), ('FAIL', 'transparent input(s) 0 of 2 invalid'))]` | identical |
  | Halo 2 proof byte | `RuleFail: hook orchard: [((3532820, 1), ('FAIL', 'Halo 2 ironwood.bundle rejected'))]` | identical |
  | both | `RuleFail: hook transparent: ...` (transparent is evaluated first) | identical |
  In all three the ZIP 221 history check (which runs earlier in fast, overlapped) would also have
  failed (hashAuthDataRoot changes); fast reports the hook error, as the sequential code does.

## Lab tools (`tools/`)

- `mklab.sh <lab> <golden state> base|fast`: a node root next to the live one, with copies of
  node/*.py (+ patches for `fast`), symlinks to the read-only parts, and an APFS clone of the
  golden state (itself a `cp -c` clone of node/state taken right after a commit, `PRAGMA
  quick_check` ok).
- `fetch_blocks.py`: real blocks by verified hash (net.Fetcher, 3 peers).
- `replay.py`: rolls a lab state back (undo data) and replays real blocks one at a time as they
  would arrive (base: spool chunk; fast: handed to tipfeed like a received block, after cutting
  the lab header index back so the Bend header checks run too); prof.py times every stage.
- `ablate.sh`, `abba.sh`: base / fast / each switch off; A-B alternation under load.
- `digest.py`, `tamper.py`, `summarize.py`, `compare_live.py` (lab announcement times vs the
  live node's commit times for the same heights).

## Not done / caveats (honest list)

- **Peer slots.** From this IP most peers refuse or drop new connections within seconds (measured:
  12 of 12 handshakes refused in one probe; push peers lasted 0-110 s). Own push peers delivered
  only 3 inv-announced blocks in the final run; the follow tap carried most. In production the tap
  depends on zebend_follow.py running and on its work-dir layout (`work/win/<h>/block.bin`); without
  it tipsync falls back to its own peers, the header poll and, last, the old polling cycle.
- Follow-tap times start when follow had the block, not at the network's first announcement; in one
  burst (3,532,895-896) follow lagged and the live node had committed them first (excluded above).
- Not exercised live: a real reorg (the code path is tiphdr.py's drop_tip + sync.py's rollback,
  unchanged) and a block that fails validation on mainnet (tampered blocks in the lab only).
- Long-lived Bend worker processes: not built (Bend start-up is 4-17 ms here; the Python interpreter
  per hook was the real churn and is gone). RedPallas block batching: not done (above).
- During probing I connected once for 150 s to 136.115.98.175 (follow's fixed header peer, it was in
  peers.txt); follow kept running. tipsync now never picks net.KNOWN peers.
- Lab leftovers: `/Users/betterclever/projects/zecathon/ftlab/` (golden clone of node/state at
  3,532,820, the `base` and `fast` lab roots, 600 fetched blocks). Delete when done; nothing there
  is used by the live node.
