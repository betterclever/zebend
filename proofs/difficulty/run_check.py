# Driver: extracts (height, time, nBits) from fetched raw headers (byte slicing only)
# and runs the Bend era-aware difficulty check in chunks overlapping by 28 records.
import os, re, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
G = os.path.join(HERE, "../../node/headers/data/genesis")
L = 1487
lo_h, hi_h = int(sys.argv[1]), int(sys.argv[2])     # check heights [lo_h, hi_h)
files = [(s, f"h_{s}.bin") for s in (1, 500001, 1000001, 1500001, 2000001, 2500001, 3000001)]
files.append((3400000, "../mainnet.bin"))
def header(h):
    for start, name in reversed(files):
        if h >= start:
            with open(os.path.join(G, name), "rb") as f:
                f.seek((h - start) * L)
                return f.read(L)
tot = [0, 0, 0, 0]; bad = []
chunk = 100_000
h = lo_h
while h < hi_h:
    first = max(1, h - 28)                    # 28 records of context before the checked range
    last = min(hi_h, h + chunk)
    buf = bytearray()
    for k in range(first, last):
        hd = header(k)
        buf += struct.pack("<I", k) + hd[100:108]
    tmp = os.path.join(HERE, "records.bin")
    open(tmp, "wb").write(buf)
    out = subprocess.run([os.path.join(HERE, "check_era"), tmp], capture_output=True, text=True).stdout
    nums = [tuple(map(int, m)) for m in re.findall(r"(\d+)/(\d+)", out)]
    (po, pn), (qo, qn) = nums
    tot = [tot[0] + po, tot[1] + pn, tot[2] + qo, tot[3] + qn]
    mm = re.search(r"mismatches \(newest first\): (.*)", out).group(1).split()
    bad += mm
    print(f"heights {first}..{last - 1}: pre {po}/{pn}  post {qo}/{qn}  mismatches {mm[:4]}", flush=True)
    h = last
os.remove(os.path.join(HERE, "records.bin"))
print(f"TOTAL pre-Blossom {tot[0]}/{tot[1]}  post-Blossom {tot[2]}/{tot[3]}  mismatching heights (sample) {bad[:16]}")
