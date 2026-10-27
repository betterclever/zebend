#!/usr/bin/env python3
"""Run the Bend block checker on every fetched block and diff it with the Rust oracle.

Also runs tamper tests: a byte flipped in a transaction's effecting data (changes the
txid, so hashMerkleRoot breaks) and in its authorizing data (a signature: the txid is
unchanged, so only hashBlockCommitments breaks, which is ZIP 244's split at work).
"""
import pathlib, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
data = here / "data"
headers = here.parent / "headers" / "data" / "mainnet.bin"
H0 = 3400000

def run(blk, hist, h):
    out = subprocess.run([str(here / "block_main"), str(blk), str(hist), str(h), str(headers), str(H0)],
                         capture_output=True, text=True, check=True).stdout
    return [l for l in out.splitlines() if l.strip()]

ok = 0
heights = sorted(int(p.stem) for p in data.glob("*.expected"))
txs = 0
for h in heights:
    got = run(data / f"{h}.bin", data / f"{h}.hist", h)
    want = (data / f"{h}.expected").read_text().splitlines()
    body, extra = got[:-1], got[-1]
    same = body == want
    txs += sum(1 for l in want if l.startswith("tx "))
    m = [l for l in got if l.startswith("merkle")][0].split()[-1]
    c = [l for l in got if l.startswith("commitments")][0].split()[-1]
    print(f"{h}: {len(want) - 4:>2} txs  bend==oracle {same}  merkle {m}  commitments {c}  {extra}")
    ok += same and m == "MATCH" and c == "MATCH" and extra == "verified_header MATCH"
print(f"{ok}/{len(heights)} blocks: every line identical to the oracle, roots MATCH, header = verified header ({txs} txs)")

# Tamper tests on the last v6 block: flip one byte in effecting data, then in a signature.
h = 3528204
raw = bytearray((data / f"{h}.bin").read_bytes())
oracle = (data / f"{h}.expected").read_text().splitlines()
# the 53,350-byte v6 transaction with 16 Orchard actions; its offset from the oracle's byte lengths
lens = [int(l.split()[4]) for l in oracle if l.startswith("tx ")]
k = lens.index(53350)
start1 = 1487 + 1 + sum(lens[:k])
# tx k is a v6 tx with no transparent or Sapling parts and 16 Orchard actions, so its layout is:
# header 20 | vin 0 | vout 0 | sapling spends 0 | outputs 0 | nActions (1 byte) | actions (820 each) |
# flags 1 | valueBalance 8 | anchor 32 | proof (CompactSize + bytes) | 16 spend-auth sigs | binding sig 64 |
# Ironwood nActions = 0 (1 byte).
assert raw[start1 + 24] == 16 and raw[start1 + lens[k] - 1] == 0, "unexpected tx layout"
proof_len = int.from_bytes(raw[start1 + 25 + 16 * 820 + 41 + 1:start1 + 25 + 16 * 820 + 41 + 3], "little")
assert raw[start1 + 25 + 16 * 820 + 41] == 0xfd
cases = [
    (f"tx {k}, a memo ciphertext byte (effecting data: changes the txid)", start1 + 25 + 212 + 5),
    (f"tx {k}, a Halo 2 proof byte (authorizing data: txid unchanged)", start1 + 25 + 16 * 820 + 44 + proof_len // 2),
    (f"tx {k}, the binding signature's last byte (authorizing data)", start1 + lens[k] - 2),
]
for name, off in cases:
    t = bytearray(raw)
    t[off] ^= 1
    p = here / "t" / "tampered.bin"
    p.write_bytes(t)
    got = run(p, data / f"{h}.hist", h)
    m = [l for l in got if l.startswith("merkle")][0].split()[-1]
    c = [l for l in got if l.startswith("commitments")][0].split()[-1]
    print(f"tamper {name}: merkle {m}, commitments {c}")
sys.exit(0 if ok == len(heights) else 1)
