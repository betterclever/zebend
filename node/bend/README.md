# node/bend: `blockdelta`, every block's state deltas, in Bend

`bin/blockdelta <window.bin>` parses a window of raw mainnet blocks of **any era** (v1/v2
Sprout with PHGR JoinSplits, v3 Overwinter, v4 Sapling with Groth16 JoinSplits, v5 NU5, v6
NU6.3 with Ironwood) and prints what the full node's state needs from each block, plus the two
checks a checkpointed block needs: its header is byte-identical to the verified header at its
height, and its txids hash to the header's merkle root. All of it is Bend: parsing, SHA-256d
(v1–v4 txids, block hash, merkle tree), ZIP 244 (v5/v6 txids), sigop counting, decimal output.

```sh
python3 mkwin.py /tmp/w.bin 0 396 419201 1750000 3460010   # build a window from data/<h>.bin
../bin/blockdelta /tmp/w.bin
```

## Input

`window.bin`: records until EOF: `u32 LE height | 1487-byte verified header | u32 LE block
length | block`. The caller supplies the verified header (from `zcash/headers`, verified in
Bend); `blockdelta` compares the block's header with it byte for byte. Records are read one at
a time (`File.read_at`), so a window can be large; memory is ~80 MB for a 6.5 MB window.

## Output (one line each; implemented exactly as below)

```
block <h> <hash> <prevhash> time <u32> bits <8hex> size <bytes> txs <n> header MATCH|MISMATCH merkle MATCH|MISMATCH
tx <i> <txid> v <ver> ow <0|1> grp <8hex> br <8hex> lock <u32> exp <u32> size <bytes> sigops <n>
cb <scriptSig hex> <sequence>                  any input whose prevout is null (0^32, 0xffffffff)
in <k> <prev txid> <vout index> <sequence>     every other transparent input
out <k> <value> <scriptPubKey hex>
js <vpub_old> <vpub_new> <anchor> <nf1> <nf2> <cm1> <cm2>       per Sprout JoinSplit description
sap <valueBalance> <nspends> <noutputs>        only if the tx has Sapling spends or outputs
ss <anchor> <nf>                               per Sapling spend (v5/v6: the shared anchor, repeated)
so <cmu>                                       per Sapling output
orch <valueBalance> <anchor> <flags 2hex> <nactions>    Orchard bundle, if any actions
oa <nf> <cmx>                                  per Orchard action
iw <valueBalance> <anchor> <flags 2hex> <nactions>      Ironwood bundle, if any actions
ia <nf> <cmx>                                  per Ironwood action
end <h>
```

- Block hash, prev hash, txid and `in` prev txid: **display order** (byte-reversed, as RPCs
  and explorers show them). Nullifiers, note commitments, anchors, scripts: **wire byte order**.
- Amounts are decimal zatoshis: `out` values and `js` vpub are unsigned; `sap`/`orch`/`iw`
  valueBalance are signed (two's complement in the block, printed with `-`).
- `ow 0` for v1/v2 (then `grp` = 0); `br` is the consensus branch id field of v5/v6 (0 before).
- `sigops`: zcashd's legacy `GetLegacySigOpCount` (sum of `GetSigOpCount(false)` over every
  scriptSig, coinbase included, and every scriptPubKey: CHECKSIG/VERIFY 1, CHECKMULTISIG/VERIFY
  20, counting stops at a push that runs past the end). P2SH-accurate counts are not computed.
- A block the wire validator rejects prints `block <h> INVALID wire` then `end <h>`; the next
  record is processed normally.

## Module API (for the consensus rules engine)

`parse.bend` (`import ./parse.bend as P`): a cursor `P.C{xs, pos}`, `P.start(bytes)`,
`P.skip(c, k)`, `P.cs(c)` (CompactSize), and `P.tx(c) -> P.Tx`:

```
P.Tx{ver, ow: Bool, grp, br, ins: +List<P.TIn>, outs: +List<P.TOut>, lock, exp,
     js: +List<P.Js>, sap: P.Sap, orch: P.Bun, iron: P.Bun, size}
P.TIn{prev (32 B, internal order), idx, script, seq}      P.TOut{value: H.U64, script}
P.Js{old: H.U64, new: H.U64, anchor, nf1, nf2, cm1, cm2}
P.Sap{vb: H.U64, spends: +List<P.SSp{anchor, nf}>, outs: +List<cmu>, c}
P.Bun{present: Bool, vb: H.U64, anchor, flags, acts: +List<P.Act{nf, cmx}>, c}
```

