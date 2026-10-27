#!/usr/bin/env python3
"""NU7 in the full node's rules engine (node/bin/rules_nu7, rules.bend + zcash/consensus/nu7) on
Mainnet heights >= 3,543,405, before any real NU7 Mainnet block exists.

Each case relabels a real Mainnet block (node/bend/data/3528000.bin, NU6.3) to an NU7 height:
BIP34 height and coinbase nExpiryHeight set to the new height, non-coinbase v5/v6 consensus
branch ids set to NU7's 0x77190ad9 (their nExpiryHeight to 0), and the coinbase outputs rebuilt to what NU7 requires
(values from the Zebra oracle, data/vectors: subsidy 52,083,333, FS_FPF_ZCG_H3 4,166,666,
FS_CCF_H3 6,249,999; MinerFees = fees - floor(6 fees / 10)). Signatures/proofs are not
checked by bin/rules (they are the hooks' job), so the relabelled block is a valid NU7 block as
far as these rules go. The expected verdicts are written down here from the ZIPs, not taken
from Bend. Spent outputs come from lightwalletd (node/rules/test_rules.TestStore).
usage: nu7_rules_mainnet.py"""
import os, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
NU7 = ROOT / "zcash/consensus/nu7"
# The proposed node/rules.py (zcash/consensus/nu7/wiring/rules.py) and the NU7 rules.bend build
# (zcash/consensus/nu7/rules/rules_nu7.bend -> bin/rules_nu7); nothing the live node runs is touched.
os.environ.setdefault("ZEBEND_RULES_BIN", str(NU7 / "bin/rules_nu7"))
sys.path[:0] = [str(NU7 / "wiring"), str(ROOT / "node"), str(ROOT / "node/rules")]
import rules
assert Path(rules.__file__).parent == NU7 / "wiring"
from test_rules import DATA, TestStore, delta, cs
from tamper_rules import txs_of, join, layout

ZCG_P2SH = bytes.fromhex("a914c20cd5bdf7964ca61764db66bc2531b1792a084d87")
ZCG_P2PKH = bytes.fromhex("76a9142a7e627ed7e826b72168ab98740e563d0c52987a88ac")  # ZIP 2008
NU7_BRANCH = 0x77190AD9
SEED = 36858445520
BIG = 10 ** 15


def expected_issuance(h):
    """(subsidy, zcg value, zcg script, deferred) per ZIP 218 / 214 rev. 3 / 207 rev. 2 / 2008."""
    if h < 6132390:
        return 52083333, 4166666, (ZCG_P2PKH if h >= 3612390 else ZCG_P2SH), 6249999
    return 26041666, 0, None, 0


def bip34(h):
    b = h.to_bytes(4, "little").rstrip(b"\0")
    if b[-1] & 0x80:
        b += b"\0"
    return bytes([len(b)]) + b


def relabel(h, keep=None, cb_outs=None, miner_delta=0, fees=None, extra_v4=False):
    raw = (DATA / "3528000.bin").read_bytes()
    hdr, txs, blk = txs_of(3528000, raw)
    keep = keep if keep is not None else [i for i, t in enumerate(blk["txs"]) if t["v"] >= 5]
    if extra_v4:
        keep = sorted(set(keep) | {1})
    new = []
    for i in keep:
        t = bytearray(txs[i])
        if blk["txs"][i]["v"] >= 5:
            struct.pack_into("<I", t, 8, NU7_BRANCH)
        if i > 0 and blk["txs"][i]["v"] >= 3:
            struct.pack_into("<I", t, layout(t)["exp"], 0)  # nExpiryHeight 0: no expiry
        new.append(bytes(t))
    # coinbase: height push, expiry, outputs
    cb = bytearray(new[0])
    L = layout(cb)
    j = 20
    _, j = cs(cb, j)
    j += 36
    sl, k = cs(cb, j)
    old = bytes(cb[k:k + sl])
    push = bip34(h)
    assert old[:len(push)][0] == push[0], "height push length must stay the same"
    cb[k:k + len(push)] = push
    struct.pack_into("<I", cb, L["exp"], h)
    end_outs = L["outs"][-1][2] + L["outs"][-1][3]
    start_outs = L["outs"][0][0]
    vouts = b"".join(struct.pack("<q", v) + bytes([len(s)]) + s for v, s in cb_outs)
    nb = bytes([len(cb_outs)])
    # the vout count's CompactSize is the byte before the first output
    cb = cb[:start_outs - 1] + nb + vouts + cb[end_outs:]
    new[0] = bytes(cb)
    return join(hdr, new)


def fees_of(h, raw, st):
    """Fees of the non-coinbase txs (test scaffolding, from lightwalletd prevouts)."""
    b = delta({h: raw})[0]
    st.fetch([p for t in b["txs"] for (p, _, _) in t["ins"]])
    f = 0
    for t in b["txs"][1:]:
        tin = sum(st.utxo(p, v)[0] for (p, v, _) in t["ins"])
        vb = sum(t[k]["vb"] for k in ("sap", "orch", "iw") if t[k])
        f += tin + vb - sum(o[1] for o in t["outs"]) - sum(j["vpub_old"] - j["vpub_new"] for j in t["js"])
    return f


