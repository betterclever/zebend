#!/usr/bin/env python3
"""Cross-checks Zakura's NU7 dump (data/vectors/zakura.jsonl, from Zakura
crates/zakura-consensus/tests/nu7_diff_dump.rs @ 52967ff4f4d8) against Zebra's oracle
(target/release/nu7-oracle, zebra-chain @ 1e03ee753fbc).

Run on the Mac: python3 cross.py [zakura.jsonl]. Writes data/vectors/cross_report.json and prints
per-quantity counts of compared values and disagreements, with examples.
Scenario -> oracle network: testnet-real -> testnet, testnet-A1 -> testnet@4200000,
testnet-A2 -> testnet@4187001, regtest-R -> regtest@300 (built like Zakura's build_testnet /
build_regtest; see main.rs `network`).
"""
import collections, json, os, random, subprocess, sys, bisect

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "target/release/nu7-oracle")
VEC = os.path.join(HERE, "../data/vectors")
ZPATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(VEC, "zakura.jsonl")

# Scenario parameters copied from nu7_diff_dump.rs `nu7_diff_dump()`.
SCEN = {
    "testnet-real": dict(net="testnet", a=4_465_026, lo=4_463_026, hi=16_465_026, testnet=True, diff=True),
    "testnet-A1": dict(net="testnet@4200000", a=4_200_000, lo=4_198_000, hi=16_200_000, testnet=True, diff=True),
    "testnet-A2": dict(net="testnet@4187001", a=4_187_001, lo=4_185_001, hi=16_187_001, testnet=True, diff=False),
    "regtest-R": dict(net="regtest@300", a=300, lo=1, hi=2_000_000, testnet=False, diff=True),
}
RECV = ["Ecc", "ZcashFoundation", "MajorGrants", "Deferred"]


def oracle(args, lines):
    r = subprocess.run([BIN] + args, input="".join(l + "\n" for l in lines),
                       capture_output=True, text=True, check=True)
    return [json.loads(l) for l in r.stdout.splitlines()]


def s(v):
    """Normalises an oracle value to Zakura's string form."""
    return "none" if v is None else str(v).lower() if isinstance(v, bool) else str(v)


class Tally:
    def __init__(self):
        self.n = collections.Counter()
        self.bad = collections.defaultdict(list)

    def cmp(self, scen, q, key, h, zak, zeb):
        k = f"{scen}/{q}"
        self.n[k] += 1
        if zak != zeb:
            self.bad[k].append(dict(key=key, h=h, zakura=zak, zebra=zeb))


def chain_lines(a, start, end, bits, interval, fixed=29):
    """Zakura difficulty_chain: t(start)=1760000000, t(h)=t(h-1)+interval(h), first 29 fixed."""
    out, t = [], 1_760_000_000
    for h in range(start, end + 1):
        if h > start:
            t += interval(h)
        out.append(f"{h} {t} {bits if h <= start + fixed - 1 else '?'}")
    return out


