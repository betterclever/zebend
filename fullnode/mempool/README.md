# fullnode/mempool: a transaction mempool for the Zebend full node

**Status (Oct 27, 18:21): running against the live tip instance (`state-tip`, assumed state from
3,522,000, NOT genesis-verified), on mainnet.** A separate process: it reads the node's state
read-only (SQLite `mode=ro`, like `rpc.py`) and changes no existing `fullnode/*.py` file.
Integration with `rpc.py` is a patch (`patches/`), applied by hand.

```sh
cd fullnode/mempool
python3 mempool.py --state ../state-tip            # P2P on 8233, RPC on 18234 (forwards the rest to rpc.py 18233)
python3 ../rpccli.py --port 18234 getrawmempool true
python3 ../rpccli.py --port 18234 getmempoolstats
python3 tests/test_tamper.py                       # tampered / double-spend txs rejected
python3 tests/test_reorg_readmit.py 3              # reorg re-admission on a copy of the state
python3 tests/test_relay_local.py                  # RPC -> P2P relay between two local instances, protocol, rate limit
python3 tests/test_eviction.py                     # ZIP 401 eviction + rejection caches
python3 tests/test_lightwalletd.py                 # lightwalletd GetMempoolTx / GetMempoolStream
python3 tests/live_report.py                       # report of the live mainnet run (journal + RPC + state)
```

Build the policy program (Bend): `../../heavy.sh ~/.bend/bin/bend bend/txpolicy.bend -o bin/txpolicy`.

## What decides what

All consensus decisions are made by **the same Bend programs that validate blocks**. Python
moves bytes, looks things up in SQLite, and compares what Bend prints.

A candidate transaction is checked as the only non-coinbase transaction of a **synthetic block
at height tip+1** (`txcheck.py`): header-shaped prefix with hashPrevBlock = tip, time = the next
block's median-time-past (Zebra's mempool uses it for lock times), the tip's bits; a synthetic
v5 coinbase (BIP34 height tip+1, one 0-value `OP_TRUE` output, 0 sigops); then the candidate.

| Step | Program | What |
|---|---|---|
| parse | `fullnode/bin/blockdelta` (Bend) | node/wire validator gate, txid, inputs, outputs, nullifiers, anchors, value balances |
| wtxid, ZIP 317, standardness | `mempool/bin/txpolicy` (Bend, `bend/txpolicy.bend`, new) | ZIP 244 auth digest (node/block code), logical actions, conventional fee, unpaid actions, min fee rate, standardness |
| lookups | `admit.py` (SQLite, read-only) | spent outputs exist and are unspent (chain or mempool); no nullifier in the chain's sets or the mempool; not already mined; Ironwood anchors |
| consensus rules | `fullnode/bin/rules` (Bend) | every non-crypto rule, at tip+1: value balance / fee >= 0, expiry, lock time, sizes, sigops, versions + branch id, coinbase maturity, duplicates, ... |
| crypto | hooks `transparent`, `sapling`, `orchard` (Bend) | scripts + ECDSA + sighash; Groth16 + RedJubjub; RedPallas + Halo 2 |

Lines of the synthetic block that are about the synthetic coinbase/header (`tx 0`, `miner_fees`,
`issuance_required_outputs`, `mtp`, header/merkle MISMATCH) are ignored; block-level lines that
can only come from the candidate (`duplicate_spend`, `sigops`, `coinbase_first`, `wire`) are
attributed to it. The per-block `fees` line of `bin/rules` is the candidate's fee; its `sigops`
is the candidate's legacy + P2SH count.

`bin/rules` is rebuilt by others while this runs (its NU7 build reads 7 value pools, the older
6): `txcheck.rules_pool_names()` probes the layout on a coinbase-only block whenever the binary
changes (both layouts tested; the wrong one crashes or prints a different pool count).

### Consensus checks at admission (the same code as blocks)

