#!/usr/bin/env python3
"""Tamper tests for bin/rules: each case changes one thing in a real mainnet block (or in the
spent-output context) and must fail exactly the intended rule (every other rule still passes).

Byte surgery here is test scaffolding: transaction boundaries come from blockdelta's sizes.
Turnstile rules are ignored except in the turnstile case (single-block windows have no pools).
"""
import struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))
import rules
from test_rules import DATA, TestStore, delta, cs, tx_info

BIG = 10 ** 15


def txs_of(h, raw):
    blk = delta({h: raw})[0]
    return raw[:1487], [bytes(x) for x in rules.tx_slices(raw, [t["size"] for t in blk["txs"]])], blk


def join(hdr, txs):
    n = len(txs)
    c = bytes([n]) if n < 0xfd else b"\xfd" + struct.pack("<H", n)
    return hdr + c + b"".join(txs)


def layout(raw):
    """Offsets inside a tx: version, ins [(seq_off)], outs [(value_off, script_len_off, script_off, slen)], lock_off, exp_off."""
    ver = struct.unpack_from("<I", raw, 0)[0] & 0x7fffffff
    i = 4 if ver <= 2 else 8 if ver <= 4 else 20
    nin, i = cs(raw, i)
    ins = []
    for _ in range(nin):
        i += 36
        sl, i = cs(raw, i)
        i += sl
        ins.append(i)
        i += 4
    nout, i = cs(raw, i)
    outs = []
    for _ in range(nout):
        vo = i
        sl, j = cs(raw, i + 8)
        outs.append((vo, i + 8, j, sl))
        i = j + sl
    if ver >= 5:
        lock, exp = 12, 16
    else:
        lock, exp = i, i + 4 if ver >= 3 else None
    return {"ver": ver, "ins": ins, "outs": outs, "lock": lock, "exp": exp}


def put32(b, off, v):
    b[off:off + 4] = struct.pack("<I", v)


def add_value(b, off, d):
    v = struct.unpack_from("<q", b, off)[0]
    b[off:off + 8] = struct.pack("<q", v + d)


def run(h, raw, st, pools=None, override=None):
    blocks = delta({h: raw})
    if "invalid" in blocks[0]:
        return ["wire"]
    st.fetch([p for t in blocks[0]["txs"] for (p, _, _) in t["ins"]])
    store = st
    if override:
        class O:
            def utxo(self, txid, vout):
                return override(txid, vout, st.utxo(txid, vout))

            def get(self, k, d=None):
                return d
        store = O()
    r = rules.run_rules(blocks, store, {h: raw}, pools or {}, tag=f"t{h}")[h]
    fs = r.get("fails", [])
    if pools is None:
        fs = [f for f in fs if not f.startswith("turnstile_")]
    return fs


def pick(blk, pred):
    for t in blk["txs"][1:]:
        if pred(t):
            return t["i"]
    raise SystemExit("no suitable tx")