def run(h, raw, st, pools):
    blocks = delta({h: raw})
    if "invalid" in blocks[0]:
        return ["wire"], None
    st.fetch([p for t in blocks[0]["txs"] for (p, _, _) in t["ins"]])
    r = rules.run_rules(blocks, st, {h: raw}, pools, tag=f"nu7_{h}")[h]
    return r.get("fails", []), r


def main():
    st = TestStore()
    results = []
    miner_script = None
    raw0 = (DATA / "3528000.bin").read_bytes()
    _, _, blk0 = txs_of(3528000, raw0)
    miner_script = max(blk0["txs"][0]["outs"], key=lambda o: o[1])[2]
    pools = {n: BIG for n in rules.POOL_NAMES}
    pools["nsm"] = 0

    def case(name, h, want, tamper=None, nsm_before=0, check_nsm=True):
        # fees of the block as it will be (same txs regardless of the coinbase)
        base = relabel(h, cb_outs=[(0, miner_script)], **(tamper or {}).get("relabel", {}))
        f = fees_of(h, base, st)
        sub, zv, zs, dv = expected_issuance(h)
        miner = sub - zv - dv + (f - (f // 10 * 6 + f % 10 * 6 // 10))
        outs = [(miner, miner_script)] + ([(zv, zs)] if zv else [])
        if tamper and "outs" in tamper:
            outs = tamper["outs"](outs, f)
        raw = relabel(h, cb_outs=outs, **(tamper or {}).get("relabel", {}))
        p = dict(pools, nsm=nsm_before)
        fails, r = run(h, raw, st, p)
        names = sorted({x.split()[0] for x in fails})
        ok = names == sorted(want)
        nsm_note = ""
        if r and check_nsm and not want:
            exp_nsm = nsm_before + (SEED if h == 3543405 else 0) + (f // 10 * 6 + f % 10 * 6 // 10)
            ok = ok and r["pools"]["nsm"] == exp_nsm
            nsm_note = f" nsm {r['pools']['nsm']} (want {exp_nsm})"
        results.append(ok)
        print(f"{'ok  ' if ok else 'BAD '} {name:<58} h {h} fees {f}: {fails}{nsm_note}")

    case("NU7 activation block, ZCG to P2SH, 40% of fees to miner", 3543405, [])
    case("NU7 block before the ZIP 2008 switch (3,612,389)", 3612389, [], nsm_before=SEED)
    case("NU7 block after the ZIP 2008 switch: ZCG to P2PKH", 3612390, [], nsm_before=SEED)
    case("third halving 6,132,390: subsidy 26,041,666, streams ended", 6132390, [], nsm_before=SEED)
    case("miner claims 100% of the fees (pre-NU7 rule)", 3543405, ["miner_fees"],
         {"outs": lambda o, f: [(o[0][0] + f // 10 * 6 + f % 10 * 6 // 10, o[0][1])] + o[1:]})
    case("miner claims 1 zat less than MinerFees", 3543405, ["miner_fees"],
         {"outs": lambda o, f: [(o[0][0] - 1, o[0][1])] + o[1:]})
    case("pre-NU7 subsidy 156,250,000 at NU7", 3543405, ["issuance_required_outputs", "miner_fees"],
         {"outs": lambda o, f: [(o[0][0] + 156250000 - 52083333 - 12500000 + 4166666 - 18750000 + 6249999, o[0][1]),
                                (12500000, ZCG_P2SH)]})
    case("ZCG paid to the old P2SH after the switch", 3612390, ["issuance_required_outputs"],
         {"outs": lambda o, f: [o[0], (o[1][0], ZCG_P2SH)]}, nsm_before=SEED)
    case("ZCG paid before the switch to the new P2PKH", 3612389, ["issuance_required_outputs"],
         {"outs": lambda o, f: [o[0], (o[1][0], ZCG_P2PKH)]}, nsm_before=SEED)
    case("ZCG output 1 zat short (to miner)", 3600000, ["issuance_required_outputs"],
         {"outs": lambda o, f: [(o[0][0] + 1, o[0][1]), (o[1][0] - 1, o[1][1])]}, nsm_before=SEED)
    case("pre-third-halving subsidy 52,083,333 at 6,132,390", 6132390, ["miner_fees"],
         {"outs": lambda o, f: [(o[0][0] + 52083333 - 26041666, o[0][1])]}, nsm_before=SEED)
    case("a v4 transaction after NU7 (ZIP 2003)", 3543405, ["tx_version"], {"relabel": {"extra_v4": True}})
    case("NSM balance would go negative (turnstile_nsm)", 3600000, ["turnstile_nsm"], nsm_before=-(10 ** 9), check_nsm=False)
    # ZIP 218 action limits: the 2022 sandblasting block 1,750,000 (2,044 Sapling spends +
    # outputs) read at an NU7 height must fail shielded_action_limits (among the other rules a
    # relabelled pre-NU5 block breaks), and must not at the last pre-NU7 height.
    raw = (DATA / "1750000.bin").read_bytes()
    for h, want in ((3543405, True), (3543404, False)):
        fails, _ = run(h, raw, st, {})
        got = any(x.startswith("shielded_action_limits") for x in fails)
        results.append(got == want)
        print(f"{'ok  ' if got == want else 'BAD '} {'block 1,750,000 (2,044 Sapling IOs) read at ' + str(h):<58} shielded_action_limits {'reported' if got else 'not reported'}")
    print(f"NU7 mainnet rules cases: {sum(results)}/{len(results)} as expected")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
