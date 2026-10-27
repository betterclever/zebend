#!/usr/bin/env python3
"""Differential test: Bend (bin/t_vec, nu7.bend) vs the Zebra 1e03ee75 oracle vectors in
data/vectors (built by oracle/gen.py; Zebra and Zakura agree on all of them, oracle/cross.py).

Compared per network:
  heights: halving index, ScheduledBlockSubsidy, and from the Revision 2 funding-stream start
           height on: the FS_FPF_ZCG_H3 (MajorGrants) value and recipient script, the
           FS_CCF_H3 (Deferred) value;
  fees:    NSMFeeContribution and MinerFees;
  nsm:     AdditionalBlockSubsidy and BlockSubsidy (scheduled + additional).
usage: compare_vectors.py   (prints one summary line per set; exit 1 on any mismatch)"""
import json, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
VEC = HERE / "data/vectors"
TMP = HERE / "data/tmp"
FS_START = {"main": 3146400, "test": 3536500}


def bend(mode, net, words):
    TMP.mkdir(parents=True, exist_ok=True)
    p = TMP / f"cmp_{mode}_{net}.bin"
    p.write_bytes(b"".join(struct.pack("<I", w) for w in words))
    out = subprocess.run([str(HERE / "bin/t_vec"), mode, net, str(p), str(p.stat().st_size)],
                         capture_output=True, text=True).stdout
    return [l.split() for l in out.splitlines() if l.strip()]


def u64(v):
    return [v & 0xFFFFFFFF, v >> 32]


bad = 0
for net, zn in (("main", "mainnet"), ("test", "testnet")):
    zs = [json.loads(l) for l in open(VEC / f"zebra_heights_{zn}.jsonl")]
    zs = [z for z in zs if z["h"] < 2**32]
    rows = bend("heights", net, [z["h"] for z in zs])
    n = mism = 0
    for z, r in zip(zs, rows, strict=True):
        assert int(r[1]) == z["h"]
        got = {"halving": int(r[3]), "subsidy": int(r[5])}
        want = {"halving": z["halving"], "subsidy": int(z["scheduled_block_subsidy"])}
        if z["h"] >= FS_START[net]:
            got.update(zcg=int(r[7]), deferred=int(r[10]))
            want.update(zcg=int(z["fs"].get("MajorGrants", 0)), deferred=int(z["fs"].get("Deferred", 0)))
            if want["zcg"]:
                got["script"], want["script"] = r[8], z["fs_script"]["MajorGrants"]
        n += len(want)
        if got != want:
            mism += 1
            if mism <= 5:
                print("MISMATCH heights", net, z["h"], got, want)
    print(f"heights {net}: {len(zs)} heights, {n} values, {mism} mismatching heights")
    bad += mism

    zs = [json.loads(l) for l in open(VEC / f"zebra_fees_{zn}.jsonl")]
    rows = bend("fees", net, [w for z in zs for w in [z["h"]] + u64(int(z["fees"]))])
    mism = 0
    for z, r in zip(zs, rows, strict=True):
        if (int(r[2]), int(r[4]), int(r[6])) != (int(z["fees"]), int(z["contribution"]), int(z["miner"])):
            mism += 1
            print("MISMATCH fees", net, z, r)
    print(f"fees {net}: {len(zs)} cases, {mism} mismatches")
    bad += mism

    zs = [json.loads(l) for l in open(VEC / f"zebra_nsm_{zn}.jsonl")]
    zs = [z for z in zs if not str(z.get("additional", "")).startswith("ERR")]
    rows = bend("nsm", net, [w for z in zs for w in [z["h"]] + u64(int(z["balance"]))])
    hs = bend("heights", net, [z["h"] for z in zs])
    mism = 0
    for z, r, hr in zip(zs, rows, hs, strict=True):
        got = (int(r[4]), int(hr[5]) + int(r[4]))
        want = (int(z["additional"]), int(z["subsidy_with_parent"]))
        if got != want:
            mism += 1
            print("MISMATCH nsm", net, z, r)
    print(f"nsm {net}: {len(zs)} cases (ERR rows excluded), {mism} mismatches")
    bad += mism
sys.exit(1 if bad else 0)
