# zebend fullnode: a Zcash full node that keeps state, not blocks

**Status (Oct 26, end of the first session): a working pipeline, not yet a replacement node.**
The genesis sync runs but is limited by how fast peers serve old blocks (§2): at the rates
measured here it would take days. As a fallback, a second instance runs **full validation
from just below the last checkpoint** with an *assumed* (oracle-assisted) starting state; it is
labelled as such everywhere and is **not genesis-verified**. Numbers below come from `logs/`.

```sh
python3 checkpoints.py              # once: Bend re-hashes every verified header, checks Zebra's checkpoints
python3 tiphdr.py                   # extend the verified headers to the live tip (Bend: zebend-p2p + equihash)
python3 download.py --peers 30      # blocks from genesis into a bounded spool (resumable)
python3 sync.py                     # Bend extraction + rules + state, one atomic commit per window (resumable; see §6)
python3 rpc.py --port 8232          # zcashd-compatible JSON-RPC subset
python3 rpccli.py getblockchaininfo

# fallback instance (assumed state from 3,522,000; NOT genesis-verified):
ZEBEND_STATE=$PWD/state-tip ZEBEND_SPOOL=$PWD/spool-tip python3 download.py --from 3522000
ZEBEND_STATE=$PWD/state-tip ZEBEND_SPOOL=$PWD/spool-tip python3 sync.py --assumed-start 3522000
ZEBEND_STATE=$PWD/state-tip python3 rpc.py --port 18233
```

## Architecture

```
 download.py (net.py)             sync.py                                              rpc.py
 ─────────────────────            ──────────────────────────────────────────────────   ──────────────────────
 P2P, many peers (IPv4+IPv6,      bin/blockdelta (Bend), parallel: block hash, header   JSON-RPC over the state;
 addr gossip, address book),       == verified header, merkle root over Bend txids,     block/tx bytes fetched
 per-peer request sizing,          per-tx state deltas                                  from P2P on demand and
 sliding window over heights      checkpoint rules (every height)                       re-checked by Bend
   ──► spool/ (≤ 30 GB, chunk     bin/rules (Bend): audit mode ≤ checkpoint (tracks     before use
   deleted after its window        pools from genesis), full mode above it
   commits)                       anchors; verifier hooks (transparent, sapling, orchard)
                                  store.py: SQLite + leaf logs, one atomic commit/window
                                  (writer process; pipelined, see §6)
```

Python moves bytes, looks things up and compares what Bend prints. Parsing, hashing, txids,
merkle roots, header-chain hashes, the Sprout tree and every consensus-rule decision are Bend:
`hdr/hdrchain.bend`, `bend/{delta,parse,zip244}.bend` (see `bend/README.md`),
`rules/rules.bend` (see `rules/README.md`), `trees/sprout.bend`. Storage lookups (UTXO,
nullifier and anchor membership) are SQLite.

## 1. Checkpoint sync

**Checkpoint list:** Zebra's `zebra-chain/src/parameters/checkpoint/main-checkpoints.txt` at
commit `7a839a630da08739017ceb0e5516755a0b57ad52` (2026-10-19), saved as
`checkpoints/main-checkpoints.txt` (sha256 `583a8aeb808db374635239c2372b308a52deefcd370e2766cf1a6e0dc7ebba80`):
14,444 checkpoints, the last at **3,522,460**.

`checkpoints.py` runs `hdr/hdrchain` (Bend: SHA-256d of every header and every hashPrevBlock
link) over all headers 1..3,528,279, which `node/headers` had already verified in Bend
(Equihash, hash ≤ target, links), in 142 slices (131 s). Result (`state/hdr/checkpoints.json`):
**14,444 / 14,444 checkpoint hashes equal the Bend-computed hashes**, every link holds. The
Bend hashes are `state/hdr/hashes.bin`, the index the node requests and checks blocks by.
`tiphdr.py` extends it above 3,528,279 with the same Bend programs follow uses (zebend-p2p
hashes + links, equihash: Equihash, target, links, difficulty): 3,528,280..3,530,563 appended,
all checks PASS.

