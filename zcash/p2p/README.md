# Zebend P2P: Zcash mainnet networking in Bend

A Bend 2 program that finds Zcash mainnet peers, performs the protocol handshake,
and downloads block headers, hashing every header with SHA-256d and checking every
prev-hash link in Bend. Native build (`bend main.bend -o zebend-p2p`, Bend 2.0.38).

```sh
~/.bend/bin/bend main.bend -o zebend-p2p
./zebend-p2p                      # DNS seeds -> first peer that completes a session
./zebend-p2p 136.115.98.175       # a specific peer
# args: [peer|-] [protocol] [start-height] [start-hash] [batches] [check-height] [check-hash]
```

## What runs in Bend

| Piece | File | How it is checked |
|---|---|---|
| SHA-256 / SHA-256d over U32 (FIPS 180-4, 16-word sliding schedule) | `sha256.bend` | `t_sha.bend`: "", "abc", the 448-bit vector and SHA-256d("abc") equal `shasum` / Python |
| Message framing: magic `24e92764`, command, length, SHA-256d checksum; parser with checksum verification | `msg.bend` | the `version` frame is byte-identical to a Python reference (`t_ver.bend`, `tools/probe.py`) |
| `version` (protocol 170190, `/Zebend:0.1.0/`), `verack`, `ping`→`pong`, `getheaders`, `getaddr`, `headers`, `addr` | `node.bend` | live peers accept the handshake and serve headers |
| Header parsing (140 fixed bytes + CompactSize + 1344-byte Equihash solution = 1487 bytes), SHA-256d block hash, prev-hash linkage, checkpoint comparison | `node.bend` | see below |
| Event loop: one self-recursive IO loop (print → send → `TCP.try_recv_bytes` 5 s → drain) around a pure message processor | `main.bend` | |
| DNS: `DNS.resolve` foreign effect (`getaddrinfo` on an IO helper thread) | `dns.c` | resolves `mainnet.seeder.zfnd.org` and `dnsseed.z.cash` |
| Wall clock for the version timestamp: `Clock.unix` foreign effect | `clock.c` | |

Bend has no 64-bit integers, so u64 fields are `U64{lo, hi}`; bytes are `List<U32>`.
`order.py` sorts a file's defs callees-first (Bend requires it) and `fixplus.py` adds `+`
(reusable) annotations the checker asks for. Both are dev helpers only.

## Live session (excerpt of `out/session.txt`, 2026-10-24)

```
Zebend P2P: Zcash mainnet, in Bend
DNS seeds resolved: 32 addresses
connected to 199.170.132.107:8233
-> version (protocol 170190, /Zebend:0.1.0/)
!! receive failed: Connection reset by peer (errno 54)
   no headers from 199.170.132.107; trying the next peer
...
connected to 136.115.98.175:8233
-> version (protocol 170190, /Zebend:0.1.0/)
<- version: protocol 170190, user agent /Zebra:7.0.0/, best height 3528273
-> verack
<- verack: handshake complete
-> getheaders after #3522060 (00000000000705964fc4c75da9cce97978197b666c9dcdfc1bcf8d44cd776e4d)
-> getaddr
<- headers: 160 headers, 238081 bytes
  #3522061  0000000000618b705628c3c87b41016ed08089021d166aa087c5266595332e87  time 1792323954  bits 1b69f731  v4  sol 1344B
  ...
<- addr: 335 peer addresses
<- headers: 160 headers, 238081 bytes
<- headers: 160 headers, 238081 bytes
  CHECKPOINT #3522460: SHA-256d computed in Bend == Zebra's mainnet checkpoint
summary: 480 headers linked and hashed in Bend, tip #3522540, checkpoints matched: 1, peer addresses learned: 335
```

Peers seen completing sessions: `/Zebra:7.0.0/` (34.80.219.125, 136.115.98.175) and
`/Zakura:1.7.0/` (54.39.196.12), all at protocol 170190, best height ≈ 3,528,27x.

## Evidence

- The start locator is Zebra's mainnet checkpoint 3,522,060 (`out/zebra-main-checkpoints.txt`,
  fetched from the Zebra repo). Three `getheaders` rounds return heights 3,522,061–3,522,540.
- Every header's prev-hash field equals the Bend-computed SHA-256d of the previous one.
- The Bend hash at height 3,522,460 equals Zebra's published checkpoint hash.
- Independent recheck: Python recomputes SHA-256d for all 480 headers in `out/headers.bin`
  and matches the hashes Bend wrote to `out/heights.txt`; all prev links hold; every header
  is 1487 bytes with solution length `fd 40 05` (1344).

## Output for the headers component

- `out/headers.bin`: raw 1487-byte headers, concatenated, oldest first.
- `out/heights.txt`: `height hash` per line (hash in display byte order).

## Gaps and limits

- **No Equihash or difficulty check here**: that's the `headers/` component. This client
  verifies hashes and linkage only; a malicious peer could serve a valid-linking fake
  chain. The checkpoint comparison catches that only at checkpoint heights.
- **Peer acceptance:** about 1 in 5 seed peers completes a session. The rest reset or close
  right after our `version`. `tools/probe.py` (plain Python) gets the same resets at protocol
  170190–170220, so it's peer-side policy, not our encoding. Peers older than protocol
  170160 drop us after their `version`, so the default is 170190 (what Zebra 7 / Zakura 1.7 send).
  Repeated connections from one IP get reset for a while (rate limiting).
- Only IPv4 (Bend's TCP takes IPv4 literals). DNS is a foreign C effect, so `main` is outside
  Bend's proof guarantees (`bend --check-only` says so); the JS twin of `DNS.resolve` returns ENOSYS.
- Requests run in sequence on one connection; no `inv`/block relay, no mempool, no `addr`
  persistence, no inbound connections.
- `getheaders` sends a single locator hash, not a full block locator.
