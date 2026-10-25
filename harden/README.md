# harden/: production hardening of Zebend's Bend code

Four parts: differential fuzzing of every parser against the Rust crates, resource limits,
a constant-time ivk path for the scanner, and one CI script. Nothing outside `harden/` was
edited. The fixed code lives here, and **"Merge plan"** below lists what goes where.

## Results at a glance

| Parser (Bend) | Reference | Cases | Mismatches | Crashes | Peak RSS / chunk |
|---|---|---:|---:|---:|---:|
| CompactSize, `lib/cs.bend` | `zcash_encoding::CompactSize::read` | 100,000 | **0** | 0 | 3 MiB |
| Block header, `lib/blk.bend` | `zcash_primitives BlockHeader::read` + 1344-byte solution | 100,000 | **0** | 0 | 98 MiB |
| P2P framing, `lib/frame.bend` | zcashd `CMessageHeader::IsValid` rules (written out in the oracle) | 100,000 | **0** | 0 | 63 MiB |
| Transaction v1–v6, `lib/txv.bend` | `zcash_primitives Transaction::read` (+ full consumption) | 200,000 | **0** | 0 | 101 MiB |
| Block splitter, `lib/blk.bend` | header + `CompactSize` + `Transaction::read` × n + exact end | 103,000 | **0** | 0 | 51 MiB |
| Halo 2 bundle input, `lib/bundle.bend` | the format's spec (`tools/bgen.py`; Zebend's own format, no Rust parser) | 100,000 | **0** | 0 | 94 MiB |
| *current* node/p2p `read_compact` | same as CompactSize | 100,000 | 59,675 | 0 | 3 MiB |
| *current* node/p2p `msg.parse` | same as P2P framing | 100,000 | 30,780 | 0 | 63 MiB |

Every mismatch in the current node/p2p code is an input Rust rejects that node/p2p accepts
(`0 -> 1`) or keeps waiting on (`0 -> 2`). The hardened parsers agree with Rust on every one
of the 803,000 cases. All runs are on the M5 Max, in chunks of ≤ 4 MB of input per process.

| Constant-time scan (`scan_ct/`) | 1 thread | 18 threads | Metal |
|---|---:|---:|---:|
| scan2 as is (medians of 3, outputs/s) | 13,430 | 185,130 | 1,115,506 |
| masked selects (medians of 3, outputs/s) | 13,003 | 174,298 | 894,689 |
| cost | −3% | −6% | −20% |

The hit lists MATCH at 4,096 / 16,384 / 65,536 / 262,144 outputs for both builds on Metal,
and at 16,384 (1T) and 65,536 (18T) on CPU.

## 1. Differential fuzzing

