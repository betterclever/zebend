#!/usr/bin/env python3
"""Sapling verifier hook for fullnode (contract: fullnode/hooks/README).

    sapling/hook.py <list file>      each line: base path P with P.tx, P.ctx, P.json

All checks are Bend; Python only moves bytes and maps Bend's output back to items:
  1. sapling/tx/tx_main (Bend) parses each tx (v4 ZIP 243 / v5, v6 ZIP 244), computes the
     txid and shielded sighash (transparent inputs: amounts/scripts from P.ctx), checks every
     Sapling description (cv, rk, epk decode and are not small order; cmu canonical),
     verifies every RedJubjub spend-auth and the binding signature (bvk from cvs and
     valueBalance = the value-balance check), and writes one Groth16 record per spend and
     output (proof + raw fields, from its own parse).
  2. sapling/tx/g16_raw (Bend, sapling/groth16/verify_raw_main) verifies every proof,
     computing the public inputs from the raw fields.

Prints one line per item:
    verdict <height> <txidx> PASS
    verdict <height> <txidx> FAIL <reason>
    verdict <height> <txidx> SKIPPED <reason>   (v2/v3 BCTV14 JoinSplits only)
PASS = txid equals P.json's, all description checks, all spend-auth + binding signatures and
all spend/output proofs valid; for v4 txs with Sprout JoinSplits also the joinSplitSig
(Ed25519, ZIP 215 rules, over the ZIP 243 sighash; consensus/gaps/ed25519) and every JoinSplit's
Groth16 proof (public inputs incl. h_sig computed in Bend from the raw fields). Not covered here:
anchors (sync.py checks Sapling and Sprout anchors against the node's trees).
Other versions: FAIL unsupported-version.

(consensus/gaps/sprout copy of sapling/hook.py: Sprout JoinSplits are verified instead of
being reported FAIL unsupported-joinsplit.)
"""
import json, os, pathlib, struct, subprocess, sys

DEBUG = os.environ.get("HOOK_DEBUG") == "1"  # tests: per-stage verdicts

here = pathlib.Path(__file__).resolve().parent
SAP = here.parent.parent.parent / "sapling"
TX_MAIN = here / "tx_main"          # consensus/gaps/sprout/tx_main.bend (stx.bend + JoinSplits)
G16 = SAP / "tx/g16_raw"            # sapling/groth16/verify_raw_main.bend (kinds 0, 1, 2)
VK = SAP / "groth16/data"
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
            ver = int.from_bytes(t[:4], "little") & 0x7FFFFFFF if len(t) >= 4 else -1
            if ver in (2, 3):  # pre-Sapling JoinSplits: BCTV14 proofs (never above the checkpoint)
                print(f"verdict {h} {i} SKIPPED bctv14-joinsplit-v{ver} (BCTV14 proofs not implemented)")
            else:
                print(f"verdict {h} {i} FAIL unsupported-version")
            continue
        q = res.get(k)
        k += 1
        if q is None or len(q) < 10:
            print(f"verdict {h} {i} FAIL no output from sapling/tx/tx_main")
            continue
        ns, no, nj = int(q[4]), int(q[5]), int(q[9])
        jsig = q[10][5:] if len(q) > 10 and q[10].startswith("jsig=") else "?"
        verd = q[11] if len(q) > 11 else ""
        prf = digits[pos:pos + ns + no + nj]
        pos += ns + no + nj
        if DEBUG:
            print(f"debug {h} {i} ns={ns} no={no} nj={nj} cons={q[8]} jsig={jsig} redjubjub={verd} groth16={prf}")
        if "txid" in m and bytes.fromhex(q[2])[::-1].hex() != m["txid"]:
            print(f"verdict {h} {i} FAIL txid mismatch (Bend {bytes.fromhex(q[2])[::-1].hex()})")
        elif q[8] != "1":
            print(f"verdict {h} {i} FAIL sapling-description (cv/rk/epk small order or undecodable, or cmu non-canonical)")
        elif "0" in verd or len(verd) != ns + (1 if ns + no else 0):
            print(f"verdict {h} {i} FAIL redjubjub {verd} (spend-auth..., binding)")
        elif nj > 0 and jsig != "1":
            print(f"verdict {h} {i} FAIL joinsplitsig ed25519 {jsig}")
        elif nj == 0 and jsig != "-":
            print(f"verdict {h} {i} FAIL joinsplitsig unexpected {jsig}")
        elif len(prf) != ns + no + nj or any(d != "1" for d in prf):
            print(f"verdict {h} {i} FAIL groth16 {prf} (spends..., outputs..., joinsplits; 0 decode, 2 pairing, 3 fields)")
        else:
            print(f"verdict {h} {i} PASS")
    for f in (txs, recs):
        if f.exists():
            f.unlink()


if __name__ == "__main__":
    main(sys.argv[1])
