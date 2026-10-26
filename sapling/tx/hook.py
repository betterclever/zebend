#!/usr/bin/env python3
"""Adapter for fullnode's verifier-hook contract (fullnode/hooks/README) covering the
NON-PROOF Sapling checks: Bend parses each tx (v4 ZIP 243 / v5 ZIP 244), computes its
shielded sighash, checks every Sapling description (cv, rk, epk decode and are not small
order; cmu canonical) and verifies every RedJubjub spend-auth and the binding signature
(bvk from the cvs and valueBalance, i.e. the value-balance check).

    hook.py <list file>          (each line: base path P with P.tx, P.ctx, P.json)

Prints one line per item:
    verdict <height> <txidx> PASS
    verdict <height> <txidx> FAIL <reason>

NOT covered here (must come from other components before a tx can be called valid):
Groth16 spend/output proofs (sapling/groth16), Sprout JoinSplit proofs and joinSplitSig.
v6 transactions go through node/tx's parser but were not tested here -> FAIL "untested".
"""
import json, pathlib, struct, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
TX_MAIN = here / "tx_main"


def main(lst):
    items = []
    for line in open(lst):
        p = line.strip()
        if not p:
            continue
        meta = json.loads(pathlib.Path(p + ".json").read_text())
        tx = pathlib.Path(p + ".tx").read_bytes()
        ctxp = pathlib.Path(p + ".ctx")
        ctx = ctxp.read_bytes() if ctxp.exists() else b""
        items.append((meta, tx, ctx))
    out_lines = []
    run = [(m, t, c) for m, t, c in items if t[:4] in (b"\x04\x00\x00\x80", b"\x05\x00\x00\x80")]
    res = {}
    if run:
        f = pathlib.Path(lst).with_suffix(".sapling_txs.bin")
        with open(f, "wb") as o:
            o.write(struct.pack("<I", len(run)))
            for m, t, c in run:
                o.write(struct.pack("<II", int(m["height"]), len(t)) + t + struct.pack("<I", len(c)) + c)
        out = subprocess.run([str(TX_MAIN), str(f)], capture_output=True, text=True).stdout.split("\n")
        for l in out:
            p = l.split()
            if p and p[0].isdigit():
                res[int(p[0])] = p
    k = 0
    for m, t, c in items:
        h, i = m["height"], m["txidx"]
        if t[:4] not in (b"\x04\x00\x00\x80", b"\x05\x00\x00\x80"):
            print(f"verdict {h} {i} FAIL untested tx version (sapling/ covers v4 and v5)")
            continue
        p = res.get(k)
        k += 1
        if p is None or len(p) < 9:
            print(f"verdict {h} {i} FAIL no output from sapling/tx/tx_main")
            continue
        txid_internal = bytes.fromhex(p[2])
        if "txid" in m and txid_internal[::-1].hex() != m["txid"]:
            print(f"verdict {h} {i} FAIL txid mismatch (Bend {txid_internal[::-1].hex()})")
        elif p[8] != "1":
            print(f"verdict {h} {i} FAIL Sapling description check (cv/rk/epk small order or undecodable, or cmu non-canonical)")
        elif len(p) > 9 and "0" in p[9]:
            print(f"verdict {h} {i} FAIL RedJubjub signature(s) invalid: {p[9]} (spend-auth..., binding)")
        else:
            print(f"verdict {h} {i} PASS")


if __name__ == "__main__":
    main(sys.argv[1])
