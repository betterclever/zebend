"""The verified header chain the full node syncs against (transport index + header bytes).

Header bytes come from zcash/headers: every mainnet header from height 1 to 3,528,279, fetched
from P2P peers and verified in Bend (Equihash, hash <= target, prev links; see
zcash/headers/history/verify_all.log). The Bend program `bin/hdrchain` re-hashes them (SHA-256d
in Bend), checks every link again and checks the hash at every Zebra checkpoint height
(checkpoints/main-checkpoints.txt); its output `state/hdr/hashes.bin` (32 bytes per height,
internal byte order) is the index this module serves.

Until hdrchain has run, `routing_index()` builds the same index with hashlib so downloads can
start; such hashes are only used to *ask* peers for blocks. Every block is accepted only if
Bend finds its header byte-identical to the verified header at that height.
"""
import hashlib, os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
HDR = 1487
GEN = ROOT / "zcash/headers/data/genesis"
PARTS = [(GEN / f"h_{s}.bin", s) for s in (1, 500001, 1000001, 1500001, 2000001, 2500001, 3000001)]
PARTS.append((ROOT / "zcash/headers/data/mainnet.bin", 3400000))
# Headers above 3,528,279 that tiphdr.py fetched and verified in Bend (zebend-p2p + equihash).
EXTRA = HERE / "state/hdr/extra.bin"
if EXTRA.exists():
    PARTS.append((EXTRA, 3528280))
GENESIS_HASH = "00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08"


def part_for(h):
    """(file, offset) of the verified header at height h >= 1."""
    best = None
    for p, s in PARTS:
        n = p.stat().st_size // HDR
        if s <= h < s + n:
            best = (p, (h - s) * HDR)  # later parts win (mainnet.bin overlaps nothing)
    return best


def header(h):
    p, off = part_for(h)
    with open(p, "rb") as f:
        f.seek(off)
        return f.read(HDR)


def last_height():
    return max(s + p.stat().st_size // HDR - 1 for p, s in PARTS)


def routing_index(out: Path):
    """hashes.bin: SHA-256d of each header (internal order), height 0 = genesis. Routing only."""
    if out.exists() and out.stat().st_size == (last_height() + 1) * 32:
        return
    tmp = out.with_suffix(".tmp")
    with open(tmp, "wb") as w:
        w.write(bytes.fromhex(GENESIS_HASH)[::-1])
        h = 1
        for p, s in PARTS:
            if s > h:
                raise RuntimeError(f"gap in header files at {h}")
            with open(p, "rb") as f:
                f.seek((h - s) * HDR)
                while True:
                    buf = f.read(HDR * 20000)
                    if not buf:
                        break
                    for i in range(0, len(buf), HDR):
                        w.write(hashlib.sha256(hashlib.sha256(buf[i:i + HDR]).digest()).digest())
                    h += len(buf) // HDR
    os.replace(tmp, out)


class Index:
    def __init__(self, path: Path):
        self.f = open(path, "rb")
        self.n = path.stat().st_size // 32
        self.extra = {}  # heights above the file (headers fetched later, from Bend P2P)

    def internal(self, h):
        if h < 0:
            return bytes(32)  # genesis's hashPrevBlock
        if h in self.extra:
            return self.extra[h]
        return os.pread(self.f.fileno(), 32, h * 32)  # thread-safe (fetcher workers share it)

    def display(self, h):
        return self.internal(h)[::-1].hex()
