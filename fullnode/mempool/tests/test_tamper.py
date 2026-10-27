#!/usr/bin/env python3
"""Tampered and double-spend transactions are rejected (and the untampered originals admitted).

Uses REAL transactions only: valid txs currently in the running mempool (its RPC,
getrawmempool + getrawtransaction) and txs of a recent block (P2P via rpc.py getblock, checked by
Bend blockdelta), tampered locally. Nothing is broadcast: the admission pipeline (admit.py) runs
in this process with its own empty Pool against the instance's state (read-only).

usage: python3 tests/test_tamper.py [--state ../state-tip] [--mempool-rpc 18234] [--node-rpc 18233]
"""
import argparse, json, struct, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import txcheck as X
from admit import Admitter, ChainView
from pool import Pool


def rpc(port, method, *params):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode(),
        headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=300))
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["result"]


def flip(raw, off):
    b = bytearray(raw)
    b[off] ^= 0x01
    return bytes(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=str(HERE.parent.parent / "state-tip"))
    ap.add_argument("--mempool-rpc", type=int, default=18234)
    ap.add_argument("--node-rpc", type=int, default=18233)
    a = ap.parse_args()
    view = ChainView(a.state)
    logs = []
    adm = Admitter(view, Pool(), logs.append)
    txids = rpc(a.mempool_rpc, "getrawmempool")
    raws = {t: bytes.fromhex(rpc(a.mempool_rpc, "getrawtransaction", t, 0)) for t in txids}
    infos = {t: rpc(a.mempool_rpc, "getrawtransaction", t, 1) for t in txids}
    print(f"live mempool: {len(raws)} txs; state tip {view.tip()['height']}")
    # pick one tx of each kind
    tr = [t for t in txids if infos[t]["vin"] and infos[t]["version"] == 4]
    tr5 = [t for t in txids if infos[t]["vin"] and infos[t]["version"] >= 5]
    sh = [t for t in txids if not infos[t]["vin"] and infos[t]["version"] >= 5]
    print(f"  candidates: v4 transparent-input {len(tr)}, v5+ transparent-input {len(tr5)}, v5+ shielded-only {len(sh)}")
    cases = []  # (name, raw, expected status, expected reason substring)

    def baseline(name, t):
        cases.append((f"baseline {name} {t[:12]}", raws[t], "admitted", None))

    results = []
    total = {"pass": 0, "fail": 0, "skipped": []}

    def run(batch, fresh=False):
        """fresh: each case alone against an empty pool (tampering must be caught by validation,
        not by a conflict with another case of the same batch)."""
        if fresh:
            res = []
            for _, raw, _, _ in batch:
                adm.pool = Pool()
                res += adm.admit([(raw, "test")])
        else:
            res = adm.admit([(raw, "test") for _, raw, _, _ in batch])
        for (name, raw, want, sub), r in zip(batch, res):
            subs = sub if isinstance(sub, tuple) else (sub,)
            ok = r.status == want and (sub is None or any((r.reason or "").find(x) >= 0 for x in subs))
            total["pass" if ok else "fail"] += 1
            results.append({"case": name, "want": want, "want_reason": sub, "got": r.status, "reason": r.reason,
                            "ok": ok})
            print(f"  {'PASS' if ok else 'FAIL'}  {name}: {r.status} {('(' + r.reason + ')') if r.reason else ''}")
        return res

    # 1. baselines (each in its own pool round, so double-spend cases can follow)
    picks = [("v4-transparent", tr[:1]), ("v5+-transparent", tr5[:1]), ("v5+-shielded", sh[:1])]
    for name, ts in picks:
        if not ts:
            total["skipped"].append(f"no {name} tx in the live mempool")
            continue
        baseline(name, ts[0])
    run(cases)
    cases.clear()
    # 2. double spends against the mempool (the baselines are now in the test pool)
    for name, ts in picks:
        if not ts:
            continue
        raw = raws[ts[0]]
        # same inputs / nullifiers, different txid: change the lowest byte of the last 4 bytes
        # before the end that belong to effecting data: for v4 the nExpiryHeight is after the
        # outputs; simplest effecting change for every version: the first output value (v4/v5
        # with transparent outputs) or nExpiryHeight (v5+: offset 16).
        if raw[:4] in (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80"):
            b = bytearray(raw)
            exp = struct.unpack_from("<I", b, 16)[0]
            struct.pack_into("<I", b, 16, exp + 1 if exp else view.tip()["height"] + 20)
            ds = bytes(b)
        else:
            ds = None
            j = infos[ts[0]]
            if j["vout"]:
                v = struct.pack("<q", j["vout"][0]["valueZat"])
                i = raw.find(v)
                if i > 0:
                    ds = raw[:i] + struct.pack("<q", j["vout"][0]["valueZat"] - 1) + raw[i + 8:]
        if ds is None:
            total["skipped"].append(f"double spend {name}: no effecting field found")
            continue
        cases.append((f"double spend (mempool) of {name} {ts[0][:12]}", ds, "rejected", "spend conflict"))
    run(cases)
    cases.clear()
    # 3. tampered (fresh pool: tampering must be caught by validation, not by conflicts)
    adm.pool = Pool()
    for name, ts in picks:
        if not ts:
            continue
        t = ts[0]
        raw = raws[t]
        j = infos[t]
        if raw[:4] in (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80"):
            # authorizing data (txid unchanged): a byte of the last 64 bytes (a binding signature
            # for v5 shielded bundles; else the last transparent scriptSig region is earlier)
            # shielded-only v5/v6: the last bytes are the last bundle's binding signature (authorizing
            # data, txid unchanged) -> a hook must fail; transparent-only: the trailing empty-bundle
            # counts -> malformed
            cases.append((f"tampered last byte {name} {t[:12]}", flip(raw, len(raw) - 1), "rejected",
                          "consensus (hook)" if not j["vin"] else None))
            b = bytearray(raw)
            struct.pack_into("<I", b, 16, view.tip()["height"])  # expiry = tip < tip+1
            cases.append((f"expiry = tip {name} {t[:12]}", bytes(b), "rejected", "expired"))
            b = bytearray(raw)
            struct.pack_into("<I", b, 8, int("5437f330", 16))  # NU6.2 branch id
            # v5: bin/rules branch_id; v6 with a pre-NU6.3 branch id is already refused by the wire validator
            cases.append((f"wrong branch id (NU6.2) {name} {t[:12]}", bytes(b), "rejected", ("branch_id", "malformed")))
        if j["vin"]:
            # a scriptSig byte: the first input's scriptSig starts after its 36-byte outpoint
            pt = bytes.fromhex(j["vin"][0]["txid"])[::-1] + struct.pack("<I", j["vin"][0]["vout"])
            i = raw.find(pt)
            if i > 0:
                cases.append((f"tampered scriptSig (signature byte) {name} {t[:12]}", flip(raw, i + 36 + 10),
                              "rejected", "transparent"))
        if j["vout"]:
            v = struct.pack("<q", j["vout"][0]["valueZat"])
            i = raw.find(v)
            if i > 0:
                big = raw[:i] + struct.pack("<q", j["vout"][0]["valueZat"] + 10**12) + raw[i + 8:]
                cases.append((f"output +10,000 ZEC {name} {t[:12]}", big, "rejected", "value_balance"))
                cases.append((f"truncated {name} {t[:12]}", raw[:-5], "rejected", "malformed"))
    run(cases, fresh=True)
    cases.clear()
    # 4. ZIP 317: the fee of a baseline tx moved into its first output (fee becomes 1 zat)
    adm.pool = Pool()
    for name, ts in picks:
        if not ts or not infos[ts[0]]["vout"]:
            continue
        t = ts[0]
        r = adm.admit([(raws[t], "test")])[0]
        if r.status != "admitted":
            total["skipped"].append(f"ZIP 317 case {name}: baseline not admitted ({r.reason})")
            continue
        fee = r.entry.fee
        adm.pool = Pool()
        j = infos[t]
        v = struct.pack("<q", j["vout"][0]["valueZat"])
        i = raws[t].find(v)
        low = raws[t][:i] + struct.pack("<q", j["vout"][0]["valueZat"] + fee - 1) + raws[t][i + 8:]
        cases.append((f"fee {fee} -> 1 zat {name} {t[:12]}", low, "rejected", "ZIP 317"))
    run(cases, fresh=True)
    cases.clear()
    # 5. chain double spends and an already-mined tx: transactions of a recent block
    tip = view.tip()["height"]
    mined = []
    for h in range(tip - 1, tip - 7, -1):
        blk = bytes.fromhex(rpc(a.node_rpc, "getblock", str(h), 0))
        p = X.tmp("tblk.bin")
        p.write_bytes(X.window_bytes([(h, blk)]))
        b = X.parse_delta(X.run(X.BIN_FN / "blockdelta", p).stdout)[0]
        p.unlink()
        off = X.HDR + len(X.cs(len(b["txs"])))
        for t in b["txs"]:
            if not t["cb"]:
                mined.append((t, blk[off:off + t["size"]]))
            off += t["size"]
    shielded = [m for m in mined if any(m[0]["nfs"].values()) and not m[0]["ins"] and m[1][:4] in (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80")]
    transp = [m for m in mined if m[0]["ins"] and m[1][:4] in (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80")]
    mined = transp[:2] + shielded[:2] + [m for m in mined if m[1][:4] == b"\x04\x00\x00\x80"][:1]
    if not shielded:
        total["skipped"].append("no v5+ tx with nullifiers in the last 6 blocks")
    adm.pool = Pool()
    for t, raw in mined:
        cases.append((f"already mined {t['txid'][:12]}", raw, "rejected", "mined"))
        if raw[:4] in (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80"):
            bb = bytearray(raw)
            exp = struct.unpack_from("<I", bb, 16)[0]
            struct.pack_into("<I", bb, 16, exp + 1 if exp else tip + 20)
            sub = ("duplicate spend", "spent in the chain")  # nullifier in the chain's set / input spent
            cases.append((f"double spend of a mined tx (same inputs/nullifiers, expiry+1) "
                          f"{t['txid'][:12]}", bytes(bb), "rejected", sub))
    run(cases, fresh=True)
    print(f"\nRESULT: {total['pass']} PASS, {total['fail']} FAIL; skipped: {total['skipped'] or 'none'}")
    out = HERE / "results" / "tamper.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps({"tip": tip, "results": results, "skipped": total["skipped"]}, indent=1))
    return 0 if total["fail"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
