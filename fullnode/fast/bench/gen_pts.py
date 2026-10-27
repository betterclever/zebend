"""Random + edge-case point encodings for t_pts rnd: records kind(1) | 32 bytes (LE)."""
import os, random, sys
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
R = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001  # Jubjub base (BLS r)
P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001  # Pallas base
out = bytearray()
def rec(k, v, sign):
    out.append(k)
    out.extend((v | (sign << 255)).to_bytes(32, "little"))
n = int(sys.argv[3]) if len(sys.argv) > 3 else 20000
for k, m in ((0, R), (1, R), (2, P), (3, P)):
    edge = [0, 1, 2, 3, 4, 5, m - 1, m - 2, m, m + 1, m + 5, 2**255 - 1, 2**254, m - 5, (m - 1) // 2, (m + 1) // 2]
    for v in edge:
        if v < 2**255:
            rec(k, v, 0); rec(k, v, 1)
    for _ in range(n):
        r = random.random()
        v = random.getrandbits(255) if r < 0.1 else random.randrange(m) if r < 0.97 else random.randrange(m, 2**255)
        rec(k, v, random.getrandbits(1))
open(sys.argv[1], "wb").write(out)
print(len(out) // 33, "records")
