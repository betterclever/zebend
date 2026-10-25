#!/usr/bin/env python3
"""Extend the verified header chain above node/headers' last height, to the live tip.

Same Bend programs as follow (read-only use of follow/bin): zebend-p2p (node/p2p: P2P
getheaders; SHA-256d hashes and prev links computed in Bend) and equihash (blake3x/eqv3:
Equihash, hash <= target, links, difficulty, with the 28 previous headers for the difficulty
window). Accepted headers are appended to state/hdr/extra.bin and their Bend-computed hashes
to state/hdr/hashes.bin (the index sync/download use). Run repeatedly; each run appends what
peers have.

usage: tiphdr.py [--peer IP]
"""
import argparse, os, re, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers

FOLLOW_BIN = HERE.parent / "follow/bin"
HDRDIR = HERE / "state/hdr"
EXTRA = HDRDIR / "extra.bin"
HDR = 1487
PEERS = ["136.115.98.175", "34.80.219.125", "54.39.196.12", "38.190.136.76"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--peer", default=None)
    a = ap.parse_args()
    idx = headers.Index(HDRDIR / "hashes.bin")
    top = idx.n - 1
    work = HERE / "work/tiphdr"
    r = None
    for peer in ([a.peer] if a.peer else PEERS):
        shutil.rmtree(work, ignore_errors=True)
        (work / "out").mkdir(parents=True)
        try:
            r = subprocess.run([str(FOLLOW_BIN / "zebend-p2p"), peer, "170190", str(top), idx.display(top), "13",
                                str(top), idx.display(top)], cwd=work, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            continue
        hp, bp = work / "out/heights.txt", work / "out/headers.bin"
        if hp.exists() and bp.exists() and bp.stat().st_size:
            break
    else:
        if r is not None and "does not link" in (r.stdout + r.stderr):
            return drop_tip(top)  # peers do not know our tip: it lost a block race
        print("no headers from any peer")
        return 1
    pairs = re.findall(r"^(\d+) ([0-9a-f]{64})$", hp.read_text(), re.M)
    raw = bp.read_bytes()
    assert len(raw) == len(pairs) * HDR and int(pairs[0][0]) == top + 1
    if raw[4:36] != idx.internal(top):
        return drop_tip(top)
    return append(idx, top, pairs, raw, work)


def drop_tip(top):
    if True:
        # Reorg at the tip: drop our last 10 verified headers above node/headers' range and let
        # the next run fetch the peers' chain from there; sync.py rolls the state back to the
        # last block whose hash is still on the index (Store.rollback_to, undo data).
        keep = max(3528279, top - 10)
        n_drop = top - keep
        if n_drop <= 0:
            print("reorg below the extra headers: not handled")
            return 2
        with open(EXTRA, "r+b") as f:
            f.truncate(EXTRA.stat().st_size - n_drop * HDR)
        with open(HDRDIR / "hashes.bin", "r+b") as f:
            f.truncate((keep + 1) * 32)
        print(f"reorg at the tip: dropped headers {keep + 1}..{top}; refetching")
        return 3


def append(idx, top, pairs, raw, work):
    prev28 = b"".join(headers.header(h) for h in range(top - 27, top + 1))
    hfile = work / "chk.bin"
    hfile.write_bytes(prev28 + raw)
    n = 28 + len(pairs)
    out = subprocess.run([str(FOLLOW_BIN / "equihash"), str(hfile), str(n), str(n), "4", "+RTS", "--gpu", "off", "-RTS"],
                         capture_output=True, text=True).stdout
    got = dict((k, (int(x), int(y))) for k, x, y in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M))
    want = {"equihash valid": (n, n), "hash <= target": (n, n), "prev-hash links": (n - 1, n - 1),
            "difficulty (nBits == expected)": (len(pairs), len(pairs))}
    if got != want:
        print(f"Bend header checks failed: {got}")
        return 1
    with open(EXTRA, "ab") as f:
        f.write(raw)
    with open(HDRDIR / "hashes.bin", "ab") as f:
        f.write(b"".join(bytes.fromhex(x)[::-1] for _, x in pairs))
    print(f"appended {len(pairs)} headers {pairs[0][0]}..{pairs[-1][0]} (Equihash, target, links, difficulty: Bend PASS)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
