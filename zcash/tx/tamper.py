#!/usr/bin/env python3
"""Negative tests: tamper real mainnet transactions and check the Bend binary rejects
them for the right reason. Usage: tamper.py [binary] [dir]

Each case states what must change: the txid (effecting data), the sighash, and which
signatures must fail. A case passes only if Bend reports exactly that."""
import pathlib, subprocess, sys

binary = sys.argv[1] if len(sys.argv) > 1 else "./tx_main"
d = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "mainnet")
work = pathlib.Path("tampered")
work.mkdir(exist_ok=True)


def cs(b, p):
    k = b[p]
    if k < 253:
        return k, 1
    n = {253: 2, 254: 4, 255: 8}[k]
    return int.from_bytes(b[p + 1:p + 1 + n], "little"), 1 + n


def layout(b):
    """Offsets of the Orchard-protocol bundles (independent re-implementation, for tampering)."""
    v6 = (int.from_bytes(b[0:4], "little") & 0x7FFFFFFF) == 6
    p = 20
    n, s = cs(b, p); p += s
    for _ in range(n):
        p += 36; l, s = cs(b, p); p += s + l + 4
    n, s = cs(b, p); p += s
    for _ in range(n):
        p += 8; l, s = cs(b, p); p += s + l
    ns, s = cs(b, p); p += s + 96 * ns
    no, s = cs(b, p); p += s + 756 * no
    if ns + no:
        p += 8 + (32 if ns else 0) + 256 * ns + 192 * no + 64
    bundles = []
    for pool in (["orchard", "ironwood"] if v6 else ["orchard"]):
        n, s = cs(b, p); acts = p + s; tail = acts + 820 * n
        if n:
            pl, s2 = cs(b, tail + 41)
            sigs = tail + 41 + s2 + pl
            end = sigs + 64 * n + 64
        else:
            sigs = end = tail
        bundles.append(dict(pool=pool, n=n, acts=acts, tail=tail, sigs=sigs, end=end))
        p = end
    return [x for x in bundles if x["n"]]


def run(raw, ctx, tag):
    t, c = work / f"{tag}.bin", work / f"{tag}.ctx"
    t.write_bytes(raw); c.write_bytes(ctx)
    out = subprocess.run([binary, str(t), str(c)], capture_output=True, text=True, timeout=600).stdout
    return dict(l.split(" ", 1) for l in out.splitlines() if " " in l)


def oks(r, pool):
    return {k: v for k, v in r.items() if k.startswith(pool) and k.endswith("_ok")}


results = []


def case(name, base, mutate, expect_txid_change, expect_sighash_change, expect_fail, expect_ok):
    raw = bytearray((d / f"{base}.bin").read_bytes())
    ctx = (d / f"{base}.ctx").read_bytes()
    want = dict(l.split(" ", 1) for l in (d / f"{base}.txt").read_text().splitlines())
    b = layout(bytes(raw))[0]
    mutate(raw, b)
    r = run(bytes(raw), ctx, f"{base}_{name}")
    pool = b["pool"]
    o = oks(r, pool)
    failed = sorted(k for k, v in o.items() if v == "0")
    passed = sorted(k for k, v in o.items() if v == "1")
    ok = (r.get("txid") != want["txid"]) == expect_txid_change \
        and (r.get("sighash") != want["sighash"]) == expect_sighash_change \
        and set(failed) == {f"{pool}.{x}" for x in expect_fail(b)} \
        and set(passed) == {f"{pool}.{x}" for x in expect_ok(b)}
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {base} {name}: txid {'changed' if r.get('txid') != want['txid'] else 'same'}, "
          f"sighash {'changed' if r.get('sighash') != want['sighash'] else 'same'}, rejected {len(failed)}/{len(o)} signature checks"
          + ("" if ok else f"\n      failed={failed}\n      passed={passed}"))


def all_sigs(b):
    return [f"a{j}.spend_auth_ok" for j in range(b["n"])] + ["binding_ok"]


def flip(off):
    def m(raw, b):
        raw[off(b)] ^= 0x01
    return m


for base in ("tx_0", "tx_20", "tx_16"):
    # Effecting data (an encrypted memo byte): new txid and sighash, so every signature fails.
    case("memo-byte", base, flip(lambda b: b["acts"] + 160 + 300), True, True, all_sigs, lambda b: [])
    # A spend-auth signature's S: not effecting data, so txid and sighash stay; only that signature fails.
    case("spend-auth-sig", base, flip(lambda b: b["sigs"] + 64 * (b["n"] - 1) + 40), False, False,
         lambda b: [f"a{b['n'] - 1}.spend_auth_ok"],
         lambda b: [f"a{j}.spend_auth_ok" for j in range(b["n"] - 1)] + ["binding_ok"])
    # The binding signature: only it fails.
    case("binding-sig", base, flip(lambda b: b["end"] - 10), False, False,
         lambda b: ["binding_ok"], lambda b: [f"a{j}.spend_auth_ok" for j in range(b["n"])])

    # valueBalance + 1 zatoshi (value created from nothing): txid/sighash change, bvk changes.
    def vb_plus_one(raw, b):
        v = int.from_bytes(raw[b["tail"] + 1:b["tail"] + 9], "little", signed=True) + 1
        raw[b["tail"] + 1:b["tail"] + 9] = v.to_bytes(8, "little", signed=True)
    case("value-balance+1", base, vb_plus_one, True, True, all_sigs, lambda b: [])

print(f"{sum(results)}/{len(results)} tamper cases rejected exactly as expected")
sys.exit(0 if all(results) else 1)