| Rule | ≤ 3,522,460 (checkpointed) | > 3,522,460 (full validation) |
|---|---|---|
| Header: Equihash, hash ≤ target, prev link, difficulty (Bend) | ✅ all headers | ✅ |
| Block hash == hash chain through Zebra's checkpoints; header bytes == verified header | ✅ every block | ✅ |
| Merkle root over Bend-computed txids (SHA-256d v1–v4, ZIP 244 v5/v6) | ✅ | ✅ |
| Wire well-formedness, block ≤ 2,000,000 bytes (node/wire validator) | ✅ | ✅ |
| First tx is a coinbase | ✅ | ✅ |
| Every transparent input spends an existing unspent output; no BIP 30 overwrite | ✅ (state) | ✅ (state) |
| No nullifier reused (Sprout, Sapling, Orchard, Ironwood) | ✅ (state) | ✅ (state) |
| Non-crypto consensus rules (`rules/README.md`: coinbase, issuance/funding streams/lockbox, fees, value balance, maturity + coinbase shielding, expiry, lock time, sizes, sigops incl. P2SH, versions + branch ids, duplicates, turnstile) | audit only (run, logged, not enforced) | ✅ enforced (bin/rules) |
| Turnstile (no pool negative) | audit, pools tracked from genesis | ✅ when pools are tracked from genesis; **SKIPPED** in the assumed-state instance |
| Ironwood anchors | trusted | ✅ (roots: follow's Bend-computed tree, see §3) |
| Orchard, Sapling, Sprout anchors | trusted | **SKIPPED (tree builder pending)** |
| Orchard/Ironwood RedPallas + Halo 2 | trusted | ✅ hook `orchard` (follow's Bend verifiers) |
| Transparent scripts/ECDSA/sighash | trusted | **SKIPPED (component pending)**: hook `transparent` |
| Sapling/Sprout proofs and signatures | trusted | **SKIPPED (component pending)**: hook `sapling` |
| ZIP 221 history root / hashBlockCommitments | not checked | not checked (pending) |
| NU7 (3,543,405) issuance (ZIPs 218/235/237), Sprout retirement | — | pending (printed `skip`); branch id 0x77190ad9 and v4 retirement implemented, untested |

"Trusted" is the trust Zebra's checkpoint verifier places in its list. "Audit" means bin/rules
runs on every checkpointed block and any disagreement with the canonical chain is logged as
`AUDIT:` and counted in `meta.audit_disagreements` (it would be a bug in our rules).

Hook interface (for the transparent/, sapling/, sapling/groth16/ components): `hooks/README`.
A missing hook is reported `SKIPPED (component pending)` per tx, never as a pass.

## 2. Download throughput (the bottleneck)

`net.py` is transport only (no block parsing: a block is placed by the raw 32 bytes of its
hashPrevBlock field and written to the spool as raw bytes; the downloader uses <1% CPU).
Bend extraction, rules and state run in `sync.py`, a separate process reading the spool.

What limits P2P block serving (Zebra main: `zebrad/src/components/inbound.rs`,
`zebra-network/src/{constants.rs,peer/connection.rs}`), all confirmed by measurement here:
- `DEFAULT_MAX_CONNS_PER_IP = 1`, `MIN_INBOUND_PEER_CONNECTION_INTERVAL = 1 s` (per node): a
  second connection from our IP, or a reconnect while another node is connecting, is reset.
  Our IPv4 already holds follow's 8 connections, so those nodes are reachable only over IPv6.
- A `getdata` is served sequentially, at most 16 blocks / 1 MB (`GETDATA_MAX_BLOCK_COUNT`,
  `GETDATA_SENT_BYTES_LIMIT`), one request at a time per connection; a response that takes more
  than 5 s (`MAX_INBOUND_RESPONSE_TIME`) or meets a loaded inbound service makes Zebra drop the
  connection with probability 5–50 % (`handle_inbound_overload`).
- Old blocks are cold on the peers' disks: measured service time is 0.01–3 s per block.

### Before / after

| Fetcher | Heights | Window | blocks/s | MB/s | Peers | Notes |
|---|---|---|---|---|---|---|
| follow's swarm (before) | 3,529,283–3,530,029 | 134 s | 5.6 | ~1 | 8→3 | from follow/README |
| v1 (02:25–03:06): 40–60 targets, 1×12-block request per Zebra peer | 0 → 56,098 | 40 min | ~32 | 0.45–0.60 | 3–20 | 24 handshakes per 2 s: peers started resetting us |
| v1, spam era bench | 1,800,000+ | 229 s | 0.5 | 0.21 | 1–3 | most peers resetting our IP |
| v1, fallback instance near the tip | 3,522,000 → 3,530,564 | ~30 min | 3–7 | 0.1–0.3 | 4–11 | |
| v1 + 4/2 s handshake cap (03:48) | 56,000 → 57,269 | 3 min | 4–7 | 0.06–0.12 | 2–8 | 204 handshake resets: our IP was rate-limited |
| **v2** (04:00): 1 conn/IP + exp. backoff, per-peer request sizing, 2-deep pipeline, scoring + eviction, offset-based buffered reads | 67,000 → 84,885 | 6 min | 49–56 | 0.88–1.04 | 14–17 | best peer 0.38 MB/s |
| **v2b** (04:08): + 4-deep pipeline for fast peers | 84,000 → 107,130 | 10 min | 35–74 | **1.5–2.1** (5-min windows) | 6–22 | best peers 0.89 / 0.51 MB/s; 600+ handshake resets |

(see "Results" for the final long-run line)

**10 MB/s is not reached.** Per peer we measure 0.04–0.9 MB/s; ~15–20 peers accept us at a
time; 600+ handshakes per 10 min are reset (IP rate limiting and full inbound slots). At
~2 MB/s a 277 GB genesis sync takes ~38 h; at Zakura's 18 MB/s average it would need ~20 peers
at 0.9 MB/s, which this IP does not get. What would get there: peers we control or that
whitelist us (a local zcashd/Zebra), more source IPs, or a block archive checked against the
verified header chain exactly like P2P blocks.

**Fallback (running):** full validation from just below the last checkpoint, `sync.py
--assumed-start 3522000` (`assumed.py`), state in `state-tip/`. The state starts empty at
3,522,000; every spent output created before that comes from lightwalletd (labelled oracle)
and is used only if Bend recomputes the creating transaction's txid equal to the one the input
names (value, script and coinbase-ness are then authenticated by the spending transaction).
Not authenticated: the creating height (only used for coinbase maturity) and that the output
was still unspent at 3,522,000. Each such output is listed in `oracle_prevout`. Value pools
are unknown there, so the turnstile is SKIPPED. `live.py` keeps it at the tip (tiphdr.py +
download every 60 s). **This instance is not genesis-verified.** The genesis sync continues
in `state/`; only that instance may ever be called genesis-verified.

## 3. State without blocks (`store.py`)

SQLite (WAL, `synchronous=FULL`) + append-only leaf logs, per instance directory
(`state/`, `state-tip/`; `ZEBEND_STATE`). Budget: < 60 GB.

| Table / file | Content |
|---|---|
| `utxo`, `addr` | transparent unspent outputs (value, script, height, coinbase) + script → outpoint index (`addr` is RPC-only: below the last checkpoint sync.py leaves it empty, `meta.addr_deferred`, and rebuilds it from `utxo` before the first fully validated window) |
| `nf` | nullifier sets: Sprout, Sapling, Orchard, Ironwood |
| `tx` | txid → (height, index); getrawtransaction refetches the block |
| `blk` | block index (hash, prev, time, size, tx count, bits) |
| `anchor` | tree roots per pool (filled as tree builders land) |
| `undo` | per-block undo data, last 200 blocks (`Store.rollback_to`) |
| `meta` | tip, leaf-log lengths, value pools (+ `pools@<h>` per window), rules summary, audit count |
| `leaves/<pool>.bin/.blk` | every note commitment in tree order + per-block counts |
| `oracle_prevout` | (assumed-state instance only) outputs taken from the oracle |

One SQLite transaction per window (≤ 2,000 blocks / 96 MB), written by a separate writer process
(§6); leaf logs fsynced before it and
truncated back to the committed lengths on start. A crash anywhere resumes at the last
committed window; spool chunks are deleted only after their last block commits; windows never
mix checkpointed and fully validated blocks.

**Durability, tested:** `kill -9` of sync.py in the middle of the window 10,000–11,999: on
restart the tip was the last committed one (9,999), leaf logs matched it, and the window was
redone (`logs/sync.log`, "restart after SIGKILL"). **Reorg/undo** (`test_reorg.py`, on a copy):
digest of every table + leaf logs + pools at 105,999, `rollback_to(105,849)` with the undo
data, re-apply the same 150 blocks with sync.py: digest identical (PASS). The first run of this
test found a real bug (an output created and spent in the same block was resurrected on
rollback), fixed in `store.py`. Tip reorgs: `tiphdr.py` cuts the last 10 extra headers when
peers' headers do not link; sync.py then rolls the state back to the last block still on the
verified chain. (Not yet exercised by a real mainnet reorg.)

Note on the genesis state's tip going from 52,999 to 9,999 at 03:52: not a loss. The state
was deliberately wiped and rebuilt from the kept spool twice (03:24, to run the rules engine in
audit mode from genesis so value pools are tracked; 03:52, to store per-block pools so a
rollback restores them exactly); the SIGKILL test happened right after the second rebuild,
at 9,999.

**Trees.** All four pools' leaves are logged, so trees can be built later without the blocks.
- Sprout: `trees/sprout.bend` (Bend, SHA256Compress tree, depth 29). Tested on the real chain
  (`trees/test_sprout.py 2000 20000`): 31,488 of 31,494 JoinSplit anchors in heights
  2,000–20,000 are roots the Bend tree produced; empty root `d7c612c8…59d2` (= zcashd's
  `59d2cde5…c6d7` byte-reversed). The 6 others are 2nd–5th JoinSplits of multi-JoinSplit txs:
  zcashd's interstitial roots are computed from the tree *at the first JoinSplit's anchor*,
  not from the current tree; not implemented yet (Sprout retires at NU7, low priority).
- Ironwood: the fallback instance checks anchors against follow's Bend-computed roots
  (`state-tip/ironwood_roots.txt` = snapshot of `follow/state/roots.txt`).
- Orchard (Sinsemilla, `follow/bin/frontier`): not wired yet. Sapling (Pedersen hash): the
  `sapling/` component. Their anchors are SKIPPED above the checkpoint.

## 4. Consensus rules

See `rules/README.md` (Bend rules engine; per-rule status, tested on 94 real blocks and 16
tampered ones) and the table in §1. In the fallback instance every window above the
checkpoint logs e.g.
`full validation 3522861..3523060: every consensus rule PASS (turnstile SKIPPED …); hooks:
transparent SKIPPED (component pending) 683 tx, sapling SKIPPED 59 tx, orchard PASS 503`.

## 5. RPC (`rpc.py`)

zcashd-compatible JSON-RPC (POST, JSON-RPC 1.0/2.0, batch). Tested by hand with `rpccli.py`:
`getblockcount`, `getbestblockhash`, `getblockhash`, `getblockheader` (JSON/hex), `getblock`
0/1/2 (the block is fetched from a peer by its verified hash and served only if Bend reports
header MATCH and merkle MATCH), `getblockchaininfo` (upgrades incl. NU6.2, NU6.3, NU7
3,543,405 / 0x77190ad9, consensus branch ids, value pools when tracked), `getinfo`,
`getrawtransaction` 0/1, `getaddressutxos`/`getaddressbalance`/`getaddresstxids` (UTXO address
index: unspent outputs only), `sendrawtransaction` (Bend wire validation + txid, then a `tx`
message to up to 4 peers; not yet tested with a real transaction), `getdifficulty`,
`getnetworkinfo`, `getmininginfo`, `help`. `z_gettreestate`: no tree states yet (pending).

**Real lightwalletd, tested** (zcash/lightwalletd `4abfe9cd`, 2026-10-22, built in
`../../lwd-build`; started with `--no-backend-check` because it only accepts zebrad/zakura/
zcashd subversions and we don't impersonate one): it ingested every block from 0 to the
genesis instance's tip (55,999 at the time; ~75 blocks/s, each block Bend-checked by our RPC)
and answered over gRPC (`grpcurl`): `GetLightdInfo` (chain main, blockHeight 55,999,
estimatedHeight 3,530,563, saplingActivationHeight 419,200), `GetLatestBlock`, `GetBlock 1000`
(compact block with the coinbase outputs), `GetAddressUtxos` and `GetTaddressBalance` for
t1TwmpXD8LML63HrrGEYv2eS31vaEb8C1NF (from our UTXO index). Not tested: wallet sync over
Sapling-era blocks (needs `z_gettreestate`, i.e. the Sapling tree), `GetTransaction`,
`SendTransaction` via lightwalletd.

`sendrawtransaction` tested with a real mined tx (3,530,102 tx 2bac5d92…): Bend accepted it and
returned the same txid; a truncated hex is rejected (-22). Relay of a *new* tx not tested.

## 6. Sync throughput (`sync.py`, `store.py`, `rules.py`)

**Profile of the old sync** (one 101 MB window, 324,127–324,435, 309 blocks, 9,751 tx, 648,639
transparent inputs, 110,815 outputs; the 2018 consolidation era): 254 s in total, of which
bin/rules ~200 s (one process over the whole window), the Python ctx builder 26 s (bytes
`+=` per input: quadratic in block size, plus one SELECT per input), state 27–34 s, blockdelta
7–16 s. Findings:
- **bin/rules is superlinear in its input size**: 1.3 s/MB on a 100 MB window, 0.36 s/MB on
  20 MB, 0.14–0.16 s/MB on 2–6 MB (same blocks). blockdelta: 0.19–0.28 s/MB at 2–6 MB.
- **State**: the window's random-key B-tree writes dirty most of the `utxo` table: 1.9 GB of
  WAL per window (464k pages); COMMIT 2 s, WAL checkpoint 6–20 s, 650k row deletes 2 s;
  `synchronous=FULL` vs `NORMAL`: no measurable difference (one fsync per window). Per-row
  Python `execute` calls, a second SELECT per input in the rules ctx builder, and the `addr`
  index (2.3 GB, RPC-only) added the rest.
- **The GIL**: a SQLite writer *thread* next to a busy Python thread is starved (600k deletes:
  4.9 s alone, 641 s next to a CPU-bound thread; lookups 1.5 s alone, 13 s next to a writer
  thread). Hence a writer *process*.
- With `--keep-spool`, every window re-read every chunk since genesis (13 GB at 324k).

**Changes:**
1. *bin/rules in parallel parts* (`rules.run_rules`): the window is cut into parts of about
   total/jobs bytes (≤ 8 MB), one bin/rules process each. bin/rules carries exactly one value
   from block to block (the value pools); part k starts from pools *predicted* in Python and its
   output is used only if that start equals the pools bin/rules itself printed after part k−1's
   last block, otherwise the part is rerun from the printed pools. Every verdict is therefore
   the one a single sequential run prints. Reruns so far: 0. blockdelta parts ≤ 8 MB.
2. *Pipeline*: window k+1's spool read + blockdelta run in a background thread while window k is
   checked, audited and resolved; all Bend processes share one pool of `--jobs` (default
   cores − 2 = 16).
3. *State*: one sorted batch lookup of every prevout per window (shared by the rules ctx and the
   state); the window is resolved in Python in block/tx order (same semantics: missing input,
   double spend in the window, BIP 30, nullifier reuse) and written with one sorted
   `executemany` per table by a **writer process** (`store.Writer`), one transaction per
   window, while the main process already works on the next window (lookups see the
   committed state plus the overlay of the window in flight, `Store.pending`). Reads use a
   second connection. Undo data unchanged (last 200 blocks; rollback works everywhere).
4. `addr` index deferred below the last checkpoint (rebuilt from `utxo` in one sorted pass;
   rebuilt index verified identical to the incrementally maintained one at 12,000).
5. Spool chunks indexed once; chunks below the window never re-read.
6. Kept: WAL, `synchronous=FULL` (every commit durable in the WAL), autocheckpoint after each
   commit (on the writer process, off the critical path). Tried and rejected (measured slower):
   a 4 GB WAL between checkpoints (every page read searches the WAL index: lookups 3× slower)
   and multi-window transactions (`--commit-mb 1024`: cache spill, 2.0 vs 4.7 MB/s).

**Before / after** (Mac M5 Max, 18 cores; bench spools are hard links of the live spool, state
clones of the 324,126 genesis snapshot; spam-era base state: that snapshot relabelled with the
32,292 outside prevouts of 1,800,000–1,802,999 from the oracle, pools unknown, bench only):

| Range | Code | Blocks | MB | Time | blocks/s | MB/s |
|---|---|---|---|---|---|---|
| 324,127–324,700 (consolidations) | old | 574 | 193 | 380 s | 1.5 | 0.51 |
| 324,127–332,000 | new | 7,874 | 888 | 189 s | 41.8 | **4.71** |
| 1,800,000–1,800,449 (spam) | old | 450 | 202 | 55 s | 8.2 | 3.68 |
| 1,800,000–1,802,999 (spam) | new | 3,000 | 1,203 | 64 s | 47.1 | **18.9** |
| 0–12,000 (genesis rebuild) | old / new | 12,001 | 212 | 148 s / 16 s | 81 / 729 | 1.4 / 12.9 |

Spam era: ~5 s per 100 MB window, bound by Bend (rules parts + blockdelta on 16 cores);
consolidation era: bound by the state (writer 5–32 s per 100 MB window, prevout lookups
3–14 s), 9× faster than before but still below the downloader there.

**Equivalence and safety (all on copies):** genesis..12,000 rebuilt by old and new code: every
table (utxo, nf, tx, blk incl. per-block pools, anchor, undo blobs), meta pools/tip/leaf
lengths and leaf logs identical; `addr` identical after the rebuild. The live genesis state
committed by the old code at 324,435 equals a new-code rebuild of 324,127–324,435 from the
324,126 snapshot (every table except the deferred `addr`). Per-block pools and audit
disagreements (0) identical old vs new on 324,127–324,700 and 1,800,000–1,800,449.
`test_reorg.py 150` at 12,000: PASS. SIGKILL of the whole process tree (sync, writer, Bend
children) mid-run, twice (different moments): restart resumed at the last commit (13,500 /
13,000) and the state at 20,000 is identical to an uninterrupted run (PASS).

**State size:** at 324,435 the database holds `utxo` 4.19 GB (28.8M outputs), `addr` 2.30 GB
(now deferred), `tx` 0.15 GB (3.08M tx), `blk` 0.07, `nf` 0.05, `undo` 0.04 GB; leaf logs 32 MB.
That is ~21 GB per million blocks *so far* without `addr` (28 GB with it), but the size follows
the UTXO set (an early-era dust/consolidation set, not a per-block growth): whether the full
chain fits in 60 GB depends on the UTXO set later on; to be re-measured as the sync advances.

**Live genesis instance after the switch** (Oct 27, 14:05, from the old code's committed tip
324,435, without `--keep-spool`; the 324 consumed chunks below the tip were moved to
`work/spool-kept/`, 12 GB): first 8 minutes 324,435 → 342,769 at 36.9 blocks/s, 3.86 MB/s
(consolidation era), writer process RSS 3.6 GB, main 2.6 GB; downloader restarted at 1.58M,
23 MB/s.

## Results (04:20, Oct 26)

- **Genesis instance (`state/`, genesis-verified so far):** tip **105,999**, every block
  checkpoint-checked in Bend, rules engine in audit mode on every block with **0
  disagreements**, value pools tracked from genesis (at 105,849: transparent 1,173,242.11 ZEC,
  Sprout 24,731.33 ZEC), 14.7M UTXOs, 4.0 GB state, 2.6 GB spool. Download at 107,411.
- **Download (v2b fetcher):** 1.5–2.1 MB/s over 5-minute windows (35–74 blocks/s on blocks of
  ~20 KB; 3 blocks/s on the ~600 KB blocks after 106,000); 6–22 peers; per peer, best
  0.87 MB/s (Zebra 4.3), 0.63 (Zebra 7.0), then 0.04–0.31. Target 10 MB/s **not reached**.
- **Fallback instance (`state-tip/`, assumed state from 3,522,000, NOT genesis-verified):** tip
  3,530,611 (live, minute granularity), 8,612 blocks; 8,151 above the checkpoint fully
  validated by bin/rules with every rule PASS, Ironwood anchors PASS, orchard hook PASS;
  transparent and sapling hooks SKIPPED (component pending); 31,159 spent outputs from the
  oracle (Bend-checked txids). One FAIL seen and fixed: an Ironwood anchor newer than the
  root snapshot (the root set now refreshes from follow's live roots).
- **(Superseded by §6: bin/rules now runs in parallel parts.)** Bottleneck after download: bin/rules (audit) is one process per window: ~1.3 s per 2 MB
  block. In the 2022 spam era this would fall behind the download; it needs splitting into
  parallel parts (pool deltas per part, folded in Bend). Not done yet.
- **Disk:** 4.0 GB + 2.6 GB spool + 47 MB; Mac free space 186 GB.
