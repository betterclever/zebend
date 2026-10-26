#!/usr/bin/env python3
"""data/mixed.bin: data/real.bin with every 97th record (index % 97 == 50) replaced by its
tampered copy from data/tamper.bin; official verdicts taken from the matching official files.
Exercises batch failure + per-proof fallback."""
import os, struct
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
def recs(path):
    b = open(path, 'rb').read(); i = 0; out = []
    while i < len(b):
        kind = struct.unpack('<I', b[i:i + 4])[0]; n = 200 + 32 * (7 if kind == 0 else 5); out.append(b[i:i + n]); i += n
    return out
r, t = recs(f'{D}/real.bin'), recs(f'{D}/tamper.bin')
ro = [l for l in open(f'{D}/official_real.txt') if not l.startswith('#')]
to = [l for l in open(f'{D}/official_tamper.txt') if not l.startswith('#')]
pick = [i % 97 == 50 for i in range(len(r))]
open(f'{D}/mixed.bin', 'wb').write(b''.join(t[i] if p else r[i] for i, p in enumerate(pick)))
open(f'{D}/official_mixed.txt', 'w').write('# real.bin with every 97th record replaced by its tampered copy\n' + ''.join(to[i] if p else ro[i] for i, p in enumerate(pick)))
print(f'mixed: {len(r)} records, {sum(pick)} tampered')