def main():
    T = Tally()
    rows = collections.defaultdict(list)
    for l in open(ZPATH):
        r = json.loads(l)
        rows[r["scenario"]].append(r)
    for scen, P in SCEN.items():
        R = rows.get(scen, [])
        if not R:
            print(f"{scen}: no Zakura rows"); continue
        net, a, lo, hi = P["net"], P["a"], P["lo"], P["hi"]
        cheap = collections.defaultdict(list)    # (q,key) -> sorted [(h, v)]
        exp = collections.defaultdict(dict)       # (q,key) -> {h: v}
        struct = {}
        for r in R:
            q, k, h, v = r["quantity"], r["key"], r["height"], r["value"]
            if h is None:
                struct[(q, k)] = v
            elif q in ("funding_stream_address", "nsm_reissuance", "fee_burn", "miner_fee_share",
                       "tx_version_allowed") or q.startswith(("expected_bits", "median_time_past", "is_min")):
                exp[(q, k)][h] = v
            else:
                cheap[(q, k)].append((h, v))
        for v in cheap.values():
            v.sort()

        # ---- Per-height cheap quantities (Zakura emits change points only: step lookup).
        hs = {h for v in cheap.values() for h, _ in v} | {h for d in exp.values() for h in d}
        hs |= {h - 1 for h in hs}
        rng = random.Random(scen)
        hs |= {rng.randint(lo, hi) for _ in range(3000)}
        if scen == "testnet-real":
            hs |= {int(x) for x in open(os.path.join(VEC, "heights_testnet.txt"))}
        hs = sorted(h for h in hs if lo <= h <= hi)
        zeb = {o["h"]: o for o in oracle(["heights", net], map(str, hs))}

        def step(q, k, h):
            v = cheap.get((q, k))
            if not v:
                return None
            i = bisect.bisect_right(v, (h, "￿")) - 1
            return v[i][1] if i >= 0 else None

        for h in hs:
            o = zeb[h]
            fs = o["fs"] if isinstance(o["fs"], dict) else {}
            pairs = [("nu", "", o["nu"]), ("branch_id", "", o["branch_id"]),
                     ("target_spacing", "", o["target_spacing"]),
                     ("averaging_window", "", o["averaging_window"]),
                     ("halving_index", "", o["halving"]),
                     ("block_subsidy", "", o["scheduled_block_subsidy"]),
                     ("lockbox_value", "", fs.get("Deferred", "0") if isinstance(o["fs"], dict) else o["fs"]),
                     ("miner_subsidy", "", o["miner_subsidy"])]
            pairs += [("funding_stream_value", r, fs.get(r, "0") if isinstance(o["fs"], dict) else o["fs"]) for r in RECV]
            if P["testnet"]:
                pairs.append(("testnet_min_difficulty_gap_secs", "", o["min_difficulty_gap"]))
            for q, k, zv in pairs:
                z = step(q, k, h)
                if z is not None:
                    T.cmp(scen, q, k, h, z, s(zv))
            for r in RECV:
                z = exp[("funding_stream_address", r)].get(h)
                if z is not None:
                    T.cmp(scen, "funding_stream_address", r, h, z, s(o["fs_addr"][r]))

        # ---- NSM reissuance: Zakura block_subsidy(h, Some(bal)) - halving_block_subsidy(h);
        # Zebra block_subsidy_with_parent_nsm_value_balance(h, bal) - scheduled_block_subsidy(h).
        nsm_in = [(h, int(k)) for (q, k), d in exp.items() if q == "nsm_reissuance" for h in d]
        for o in oracle(["nsm", net], [f"{h} {b}" for h, b in nsm_in]):
            swp = o["subsidy_with_parent"]
            sched = zeb.get(o["h"], {}).get("scheduled_block_subsidy")
            zv = str(int(swp) - int(sched)) if swp.isdigit() and sched and sched.isdigit() else swp
            T.cmp(scen, "nsm_reissuance", o["balance"], o["h"], exp[("nsm_reissuance", o["balance"])][o["h"]], zv)

        # ---- Fees.
        fee_in = sorted({(h, int(k)) for (q, k), d in exp.items() if q == "miner_fee_share" for h in d})
        for o in oracle(["fees", net], [f"{h} {f}" for h, f in fee_in]):
            T.cmp(scen, "miner_fee_share", o["fees"], o["h"], exp[("miner_fee_share", o["fees"])][o["h"]], s(o["miner"]))
            T.cmp(scen, "fee_burn", o["fees"], o["h"], exp[("fee_burn", o["fees"])][o["h"]], s(o["contribution"]))

        # ---- Structural.
        c = oracle(["consts", net], [])[0]
        T.cmp(scen, "halving_heights", "", None, struct.get(("halving_heights", "")),
              ",".join(s(x) for x in c["height_for_halving_1_to_6"]))
        T.cmp(scen, "nsm_reissuance_start_height", "", None, struct.get(("nsm_reissuance_start_height", "")),
              s(c["nsm_reissuance_height"]))
        bnd = oracle(["boundaries", net], [])
        for r in RECV:
            ranges = [f"{fs['start']}..{fs['end']}" for fs in c["funding_streams"] if r in fs["recipients"]]
            T.cmp(scen, "funding_stream_ranges", r, None, struct.get(("funding_stream_ranges", r)),
                  ",".join(ranges) or "none")
            if r == "Deferred":
                zb = "none"
            else:
                bs = [b for fs, bd in zip(c["funding_streams"], bnd) if r in fs["recipients"]
                      for b in bd["boundaries"] if b > max(bd["start"], a)]
                zb = ",".join(map(str, sorted(bs)[:10])) or "none"
            T.cmp(scen, "address_period_boundaries", r, None, struct.get(("address_period_boundaries", r)), zb)

        # ---- Difficulty chains D and D2 (nu7_diff_dump.rs difficulty_chain).
        if P["diff"]:
            PRE = [37, 75, 90, 60, 150, 20, 25, 25, 10, 500, 75, 30]
            POST = [12, 25, 30, 20, 50, 25, 8, 40, 25, 480, 25, 460]
            start, end = (a - 200, a + 300) if P["testnet"] else (1, 600)
            bits = "1f07ffff" if P["testnet"] else "200f0f0f"
            chains = [("", chain_lines(a, start, end, bits, lambda h: PRE[h % 12] if h < a else POST[h % 12]))]
            if P["testnet"]:
                PRE2 = [60, 90, 75, 70, 80, 75, 65, 85, 75, 72, 78, 75]
                POST2 = [20, 30, 25, 23, 27, 25, 22, 28, 25, 24, 26, 25]
                def d2(h):
                    if h < a:
                        return 225 if a - 100 <= h < a - 60 else 25 if a - 60 <= h < a - 30 else PRE2[h % 12]
                    return 75 if a + 100 <= h < a + 150 else 8 if a + 150 <= h < a + 200 else POST2[h % 12]
                chains.append(("_d2", chain_lines(a, start, end, "1d00ffff", d2)))
            for suf, lines in chains:
                for o in oracle(["diffchain", net], lines):
                    h = o["h"]
                    if h + 150 < a or h <= start + 28:
                        continue
                    z = exp[("expected_bits" + suf, "")].get(h)
                    T.cmp(scen, "expected_bits" + suf, "", h, z, "0x" + o["expected"])
                    z = exp[("median_time_past" + suf, "")].get(h)
                    T.cmp(scen, "median_time_past" + suf, "", h, z, s(o.get("mtp")))
                    if P["testnet"] and not suf:
                        T.cmp(scen, "is_min_difficulty_block", "", h,
                              exp[("is_min_difficulty_block", "")].get(h), s(o.get("min_diff")))

    report = {"compared": dict(T.n), "disagreements": {k: len(v) for k, v in T.bad.items()},
              "examples": {k: v[:20] for k, v in T.bad.items()}}
    with open(os.path.join(VEC, "cross_report.json"), "w") as f:
        json.dump(report, f, indent=1, sort_keys=True)
    tot = sum(T.n.values()); bad = sum(len(v) for v in T.bad.values())
    for k in sorted(T.n):
        print(f"{k:55s} {T.n[k]:7d} {len(T.bad.get(k, [])):6d}")
        for e in T.bad.get(k, [])[:3]:
            print("    ", e)
    print(f"TOTAL compared {tot}, disagreements {bad}")


main()
