#!/usr/bin/env python3
"""zebend validate: check one real Zcash mainnet Ironwood transaction end to end.

Every cryptographic check runs in Bend (the binaries of zcash/headers, zcash/block,
zcash/tx, zcash/halo2/verifier, zcash/state and node/validate/nf_check). This driver only copies
bytes, slices files, applies the optional tamper, runs those programs and compares
their printed results. It computes no hash, signature, proof or tree itself.

usage: zebend_validate.py [--tx tx_0] [--tamper header|ciphertext|proof|signature|note|doublespend]
"""
import argparse, re, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
HDR_FILE, HDR_BASE, HDR_LEN = ROOT / "zcash/headers/data/mainnet.bin", 3_400_000, 1487
DIFF_WINDOW = 28  # predecessors the difficulty check needs
TAMPERS = ["header", "ciphertext", "proof", "signature", "note", "doublespend"]

BIN = {
    "headers": ROOT / "zcash/headers/verify",
    "block": ROOT / "zcash/block/block_main",
    "tx": ROOT / "zcash/tx/tx_main",
    "halo2": ROOT / "zcash/halo2/verifier/bundle_main_fast",
    "tree": ROOT / "zcash/state/tree_main",
    "nf": ROOT / "node/validate/nf_check",
}


def run(name, *args, cwd=None):
    t = time.perf_counter()
    out = subprocess.run([str(BIN[name]), *map(str, args)], capture_output=True, text=True, cwd=cwd)
    return out.stdout + out.stderr, time.perf_counter() - t


def kv(text):
    """Bend components print `name value` lines."""
    return dict(l.split(" ", 1) for l in text.splitlines() if " " in l)


def flip(path: Path, offset: int):
    b = bytearray(path.read_bytes())
    b[offset] ^= 0x01
    path.write_bytes(b)


