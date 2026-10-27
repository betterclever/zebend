#!/usr/bin/env python3
"""NU7 rehearsal, part 2: tiphdr.py's / follow's header acceptance across the activation, on real
Testnet headers (Testnet NU7 4,465,026; halving 4,497,948).

tiphdr.append() runs `equihash7 <113 context headers + k new> n n 4 <first height> main` and
accepts iff equihash/target/links are all n/n (n-1 links) and the difficulty checks all pass and
cover >= k headers. Here the same call and the same acceptance test run with network `test` for
every activation-relative position of a batch (k = 1, 2, 3 new headers: what live.py's 60 s
loop sees at 25 s blocks; k = 160: a catch-up batch), so an off-by-one in the context size or
the window switch would show up as a rejected valid batch.
usage: nu7_headers.py"""
import re, subprocess, sys
from pathlib import Path

ROOT = Path("/Users/betterclever/projects/zecathon/zebend")
EQ = ROOT / "node/follow/bin/equihash7"
TN = ROOT / "zcash/consensus/nu7/data/testnet/headers.bin"
FIRST, HDR, CTX = 4460000, 1487, 113
WORK = Path(__file__).resolve().parent.parent / "work" / "nu7_headers"
WORK.mkdir(parents=True, exist_ok=True)
data = TN.read_bytes()


def hdr(h):
    return data[(h - FIRST) * HDR:(h - FIRST + 1) * HDR]


def accept(top, k, ctx=CTX, net="test"):
    """tiphdr.append's decision for new headers top+1..top+k with ctx context headers."""
    f = WORK / f"chk_{top}_{k}.bin"
    f.write_bytes(b"".join(hdr(h) for h in range(top - ctx + 1, top + k + 1)))
    n = ctx + k
    out = subprocess.run([str(EQ), str(f), str(n), str(n), "4", str(top - ctx + 1), net, "+RTS", "--gpu", "off", "-RTS"],
                         capture_output=True, text=True, timeout=600).stdout
    f.unlink()
    got = dict((m[0], (int(m[1]), int(m[2]))) for m in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M))
    want = {"equihash valid": (n, n), "hash <= target": (n, n), "prev-hash links": (n - 1, n - 1)}
    dk, dn = got.pop("difficulty (nBits == expected)", (0, -1))
    return got == want and dk == dn and dn >= k, (got, dk, dn)


A, H3 = 4465026, 4497948
cases = []
for base in (A, H3):
    for off in list(range(-3, 4)) + [50, 101, 102, 103, 104, 113, 114, 200]:
        for k in (1, 2, 3):
            cases.append((base + off - 1, k))  # top = last header we have; new ones start at base+off
    cases.append((base - 80, 160))
    cases.append((base - 1, 160))
bad = []
for top, k in cases:
    ok, det = accept(top, k)
    if not ok:
        bad.append((top + 1, k, det))
print(f"{len(cases)} batches across Testnet NU7 activation and halving: {len(cases) - len(bad)} accepted")
for b in bad:
    print("  REJECTED valid batch starting at", b)
# negative control: a tampered nBits in the first new header must be rejected
top = A
h1 = bytearray(hdr(top + 1))
h1[104] ^= 1
f = WORK / "neg.bin"
f.write_bytes(b"".join(hdr(h) for h in range(top - CTX + 1, top + 1)) + bytes(h1))
out = subprocess.run([str(EQ), str(f), str(CTX + 1), str(CTX + 1), "4", str(top - CTX + 1), "test", "+RTS", "--gpu", "off", "-RTS"],
                     capture_output=True, text=True, timeout=600).stdout
print("negative control (nBits tampered):", "rejected" if re.search(r"difficulty \(nBits == expected\) (\d+)/(\d+)", out)
      and len(set(re.search(r"difficulty \(nBits == expected\) (\d+)/(\d+)", out).groups())) == 2 or "equihash valid 113/114" in out
      else "NOT rejected: " + out[-300:])
# with too little context (follow's old 29 headers): what happens right after activation
ok, det = accept(A + 10, 1, ctx=29)
print("ctx=29 (follow's pre-wiring buffer) at A+11:", "accepted" if ok else f"rejected {det}")
print("RESULT", "PASS" if not bad else "FAIL")
