"""fasttip reorg: fork choice on the push path (used by tipfeed.py).

A competing chain is announced as a block (inv / follow tap) or headers (unsolicited, or a reply
to our getheaders) whose hashPrevBlock is not our verified tip. tipfeed collects such headers in
a side store, walks them back to a block of our verified chain (the fork point F) and then:

  1. refuses, loudly, a fork deeper than the undo depth (store.UNDO_DEPTH = 600, ZIP 218) or below
     the fixed header files (heights < 3,528,280): `REORG REFUSED` in the log, nothing changes;
  2. checks the competing headers in Bend exactly as tiphdr.py / tipfeed check headers extending
     our tip (`bend_check`: follow's equihash7 = Equihash, hash <= target, prev links, difficulty
     by height with the 113 headers below F; node/hdr/hdrchain = SHA-256d of each header in Bend
     and its link to our hash at F). The acceptance rule is tiphdr.append's, verbatim;
  3. compares chain work above F: sum over headers of 2^256 / (target + 1), target from nBits.
     The competing nBits are the ones Bend just verified (== expected difficulty, hash <= target);
     ours are the verified headers in state/hdr/extra.bin. Strictly more work is required:
     a competing chain with less OR EQUAL work is ignored (first seen wins on a tie, as zcashd and
     Zebra do);
  4. switches the header index (`switch_index`) to F + the competing headers. sync.py's existing
     reorg path then sees its tip off the index and rolls the state back with store.rollback_to
     (undo data; history.window_start_below), unchanged and tested by node/test_reorg.py, and
     takes the competing blocks from tipfeed's buffer like any pushed block.

Crash safety of the index switch (SIGKILL at any point): hashes.bin and extra.bin are each
replaced atomically (APFS clone of the file, truncate/append, fsync, rename), in the order
  (1) hashes.bin := hashes[0..F]          (2) extra.bin := headers[..F] + competing
  (3) hashes.bin := hashes[0..F] + Bend hashes of the competing headers.
Every intermediate state is "hashes.bin is a prefix of the headers in extra.bin", which
`reconcile` (run when tipfeed starts) turns into a consistent index by cutting extra.bin back to
hashes.bin. sync.py then rolls the state back to the last block still on the index (at worst F)
and the competing chain is fetched again. Readers that opened hashes.bin before a switch keep a
consistent (old) view: rename gives the new file a new inode.
"""
import os, re, shutil, signal, sqlite3, struct, subprocess, json
from pathlib import Path

HDR = 1487
EXTRA_FIRST = 3528280          # first height in state/hdr/extra.bin (below: the fixed zcash/headers files)
UNDO_DEPTH = 600               # store.UNDO_DEPTH (ZIP 218)
CTX = 113                      # PoWAveragingWindow (102 from NU7) + PoWMedianBlockSpan, as tiphdr.py
NBITS_OFF = 4 + 32 + 32 + 32 + 4  # version, prev, merkle root, block commitments, time


def target_of(hdr):
    bits = struct.unpack_from("<I", hdr, NBITS_OFF)[0]
    exp, mant = bits >> 24, bits & 0x007FFFFF
    if bits & 0x00800000:  # negative compact target: invalid (Bend's difficulty check rejects it anyway)
        return 0
    return mant << (8 * (exp - 3)) if exp > 3 else mant >> (8 * (3 - exp))


def work_of(hdr):
    """Chain work of one header: 2^256 / (target + 1) (zcashd GetBlockProof, Zebra Work)."""
    t = target_of(hdr)
    return (1 << 256) // (t + 1) if t > 0 else 0


def chain_work(hdrs):
    return sum(work_of(h) for h in hdrs)