| Check | How | Status |
|---|---|---|
| well-formed, txid | blockdelta (node/wire gate) | ✅ |
| inputs exist, unspent (chain UTXO set or an earlier mempool tx), not spent by another mempool tx | lookups | ✅ |
| assumed-state instance: outputs created before 3,522,000 | lightwalletd oracle (`follow-lwd rawtx`), used only if Bend recomputes the creating tx's txid; must be older than 3,522,000 and not in `oracle_prevout` | ✅ **labelled oracle data**, as in `assumed.py`; a pre-3,522,000 double spend is not detectable (same limit as the node) |
| nullifiers not in the chain's sets (Sprout, Sapling, Orchard, Ironwood) nor in the mempool | lookups | ✅ |
| Ironwood anchors: a root of an earlier block | follow's Bend-computed roots (as sync.py) | ✅ |
| Orchard, Sapling, Sprout anchors | — | **SKIPPED (tree builders pending)**, as in the node |
| every non-crypto rule at tip+1 | bin/rules | ✅ |
| turnstile | bin/rules | **SKIPPED** in `state-tip` (pools not tracked); checked when the state tracks pools |
| transparent scripts / ECDSA / sighash | hook `transparent` | ✅ |
| Sapling proofs + signatures | hook `sapling` | ✅ (Sprout JoinSplits: the hook FAILs them, unsupported) |
| Orchard / Ironwood signatures + Halo 2 | hook `orchard` | ✅ |
| coinbase txs | bin/rules + extraction | rejected |

### Policy (not consensus), following Zebra main 1e03ee7

| Policy | Where | Zebra source |
|---|---|---|
| ZIP 317: unpaid actions > 0 rejected; fee >= clamp(100 · size / 1000, 100, 1000) | txpolicy.bend | `zebra-chain/src/transaction/unmined/zip317.rs` (MARGINAL_FEE 1,000, GRACE_ACTIONS 2, BLOCK_UNPAID_ACTION_LIMIT 0) |
| standardness: scriptSig <= 1,650 B and push-only; sigops <= 4,000; outputs P2PKH / P2SH / P2PK / OP_RETURN (<= 83 B, at most one); bare multisig rejected; dust | txpolicy.bend | `zebrad/.../mempool/storage.rs` `reject_if_non_standard_tx` |
| AreInputsStandard (spent-output kinds, scriptSig argument counts) | — | **not implemented** |
| ZIP 401: cost = max(size, 10,000); limit 80,000,000 (`--cost-limit`); eviction weight = cost + 40,000 if fee < conventional fee; weighted-random eviction (new tx included) with its dependents | pool.py | `storage.rs` insert, `verified_set.rs` evict_one, `unmined.rs` |
| rejection caches: exact (wtxid; consensus/policy failures; cleared each block), same-effects-tip (txid; conflicts, missing inputs; cleared each block), same-effects-chain (txid; expired, duplicate spend, mined, randomly evicted; <= 40,000 entries, 1 h, cleared on a reorg) | pool.py | `storage.rs` |
| expiry against tip+1 at admission; removal when tip >= nExpiryHeight | bin/rules / admit.recheck | `transaction.rs`, `storage.rs remove_expired_transactions` |
| a child of a mined tx stays (its input is now a chain output) | admit.recheck | `clear_mined_dependencies` |

## Lifecycle

