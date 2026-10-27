#!/usr/bin/env python3
"""Malformed Halo 2 bundle inputs (data/bprobe/*.bin) derived from halo2's h0 bundle. Only
ok.bin is well formed; bundle_main_h must print `result 0` for every other one quickly."""
import os, struct

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(f'{HERE}/../../zcash/halo2/verifier/data/bundles/h0.bin', 'rb').read()
np_, ni, pl = struct.unpack('<3I', src[:12])
body = src[12:]
out = f'{HERE}/data/bprobe'
os.makedirs(out, exist_ok=True)
cases = {
    'ok': src,
    'np_huge': struct.pack('<3I', 0xffffffff, ni, pl) + body,   # old: never finished
    'np_1000': struct.pack('<3I', 1000, ni, pl) + body,
    'ni_huge': struct.pack('<3I', np_, 0xffffffff, pl) + body,   # old: ~8 GB, then crashed
    'ni_0': struct.pack('<3I', np_, 0, pl) + body,
    'plen_huge': struct.pack('<3I', np_, ni, 0xffffffe0) + body,
    'trailing': src + b'\0' * 64,                                # old: accepted
    'empty': b'',
    'short': src[:7],
    'ival_noncanon': src[:-32] + b'\xff' * 32,
}
for k, v in cases.items():
    open(f'{out}/{k}.bin', 'wb').write(v)
print(f'{len(cases)} probes in {out}')
