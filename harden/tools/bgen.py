#!/usr/bin/env python3
"""Bundle-input fuzz corpus for lib/bundle.bend: bgen.py N SEED OUT.
Mutates the real bundles in halo2/verifier/data/bundles*; the verdict is the reference
spec written out in Python (this format is Zebend's own, so there is no Rust parser)."""
import glob, os, random, struct, sys

P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
HERE = os.path.dirname(os.path.abspath(__file__))


def verdict(b):
    if len(b) < 12:
        return '0'
    np_, ni, pl = struct.unpack_from('<3I', b)
    if not (1 <= np_ <= 2439 and ni == 10 and pl == 2720 + 2272 * np_ and len(b) == 12 + pl + 320 * np_):
        return '0'
    off = 12 + pl
    for k in range(10 * np_):
        if int.from_bytes(b[off + 32 * k: off + 32 * k + 32], 'little') >= P:
            return '0'
    return f'1 {np_}'


def mutate(r, s, seeds):
    b = bytearray(s)
    k = r.randrange(12)
    if k == 0:
        return 'keep', bytes(b)
    if k == 1:
        i = r.randrange(3)
        v = r.choice([0, 1, 2, 9, 10, 11, 2439, 2440, 0xffffffff, 0x80000000, r.getrandbits(32),
                      struct.unpack_from('<I', b, 4 * i)[0] + r.choice([-1, 1])]) & 0xffffffff
        struct.pack_into('<I', b, 4 * i, v)
        return f'header{i}', bytes(b)
    if k == 2:
        return 'truncate', bytes(b[:r.randrange(len(b))])
    if k == 3:
        return 'append', bytes(b) + r.randbytes(r.choice([1, 31, 32, 320]))
    if k == 4:
        i = r.randrange(len(b)); b[i] ^= 1 << r.randrange(8)
        return 'bitflip', bytes(b)
    if k == 5:
        np_, _, pl = struct.unpack_from('<3I', b)
        j = r.randrange(max(1, 10 * np_)); off = 12 + pl + 32 * j
        v = r.choice([P, P + 1, 2**256 - 1, P - 1, 0, r.getrandbits(256)])
        b[off:off + 32] = v.to_bytes(32, 'little')
        return 'ival', bytes(b[:len(s)])
    if k == 6:
        # consistent reshape: np changed with plen and length following it
        np_ = r.choice([0, 1, 2, 3, 2439, 2440])
        if np_ > 4:
            b2 = struct.pack('<3I', np_, 10, (2720 + 2272 * np_) & 0xffffffff) + bytes(b[12:])
            return 'reshape_big', b2
        body = r.randbytes(2720 + 2272 * np_) + b''.join(
            r.randrange(P).to_bytes(32, 'little') for _ in range(10 * np_))
        return 'reshape', struct.pack('<3I', np_, 10, 2720 + 2272 * np_) + body
    if k == 7:
        return 'random', r.randbytes(r.randrange(64))
    if k == 8:
        return 'splice', bytes(b[:r.randrange(len(b))]) + r.choice(seeds)[r.randrange(12, 200):]
    if k == 9:
        i = r.randrange(len(b)); del b[i]
        return 'delete_byte', bytes(b)
    if k == 10:
        i = r.randrange(len(b) + 1); b[i:i] = bytes([r.randrange(256)])
        return 'insert_byte', bytes(b)
    return 'concat', bytes(b) + r.choice(seeds)


def main():
    n, seed, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    files = sorted(f for f in glob.glob(f'{HERE}/../../halo2/verifier/data/bundles*/*.bin') if 'params' not in f)
    seeds = [open(f, 'rb').read() for f in files]
    r = random.Random(seed)
    with open(out + '.cases', 'wb') as c, open(out + '.expect', 'w') as e, open(out + '.kinds', 'w') as kf:
        acc = 0
        for _ in range(n):
            kind, b = mutate(r, r.choice(seeds), seeds)
            v = verdict(b)
            acc += v != '0'
            c.write(struct.pack('<I', len(b)) + b); e.write(v + '\n'); kf.write(kind + '\n')
    print(f'{out}: {n} cases ({acc} accepted by the spec) from {len(seeds)} seed bundles')


if __name__ == '__main__':
    main()
