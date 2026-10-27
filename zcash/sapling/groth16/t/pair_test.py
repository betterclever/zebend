#!/usr/bin/env python3
"""Group / pairing layer of the Bend code (t/pair_test) against the bls12_381 crate:
the oracle's `vectors N SEED` output (random points k*G, their compressed encodings,
[s]P, Miller loop and pairing values) is converted to Bend input, and every printed
value must equal the crate's."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, '..', 'data')
N, SEED = (sys.argv[1] if len(sys.argv) > 1 else '16'), (sys.argv[2] if len(sys.argv) > 2 else '11')
ORACLE = os.path.join(HERE, '..', 'oracle', 'target', 'release', 'groth16-oracle')
lines = subprocess.run([ORACLE, 'vectors', N, SEED], capture_output=True, text=True, check=True).stdout.split('\n')
recs, want = [], []
le = lambda h: int(h, 16).to_bytes(48, 'little')
for i in range(0, len(lines) - 1, 5):
    g1, g2, sm, pr, ml = [l.split() for l in lines[i:i + 5]]
    b = le(g1[1]) + le(g1[2]) + b''.join(le(h) for h in g2[1:5]) + bytes.fromhex(g1[3]) + bytes.fromhex(g2[5]) + bytes.fromhex(sm[1])[::-1]
    assert len(b) == 116 * 4
    recs.append(b)
    want += ['g1 ' + ' '.join(g1[1:3]), 'g2 ' + ' '.join(g2[1:5]), 'smul ' + ' '.join(sm[2:4]), 'ml ' + ' '.join(ml[1:]), 'pair ' + ' '.join(pr[1:])]
path = os.path.join(D, 'pair_in.bin')
open(path, 'wb').write(b''.join(recs))
got = subprocess.run([os.path.join(HERE, 'pair_test'), path], capture_output=True, text=True).stdout.split('\n')
bad = sum(1 for g, w in zip(got, want) if g != w) + abs(len(want) - len([g for g in got if g]))
for g, w in zip(got, want):
    if g != w:
        print('MISMATCH\n got ', g[:150], '\n want', w[:150]); break
print(f'pairing layer: {len(recs)} vectors x 5 values (G1 decode, G2 decode, [s]P, Miller loop, pairing) vs bls12_381: {len(want) - bad}/{len(want)} equal')
sys.exit(1 if bad else 0)
