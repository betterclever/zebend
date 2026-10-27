#!/usr/bin/env python3
"""Unit cases for mempool/bin/txpolicy (Bend): standardness incl. AreInputsStandard, ZIP 317.

The transactions are real ones (a recent block's txs, via rpc.py getblock + blockdelta); the
policy program only parses them, so the cases vary the inputs it is given (fee, the spent
scriptPubKeys) or the bytes of a scriptSig / output script (the txs are never validated or sent).
usage: python3 tests/test_policy.py [--bin bin/txpolicy]
"""
import argparse, json, struct, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import txcheck as X

P2PKH = bytes.fromhex("76a914") + bytes(20) + bytes.fromhex("88ac")
P2SH = bytes.fromhex("a914") + bytes(20) + bytes.fromhex("87")
P2PK = bytes([33, 2]) + bytes(32) + b"\xac"
MS_1_1 = bytes([0x51, 33, 2]) + bytes(32) + bytes([0x51, 0xae])
MS_2_1 = bytes([0x52, 33, 2]) + bytes(32) + bytes([0x51, 0xae])  # m > n: not a standard template
NONSTD = b"\x51"
NULLDATA = b"\x6a\x04abcd"


def rpc(port, method, *params):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode())
    r = json.load(urllib.request.urlopen(req, timeout=300))
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["result"]


