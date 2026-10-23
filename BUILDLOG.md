# How Zebend was built

Zebend was built during the Zecathon 2026 window by one person who was new to Zcash
cryptography, working with Claude (Opus 5.5) in Claude Code. Claude wrote the code and ran
the experiments; the human chose the direction, pushed the ambition, and learned the
cryptography along the way. Parallel Claude sub-agents built independent components, each
checked against an official implementation before it counted as done.

Times are local (UTC+4) and come from shell output and file timestamps in the sessions.
The git history starts at the first snapshot; earlier work is reconstructed from those logs.

## Oct 18: research
- Read the Zecathon rules and criteria. Surveyed the ecosystem: Ironwood replacing Orchard
  after the soundness bug, ZIP 2005 quantum recoverability, NU7, Zakura, CipherPay.
- Found the gap nobody had filled: ZIP 2005 specifies a Recovery Statement, but no public
  implementation exists.

## Oct 19–20: learning
- Read ZIP 2005 end to end; learned elliptic curves, Pasta, Sinsemilla, commitments and the
  quantum threat model from first principles.


## Oct 22: the Mac
- Ported the prover to native macOS; patched RISC Zero's Metal shaders for the macOS 27
  toolchain. Proof in 11.7 minutes.

## Oct 24: Bend
- 02:09: first Bend 2 program on the M5 Max GPU (`pow2!(20n)` on Metal).
- Three parallel builds: proven ZIP 318 migration planner (6 laws), proven ZIP 209 turnstile
  and NU6.3/NU7 pool rules (9 laws), GPU trial decryption matching `orchard` exactly.
- `bend2wasm`: Bend has no WebAssembly target, so we made one (Bend's C output + guarded
  patches + wasi-sdk). Runs in wasmtime, Node and a browser WASI shim.
- Halo 2: a Rust oracle dumping all 5,487 intermediate values of the official verifier on a
  real Orchard proof; the Orchard circuit's 193 gate polynomials generated as Bend (193/193
  match); Pasta fields, Vesta and a GPU MSM (all match `pasta_curves`); and the full Halo 2
  algorithm in Bend accepting an honest toy proof and rejecting a tampered one.
- P2P: a Bend binary handshakes with live Zebra 7.0.0 and Zakura 1.7.0 mainnet peers and
  downloads headers, re-hashed in Bend and matched to Zebra's checkpoint.

_(continued as components land)_
