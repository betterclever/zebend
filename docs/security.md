# Security

## Status

Zebend has not been audited. It is a second, independent check on Zcash, and is most useful running
beside a production node, not instead of one. Do not rely on it alone for funds.

## What Zebend checks

Above Zebra's last checkpoint, every block gets every consensus check Zakura makes: the rules engine,
transparent scripts and signatures, Sapling and Sprout proofs and signatures, Orchard and Ironwood
proofs and signatures, anchors for all four pools, the ZIP 221 history root, and the value-pool
turnstile. A check that cannot run fails closed: the block is refused, never silently accepted.

## What it does not cover

- Blocks below the last checkpoint are trusted to Zebra's checkpoint list, as in Zebra and Zakura.
- The proof systems' soundness and the hardness assumptions under them.
- Field arithmetic and curve formulas are tested, not proven (see [proofs.md](proofs.md)).
- The mempool checks only Ironwood anchors; it has no orphan pool.
- The node has days of operation, not years of adversarial exposure. Peer handling has been fuzzed
  and resource-limited, but not tested against a hostile network.

## Constant time

Wallet trial decryption (`research/scan2`) handles the incoming viewing key in constant time:
every key-dependent lookup reads all entries through masked selects.

## Reporting

- A bug in Zebend: open an issue.
- A soundness issue in **Zcash itself** found with Zebend's tools, such as the circuit
  under-constraint checker in `zcash/halo2/constraints`: report it privately to the Zcash security
  contacts (the Zcash Foundation and Shielded Labs) before anything is published. Zebend keeps its
  analysis of the live circuits out of the repository for this reason.
