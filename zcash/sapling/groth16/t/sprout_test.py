#!/usr/bin/env python3
"""Sprout JoinSplit public inputs computed by Bend (t/sprout_test, sprout_inputs.bend) vs
(1) the oracle's inputs (zcash_proofs' packing, written into data/<SET>.bin) and
(2) Python's hashlib BLAKE2b h_sig + packing.  python3 t/sprout_test.py [SET]  (default mig_real)"""
import hashlib, os, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); D = os.path.join(HERE, '..', 'data')
S = sys.argv[1] if len(sys.argv) > 1 else 'mig_real'
def recs(path, L):
    b = open(path, 'rb').read(); i = 0; out = []
    while i < len(b):
        k = struct.unpack('<I', b[i:i + 4])[0]; out.append((k, b[i:i + L[k]])); i += L[k]
    return out
raw = [r for k, r in recs(os.path.join(D, f'{S}_raw.bin'), {0: 328, 1: 296, 2: 504}) if k == 2]
ora = [r for k, r in recs(os.path.join(D, f'{S}.bin'), {0: 424, 1: 360, 2: 488}) if k == 2]
w = lambda v: ' '.join('%08x' % ((v >> (32 * j)) & 0xffffffff) for j in range(8))
py, orc = [], []
for r, o in zip(raw, ora):
    f = lambda j: r[200 + 32 * j:232 + 32 * j]
    hs = hashlib.blake2b(f(1) + f(2) + f(3) + f(8), digest_size=32, person=b'ZcashComputehSig').digest()
    msg = f(0) + hs + f(2) + f(4) + f(3) + f(5) + f(6) + f(7) + r[488:504]
    bits = [(x >> (7 - j)) & 1 for x in msg for j in range(8)]
    py.append(' '.join(w(sum(bt << k for k, bt in enumerate(bits[c:c + 254]))) for c in range(0, len(bits), 254)))
    orc.append(' '.join(w(int.from_bytes(o[200 + 32 * t:232 + 32 * t], 'little')) for t in range(9)))
out = subprocess.run([os.path.join(HERE, 'sprout_test'), os.path.join(D, f'{S}_raw.bin')], capture_output=True, text=True).stdout
got = [l[3:].strip() for l in out.split('\n') if l.startswith('in ')]
ok = sum(g == p == o for g, p, o in zip(got, py, orc))
print(f'sprout inputs ({S}): {len(raw)} JoinSplits; Bend == oracle == Python on {ok}/{len(raw)}' + ('' if len(got) == len(raw) else f' (Bend printed {len(got)})'))
sys.exit(0 if ok == len(raw) == len(got) else 1)