def main():
    st = TestStore()
    cases = []

    def case(name, h, want, mk=None, pools=None, override=None):
        raw = (DATA / f"{h}.bin").read_bytes()
        if mk:
            raw = mk(raw)
        fs = run(h, raw, st, pools, override)
        names = sorted({f.split()[0] for f in fs})
        ok = names == sorted(want if isinstance(want, list) else [want])
        cases.append(ok)
        print(f"{'ok  ' if ok else 'BAD '} {name:<40} block {h}: {fs}")

    # 1. coinbase overpays by 1 zat (NU6+: must equal subsidy + fees exactly; pre-NU6: <=)
    def cb_over(raw, out_k=0):
        hdr, txs, blk = txs_of(3528000, raw)
        t = bytearray(txs[0])
        L = layout(t)
        # the miner's output: the one that is not a funding-stream output (the largest)
        k = max(range(len(L["outs"])), key=lambda j: struct.unpack_from("<q", t, L["outs"][j][0])[0])
        add_value(t, L["outs"][k][0], 1)
        txs[0] = bytes(t)
        return join(hdr, txs)
    case("coinbase overpays by 1 zat", 3528000, "miner_fees", cb_over)

    # 2. a non-coinbase tx pays out more than it spends (fee < 0)
    def neg_fee(raw):
        hdr, txs, blk = txs_of(2444391, raw)
        i = pick(blk, lambda t: t["ins"] and t["outs"])
        t = bytearray(txs[i])
        add_value(t, layout(t)["outs"][0][0], 10 ** 12)
        txs[i] = bytes(t)
        return join(hdr, txs)
    # the block's fees drop below what the coinbase claims, so miner_fees fails with it
    case("fee < 0 (output + 10,000 ZEC)", 2444391, ["value_balance", "miner_fees"], neg_fee)

    # 3. spends a coinbase output 50 blocks old (ctx says from-coinbase, height h-50); the
    #    spending tx has no transparent outputs in block 1712999? use a tx with outputs: then
    #    the shielding rule also applies, so pick a tx without transparent outputs.
    blk = delta({2247653: (DATA / "2247653.bin").read_bytes()})[0]
    tgt = next(t for t in blk["txs"][1:] if t["ins"])
    first = tgt["ins"][0][:2]
    def immature(txid, vout, u):
        if (txid, vout) == first:
            return (u[0], u[1], 2247653 - 50, 1)
        return u
    outs = len(tgt["outs"])
    # the spending tx has transparent outputs, so the shielding rule fires too (as in Zebra)
    case("immature coinbase spend (50 deep)", 2247653,
         ["coinbase_maturity"] + ([] if outs == 0 else ["coinbase_spend_transparent_outputs"]), override=immature)
    def mature_cb(txid, vout, u):
        if (txid, vout) == first:
            return (u[0], u[1], 2247653 - 500, 1)
        return u
    case("mature coinbase spend with transparent outputs", 2247653, "coinbase_spend_transparent_outputs", override=mature_cb)

    # 4. expired tx: nExpiryHeight = h - 1 on a v5 tx
    def expired(raw, h=3460010):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["v"] >= 5)
        t = bytearray(txs[i])
        put32(t, 16, h - 1)
        txs[i] = bytes(t)
        return join(hdr, txs)
    case("expired tx (expiry = h - 1)", 3460010, "expired", expired)

    # 5. non-final lock time: lock = h + 10 and one input sequence 0
    def nonfinal(raw, h=3528000):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["ins"])
        t = bytearray(txs[i])
        L = layout(t)
        put32(t, L["lock"], h + 10)
        put32(t, L["ins"][0], 0)
        txs[i] = bytes(t)
        return join(hdr, txs)
    case("non-final lock time (h + 10, seq 0)", 3528000, "lock_time", nonfinal)

    # 6. wrong consensus branch id: NU6.2's id on a v5 tx at an NU6.3 height
    def branch(raw, h=3460010):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["v"] == 5)
        t = bytearray(txs[i])
        put32(t, 8, 0x5437f330)
        txs[i] = bytes(t)
        return join(hdr, txs)
    case("wrong branch id (NU6.2 at NU6.3)", 3460010, "branch_id", branch)

    # 7. wrong version for the height: a Sapling-era v4 tx rewritten as a v3 (Overwinter) tx
    def v3(raw, h=500000):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["v"] == 4 and not t["sap"] and not t["js"])
        t = bytearray(txs[i])
        L = layout(t)
        e = L["exp"] + 4  # then valueBalance (8), nSpends, nOutputs, nJoinSplit (3 x 0)
        assert t[e + 8:e + 11] == b"\0\0\0" and len(t) == e + 11
        t = t[:e] + b"\0"  # v3: ... expiry, nJoinSplit = 0
        put32(t, 0, 0x80000003)
        put32(t, 4, 0x03C48270)
        txs[i] = bytes(t)
        return join(hdr, txs)
    case("v3 tx in a Sapling-era block", 500000, "tx_version", v3)

    # 8. duplicate input: the same transparent spend twice in one block (pre-NU6 block, so the
    #    coinbase may claim less than subsidy + fees)
    def dup_in(raw, h=2444391):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["ins"])
        return join(hdr, txs + [txs[i]])
    case("duplicate transparent input in block", 2444391, "duplicate_spend", dup_in)

    # 9. duplicate nullifier: a shielded spend repeated in the block
    def dup_nf(raw, h=1712999):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: any(t["nfs"][p] for p in t["nfs"]))
        return join(hdr, txs + [txs[i]])
    case("duplicate nullifier in block", 1712999, "duplicate_spend", dup_nf)

    # 10. pool going negative: the Sapling pool is 0 before a block that takes value out of it
    big = {n: BIG for n in rules.POOL_NAMES}
    hs = None
    for h in (1750000, 1800000, 1700000, 2128340, 2371685, 3460010, 1803987, 1818842):
        b = delta({h: (DATA / f"{h}.bin").read_bytes()})[0]
        if sum(t["sap"]["vb"] for t in b["txs"] if t["sap"]) > 0:
            hs = h
            break
    case("Sapling pool goes negative (turnstile)", hs, "turnstile_sapling", pools=dict(big, sapling=0))
    fs = run(hs, (DATA / f"{hs}.bin").read_bytes(), st, dict(big))
    ok = fs == []
    cases.append(ok)
    print(f"{'ok  ' if ok else 'BAD '} {'same block, every pool large':<40} block {hs}: {fs}")

    # 11. sigops > 20,000: one output script made of 1,001 OP_CHECKMULTISIG (20,020 sigops)
    def sigops(raw, h=2444391):
        hdr, txs, blk = txs_of(h, raw)
        i = pick(blk, lambda t: t["outs"])
        t = bytearray(txs[i])
        vo, lo, so, sl = layout(t)["outs"][0]
        new = b"\xae" * 1001
        t = t[:lo] + b"\xfd" + struct.pack("<H", len(new)) + new + t[so + sl:]
        txs[i] = bytes(t)
        return join(hdr, txs)
    case("block sigops > 20,000", 2444391, "sigops", sigops)

    # 12. missing funding stream output: ZCG paid 1 zat short, the miner 1 zat more (so the
    #     total still balances): only the required-output check fails
    def fs_short(raw, h=3528000):
        hdr, txs, blk = txs_of(h, raw)
        t = bytearray(txs[0])
        L = layout(t)
        vals = [struct.unpack_from("<q", t, o[0])[0] for o in L["outs"]]
        miner = max(range(len(vals)), key=lambda j: vals[j])
        zcg = min(range(len(vals)), key=lambda j: vals[j])
        add_value(t, L["outs"][zcg][0], -1)
        add_value(t, L["outs"][miner][0], 1)
        txs[0] = bytes(t)
        return join(hdr, txs)
    case("funding stream output 1 zat short", 3528000, "issuance_required_outputs", fs_short)

    # 13. BIP34: coinbase height one off
    def bip34(raw, h=1000000):
        hdr, txs, blk = txs_of(h, raw)
        t = bytearray(txs[0])
        i = 4 if layout(t)["ver"] <= 2 else 8 if layout(t)["ver"] <= 4 else 20
        _, i = cs(t, i)
        i += 36
        _, i = cs(t, i)
        assert t[i] == 3 and struct.unpack_from("<I", bytes(t[i + 1:i + 4]) + b"\0")[0] == h
        t[i + 1] ^= 1
        txs[0] = bytes(t)
        return join(hdr, txs)
    case("coinbase height (BIP34) off by one", 1000000, "coinbase_height", bip34)

    # 14. a second coinbase-like tx (null prevout) after the first
    def second_cb(raw, h=1000000):
        hdr, txs, blk = txs_of(h, raw)
        return join(hdr, txs + [txs[0]])
    case("second coinbase in block", 1000000, "coinbase_first", second_cb)

    print(f"tamper cases: {sum(cases)}/{len(cases)} fail exactly the intended rule")


if __name__ == "__main__":
    main()