`mempool.py` polls the instance's tip every 2 s (and on a block `inv`). After each new tip:
tip-scoped rejection caches cleared; mined txs removed (the state's tx index); txs whose inputs
or nullifiers are now spent in the chain removed (with their dependents); expired removed; and
**every remaining tx is run through `bin/rules` again at the new tip+1** (expiry, branch id at an
upgrade, ...). On a **reorg** (a cached block's hash no longer matches the state, or the tip goes
down) the chain-scoped caches are cleared and the disconnected blocks' transactions are
re-admitted first (oldest block first, block order), validated against the new tip, then the
re-check runs. The disconnected blocks come from a cache of the last 12 blocks, fetched by hash
over P2P and checked by Bend blockdelta (hash == the state's hash, merkle MATCH).

The state lags the network by one to a few blocks (`live.py` polls every 60 s). A tx spending
an output of a block the state has not synced is rejected as *missing input (the state is
behind the network)*, a tip-scoped rejection: it is fetched again when a peer announces it
after the next block (the crawler asks 3 peers for their mempool every 75 s).

## P2P (`p2p.py`)

Listens on `--port` (default 8233, dual-stack), keeps `--peers` (default 8) outbound peers.
version/verack (relay flag 1, services 0), ping/pong, getaddr -> addr, addr/addrv2 -> address
book, getheaders/getblocks -> empty answers. Transactions: inv (MSG_TX, MSG_WTX = ZIP 239 txid ||
auth digest) -> getdata (<= 50 outstanding per peer, retried from another announcer after 20 s
or a notfound); tx -> admission; getdata -> tx / notfound (a MSG_WTX with another auth digest is
notfound); `mempool` -> inv of the whole mempool; admitted txs announced to every other peer
(batched every 0.5 s). Per-peer token buckets: 50 msg/s (burst 500), 500 inv entries/s (burst
50,000), 1 MB/s of tx bytes (burst 8 MB); > 200 violations: disconnect and 30 min ban.
Inbound: 64 max, 1 per IP (loopback exempt).

## RPC (`--rpc-port`, default 18234)

`getrawmempool` [verbose: size, fee, modifiedfee, time, height, descendant*, depends],
`getmempoolinfo`, `getrawtransaction` (mempool txs, zcashd format without height/blockhash;
others forwarded), `sendrawtransaction` (admits with full validation, then relays; zcashd error
codes -22 decode, -25 missing inputs, -26 rejected, -27 already in chain; a tx already in the
mempool returns its txid), `getpeerinfo`, `getmempoolstats`, `getmempooltx` (mempool only, for
rpc.py). Every other method is forwarded to `--rpc-backend` (rpc.py), so lightwalletd can use
this port as its zcashd.

## Integration patch (not applied)

`patches/rpc-mempool.patch` (rpc.py): `getrawmempool`, `getmempoolinfo` and
`sendrawtransaction` are answered by the mempool process (`ZEBEND_MEMPOOL_RPC`, default
`http://127.0.0.1:18234/`; empty = old behaviour); `getrawtransaction` falls back to the
mempool (`getmempooltx`, which never forwards: no loop). Apply with
`git apply fullnode/mempool/patches/rpc-mempool.patch` and restart rpc.py. **No change to
live.py is needed**: the mempool follows the tip by polling the state read-only.

## Results

All measured on Oct 27 on the Mac (M5 Max), against `state-tip` (assumed state from 3,522,000,
**NOT genesis-verified**). Raw outputs: `tests/results/`, live journal `logs/journal.jsonl`.

**Live mainnet run, 15:39–18:21 IST (2.66 h, tips 3,532,303 → 3,532,427), final code**
(`tests/live_report.py` -> `tests/results/live.json`):

| | |
|---|---|
| distinct txs received (all over P2P, from Zakura/Zebra peers) | 683 |
| admitted | **672** (11 of them after an earlier tip-scoped rejection) |
| rejected (final) | 11 — all tip-scoped Ironwood anchor rejections caused by the state lagging the network: 9 "anchor is a root of a block above the state's tip", 2 "anchor unknown at the state's tip". **All 11 were mined later**, i.e. valid at the network tip; they were never re-announced to us before being mined. |
| admitted, then mined in a later block | **662** (heights 3,532,308–3,532,427) |
| admitted, still in the mempool at the end | 10 |
| admitted, removed for another reason | 0 |
| Bend wtxid (ZIP 244 auth digest) == the peer's MSG_WTX inv id | 525 / 525 v5+ txs announced by wtxid |
| Ironwood anchors checked PASS / SKIPPED (follow behind) | 232 / 4; Sapling 8 and Orchard 6 anchors SKIPPED (tree builders pending) |
| oracle prevouts (pre-3,522,000 outputs, Bend-checked txid) | 166 fetched, 166 accepted, 0 mismatches |
| admission time per batch | median 0.15 s, max 1.15 s (earlier run, 14 txs); RSS ~55 MB after 2.7 h |
| reorgs seen on mainnet | 0 (tested on a copy instead, below) |

Relay on mainnet: 672 txs announced by inv to up to 7 peers each (4,023 inv entries). **2 txs
were fetched from us** (getdata -> tx) by peer 152.53.248.67, 22 s and 27 s after our inv
(2ff131ec…, ccdc8e66…; both mined at 3,532,308). For 534 of the 672 txs another peer announced
the tx to us after we had announced it (215 from a peer we had not sent the inv to), but **nothing
shows those peers got it from us**: we are usually not the first to hear a tx. So "a tx relayed
by us comes back from another peer's inv" is **not demonstrated** on mainnet; what is shown is
peers accepting our announcements (2 getdata) and, locally, a full RPC -> P2P relay chain (below).
No inbound connection from the internet arrived (14 inbound connections, all from 127.0.0.1:
local processes and tests); the listener is tested locally only.

**Tests** (each on real mainnet transactions; nothing created or broadcast):

| Test | Result |
|---|---|
| `test_tamper.py`: baselines admitted; mempool double spends (input, Ironwood nullifier); tampered scriptSig / binding sig / output +10,000 ZEC / expiry = tip / NU6.2 branch id / truncation; fee -> 1 zat (ZIP 317); already mined; double spends of mined txs' inputs and nullifiers | **32/32 PASS** (NU7 build of bin/rules). Each rejection by the intended check: hook transparent / orchard, bin/rules value_balance / expired / branch_id, wire validator, ZIP 317, spend conflict, duplicate spend |
| `test_policy.py`: AreInputsStandard, scriptSig rules, output kinds, OP_RETURN, dust, sigops, ZIP 317 edges | **25/25 PASS** |
| `test_eviction.py`: total cost never over the limit, evicted txs in RecentlyEvicted, eviction frequency vs weights (20,000 trials: 0.098/0.493/0.309/0.100 vs 0.10/0.50/0.30/0.10), exact + malformed caches, cleared at a new block | **7/7 PASS** |
| `test_reorg_readmit.py 5` (copy at 3,532,303; rollback 5, then 5 more; re-apply 10 blocks with sync.py) | **PASS**: 42/50 disconnected txs re-admitted, the other 8 exactly those whose Ironwood anchor is a root of a disconnected block; 2nd rollback 22/22 re-admitted; 22 mempool txs removed by the anchor re-check (+1 dependent), 0 left anchored above the tip; after re-apply 55/55 removed as mined |
| `test_relay_local.py` (B: RPC, C: P2P peer of B) | **13/13 PASS**: 6/6 txs admitted by B via sendrawtransaction, fetched by C over inv/getdata/tx and admitted; ping, getaddr, mempool, getdata/notfound (incl. wrong auth digest), ping flood cut off (494 of 1,247 answered, disconnected) |
| `test_lightwalletd.py` (real lightwalletd with port 18234 as its zcashd) | **PASS**: GetMempoolTx (all pools) 15 txs = getrawmempool 15; default (shielded) 4; GetMempoolStream 15 raw txs |

Bugs found and fixed during the run (kept here because they affected earlier, discarded runs):
an exponential recursion in txpolicy.bend (both arms of `sel_u32` evaluated: a 55-output tx hung
it); oracle outputs from blocks above the state's tip were accepted as pre-start outputs; a
child of a mined tx was removed with it; Ironwood anchors newer than the loaded root set were
rejected as invalid (2 of them were later mined: now refreshed and tip-scoped);
`bin/rules` switched to the 7-pool NU7 layout while running (now probed).

**Not done / limits:** Orchard, Sapling, Sprout anchors SKIPPED (as in the node); turnstile
SKIPPED in `state-tip`; Sprout JoinSplit txs are rejected (sapling hook: unsupported);
pre-3,522,000 double spends undetectable (oracle, as in the node); no orphan pool (a tx whose
parent we have not seen is rejected tip-scoped and fetched again on a later announcement); the
state lags the network by 1–3 blocks, which causes the tip-scoped rejections above; the
genesis instance (`state/`) is far behind the tip, so the mempool is only useful on `state-tip`.

## Files

`mempool.py` (process: worker, tip follower, block cache, RPC), `admit.py` (admission,
re-check, lookups, oracle, Ironwood roots), `txcheck.py` (Bend I/O), `pool.py` (verified set,
ZIP 401, rejection caches), `p2p.py` (transport), `bend/txpolicy.bend` -> `bin/txpolicy`,
`tests/`, `patches/`. Runtime files: `logs/` (log, journal), `state/` (peers, stats), `work/`
(temporary Bend inputs, test copies).
