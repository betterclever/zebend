#!/usr/bin/env python3
"""Lab tool: tampered copies of a real block, to check that base and fasttip reject them the
same way (same error, same stage). Only bytes outside the txid (ZIP 244 authorizing data of a v5
tx) are changed, so the merkle root still matches and the block reaches the rules and hooks.

  tamper.py <blocks dir> <height> <tx index> <out dir> --what sig|proof|both
    sig:   one byte in the middle of the first transparent input's scriptSig (an ECDSA signature)
    proof: one byte in the middle of the tx's Orchard/Ironwood Halo 2 proof (located by the
           proof bytes the orchard hook wrote: <bundle file>)
<out dir>/<h>.bin is the tampered block; every other height is a symlink to the original.
"""
import argparse, struct
from pathlib import Path


def cs(b, i):
    x = b[i]
    if x < 0xfd:
        return x, i + 1
    if x == 0xfd:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    if x == 0xfe:
        return struct.unpack_from("<I", b, i + 1)[0], i + 5
    return struct.unpack_from("<Q", b, i + 1)[0], i + 9


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("blocks")
    ap.add_argument("height", type=int)
    ap.add_argument("tx", help="path of the tx bytes (.tx written by a hook run) of the tx to tamper")
    ap.add_argument("out")
    ap.add_argument("--what", choices=["sig", "proof", "both"], required=True)
    ap.add_argument("--bundle", default=None)
    a = ap.parse_args()
    src, out = Path(a.blocks), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for p in src.glob("*.bin"):
        q = out / p.name
        if not q.exists():
            q.symlink_to(p.resolve())
    blk = bytearray((src / f"{a.height}.bin").read_bytes())
    tx = Path(a.tx).read_bytes()
    off = bytes(blk).find(tx)
    assert off > 0 and bytes(blk).find(tx, off + 1) < 0, "tx not found once in the block"
    assert struct.unpack_from("<I", tx, 0)[0] & 0x7fffffff in (5, 6), "v5/v6 only (auth data outside the txid)"
    done = []
    if a.what in ("sig", "both"):
        n, i = cs(tx, 20)
        assert n >= 1
        i += 36
        sl, j = cs(tx, i)
        k = off + j + sl // 2
        blk[k] ^= 0x01
        done.append(f"scriptSig byte {j + sl // 2} of {sl}")
    if a.what in ("proof", "both"):
        b = Path(a.bundle).read_bytes()
        plen = struct.unpack_from("<I", b, 8)[0]
        proof = b[12:12 + plen]
        p = bytes(blk).find(proof, off)
        assert p > 0
        blk[p + plen // 2] ^= 0x01
        done.append(f"proof byte {p - off + plen // 2} (proof {plen} bytes)")
    q = out / f"{a.height}.bin"
    if q.is_symlink():
        q.unlink()
    q.write_bytes(bytes(blk))
    print(f"tampered block {a.height} tx at block offset {off}: {', '.join(done)}")


if __name__ == "__main__":
    main()
