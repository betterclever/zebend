# All of Zcash's proof of work, verified in Bend

`verify_all.log`: every mainnet block header from height 1 to 3,528,279, fetched from live
Zebra/Zakura peers over P2P (`fetch_all.sh`, headers-oracle `fetch`), verified by the Bend
Equihash verifier (`blake3x/eqv3`) on 18 CPU threads in 959 s:

```
TOTAL equihash 3528279/3528279  hash<=target 3528279/3528279  links 3528278/3528278
```

Slices of 100,000 headers overlap by one header, so every link, including the 35 across slice
boundaries, is checked in Bend. The driver aborts if the verifier processes fewer headers than
it was given. Not checked here: difficulty (only the post-Blossom rule is implemented) and the
genesis block itself. The ~5 GB of raw headers are not in git; `fetch_all.sh` re-fetches them.