class Report:
    def __init__(self):
        self.results = []

    def step(self, n, title, ok, secs, lines):
        self.results.append((n, title, ok))
        print(f"\n[{n}] {title:<54} {'PASS' if ok else 'FAIL'}   {secs:6.2f} s")
        for l in lines:
            print(f"      {l}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tx", default="tx_0")
    ap.add_argument("--tamper", choices=TAMPERS)
    a = ap.parse_args()

    txdir = ROOT / "zcash/tx/mainnet"
    meta = dict(re.findall(r"^(\w+) (\S+)$", (txdir / f"{a.tx}.txt").read_text(), re.M))
    height, chain_txid = int(meta["height"]), meta["txid"]
    work = ROOT / "node/validate/work" / (a.tamper or "honest")
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)

    # Inputs, copied so a tamper never touches the components' own data.
    with HDR_FILE.open("rb") as f:
        f.seek((height - DIFF_WINDOW - HDR_BASE) * HDR_LEN)
        (work / "hdrs.bin").write_bytes(f.read((DIFF_WINDOW + 1) * HDR_LEN))
    blk = ROOT / f"zcash/block/data/{height}.bin"
    shutil.copy(blk, work / "block.bin")
    shutil.copy(txdir / f"{a.tx}.bin", work / "tx.bin")
    raw_tx = (txdir / f"{a.tx}.bin").read_bytes()
    tx_in_block = blk.read_bytes().find(raw_tx)
    proof_bytes = (txdir / f"{a.tx}.ironwood.proof.bin").read_bytes()
    proof_off = raw_tx.find(proof_bytes)
    assert tx_in_block >= 0 and proof_off >= 0, "tx not found in its block, or proof not in tx"
    nf_all, cmx_all = ROOT / "zcash/state/out/nf.bin", ROOT / "zcash/state/out/cmx.bin"

    # Bend's view of the honest transaction locates the fields a tamper flips.
    honest = kv(run("tx", txdir / f"{a.tx}.bin", txdir / f"{a.tx}.ctx")[0])

    def flip_tx(off):  # same byte in the standalone tx and in the block that carries it
        flip(work / "tx.bin", off)
        flip(work / "block.bin", tx_in_block + off)

    if a.tamper == "header":
        flip(work / "hdrs.bin", DIFF_WINDOW * HDR_LEN + 108 + 5)  # a nonce byte of the block's header
    elif a.tamper == "ciphertext":
        flip_tx(raw_tx.find(bytes.fromhex(honest["ironwood.a0.epk"])) + 32 + 100)
    elif a.tamper == "proof":
        flip_tx(proof_off + len(proof_bytes) // 2)
    elif a.tamper == "signature":
        flip_tx(raw_tx.find(bytes.fromhex(honest["ironwood.a0.spend_auth_sig"])) + 10)
    elif a.tamper == "note":
        cmx_all = shutil.copy(cmx_all, work / "cmx.bin")
        pos = cmx_all.read_bytes().find(bytes.fromhex(honest["ironwood.a0.cmx"]))
        flip(cmx_all, pos + 5)
    elif a.tamper == "doublespend":
        nf_all = shutil.copy(nf_all, work / "nf.bin")
        b = bytearray(nf_all.read_bytes())
        b[0:32] = bytes.fromhex(honest["ironwood.a1.nf"])  # a later tx re-reveals this nullifier
        nf_all.write_bytes(b)

    print(f"zebend validate {a.tx}: {chain_txid} (mainnet block {height:,})"
          + (f"   [tamper: {a.tamper}]" if a.tamper else ""))
    rep, t_all = Report(), time.perf_counter()

    # 3 first (silently) so step 2 can look for the Bend-computed txid among the block's leaves.
    tx_out, t_tx = run("tx", work / "tx.bin", txdir / f"{a.tx}.ctx")
    tx = kv(tx_out)
    n_act = int(tx.get("ironwood.actions", "0"))

    # 1. header chain
    out, secs = run("headers", work / "hdrs.bin", DIFF_WINDOW + 1, DIFF_WINDOW + 1, 4)
    checks = re.findall(r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M)
    ok = len(checks) == 4 and all(x == y for _, x, y in checks)
    rep.step(1, "Header: Equihash, target, chain links, difficulty", ok, secs,
             [f"{name}: {x}/{y}" for name, x, y in checks] + [f"(block {height:,} plus its {DIFF_WINDOW} predecessors)"])

    # 2. block inclusion
    out, secs = run("block", work / "block.bin", ROOT / f"zcash/block/data/{height}.hist", height,
                    work / "hdrs.bin", height - DIFF_WINDOW)
    bh = re.search(r"^block \d+ hash ([0-9a-f]{64}) txs (\d+)", out, re.M)
    leaves = re.findall(r"^tx (\d+) v\d bytes \d+ txid ([0-9a-f]{64})", out, re.M)
    idx = next((i for i, t in leaves if t == tx.get("txid")), None)
    flags = {k: re.search(rf"^{k} [0-9a-f]+ (MATCH|MISMATCH)|^{k} (MATCH|MISMATCH)", out, re.M) for k in ("merkle", "commitments", "verified_header")}
    flags = {k: (m.group(1) or m.group(2)) if m else "missing" for k, m in flags.items()}
    ok = all(v == "MATCH" for v in flags.values()) and idx is not None
    rep.step(2, "Block: tx committed to the verified header", ok, secs, [
        f"block hash (Bend SHA-256d): {bytes.fromhex(bh.group(1))[::-1].hex() if bh else '?'}",
        f"merkle root vs header: {flags['merkle']}   ZIP 244 block commitments vs header: {flags['commitments']}",
        f"block header == header verified in step 1: {flags['verified_header']}",
        f"tx txid is leaf {idx} of {bh.group(2) if bh else '?'}" if idx is not None else "tx txid NOT among the block's merkle leaves",
    ])

    # 3. transaction
    sigs = [tx.get(f"ironwood.a{i}.spend_auth_ok") == "1" for i in range(n_act)]
    ok = all(sigs) and n_act > 0 and tx.get("ironwood.binding_ok") == "1"
    rep.step(3, "Transaction: ZIP 244 txid + sighash, RedPallas", ok, t_tx, [
        f"txid (Bend ZIP 244): {tx.get('txid')}   {'= network txid' if tx.get('txid') == chain_txid else '!= network txid ' + chain_txid}",
        f"sighash (Bend ZIP 244): {tx.get('sighash')}",
        f"spend-auth signatures: {sum(sigs)}/{n_act} valid   binding signature: {'valid' if tx.get('ironwood.binding_ok') == '1' else 'INVALID'}",
        f"Ironwood actions {n_act}, valueBalance {int.from_bytes(bytes.fromhex(tx.get('ironwood.value_balance', '00')), 'little', signed=True)} zat",
    ])

    # 4. Halo 2 proof against the public inputs Bend derived in step 3
    plen = int(tx.get("ironwood.proof_len", "0"))
    proof = (work / "tx.bin").read_bytes()[proof_off:proof_off + plen]
    inst = [bytes.fromhex(tx[f"ironwood.a{i}.instance[{j}]"]) for i in range(n_act) for j in range(10)]
    bundle = n_act.to_bytes(4, "little") + (10).to_bytes(4, "little") + plen.to_bytes(4, "little") + proof + b"".join(inst)
    (work / "bundle.bin").write_bytes(bundle)
    out, secs = run("halo2", ROOT / "zcash/halo2/verifier/data/params_g.bin", work / "bundle.bin")
    ok = re.search(r"^result 1$", out, re.M) is not None
    rep.step(4, "Proof: Ironwood Halo 2 proof verifies in Bend", ok, secs, [
        f"proof: {plen} bytes taken from the transaction; public inputs: {len(inst)} values computed by Bend in step 3",
        f"verifier: {'accepts' if ok else 'rejects'} (final MSM {'is' if ok else 'is not'} the identity)",
    ])

    # 5. shielded state
    cmx_bytes = Path(cmx_all).read_bytes()
    found = [cmx_bytes.find(bytes.fromhex(tx[f"ironwood.a{i}.cmx"])) for i in range(n_act)]
    pos = [f // 32 if f >= 0 and f % 32 == 0 else -1 for f in found]
    (work / "tx_nfs.bin").write_bytes(b"".join(bytes.fromhex(tx[f"ironwood.a{i}.nf"]) for i in range(n_act)))
    tree_out, t1 = run("tree", cmx_all, "gpu", cwd=ROOT / "zcash/state")
    nf_out, t2 = run("nf", nf_all, work / "tx_nfs.bin")
    roots = re.findall(r"^height (\d+) size (\d+): bend root ([0-9a-f]+) (MATCH|MISMATCH)", tree_out, re.M)
    dups = re.search(r"duplicates (\d+)", nf_out)
    occ = re.findall(r"^nf ([0-9a-f]+) member (\w+) occurrences (\d+)", nf_out, re.M)
    covered = [r for r in roots if all(0 <= p < int(r[1]) for p in pos)]
    ok = (bool(roots) and all(r[3] == "MATCH" for r in roots) and bool(covered) and all(p >= 0 for p in pos)
          and dups is not None and dups.group(1) == "0" and len(occ) == n_act
          and all(m == "yes" and c == "1" for _, m, c in occ))
    lines = ["output note commitments at tree positions "
             + ", ".join(str(p) if p >= 0 else "NOT FOUND" for p in pos)]
    lines += [f"tree root @ {int(h):,} ({int(s):,} leaves): {st}" for h, s, _, st in roots]
    lines += [f"mainnet nullifier set: {dups.group(1) if dups else '?'} duplicates across all Ironwood spends"]
    lines += [f"nullifier {n[:16]}…: in set {m}, occurrences {c}" for n, m, c in occ]
    rep.step(5, "State: note commitments in the tree, no double spend", ok, t1 + t2, lines)

    passed = sum(ok for _, _, ok in rep.results)
    verdict = "VALID" if passed == len(rep.results) else "INVALID"
    failed = [str(n) for n, _, ok in rep.results if not ok]
    print(f"\n{verdict}: {passed}/{len(rep.results)} steps passed"
          + (f" (failed: {', '.join(failed)})" if failed else "")
          + f"   total {time.perf_counter() - t_all:.1f} s")
    return 0 if verdict == "VALID" else 1


if __name__ == "__main__":
    sys.exit(main())