(`H` = `zcash/wire/hb.bend`; `H.U64{lo, hi}`.) `P.tx` trusts its input: gate the block with
`zcash/wire/blk.bend parse_capped` first, as `delta.bend` does. The next tx starts at
`P.skip(c, P.tx_size(t))`. `zip244.bend` `Z.txid56(bytes)` gives a v5/v6 txid (internal order);
v1–v4 txids are `S.hash_d` of the tx bytes. `delta.bend` has `udec`/`sdec` (u64/i64 decimal)
and `script_sigops`.

`zip244.bend` is zcash/block's `tx.bend` txid code with its per-element loops made linear
(each step drops the element it consumed instead of re-indexing from the start of the tx).
zcash/block's version is quadratic in outputs/actions: on the 1.96 MB block 1,750,000 it took
2.3 of the 2.5 s; now the whole block takes 0.53 s.

## Tests

**Differential, against zcash_primitives 0.31** (`oracle/`, Rust: `Transaction::read`, then
every field through the crate's accessors, printed in the same format; run
`oracle/target/release/delta-oracle <h>...` and diff): **64 of 64 real mainnet blocks
byte-identical** (heights 0, 1, 2, 396, 397, 500, 2000, 10000, 347500, 347501, 419200,
419201, 476000, 500000, 1000000, 1687104, 1700000, 1750000, 1800000, 3428143, 3460010,
3528000, plus 42 random heights: 36 uniform over 1..3,528,279, 6 in 1.7M–1.9M, 6 post-NU6.3).
Together: 371 txs (75 v1, 13 v2, 32 v3, 130 v4, 86 v5, 34 v6), 1,444 inputs, 3,210 outputs,
39 JoinSplits (PHGR and Groth16), 44 Sapling spends, 5,467 Sapling outputs, 169 Orchard and
40 Ironwood actions, 67 txs with non-zero lock time, sigop counts from 0 to 501 (multisig).
Every block: `header MATCH merkle MATCH` (header vs zcash/headers' verified header; for
genesis, which zcash/headers does not hold, vs itself — its hash equals Zebra's checkpoint 0).
The oracle's `sigops` is its own port of zcashd's `GetSigOpCount(false)` (zcash_primitives has
none), so the sigop column is checked against a second implementation, not official code.

**Tamper** (`python3 tamper.py`): 7/7 caught — a flipped byte inside a v6-era tx and inside
the v2 JoinSplit tx → `merkle MISMATCH`; block truncated by 1 byte, 1 trailing byte, block over
2,000,000 bytes → `INVALID wire`; another height's verified header → `header MISMATCH`; a
flipped header merkle-root bit → `header MISMATCH merkle MISMATCH`. An invalid record in the
middle of a window does not stop the records after it.

## Speed (M5 Max, one process, single-threaded runtime work)

| Window | Time |
|---|---|
| 500 small blocks (2.2 MB, early/mid-chain mix) | 0.50 s: **~1 ms per block** |
| 1 block of 114 KB (3,460,010, v4/v5/v6 mix) | 0.03 s |
| 1 block of 1.96 MB (1,750,000, sandblasting spam: 2,024 Sapling outputs) | 0.53 s user (0.85 s wall) |
| the 63 test blocks in one window (6.5 MB) | 1.64 s, 80 MB RSS |

So one process does ~4 MB/s on large blocks and ~1,000 blocks/s on small ones; parallel
windows scale with cores. Download, not parsing, bounds a genesis sync.

## Limits

- Extraction only: no consensus rules beyond the merkle root / header / wire form (those are
  the rules engine's job, which imports `parse.bend`). Coinbase height, values, signatures,
  proofs are not checked here.
- `sigops` is the legacy count only (no P2SH accurate count).
- `fetch_blocks.py` (test data) asks peers for blocks by the routing index
  (`../state/hdr/routing.bin`); test blocks are in `data/`.

Files: `parse.bend`, `zip244.bend`, `delta.bend` (→ `../bin/blockdelta`), `mkwin.py`,
`fetch_blocks.py`, `tamper.py`, `oracle/`, `data/`, `t/` (profiling variants, not used).
