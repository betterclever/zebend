# Verify every fetched mainnet header (heights 1..3,528,279) with the Bend Equihash verifier,
# in 100k-header slices that overlap by one header so cross-slice links are checked in Bend.
import os, re, subprocess, sys, time
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../data/genesis")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
BIN = os.path.join(ROOT, "research", "blake3x", "eqv3", "verify")
L = 1487
parts = [os.path.join(HERE, f"h_{s}.bin") for s in (1, 500001, 1000001, 1500001, 2000001, 2500001, 3000001)]
parts.append(os.path.join(ROOT, "zcash", "headers", "data", "mainnet.bin"))  # heights 3,400,000..3,528,279

def headers():
    for p in parts:
        with open(p, "rb") as f:
            while (b := f.read(L * 10000)):
                yield b

buf = b"".join(headers())
n = len(buf) // L
print(f"{n} headers (heights 1..{n})", flush=True)
tot = {"equihash": [0, 0], "target": [0, 0], "links": [0, 0]}
t0 = time.time()
tmp = os.path.join(HERE, "slice.bin")

def batch_for(count):
    # The verifier only processes whole batches, so the batch size must divide count exactly.
    for b in range(4000, 1, -1):
        if count % b == 0 and count // b <= 64:
            return b
    return count

checked_from = 0                       # height index (0-based) up to which headers are counted
lo = 0
while checked_from < n:
    hi = min(n, lo + 100_000)
    cnt = hi - lo
    b = batch_for(cnt)
    with open(tmp, "wb") as f:
        f.write(buf[lo * L:hi * L])
    out = subprocess.run([BIN, tmp, str(cnt), str(b), "12", "+RTS", "--gpu", "off", "-RTS"], capture_output=True, text=True).stdout
    get = lambda k: re.search(rf"{k} (\d+)/(\d+)", out)
    ok_e, all_e = map(int, get("equihash valid").groups())
    ok_t, all_t = map(int, get(r"hash <= target").groups())
    ok_l, all_l = map(int, get("prev-hash links").groups())
    assert all_e == cnt, f"verifier processed {all_e} of {cnt} headers"
    overlap = 1 if lo < checked_from else 0   # first header already counted in the previous slice
    tot["equihash"][0] += ok_e - (overlap if ok_e == all_e else 0); tot["equihash"][1] += all_e - overlap
    tot["target"][0] += ok_t - (overlap if ok_t == all_t else 0); tot["target"][1] += all_t - overlap
    tot["links"][0] += ok_l; tot["links"][1] += all_l
    print(f"heights {lo + 1:>9}..{hi:<9} batch {b:>5}  equihash {ok_e}/{all_e}  links {ok_l}/{all_l}  {time.time() - t0:6.0f}s", flush=True)
    checked_from = hi
    lo = hi - 1 if hi < n else hi
os.remove(tmp)
print(f"TOTAL equihash {tot['equihash'][0]}/{tot['equihash'][1]}  hash<=target {tot['target'][0]}/{tot['target'][1]}  links {tot['links'][0]}/{tot['links'][1]}  in {time.time() - t0:.0f}s")
