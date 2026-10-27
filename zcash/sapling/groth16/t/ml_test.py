#!/usr/bin/env python3
"""Per-proof intermediates of the Bend verifier vs the bls12_381 crate (oracle `dump`):
acc = IC0 + sum input_i IC_i, the 3-term Miller loop output (bit-identical, not just equal
after the final exponentiation) and the final exponentiation, for the first N records of
each set. python3 t/ml_test.py N SET...   (default 12, mig_real: includes Sprout records)"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); D = os.path.join(HERE, '..', 'data')
N = int(sys.argv[1]) if len(sys.argv) > 1 else 12
sets = sys.argv[2:] or ['mig_real']
ORACLE = os.path.join(HERE, '..', 'oracle', 'target', 'release', 'groth16-oracle')
total = bad = 0
for s in sets:
    path = os.path.join(D, f'{s}.bin')
    got = subprocess.run([os.path.join(HERE, 'ml_test')] + [os.path.join(D, f'vk_{k}.bin') for k in ('spend', 'output', 'sprout')] + [path, str(N)],
                         capture_output=True, text=True).stdout.split('\n')
    kinds = []
    for i in range(N):
        d = {l.split()[0]: ' '.join(l.split()[1:]) for l in subprocess.run([ORACLE, 'dump', path, str(i)], capture_output=True, text=True).stdout.split('\n') if l.strip()}
        kinds.append(d['kind'].split()[0])
        for j, key in enumerate(('acc', 'ml', 'fe')):
            total += 1
            if got[3 * i + j] != f'{key} {d[key]}':
                bad += 1; print('MISMATCH', s, i, key)
    print(f'{s}: first {N} records (kinds {"".join(kinds)}): acc, 3-term Miller loop, final exp')
print(f'ml_test: {total - bad}/{total} values equal to the crate')
sys.exit(1 if bad else 0)
