#!/usr/bin/env python3
"""(secp2 copy of t/hook_test.py, running tv.new through hook_new.py) hook.py end to end: real records -> fullnode hook items (P.tx, P.ctx, P.json) -> hook.py.
Each real tx must PASS; a copy with one bit of r flipped in the first signature of the
first input must FAIL.  python3 t/hook_test.py FILE.ztv [N]"""
import json, os, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
raw = open(sys.argv[1], "rb").read()
n = min(struct.unpack_from("<I", raw, 4)[0], int(sys.argv[2]) if len(sys.argv) > 2 else 50)
d = os.path.join(HERE, "../../data/t/hook_new"); os.makedirs(d, exist_ok=True)
def csz(k): return bytes([k]) if k < 253 else b"\xfd" + struct.pack("<H", k)
def vin0(tx):
    hdr = struct.unpack_from("<I", tx, 0)[0]; v = hdr & 0x7fffffff
    return 20 if v >= 5 else (8 if hdr >> 31 else 4)
lst, want, i = [], {}, 8
for k in range(n):
    h, fl, tl = struct.unpack_from("<III", raw, i); tx = raw[i + 12:i + 12 + tl]; j = i + 12 + tl
    (np_,) = struct.unpack_from("<I", raw, j); j += 4
    am, sc = b"", b""
    for _ in range(np_):
        a = raw[j:j + 8]; (sl,) = struct.unpack_from("<I", raw, j + 8); s = raw[j + 12:j + 12 + sl]; j += 12 + sl
        am += a; sc += csz(sl) + s
    i = j
    ctx = struct.pack("<I", len(am)) + am + struct.pack("<I", len(sc)) + sc
    p = vin0(tx); p += 1 if tx[p] < 253 else 3; p += 36   # first input's script length
    p += 1 if tx[p] < 253 else 3                           # first input's scriptSig
    if tx[p] == 0: p += 1                                  # multisig dummy OP_0
    bad = bytearray(tx); bad[p + 6] ^= 1                    # a byte of r in the first signature
    for idx, t, w in ((2 * k, tx, "PASS"), (2 * k + 1, bytes(bad), "FAIL")):
        b = os.path.join(d, f"{h}_{idx}")
        open(b + ".tx", "wb").write(t); open(b + ".ctx", "wb").write(ctx)
        json.dump({"height": h, "txidx": idx}, open(b + ".json", "w"))
        lst.append(b); want[(h, idx)] = w
open(os.path.join(d, "list"), "w").write("\n".join(lst) + "\n")
out = subprocess.run([sys.executable, os.path.join(HERE, "hook_new.py"), os.path.join(d, "list")], capture_output=True, text=True).stdout
got = {(int(a), int(b)): c for _, a, b, c, *_ in (l.split() for l in out.splitlines())}
ok = sum(got.get(key) == w for key, w in want.items())
print(f"{len(want)} items ({n} real PASS-expected + {n} tampered FAIL-expected): {ok} as expected, {len(want) - ok} not")
for key, w in want.items():
    if got.get(key) != w: print("  unexpected", key, w, [l for l in out.splitlines() if l.split()[1:3] == [str(key[0]), str(key[1])]])