def v4_one_input(blocks):
    for raw, t in blocks:
        if raw[:4] == b"\x04\x00\x00\x80" and len(t["ins"]) == 1 and not t["sap"] and not t["js"]:
            return raw, t
    return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default=None, help="txpolicy binary to test (default mempool/bin/txpolicy)")
    a = ap.parse_args()
    if a.bin:
        X.BIN = Path(a.bin).resolve().parent
        name = Path(a.bin).name
        if name != "txpolicy":
            d = X.WORK / "polbin"
            d.mkdir(parents=True, exist_ok=True)
            (d / "txpolicy").unlink(missing_ok=True)
            (d / "txpolicy").symlink_to(Path(a.bin).resolve())
            X.BIN = d
    tip = rpc(18233, "getblockcount")
    txs = []
    for h in range(tip, tip - 30, -1):
        blk = bytes.fromhex(rpc(18233, "getblock", str(h), 0))
        p = X.tmp("pb.bin")
        p.write_bytes(X.window_bytes([(h, blk)]))
        b = X.parse_delta(X.run(X.BIN_FN / "blockdelta", p).stdout)[0]
        p.unlink()
        off = X.HDR + len(X.cs(len(b["txs"])))
        for t in b["txs"]:
            if not t["cb"]:
                txs.append((blk[off:off + t["size"]], t))
            off += t["size"]
        if v4_one_input(txs)[0] is not None:
            break
    raw, t = v4_one_input(txs)
    if raw is None:
        print("no v4 tx with exactly one transparent input in the last 30 blocks: SKIPPED")
        return 1
    print(f"base tx {t['txid']} (v4, 1 input, {len(t['outs'])} outputs, {len(raw)} bytes)")
    # its scriptSig: after the 36-byte outpoint of the only input
    pt = bytes.fromhex(t["ins"][0][0])[::-1] + struct.pack("<I", t["ins"][0][1])
    i = raw.index(pt) + 36
    slen = raw[i]
    sig = raw[i + 1:i + 1 + slen]
    def with_sig(new):
        return raw[:i] + X.cs(len(new)) + new + raw[i + 1 + slen:]
    extra_push = with_sig(sig + b"\x01\x00")              # 3 pushes for a P2PKH spend
    reserved = with_sig(sig + b"\x50")                    # OP_RESERVED: push-only by IsPushOnly, does not execute
    nonpush = with_sig(sig + b"\x76")                     # OP_DUP: not push-only
    big = with_sig(b"\x4d" + struct.pack("<H", 1700) + bytes(1700))  # 1,703-byte scriptSig
    # outputs: replace the first output script (a P2PKH, 25 bytes) by other kinds of the same length
    o = t["outs"][0]
    j = raw.index(struct.pack("<q", o[1]) + X.cs(len(o[2])) + o[2])
    def with_out(script, value=None):
        return raw[:j] + struct.pack("<q", o[1] if value is None else value) + X.cs(len(script)) + script \
            + raw[j + 8 + len(X.cs(len(o[2]))) + len(o[2]):]
    fee = 100_000
    cases = [
        ("P2PKH spend, 2 pushes", raw, [P2PKH], "PASS", None),
        ("spent script non-standard (OP_TRUE)", raw, [NONSTD], "FAIL", "non_standard_inputs"),
        ("spent script OP_RETURN", raw, [NULLDATA], "FAIL", "non_standard_inputs"),
        ("spent P2PK expects 1 push, got 2", raw, [P2PK], "FAIL", "non_standard_inputs"),
        ("spent 1-of-1 multisig expects 2 pushes", raw, [MS_1_1], "PASS", None),
        ("spent 2-of-1 'multisig' is not a standard template", raw, [MS_2_1], "FAIL", "non_standard_inputs"),
        ("spent P2SH: redeemed = last push (a pubkey: non-standard, 0 sigops) -> accepted", raw, [P2SH], "PASS", None),
        ("no spent script for the input", raw, [], "FAIL", "non_standard_inputs"),
        ("spent scripts not given (first pass)", raw, None, "PASS", None),
        ("3 pushes for a P2PKH spend", extra_push, [P2PKH], "FAIL", "non_standard_inputs"),
        ("OP_RESERVED in scriptSig", reserved, [P2PKH], "FAIL", "non_standard_inputs"),
        ("scriptSig not push-only", nonpush, [P2PKH], "FAIL", "scriptsig_not_push_only"),
        ("scriptSig 1,703 bytes", big, [P2PKH], "FAIL", "scriptsig_too_large"),
        ("output P2SH", with_out(P2SH), [P2PKH], "PASS", None),
        ("output P2PK", with_out(P2PK), [P2PKH], "PASS", None),
        ("output bare 1-of-1 multisig", with_out(MS_1_1), [P2PKH], "FAIL", "bare_multisig"),
        ("output non-standard (OP_TRUE)", with_out(NONSTD), [P2PKH], "FAIL", "scriptpubkey_nonstandard"),
        ("output OP_RETURN 6 bytes", with_out(NULLDATA), [P2PKH], "PASS", None),
        ("output OP_RETURN 84 bytes", with_out(b"\x6a\x4c\x51" + bytes(81)), [P2PKH], "FAIL", "datacarrier_too_large"),
        ("output dust 53 zat (threshold 54 for P2PKH)", with_out(o[2], 53), [P2PKH], "FAIL", "dust"),
        ("output 54 zat (not dust)", with_out(o[2], 54), [P2PKH], "PASS", None),
    ]
    items = [(r, fee, 1, sp) for _, r, sp, _, _ in cases]
    # sigops > 4,000 and ZIP 317 on the base tx
    items.append((raw, fee, 4001, [P2PKH]))
    cases.append(("sigops 4,001 (as bin/rules would count)", raw, [P2PKH], "FAIL", "too_many_sigops"))
    res = X.policy(items)
    base = res[0]
    ca = base["conv_actions"]
    z = X.policy([(raw, ca * 1000, 1, [P2PKH]), (raw, ca * 1000 - 1, 1, [P2PKH]), (raw, 0, 1, [P2PKH])])
    ok_n = 0
    for (name, _r, _sp, want, why), r in zip(cases, res):
        s = r.get("std", {})
        ok = s.get("verdict") == want and (why is None or s.get("reason") == why)
        ok_n += ok
        print(f"  {'PASS' if ok else 'FAIL'}  {name}: std {s.get('verdict')} {s.get('reason', '')}")
    zc = [("fee = conventional fee", z[0], "PASS"), ("fee = conventional - 1", z[1], "FAIL"), ("fee 0", z[2], "FAIL")]
    for name, r, want in zc:
        ok = r["zip317"]["verdict"] == want
        ok_n += ok
        print(f"  {'PASS' if ok else 'FAIL'}  ZIP 317 {name} ({r['conv_fee']} zat for {r['conv_actions']} actions): "
              f"{r['zip317']['verdict']} {r['zip317']['reason']} unpaid {r['zip317']['unpaid']}")
    total = len(cases) + len(zc)
    print(f"\nRESULT: {ok_n}/{total} PASS")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "policy.txt").write_text(f"{ok_n}/{total}\n")
    return 0 if ok_n == total else 1


if __name__ == "__main__":
    sys.exit(main())