**Oracle.** `oracle/` is a Rust crate on `zcash_primitives` 0.31, `zcash_protocol` 0.11 and
`zcash_encoding` 0.5. `harden-oracle MODE N OUT` writes `OUT.cases` (u32 length + bytes per
case), `OUT.expect` (Rust's verdict per case) and `OUT.kinds` (the mutation applied).
`HARDEN_SEED` selects further independent batches.
- **Seeds:** 119 real mainnet transactions (`node/tx/mainnet` plus every tx of the 10
  `node/block/data` blocks; v4, v5, v6), 4 synthetic pre-Sapling transactions (Sprout v1,
  v2 with a PHGR joinsplit, v3 with a joinsplit, v4 with a Groth16 joinsplit; Rust must
  accept each one), mainnet headers, the 10 blocks, and P2P frames.
- **Mutations:** keep, truncate, append, bitflip, head_byte, CompactSize-marker rewrite,
  random 32-byte word (hits every point/field encoding), splice, insert/delete byte,
  32-bit field rewrite, garbage, concatenation. Parser-specific ones: Equihash solution
  length, declared frame length, command bytes, block tx count.
- **Accept rates (Rust):** cs 40%, hdr 40%, frame 39%, tx 40%, block 38%, bundle 24%.
  Versions 1, 2, 3, 4, 5 and 6 all appear on both sides.

**Driver.** `fuzz.py MODE [--src NAME]` splits the cases into chunks, runs `./fz MODE chunk
count` in parallel under `/usr/bin/time -l`, and compares line by line. It reports
mismatches by mutation kind (with examples), a rust→bend verdict matrix, crashed chunks
(non-zero exit or missing lines), throughput and peak RSS. `./fz` is `fz_main.bend` built
natively. Its modes are `cs hdr frame tx block bundle` (the hardened parsers) and
`cs_old frame_old` (node/p2p's current code).

**The hardened parsers** (`lib/`, all pure Bend, all `bend --check-only` clean):
- `hb.bend`: a byte cursor `S{bytes, remaining}`. Every read returns `None` on short input,
  so nothing reads past the end. Also: u64 amounts, MAX_MONEY range checks for Zatoshis
  (0..=MAX) and ZatBalance (−MAX..=MAX).
- `cs.bend`: canonical CompactSize. Rejects `fd` < 253, `fe` < 2¹⁶, any `ff`, and values
  > 0x02000000. Rejects short input.
- `txv.bend`: `Transaction::read` for Sprout v1/v2, Overwinter v3, Sapling v4, NU5 v5 and
  NU6.3 v6, rule for rule (each def cites the reader it mirrors). It covers:
  - the version-group / version pairs and the known consensus branch ids;
  - transparent amounts;
  - Sapling `cv` decoding and not-small-order checks, canonical `cmu`/anchor (BLS12-381
    scalar, `fr.bend`) and `rk` decoding (Jubjub ZIP 216, `jj.bend`);
  - JoinSplit vpub ranges, PHGR vs Groth proof sizes, and the binding signature presence
    rules;
  - Orchard/Ironwood actions: Pallas `cv`/`rk`/`epk` decoding, `rk` and `epk` not the
    identity, canonical `nf`/`cmx`/anchor;
  - the per-branch bundle version (InsecureV1 before NU6.2; Ironwood only from NU6.3),
    flag bits, and the proof length `2720 + 2272·n`.

  Each vector's count is checked against the remaining bytes (count × minimum element size)
  before any element is read. That pre-check rejects exactly the inputs that would hit EOF.
- `blk.bend`: a header is 1487 bytes with `fd 40 05` at offset 140. A block is a header, a
  canonical tx count bounded by remaining/10 (the smallest tx is 10 bytes), the txs, and an
  exact end. `parse_capped` applies MAX_BLOCK_SIZE (2,000,000) first.
- `frame.bend`: magic, command (printable up to the first NUL, then only NULs), length
  ≤ 2 MiB decided from the 24-byte header, `24 + len` computed without wrap, checksum.
- `bundle.bend`: the Halo 2 verifier's input (`np, ni, plen, proof, instances`):
  1 ≤ np ≤ 2439, ni = 10, plen = 2720 + 2272·np, exact total length, and canonical
  instance values.

### Findings

1. **node/p2p `read_compact` (also copied in node/block/bytes.bend) is not canonical and
   not bounded:** `fd 05 00` reads as 5; `ff` + 8 bytes reads as a 4-byte value (`ff ff..` →
   4294967295); there is no 0x02000000 cap; short input reads as zeros (`""` → `1 0 1`).
   59,675 of 100,000 cases are accepted where Rust rejects them. **Fixed:** `lib/cs.bend`.
2. **node/p2p `msg.parse` has no payload cap:** a header declaring 2 MiB + 1 … 4 GiB returns
   `NeedMore` forever, and node.bend keeps buffering whatever the peer sends (14,129 cases
   of `0 -> 2`). **Fixed:** the length is rejected from the header alone.
3. **node/p2p `msg.parse` length wrap:** `24 + len` is U32. With `len = 0xFFFFFFE8` the sum is
   0, and with the checksum of an empty payload (`5df6e0e2`) the message is accepted as
   `ping` with a 0-byte payload while the declared length is ~4 GiB. `rest` then becomes
   empty, dropping the rest of the buffer. **Fixed:** `len ≤ n − 24` after `n ≥ 24`.
4. **node/p2p accepts invalid commands** (non-printable bytes, bytes after a NUL), e.g.
   `v\rr\x9eck\x7f` (16,651 cases of `0 -> 1`). zcashd disconnects such peers. **Fixed.**
5. **halo2/verifier `bundle_main` trusts its header words:** `ni = 0xffffffff` grew to
   **7.9 GB RSS and crashed** after 65 s; `np = 0xffffffff` **never finished** (killed at
   120 s); `np = 1000` took 4.3 s to reject; **trailing bytes were ignored** (a bundle plus 64
   junk bytes → `result 1`). **Fixed:** `bundle_main_h.bend` (a copy of bundle_main with the
   `lib/bundle.bend` check in front). Every malformed probe is now `result 0` in ≤ 2 MB and
   < 10 ms, and the 42 bundles still agree with halo2 42/42.
6. **node/tx `parse` and node/block's splitter assume well-formed input.** They compute
   digests, not verdicts, and handle only the shapes they expect (v5/v6, or v4 via
   `v4_end`). They were not fuzzed as validators. Instead, gate them with `txv.valid` /
   `blk.parse_capped` (see "Merge plan"). With that gate in place, every byte string they
   see has been checked against Rust's reader by the fuzzing above.

No mismatches were found in the hardened parsers. Two harness issues were found and fixed
along the way: the old parser printed command names containing `\n`, which shifted the
output lines (names are now sanitized), and `tools/order.py` truncated a file before failing
on a cycle (it now writes only on success).

## 2. Resource limits

`tools/limits.py` runs each adversarial input alone and records the verdict, time and peak
RSS (bound: 256 MiB):

| parser | adversarial input | bytes | verdict | time | peak RSS |
|---|---|---:|---|---:|---:|
| tx | vin count 2²⁵ (cap), 40 bytes left | 65 | reject | 0.01 s | 2 MiB |
| tx | vin count 2²⁵ + 1 (over cap) | 25 | reject | 0.00 s | 2 MiB |
| tx | script length 2²⁵, 1 KB present | 1,086 | reject | 0.00 s | 2 MiB |
| tx | Orchard action count 2²⁵ | 4,125 | reject | 0.00 s | 3 MiB |
| tx | Sapling output count 2²⁴, 1 MB present | 1,048,604 | reject | 0.03 s | 67 MiB |
| tx | 60k joinsplits (v2), 1.9 MB of zeros | 1,900,013 | reject | 0.05 s | 120 MiB |
| block | tx count 2²⁵, header only | 1,492 | reject | 0.01 s | 2 MiB |
| block | 2,000,001 bytes (over MAX_BLOCK_SIZE) | 2,000,001 | reject | 0.05 s | 126 MiB |
| block | 199,000 minimal txs (~2 MB, valid) | 1,991,492 | `1 199000` | 0.11 s | 126 MiB |
| frame | declared length 2³² − 1, header only | 24 | reject | 0.00 s | 2 MiB |
| frame | declared length 2 MiB + 1 | 24 | reject | 0.00 s | 2 MiB |
| frame | declared length 2 MiB, 1 KB present | 1,048 | need more | 0.00 s | 2 MiB |
| frame | length 0xFFFFFFF0 / 0xFFFFFFE8 (wrap) | 88 / 24 | reject | 0.00 s | 2 MiB |
| cs | `ff` + u64 max | 9 | reject | 0.00 s | 2 MiB |

**Memory is bounded by input size, never by a declared count or length.** Every count is
checked against the remaining bytes before any element is read. The constant is ~63 bytes
of RSS per input byte (Bend's list cells), so a maximal 2 MB block peaks at ~126 MiB. The
remaining unbounded allocation is reading the input itself. A node should read with
`File.read_bytes(f, 2000001)`, or hold ≤ 2 MiB + 24 per peer buffer (the frame cap
guarantees this), so oversize input is rejected at the read. Over the whole fuzzing
campaign, peak RSS per 4 MB chunk never exceeded 101 MiB.

## 3. Constant-time ivk in the scanner

scan2's per-output work depended on the secret key in two places:
- **Table lookups:** `G.get(t, d)` walks `d` list cells (via `nth`) for each of the 64
  digits of the GLV-split ivk.
- **Sign handling:** `G.neg_if(n1, …)` / `neg_if(flip, …)` match on the GLV sign bits; one
  arm runs `B.neg`, the other nothing.

`scan_ct/scan.bend` (a copy; changes marked `CT:`) replaces both:
- `ct_get` folds over all 16 entries, selecting with `pt_sel` (limb masks via fp64's
  `B.sel`) under a branch-free `eq16(i, d) = ((i ⊕ d) − 1) >> 31`.
- `ct_neg` always computes `−y` and selects.

**Audit of the rest of the per-output path:** point add/double are the complete RCB
formulas, and field mul/add/sub are straight-line. BLAKE2b/ChaCha20 run over fixed lengths.
`prep`/`G.split` run once per key as straight-line masked arithmetic. The branches that
remain depend only on public data:
- `mid_of` on failed `epk` decompression;
- the variable-time square root on `epk`;
- `enc_fin` / `z_of` on an identity result, which only an identity `epk` can produce;
- the final hit bit (the output itself).

**Measured leak, and its removal.** The same 16,384 outputs were scanned with ivk = 1
(almost all digits 0, so the shortest walks), the real ivk, and 2²⁵⁴ − 1, on 1 thread,
3 runs each:

| build | ivk = 1 | real ivk | 2²⁵⁴ − 1 |
|---|---|---|---|
| scan2 | 1206 / 1206 / 1226 ms | 1222 / 1227 / 1229 ms | 1214 / 1231 / 1232 ms |
| scan_ct | 1238 / 1248 / 1253 ms | 1245 / 1250 / 1254 ms | 1249 / 1251 / 1316 ms |

The original leak is small in wall time (~1.5%, ~1 µs per output; the table walk is cheap
next to 32 × (4 doublings + 2 additions)) but real. The CT build shows no ivk dependence
beyond run-to-run noise.

**Cost** (medians of 3, the bench configurations from scan2's README; the load average was
5–8 from other jobs on the Mac): 1T 13,430 → 13,003 (−3%), 18T 185,130 → 174,298 (−6%),
Metal 1,115,506 → 894,689 outputs/s (−20%). Both builds use the forked Bend (`u64-rot`,
needed for `U32.mac64`), whose Metal build works for scan2 (all walks are tail-recursive).
Metal pays the most because the 16-way select is memory traffic, and the GPU is
bandwidth-bound there.

## 4. CI: `ci.sh`

```sh
./ci.sh                 # everything, on the Mac
./ci.sh --rebuild       # also rebuild fz, bundle_main_h, the suites, scan_ct, the oracle
./ci.sh --no-validate   # skip validate/zebend (the GPU tree rebuild)
```

It runs:
- every `PROOF.bend` with `--verdict`, also checking for `@unsafe`;
- the field and curve suites;
- `run_bundles.py` for the 42 bundles, nu62 and prenu62;
- the hardened verifier on the 42 bundles and the malformed probes;
- `validate/zebend validate`;
- fresh-seed fuzz smoke runs of every parser (cs/hdr/frame 20k, tx 10k, block 500,
  bundle 10k), the resource limits, and the CT scan's hit lists.

Heavy steps go through `../heavy.sh`. Logs go to `data/ci/`. The last run's table:

CI_TABLE

## Merge plan

| From | To | Change |
|---|---|---|
| `lib/cs.bend` | node/p2p/bytes.bend `read_compact`, node/block/bytes.bend `read_compact`, node/p2p/node.bend `compact2` | Return `Maybe` (or a width of 0 on failure) from the canonical, capped, length-checked reader. Callers must treat failure as a protocol error (`Bad`). |
| `lib/frame.bend` | node/p2p/msg.bend `parse` | Replace `parse_head`/`parse_magic`/`parse_body`: add `cmd_ok`, the 2 MiB cap before `NeedMore`, and `len ≤ n − 24`. `F.FBad`/`FMore`/`FGot` map to `Bad`/`NeedMore`/`Got`. |
| `lib/txv.bend` (+ `hb`, `cs`, `fr`, `jj`) | node/tx/tx_main.bend, node/block/block.bend `info` | Call `T.valid(bytes)` before `T.report`. In blocks, step through txs with `T.tx` and hand each slice to the digest code. `fr.bend`, `jj.bend` and Pallas canonicity are only needed here. |
| `lib/blk.bend` | node/block/block_main.bend, follow/ (block intake) | `K.parse_capped(bytes)` before anything else, and read files with a 2,000,001-byte limit. |
| `lib/bundle.bend`, `bundle_main_h.bend` | halo2/verifier/bundle_main*.bend (all four variants) | Put `checked(BU.valid(bb), …)` in front of `parse_bundle`, as in `bundle_main_h.bend`. |
| `scan_ct/scan.bend` | scan2/scan.bend | Take `pt_sel`, `eq16`, `ct_go`/`ct_get`, `ct_neg` and the three call sites. scan2's README "timing" note can then drop its caveat. |
| `ci.sh` | repo root CI | As is (it uses paths relative to `bend-zcash/`). |

## Files

```
oracle/            Rust oracle (harden-oracle cs|hdr|frame|tx|block N OUT; HARDEN_SEED)
lib/hb.bend        byte cursor, amounts            lib/cs.bend     canonical CompactSize
lib/fr.bend        BLS12-381 scalar field (gen_fr.py)   lib/jj.bend Jubjub decoding, small order
lib/txv.bend       transaction well-formedness     lib/blk.bend    headers, blocks, size cap
lib/frame.bend     P2P framing                     lib/bundle.bend Halo 2 bundle input
fz_main.bend       fuzz harness (./fz)             fuzz.py         differential driver
bundle_main_h.bend hardened Halo 2 verifier entry  scan_ct/        constant-time scan copy
tools/bgen.py      bundle corpus + spec            tools/limits.py resource-limit table
tools/probes.py    malformed bundle probes         tools/order.py  orders Bend defs by dependency
ci.sh              the gate
```
