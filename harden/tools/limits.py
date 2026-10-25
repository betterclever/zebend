#!/usr/bin/env python3
"""Resource-limit cases: each adversarial input runs alone through ./fz, and we record the
verdict, wall time and peak RSS. limits.py [--old] prints a table; exits 1 on a wrong verdict
or a peak RSS over the bound."""
import os, struct, subprocess, sys, re, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BOUND_MB = 256


def cs(n):
    if n < 253: return bytes([n])
    if n < 0x10000: return b'\xfd' + struct.pack('<H', n)
    return b'\xfe' + struct.pack('<I', n)


def v5_head():
    return struct.pack('<IIIII', 5 | 1 << 31, 0x26A7270A, 0xC8E71055, 0, 0)


def frame_head(n):
    return bytes.fromhex('24e92764') + b'ping'.ljust(12, b'\0') + struct.pack('<I', n) + b'\0' * 4


def cases():
    hdr = open(f'{ROOT}/node/headers/data/mainnet.bin', 'rb').read()[:1487]
    yield 'tx', 'vin count 2^25 (cap), 40 bytes left', v5_head() + cs(0x02000000) + b'\0' * 40, '0'
    yield 'tx', 'vin count 2^25+1 (over cap)', v5_head() + cs(0x02000001), '0'
    yield 'tx', 'script length 2^25, 1 KB present', v5_head() + cs(1) + b'\0' * 36 + cs(0x02000000) + b'\0' * 1024, '0'
    yield 'tx', 'orchard actions 2^25', v5_head() + b'\0\0' + b'\0\0' + cs(0x02000000) + b'\0' * 4096, '0'
    yield 'tx', 'sapling outputs 2^24, 1 MB present', v5_head() + b'\0\0' + b'\0' + cs(0x01000000) + b'\0' * (1 << 20), '0'
    yield 'tx', 'joinsplits 60k (v2), 1.9 MB of zero data', struct.pack('<I', 2) + b'\0\0' + b'\0' * 4 + cs(60000) + b'\0' * 1_900_000, '0'
    yield 'block', 'tx count 2^25, header only', hdr + cs(0x02000000), '0'
    yield 'block', '2,000,001 bytes (over MAX_BLOCK_SIZE)', hdr + cs(1) + b'\0' * (2_000_001 - 1488), '0'
    yield 'block', 'count 199,000 of 10-byte Sprout txs (~2 MB)', hdr + cs(199000) + (struct.pack('<I', 1) + b'\0\0' + b'\0' * 4) * 199000, '1 199000'
    yield 'frame', 'declared length 2^32-1, header only', frame_head(0xffffffff), '0'
    yield 'frame', 'declared length 2 MiB + 1', frame_head(2 * 1024 * 1024 + 1), '0'
    yield 'frame', 'declared length 2 MiB, 1 KB present', frame_head(2 * 1024 * 1024) + b'\0' * 1024, '2'
    yield 'frame', 'length 0xFFFFFFF0 (24 + len wraps)', frame_head(0xFFFFFFF0) + b'\0' * 64, '0'
    wrap = bytearray(frame_head(0xFFFFFFE8)); wrap[20:24] = bytes.fromhex('5df6e0e2')
    yield 'frame', 'length 0xFFFFFFE8 + checksum of empty payload (24 + len = 0)', bytes(wrap), '0'
    yield 'cs', '255 + u64 max', b'\xff' * 9, '0'


def main():
    old = '--old' in sys.argv
    d = f'{ROOT}/harden/data/limits'
    os.makedirs(d, exist_ok=True)
    bad = 0
    print(f'| parser | adversarial input | bytes | verdict | expected | time | peak RSS |')
    print('|---|---|---:|---|---|---:|---:|')
    for i, (mode, desc, b, exp) in enumerate(cases()):
        if old and mode not in ('frame', 'cs'):
            continue
        m = mode + '_old' if old else mode
        path = f'{d}/{i}.bin'
        open(path, 'wb').write(struct.pack('<I', len(b)) + b)
        t = time.time()
        p = subprocess.run(['/usr/bin/time', '-l', f'{ROOT}/harden/fz', m, path, '1'], capture_output=True, timeout=300)
        dt = time.time() - t
        rss = int(re.search(rb'(\d+)\s+maximum resident', p.stderr).group(1)) / 2**20
        got = p.stdout.decode().strip() if p.returncode == 0 else f'crash rc={p.returncode}'
        ok = got == exp and rss < BOUND_MB
        bad += not ok
        print(f'| {m} | {desc} | {len(b):,} | {got} | {exp} | {dt:.2f}s | {rss:.0f} MiB{"" if ok else " **FAIL**"} |')
        os.remove(path)
    sys.exit(1 if bad and not old else 0)


if __name__ == '__main__':
    main()
