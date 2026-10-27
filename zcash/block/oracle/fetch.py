#!/usr/bin/env python3
"""Fetch raw mainnet blocks (and the node's RPC commitment fields) from Blockchair.

Writes data/<height>.bin (raw block bytes) and data/<height>.json (the node's getblock
fields: hash, merkleroot, authdataroot, chainhistoryroot, blockcommitments, txids).
Nothing here is trusted by the Bend check except chainhistoryroot, which is labelled as
an oracle input; everything else is recomputed and compared.
"""
import json, sys, time, urllib.request, pathlib

out = pathlib.Path(__file__).resolve().parent.parent / "data"
for h in sys.argv[1:]:
    url = f"https://api.blockchair.com/zcash/raw/block/{h}"
    d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "zebend"}), timeout=60))
    b = d["data"][h]
    dec = b["decoded_raw_block"]
    (out / f"{h}.bin").write_bytes(bytes.fromhex(b["raw_block"]))
    keep = {k: dec[k] for k in ["hash", "height", "merkleroot", "authdataroot", "chainhistoryroot", "blockcommitments"]}
    keep["tx"] = dec["tx"]
    (out / f"{h}.json").write_text(json.dumps(keep, indent=1))
    print(h, "bytes", len(b["raw_block"]) // 2, "txs", len(dec["tx"]))
    time.sleep(2)
