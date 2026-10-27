#!/usr/bin/env python3
"""Sapling verifier hook for fullnode (contract: node/hooks/README).

    zcash/sapling/hook.py <list file>      each line: base path P with P.tx, P.ctx, P.json

All checks are Bend; Python only moves bytes and maps Bend's output back to items:
  1. zcash/sapling/tx/tx_main (Bend) parses each tx (v4 ZIP 243 / v5, v6 ZIP 244), computes the
     txid and shielded sighash (transparent inputs: amounts/scripts from P.ctx), checks every
     Sapling description (cv, rk, epk decode and are not small order; cmu canonical),
     verifies every RedJubjub spend-auth and the binding signature (bvk from cvs and
     valueBalance = the value-balance check), and writes one Groth16 record per spend and
     output (proof + raw fields, from its own parse).
  2. zcash/sapling/tx/g16_raw (Bend, zcash/sapling/groth16/verify_raw_main) verifies every proof,
     computing the public inputs from the raw fields.

Prints one line per item:
    verdict <height> <txidx> PASS
    verdict <height> <txidx> FAIL <reason>
PASS = txid equals P.json's, all description checks, all spend-auth + binding signatures and
all spend/output proofs valid. Not covered: anchors (out of scope by design).
Sprout JoinSplits (v4): FAIL unsupported-joinsplit (joinSplitSig / Ed25519 not implemented).
Other versions: FAIL unsupported-version.
"""
import json, pathlib, struct, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
TX_MAIN = here / "tx/tx_main"
G16 = here / "tx/g16_raw"
VK = here / "groth16/data"
OK_HDR = (b"\x04\x00\x00\x80", b"\x05\x00\x00\x80", b"\x06\x00\x00\x80")


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
    run = [(m, t, c) for m, t, c in items if t[:4] in OK_HDR]
    base = pathlib.Path(lst).with_suffix("")
    txs, recs = base.with_name(base.name + ".sap_txs.bin"), base.with_name(base.name + ".sap_recs.bin")
    res, digits = {}, ""
    if run:
        with open(txs, "wb") as o:
            o.write(struct.pack("<I", len(run)))
            for m, t, c in run:
                o.write(struct.pack("<II", int(m["height"]), len(t)) + t + struct.pack("<I", len(c)) + c)
        out = subprocess.run([str(TX_MAIN), str(txs), str(recs)], capture_output=True, text=True).stdout
        for l in out.split("\n"):
            q = l.split()
            if q and q[0].isdigit():
                res[int(q[0])] = q
        if recs.exists() and recs.stat().st_size > 0:
            g = subprocess.run([str(G16), str(VK / "vk_spend.bin"), str(VK / "vk_output.bin"), str(VK / "vk_sprout.bin"), str(recs)],
                               capture_output=True, text=True).stdout
            digits = next((l.split()[1] for l in g.split("\n") if l.startswith("verdicts ")), "")
    k, pos = 0, 0
    for m, t, c in items:
        h, i = m["height"], m["txidx"]
        if t[:4] not in OK_HDR:
            print(f"verdict {h} {i} FAIL unsupported-version")
            continue
        q = res.get(k)
        k += 1
        if q is None or len(q) < 10:
            print(f"verdict {h} {i} FAIL no output from zcash/sapling/tx/tx_main")
            continue
        ns, no, nj = int(q[4]), int(q[5]), int(q[9])
        verd = q[10] if len(q) > 10 else ""
        prf = digits[pos:pos + ns + no]
        pos += ns + no
        if "txid" in m and bytes.fromhex(q[2])[::-1].hex() != m["txid"]:
            print(f"verdict {h} {i} FAIL txid mismatch (Bend {bytes.fromhex(q[2])[::-1].hex()})")
        elif nj > 0:
            print(f"verdict {h} {i} FAIL unsupported-joinsplit")
        elif q[8] != "1":
            print(f"verdict {h} {i} FAIL sapling-description (cv/rk/epk small order or undecodable, or cmu non-canonical)")
        elif "0" in verd or len(verd) != ns + (1 if ns + no else 0):
            print(f"verdict {h} {i} FAIL redjubjub {verd} (spend-auth..., binding)")
        elif len(prf) != ns + no or any(d != "1" for d in prf):
            print(f"verdict {h} {i} FAIL groth16 {prf} (spends..., outputs; 0 decode, 2 pairing, 3 fields)")
        else:
            print(f"verdict {h} {i} PASS")
    for f in (txs, recs):
        if f.exists():
            f.unlink()


if __name__ == "__main__":
    main(sys.argv[1])
