#!/usr/bin/env python3
"""Extend the verified header chain above node/headers' last height, to the live tip.

Same Bend programs as follow (read-only use of follow/bin): zebend-p2p (node/p2p: P2P
getheaders; SHA-256d hashes and prev links computed in Bend) and equihash7 (blake3x/eqv3 +
consensus/nu7/headers: Equihash, hash <= target, links, difficulty by height, with the 113
previous headers for the difficulty window: 17 + 11 before NU7, 102 + 11 from NU7, ZIP 218). Accepted headers are appended to state/hdr/extra.bin and their Bend-computed hashes
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
# follow's zebend-p2p uses PEERS[0] (p2pblocks.KNOWN_PEERS[0]) for its own header sync; Zebra
# accepts ONE connection per source IP, so tiphdr starting with the same peer collides with it
# (one of the two is reset). tiphdr starts elsewhere and falls back to the address book.
FOLLOW_HEADER_PEER = PEERS[0]
MAX_PEERS_TRIED = 8


def candidate_peers():
    book = []
    for p in (Path(os.environ.get("ZEBEND_STATE", HERE / "state")) / "peers.txt", HERE / "state/peers.txt"):
        try:
            book += [l.strip() for l in p.read_text().splitlines() if l.strip() and ":" not in l.strip()]  # IPv4 only:
        except OSError:                                                                                  # zebend-p2p
            pass
    seen, out = set(), []
    for ip in PEERS[1:] + book[:20] + [FOLLOW_HEADER_PEER]:
        if ip not in seen:
            seen.add(ip)
            out.append(ip)
    return out[:MAX_PEERS_TRIED]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--peer", default=None)
    a = ap.parse_args()
    idx = headers.Index(HDRDIR / "hashes.bin")
    top = idx.n - 1
    work = HERE / "work/tiphdr"
    r = None
    no_link = False
    for peer in ([a.peer] if a.peer else candidate_peers()):
        shutil.rmtree(work, ignore_errors=True)
        (work / "out").mkdir(parents=True)
        try:
            r = subprocess.run([str(FOLLOW_BIN / "zebend-p2p"), peer, "170190", str(top), idx.display(top), "13",
                                str(top), idx.display(top)], cwd=work, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            continue
        no_link |= "does not link" in (r.stdout + r.stderr)
        hp, bp = work / "out/heights.txt", work / "out/headers.bin"
        if not (hp.exists() and bp.exists() and bp.stat().st_size):
            continue
        pairs = re.findall(r"^(\d+) ([0-9a-f]{64})$", hp.read_text(), re.M)
        raw = bp.read_bytes()
        if len(raw) != len(pairs) * HDR or int(pairs[0][0]) != top + 1:
            print(f"peer {peer}: malformed header batch; trying another peer")
            continue
        if raw[4:36] != idx.internal(top):
            return drop_tip(top)
        rc = append(idx, top, pairs, raw, work)
        if rc == 0:
            return 0
        # Headers that fail Bend's checks (e.g. a peer on a pre-NU7 fork, whose difficulty the NU7
        # rules reject) are not ours: ask the next peer instead of retrying the same one forever.
        print(f"peer {peer}: headers rejected by Bend; trying another peer")
    if no_link:
        return drop_tip(top)  # peers do not know our tip: it lost a block race
    print("no headers from any peer")
    return 1


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
    ctx = 113  # PoWAveragingWindow (102 from NU7) + PoWMedianBlockSpan
    prev = b"".join(headers.header(h) for h in range(top - ctx + 1, top + 1))
    hfile = work / "chk.bin"
    hfile.write_bytes(prev + raw)
    n = ctx + len(pairs)
    out = subprocess.run([str(FOLLOW_BIN / "equihash7"), str(hfile), str(n), str(n), "4", str(top - ctx + 1), "main",
                          "+RTS", "--gpu", "off", "-RTS"], capture_output=True, text=True).stdout
    got = dict((k, (int(x), int(y))) for k, x, y in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M))
    want = {"equihash valid": (n, n), "hash <= target": (n, n), "prev-hash links": (n - 1, n - 1)}
    # The checker verifies difficulty for every header after its own context window, which
    # may be shorter than ctx (113 covers NU7's window; the pre-NU7 window is 28), so it can
    # check more than the new headers. All of its checks must pass, and they must cover at
    # least the new headers (they are the last ones in the file).
    dk, dn = got.pop("difficulty (nBits == expected)", (0, -1))
    if got != want or dk != dn or dn < len(pairs):
        got["difficulty (nBits == expected)"] = (dk, dn)
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
