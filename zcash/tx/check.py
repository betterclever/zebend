#!/usr/bin/env python3
"""Runs the Bend tx binary on every transaction in mainnet/ and diffs each line it prints
against the oracle's ground truth (same names). Usage: check.py [binary] [dir]"""
import pathlib, subprocess, sys, time
binary = sys.argv[1] if len(sys.argv) > 1 else "./tx_main"
d = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "mainnet")
idx = [l.split()[0] for l in (d / "index.txt").read_text().splitlines()]
tot = {"txs": 0, "fields": 0, "mismatch": 0, "txid": 0, "sighash": 0, "spend_auth_ok": 0, "binding_ok": 0, "instance": 0, "actions": 0}
bad = []
t0 = time.time()
for name in idx:
    want = dict(l.split(" ", 1) for l in (d / f"{name}.txt").read_text().splitlines())
    out = subprocess.run([binary, str(d / f"{name}.bin"), str(d / f"{name}.ctx")], capture_output=True, text=True, timeout=600).stdout
    got = dict(l.split(" ", 1) for l in out.splitlines() if " " in l)
    tot["txs"] += 1
    for k, v in got.items():
        if k in want:
            tot["fields"] += 1
            if want[k] != v:
                tot["mismatch"] += 1
                bad.append(f"{name} {k}: bend {v[:24]}… oracle {want[k][:24]}…")
            else:
                if k == "txid": tot["txid"] += 1
                if k == "sighash": tot["sighash"] += 1
                if k.endswith("spend_auth_ok") and v == "1": tot["spend_auth_ok"] += 1
                if k.endswith("binding_ok") and v == "1": tot["binding_ok"] += 1
                if ".instance[" in k: tot["instance"] += 1
        elif k not in ("bvk",):
            pass
    tot["actions"] += sum(1 for k in want if k.endswith(".spend_auth_sig"))
    missing = [k for k in want if k not in got and k not in ("height", "bucket") and not k.endswith("proof_ok")]
    if missing:
        bad.append(f"{name}: Bend did not print {len(missing)} fields, e.g. {missing[:3]}")
print(f"{tot['txs']} txs, {tot['fields']} fields compared, {tot['mismatch']} mismatches  ({time.time() - t0:.1f}s)")
print(f"txid {tot['txid']}/{tot['txs']}  sighash {tot['sighash']}/{tot['txs']}  spend-auth sigs valid {tot['spend_auth_ok']}/{tot['actions']}"
      f"  binding sigs valid {tot['binding_ok']}  instance values {tot['instance']}/{tot['actions'] * 10}")
for b in bad[:int(__import__("os").environ.get("SHOW", "25"))]:
    print("  " + b)
sys.exit(1 if bad else 0)
