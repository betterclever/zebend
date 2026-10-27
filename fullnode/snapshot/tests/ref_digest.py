"""A hashlib reference of the snapshot digest, for TESTS ONLY (cross-checks bin/snapdigest).
The node never uses it: the digest it pins and compares is the one Bend prints."""
import hashlib, struct


def merkle(hs):
    if not hs:
        return hashlib.sha256(b"").digest()
    while len(hs) > 1:
        nxt = [hashlib.sha256(b"\x01" + hs[i] + hs[i + 1]).digest() for i in range(0, len(hs) - 1, 2)]
        if len(hs) % 2:
            nxt.append(hs[-1])
        hs = nxt
    return hs[0]


def section_root(payloads):
    return merkle([hashlib.sha256(b"\x00" + p).digest() for p in payloads])