# ------------------------------------------------------------------ Bend checks of a branch
def bend_check(base_h, base_hash, ctx_hdrs, hdrs, equihash7, hdrchain, work, tag):
    """Headers `hdrs` on top of our verified block at height base_h (hash base_hash, internal
    order), with the CTX verified headers ending at base_h as difficulty context. Same Bend
    programs and acceptance rule as tiphdr.append (+ hdrchain's hashes and links, as
    tipfeed._verify_append). Returns (ok, [Bend hashes, internal order], detail)."""
    work.mkdir(parents=True, exist_ok=True)
    hfile, nfile = work / f"chk_{tag}.bin", work / f"new_{tag}.bin"
    hfile.write_bytes(b"".join(ctx_hdrs) + b"".join(hdrs))
    nfile.write_bytes(b"".join(hdrs))
    n = len(ctx_hdrs) + len(hdrs)
    try:
        pe = subprocess.Popen([str(equihash7), str(hfile), str(n), str(n), "4", str(base_h - len(ctx_hdrs) + 1), "main",
                               "+RTS", "--gpu", "off", "-RTS"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ph = subprocess.Popen([str(hdrchain), str(nfile), "0", str(len(hdrs)), base_hash.hex()],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out_e, _ = pe.communicate(timeout=300)
        out_h, _ = ph.communicate(timeout=300)
    finally:
        hfile.unlink(missing_ok=True)
        nfile.unlink(missing_ok=True)
    got = dict((k, (int(x), int(y))) for k, x, y in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out_e, re.M))
    want = {"equihash valid": (n, n), "hash <= target": (n, n), "prev-hash links": (n - 1, n - 1)}
    dk, dn = got.pop("difficulty (nBits == expected)", (0, -1))
    hashes = re.findall(r"^h (\d+) ([0-9a-f]{64})$", out_h, re.M)
    links = re.search(r"^links (\d+)/(\d+)$", out_h, re.M)
    ok_h = (len(hashes) == len(hdrs) and [int(i) for i, _ in hashes] == list(range(len(hdrs)))
            and links is not None and links.group(1) == links.group(2) == str(len(hdrs)))
    got["difficulty (nBits == expected)"] = (dk, dn)
    if got.get("equihash valid") != want["equihash valid"] or got.get("hash <= target") != want["hash <= target"] \
            or got.get("prev-hash links") != want["prev-hash links"] or dk != dn or dn < len(hdrs) or not ok_h:
        return False, None, f"{got}, hdrchain {'ok' if ok_h else out_h.strip()[-200:]!r}"
    return True, [bytes.fromhex(x)[::-1] for _, x in hashes], f"{got}"


# ------------------------------------------------------------------ header index files
def _fsync_dir(d):
    try:
        fd = os.open(str(d), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass


def _rewrite(path, keep, append=b""):
    """path := path[:keep] + append, atomically (clone, truncate, append, fsync, rename)."""
    tmp = path.with_name(path.name + ".reorg_tmp")
    tmp.unlink(missing_ok=True)
    r = subprocess.run(["cp", "-c", str(path), str(tmp)], capture_output=True)  # APFS clone: O(1)
    if r.returncode != 0:
        shutil.copyfile(path, tmp)
    with open(tmp, "r+b") as f:
        f.truncate(keep)
        f.seek(keep)
        f.write(append)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    _fsync_dir(path.parent)


def _crash_point(name):
    """Test hook (lab only): ZEBEND_REORG_CRASH=<name> SIGKILLs this process at that point."""
    if os.environ.get("ZEBEND_REORG_CRASH") == name:
        os.kill(os.getpid(), signal.SIGKILL)


def switch_index(hdrdir, fork_h, new_hdrs, new_hashes):
    """Replace our verified headers above fork_h by new_hdrs (Bend-checked; their Bend hashes
    new_hashes). Crash-safe order: see the module doc."""
    hp, ep = Path(hdrdir) / "hashes.bin", Path(hdrdir) / "extra.bin"
    assert fork_h + 1 >= EXTRA_FIRST and len(new_hdrs) == len(new_hashes) > 0
    _rewrite(hp, (fork_h + 1) * 32)
    _crash_point("after_hashes_cut")
    _rewrite(ep, (fork_h + 1 - EXTRA_FIRST) * HDR, b"".join(new_hdrs))
    _crash_point("after_extra")
    _rewrite(hp, (fork_h + 1) * 32, b"".join(new_hashes))
    _crash_point("after_switch")


def reconcile(hdrdir, log=print):
    """Make hashes.bin and extra.bin cover the same heights (after a crash in switch_index, or in
    the old append order, extra.bin may hold headers hashes.bin does not index yet)."""
    hp, ep = Path(hdrdir) / "hashes.bin", Path(hdrdir) / "extra.bin"
    if not (hp.exists() and ep.exists()):
        return None
    for p in (hp.with_name(hp.name + ".reorg_tmp"), ep.with_name(ep.name + ".reorg_tmp")):
        p.unlink(missing_ok=True)
    hs, es = hp.stat().st_size, ep.stat().st_size
    if hs % 32:
        _rewrite(hp, hs - hs % 32)
        hs -= hs % 32
    if es % HDR:
        _rewrite(ep, es - es % HDR)
        es -= es % HDR
    n_h, n_e = hs // 32, EXTRA_FIRST + es // HDR   # heights indexed / heights with header bytes
    if n_e > n_h:
        _rewrite(ep, (n_h - EXTRA_FIRST) * HDR)
        log(f"fasttip: header index reconciled: extra.bin had headers {n_h}..{n_e - 1} that hashes.bin does not "
            f"index (interrupted append or reorg switch); cut back to {n_h - 1}")
    elif n_e < n_h:
        _rewrite(hp, n_e * 32)
        log(f"fasttip: header index reconciled: hashes.bin indexed {n_e}..{n_h - 1} without header bytes; cut back to {n_e - 1}")
    return min(n_e, n_h) - 1


def state_tip(state_dir):
    """Committed state tip (meta 'tip') read-only, or None."""
    try:
        db = sqlite3.connect(f"file:{Path(state_dir) / 'chain.sqlite'}?mode=ro", uri=True, timeout=5)
        try:
            r = db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()
        finally:
            db.close()
        return json.loads(r[0])["height"] if r else None
    except (sqlite3.Error, OSError, ValueError, KeyError):
        return None
