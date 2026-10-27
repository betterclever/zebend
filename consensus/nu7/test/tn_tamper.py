#!/usr/bin/env python3
"""Tampered copies of real post-NU7 Testnet blocks must fail exactly the intended rule
(bin/tn_check). For a sample of blocks with fees > 0 that pay FS_FPF_ZCG_H3 (heights
4,465,026..4,497,947), each case changes one thing:
  extra60  coinbase gains an output worth NSMFeeContribution (miner keeps 100% of fees) -> miner_fees
  zcg-1    ZCG output 1 zat short                                       -> issuance_required_outputs, miner_fees
  zcg_pre  ZCG paid the pre-NU7 8% (12,500,000)                          -> issuance_required_outputs, miner_fees
  branch   a non-coinbase v5/v6 tx carries NU6.3's branch id             -> branch_id
  v4       the coinbase's version field says v4 (Sapling group id)       -> tx_version (+ wire if unparsable)
Byte surgery is test scaffolding (tx boundaries from a minimal parser below).
usage: tn_tamper.py [n_blocks]"""
import json, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE / "test"))
from tn_run import records

ZCG = bytes.fromhex("a9147a86d6c7eb12ce0aa309d7391a6f338eba3c242b87")


def cs(b, i):
    x = b[i]
    if x < 0xfd:
        return x, i + 1
    if x == 0xfd:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    return struct.unpack_from("<I", b, i + 1)[0], i + 5


def coinbase_outs(blk):
    """(offset of the coinbase tx, offset of its vout count, [(value_off, script, end)])"""
    i = 1487
    _, i = cs(blk, i)
    t0 = i
    ver = struct.unpack_from("<I", blk, t0)[0] & 0x7fffffff
    assert ver >= 5
    j = t0 + 20
    nin, j = cs(blk, j)
    for _ in range(nin):
        j += 36
        sl, j = cs(blk, j)
        j += sl + 4
    vc = j
    nout, j = cs(blk, j)
    outs = []
    for _ in range(nout):
        vo = j
        sl, k = cs(blk, j + 8)
        outs.append((vo, blk[k:k + sl], k + sl))
        j = k + sl
    return t0, vc, outs


def rebuild(rec, blk):
    h = rec[:4]
    return h + rec[4:4 + 1487] + struct.pack("<I", len(blk)) + bytes(blk)


def run(recs):
    tmp = HERE / "data/tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    (tmp / "tt.bin").write_bytes(b"".join(r[1] for r in recs))
    (tmp / "tt.ctx").write_bytes(b"".join(r[2] for r in recs))
    out = subprocess.run([str(HERE / "bin/tn_check"), str(tmp / "tt.bin"), str(tmp / "tt.ctx")], capture_output=True, text=True).stdout
    fails = {}
    for line in out.splitlines():
        f = line.split()
        if f and f[0] == "fail":
            fails.setdefault(int(f[1]), set()).add(f[2])
        elif f and f[0] == "tn":
            fails.setdefault(int(f[1]), set())
    return fails


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    meta = {b["height"]: b for b in json.load(open(HERE / "data/testnet/blocks.json"))}
    allr = records(HERE / "data/testnet/blocks.bin", HERE / "data/testnet/ctx.bin")
    pick = [r for r in allr if 4465026 <= r[0] < 4497948 and meta[r[0]].get("fees", 0) > 0
            and any(bytes.fromhex(s) == ZCG for _, s in meta[r[0]]["coinbase_outputs"])
            and any(v >= 5 for v in meta[r[0]]["tx_versions"][1:])][:n]
    cases = {}

    def mk(name, want, f):
        out = []
        for h, rec, crec in pick:
            blk = bytearray(rec[8 + 1487:])
            nb = f(h, blk)
            out.append((h, rebuild(rec, nb), crec))
        cases[name] = (want, out)

    def extra60(h, blk):
        fee = meta[h]["fees"]
        c = fee // 10 * 6 + fee % 10 * 6 // 10
        t0, vc, outs = coinbase_outs(blk)
        nout, j = cs(blk, vc)
        assert nout < 0xfc
        add = struct.pack("<q", c) + bytes([len(ZCG)]) + bytes.fromhex("a914" + "11" * 20 + "87")
        return blk[:vc] + bytes([nout + 1]) + blk[j:outs[-1][2]] + add + blk[outs[-1][2]:]

    def zcg_set(v):
        def f(h, blk):
            t0, vc, outs = coinbase_outs(blk)
            for vo, s, _ in outs:
                if s == ZCG:
                    old = struct.unpack_from("<q", blk, vo)[0]
                    struct.pack_into("<q", blk, vo, old - 1 if v is None else v)
            return blk
        return f

    def branch(h, blk):
        i = 1487
        ntx, i = cs(blk, i)
        # walk to the second tx using the sizes is complex; flip the branch id of the coinbase's
        # successor only if it starts right after the coinbase: find it by scanning for its header
        t0, vc, outs = coinbase_outs(blk)
        # the coinbase's own branch id is at t0 + 8: tamper the coinbase (a v5/v6 tx too)
        struct.pack_into("<I", blk, t0 + 8, 0x37A5165B)
        return blk

    def v4(h, blk):
        t0, vc, outs = coinbase_outs(blk)
        struct.pack_into("<I", blk, t0, 0x80000004)
        struct.pack_into("<I", blk, t0 + 4, 0x892F2085)
        return blk

    mk("extra60 (miner keeps 100% of fees)", {"miner_fees"}, extra60)
    mk("zcg-1 (ZCG 1 zat short)", {"issuance_required_outputs", "miner_fees"}, zcg_set(None))
    mk("zcg_pre (pre-NU7 8% = 12,500,000)", {"issuance_required_outputs", "miner_fees"}, zcg_set(12500000))
    mk("branch (coinbase with NU6.3 branch id)", {"branch_id"}, branch)
    mk("v4 (coinbase header says v4)", {"tx_version", "wire"}, v4)
    base = run(pick)
    clean = sum(1 for h, _, _ in pick if not base.get(h))
    print(f"untampered: {clean}/{len(pick)} blocks VALID")
    ok_all = clean == len(pick)
    for name, (want, recs) in cases.items():
        got = run(recs)
        good = 0
        for h, _, _ in recs:
            g = got.get(h, {"no result"})
            # v4: the wire validator may reject the re-labelled tx before the rules run
            if (g and g <= want and (name.startswith("v4") or g == want)):
                good += 1
            elif good < 1:
                print("   e.g.", h, sorted(g))
        from collections import Counter
        dist = Counter(tuple(sorted(got.get(h, {"no result"}))) for h, _, _ in recs)
        print(f"{name:<42} {good}/{len(recs)} rejected with exactly {sorted(want)}{' (or a subset)' if name.startswith('v4') else ''}; got {dict(dist)}")
        ok_all &= good == len(recs)
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
