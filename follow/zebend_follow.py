#!/usr/bin/env python3
"""zebend follow: follow Zcash mainnet live and validate each new block's shielded parts in Bend.

Every consensus check runs in a Bend binary (bin/):
  zebend-p2p   header sync over P2P; SHA-256d block hashes and prev links   (node/p2p)
  equihash7    Equihash (200,9), hash <= target, links, difficulty by height (blake3x/eqv3 +
               consensus/nu7/headers: ZIP 218 averaging window 102 and 25 s spacing from NU7)
  block_main   wire validation, merkle root, ZIP 244 auth root and block
               commitments                                                  (node/block, node/wire)
  txx          wire validation, txid, ZIP 244 sighash, RedPallas spend-auth
               + binding sigs, Halo 2 public inputs, proof bytes, outpoints (follow/txx.bend over node/tx)
  halo2_batch  batched Orchard/Ironwood Halo 2 verification                 (perf3/v64)
  halo2_one    single-bundle verification, to pinpoint a failing batch      (perf3/v64)
  nfb          Ironwood nullifier set in 256 bucket files: reuse, repeats,
               store integrity; appends the new nullifiers                  (follow/nfb.bend over node/state)
  frontier     Ironwood note commitment tree frontier and per-block roots   (follow/frontier.bend)

Speed comes from scheduling, not from skipping checks: blocks are processed in windows of
W blocks (one block per window when live); the next window downloads from several peers
while the current one is verified; per-block and per-transaction Bend processes run on a
worker pool; Halo 2 is one batch per 512 bundles; the nullifier store reads only the buckets
a window touches.

This driver moves bytes between the binaries and compares what they print. Its own logic is
transport (p2pblocks.py: block download; bin/follow-lwd: labelled oracle values) and
bookkeeping (state files, anchor set lookup, counting). It computes no hash, signature,
proof or tree. Data the driver locates for Bend (prevout amounts/scripts for the sighash)
can only make a check fail if wrong, never pass: Bend hashes it into the sighash that the
on-chain signatures must verify against.

Labelled oracle inputs:
  * hashLightClientRoot (ZIP 221 chain history root) for block commitments, from Blockchair;
    when unavailable (rate limits) the commitments check is reported as SKIPPED. Live blocks
    are checked as soon as the oracle has them (a later line; a MISMATCH rolls back).
  * the chain's Ironwood tree root (lightwalletd GetTreeState), used only to cross-check the
    root Bend computed: the last root of each window (it commits to every earlier leaf).
  * prevout transactions (lightwalletd GetTransaction), only for txs with transparent inputs.
Out of scope, reported per block, never passed: transparent scripts and amounts, Sapling,
Sprout, coinbase/fee rules; Orchard (legacy pool) anchors and nullifiers (no Orchard state).

usage:
  zebend_follow.py [--window N] [--max-blocks N] [--live] [--tamper-next] [--hist-every N]
                   [--jobs N] [--peers N] [--profile]
"""
import argparse, json, os, queue, re, shutil, socket, struct, subprocess, sys, threading, time, urllib.request
from concurrent.futures import ThreadPoolExecutor, wait as wait_all
from pathlib import Path

import p2pblocks

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BIN = HERE / "bin"
STATE = HERE / "state"
WORK = HERE / "work"
WIN = WORK / "win"
NFB = STATE / "nfb"
PARAMS = ROOT / "halo2/verifier/data/params_g.bin"
HDR = 1487
# Headers kept for the difficulty check: PoWAveragingWindow + PoWMedianBlockSpan = 17 + 11
# before NU7, 102 + 11 from NU7 (ZIP 218). A state written before this change keeps 29; it
# grows to 114 with the next windows (pre-NU7 blocks need only 28).
DIFF_WINDOW = 113
SNAPSHOTS = 10
EMPTY_ACTIONS = 0
HALO2_CHUNK = 512  # ~450 MB per halo2_batch run
HEADER_PEER = p2pblocks.KNOWN_PEERS[0]  # the Bend P2P client's peer; the swarm avoids it

POOL = SIDE = NET = DEFERRED = None  # worker pools, sized in main()
ANCHORS = set()  # every Ironwood root since activation (roots.txt), plus the empty root
DEFERRED_FAIL = []


def log(*a):
    print(*a, flush=True)


PROF, PROF_LOCK = {}, threading.Lock()  # process -> [seconds, calls], printed with --profile


def prof(stage, secs):
    with PROF_LOCK:
        e = PROF.setdefault(stage, [0.0, 0])
        e[0] += secs
        e[1] += 1


def run(name, *args, cwd=None):
    # Under parallel load a Bend process occasionally printed nothing (about 1 run in 700,
    # all in one 30-minute window on Oct 25; not reproduced in ~422k stress runs, see
    # bendprs/empty-output.md). The likeliest cause is an external SIGKILL, so the exit
    # status is logged. Empty output can satisfy no check, so it is rerun.
    t = time.perf_counter()
    for _ in range(4):
        r = subprocess.run([str(BIN / name), *map(str, args)], capture_output=True, text=True, cwd=cwd)
        if (r.stdout + r.stderr).strip():
            break
        log(f"  rerun: {name} printed nothing (exit status {r.returncode})")
        prof(f"rerun: {name} printed nothing", 0)
    secs = time.perf_counter() - t
    prof(name, secs)
    return r.stdout + r.stderr, secs


def pmap(fn, items):
    return list(POOL.map(lambda a: fn(*a), items))


class Fail(Exception):
    pass


# ------------------------------------------------------------------ persistent state

def nfb_lengths():
    return [(NFB / f"{k}.bin").stat().st_size for k in range(256)]


def build_nfb(tip):
    """One-off: build the bucketed nullifier store from nf.bin, in Bend (re-checks all of it)."""
    log("building the bucketed nullifier store from nf.bin (once)...")
    tmp = STATE / "nfb.build"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir()
    for k in range(256):
        (tmp / f"{k}.bin").write_bytes(b"")
    with (STATE / "nf.bin").open("r+b") as f:
        f.truncate(tip["nf_bytes"])
    r = subprocess.run([str(ROOT / "heavy.sh"), str(BIN / "nfb"), str(tmp), str(STATE / "nf.bin"), "append"],
                       capture_output=True, text=True)
    n = tip["nf_bytes"] // 32
    if f"nfb new {n} buckets 256 old 0 misrouted 0 old_dups 0 new_dups 0" not in r.stdout or f"appended {n}" not in r.stdout:
        raise Fail(f"building the nullifier store: {r.stdout.strip()} {r.stderr.strip()}")
    os.replace(tmp, NFB)
    tip["nfb_bytes"] = nfb_lengths()
    atomic_write(STATE / "tip.json", json.dumps(tip, indent=1).encode())
    log(f"  {r.stdout.strip().splitlines()[0]}")


def load_state():
    tip = json.loads((STATE / "tip.json").read_text())
    if "nfb_bytes" not in tip or not NFB.exists():
        build_nfb(tip)
    # Crash consistency: append-only files are truncated back to the lengths recorded in
    # tip.json, which is replaced atomically last.
    files = [(STATE / "nf.bin", tip["nf_bytes"]), (STATE / "roots.txt", tip["roots_bytes"])]
    files += [(NFB / f"{k}.bin", n) for k, n in enumerate(tip["nfb_bytes"])]
    for p, n in files:
        if p.stat().st_size > n:
            with p.open("r+b") as f:
                f.truncate(n)
    ANCHORS.clear()
    ANCHORS.update(l.split()[2] for l in (STATE / "roots.txt").read_text().splitlines())
    return tip


def atomic_write(path: Path, data: bytes):
    tmp = path.with_suffix(path.suffix + ".new")
    with tmp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def snapshot(tip):
    d = STATE / "snapshots" / str(tip["height"])
    d.mkdir(parents=True, exist_ok=True)
    for n in ("tip.json", "headers.bin", "frontier.txt"):
        shutil.copy(STATE / n, d / n)
    snaps = sorted((STATE / "snapshots").iterdir(), key=lambda p: int(p.name))
    for old in snaps[:-SNAPSHOTS]:
        shutil.rmtree(old)


def rollback_to_below(height):
    """Restore the newest snapshot whose tip is below `height` (reorgs, late oracle FAILs)."""
    snaps = sorted((STATE / "snapshots").iterdir(), key=lambda p: int(p.name))
    keep = [d for d in snaps if int(d.name) < height]
    if not keep:
        return None
    d = keep[-1]
    for n in ("headers.bin", "frontier.txt"):
        shutil.copy(d / n, STATE / n)
    atomic_write(STATE / "tip.json", (d / "tip.json").read_bytes())
    for newer in snaps[len(keep):]:
        shutil.rmtree(newer)
    return load_state()


# ------------------------------------------------------------------ oracles and transport helpers

def cs_len(n):
    return 1 if n < 0xfd else 3 if n <= 0xffff else 5


def kv(text):
    return dict(l.split(" ", 1) for l in text.splitlines() if " " in l)


def hist_root(height, cache, quiet=False):
    """ZIP 221 chain history root (labelled oracle: Blockchair), internal byte order."""
    if height in cache:
        return cache[height]
    t = time.perf_counter()
    url = f"https://api.blockchair.com/zcash/raw/block/{height}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "zebend-follow"})
        d = json.load(urllib.request.urlopen(req, timeout=30))
        c = d["data"][str(height)]["decoded_raw_block"]["chainhistoryroot"]
        cache[height] = bytes.fromhex(c)[::-1]
    except Exception as e:  # rate limit, block not indexed yet, network
        if not quiet:
            log(f"    (history root for {height} unavailable: {e.__class__.__name__}; commitments SKIPPED)")
        return None
    finally:
        prof("net: history root (Blockchair)", time.perf_counter() - t)
    return cache[height]


def _cs(b, i):
    x = b[i]
    if x < 0xfd:
        return x, i + 1
    if x == 0xfd:
        return struct.unpack_from("<H", b, i + 1)[0], i + 3
    if x == 0xfe:
        return struct.unpack_from("<I", b, i + 1)[0], i + 5
    return struct.unpack_from("<Q", b, i + 1)[0], i + 9


def tx_vouts(raw):
    """Transparent outputs (value, script) of a transaction (routing only)."""
    ver = struct.unpack_from("<I", raw, 0)[0] & 0x7fffffff
    # v1/v2: header only; v3/v4 (Overwinter/Sapling): header, group id;
    # v5/v6: header, group id, branch id, lock time, expiry height
    i = 4 if ver <= 2 else 8 if ver <= 4 else 20
    nin, i = _cs(raw, i)
    for _ in range(nin):
        i += 36
        sl, i = _cs(raw, i)
        i += sl + 4
    nout, i = _cs(raw, i)
    outs = []
    for _ in range(nout):
        v = struct.unpack_from("<q", raw, i)[0]
        sl, j = _cs(raw, i + 8)
        outs.append((v, raw[j:j + sl]))
        i = j + sl
    return outs


def fetch_prevouts(txids, cache):
    """One concurrent lightwalletd call for every transparent prevout a window needs."""
    need = sorted({t for t in txids if t not in cache})
    if need:
        out, _ = run("follow-lwd", "rawtx", *need)
        for m in re.finditer(r"^rawtx ([0-9a-f]{64}) height \d+ hex ([0-9a-f]+)$", out, re.M):
            cache[m.group(1)] = bytes.fromhex(m.group(2))
        missing = [t for t in need if t not in cache]
        if missing:
            raise ConnectionError(f"lightwalletd did not return prevout txs {missing[:3]}...")


def prev_outputs(outpoints, cache):
    """Amounts and scriptPubKeys of spent transparent outputs, in Bend's ctx layout.

    Wrong data here can only make the sighash wrong, so the on-chain signatures would fail.
    """
    amounts, scripts = b"", b""
    for txid, n in outpoints:
        vout = tx_vouts(cache[txid])[n]
        amounts += struct.pack("<q", vout[0])
        scripts += bytes([len(vout[1])]) if len(vout[1]) < 0xfd else b"\xfd" + struct.pack("<H", len(vout[1]))
        scripts += vout[1]
    return struct.pack("<I", len(amounts)) + amounts + struct.pack("<I", len(scripts)) + scripts


def lwd_roots(heights):
    out, _ = run("follow-lwd", "tree", *heights)
    return {int(h): r for h, _, r in re.findall(r"^height (\d+) size (\d+) root ([0-9a-f]{64})$", out, re.M)}


# ------------------------------------------------------------------ Bend checks

def check_headers(new_raw, heights):
    hfile = WORK / "hdrs.bin"
    prev = (STATE / "headers.bin").read_bytes()[-DIFF_WINDOW * HDR:]
    k = len(prev) // HDR
    if heights[-1] >= 3543405 and k < DIFF_WINDOW:  # NU7 headers need the full 113 (ZIP 218)
        raise Fail(f"headers {heights[0]}..{heights[-1]}: only {k} previous headers kept, NU7 needs {DIFF_WINDOW}")
    hfile.write_bytes(prev + b"".join(new_raw))
    n = k + len(new_raw)
    # equihash7 takes the height of the file's first header: the difficulty rules depend on it.
    out, _ = run("equihash7", hfile, n, n, 4, heights[0] - k, "main", "+RTS", "--gpu", "off", "-RTS")
    got = dict((k, (int(a), int(b))) for k, a, b in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M))
    want = {"equihash valid": n, "hash <= target": n, "prev-hash links": n - 1}
    # equihash7 checks the difficulty of every header with a full window in the file (28 before
    # NU7, 113 from NU7), which can include some of the k context headers: every check must
    # pass and they must cover at least the new headers (the last ones in the file).
    dk, dn = got.pop("difficulty (nBits == expected)", (0, -1))
    bad = {k: v for k, v in got.items() if v != (want[k], want[k])}
    if len(got) != 3 or bad or dk != dn or dn < len(new_raw):
        raise Fail(f"headers {heights[0]}..{heights[-1]}: {got} {out.splitlines()[:3]}")
    return hfile, heights[0] - k


def block_report(d, height, hist, hfile, h0):
    (d / "hist").write_bytes(hist or bytes(32))
    out, _ = run("block_main", d / "block.bin", d / "hist", height, hfile, h0)
    if out.startswith("INVALID"):
        raise Fail(f"block {height}: {out.strip()}")
    return out


def check_block(height, hfile, h0):
    """block_main: wire validation, merkle root, header == verified header; split into txs."""
    d = WIN / str(height)
    out = block_report(d, height, None, hfile, h0)
    txs = [(int(i), int(v), int(n), t) for i, v, n, t in
           re.findall(r"^tx (\d+) v(\d+) bytes (\d+) txid ([0-9a-f]{64})", out, re.M)]
    merkle = re.search(r"^merkle \S+ (MATCH|MISMATCH)", out, re.M)
    vh = re.search(r"^verified_header (MATCH|MISMATCH)", out, re.M)
    if not (merkle and merkle.group(1) == "MATCH" and vh and vh.group(1) == "MATCH"):
        raise Fail(f"block {height}: merkle {merkle and merkle.group(1)} header {vh and vh.group(1)}")
    raw = (d / "block.bin").read_bytes()
    off = HDR + cs_len(len(txs))
    out_txs = []
    for i, v, n, txid in txs:
        if v >= 5:
            (d / f"{i}.tx").write_bytes(raw[off:off + n])
        out_txs.append((i, v, txid))
        off += n
    if off != len(raw):
        raise Fail(f"block {height}: tx lengths from Bend do not tile the block")
    return out_txs


def check_commitments(d, height, hfile, h0, hcache, wait=0):
    """block_main with the history-root oracle: hashBlockCommitments MATCH / MISMATCH / SKIPPED."""
    hist, until = hist_root(height, hcache, quiet=wait > 0), time.time() + wait
    while hist is None and time.time() < until:
        time.sleep(15)
        hist = hist_root(height, hcache, quiet=True)
    if hist is None:
        return "SKIPPED"
    cm = re.search(r"^commitments \S+ (MATCH|MISMATCH)", block_report(d, height, hist, hfile, h0), re.M)
    return cm.group(1) if cm else "missing"


def tx_job(height, idx, txid, ctx):
    """txx on one transaction: wire validation, txid, sighash, signatures; writes its bundles."""
    d = WIN / str(height)
    out, _ = run("txx", d / f"{idx}.tx", ctx)
    if out.startswith("INVALID"):
        raise Fail(f"block {height} tx {idx}: {out.strip()}")
    kd = kv(out)
    if "amounts_digest" in kd and ctx == WORK / "empty.ctx":  # Bend needs the spent outputs
        return {"need": [(m.group(2), int(re.search(rf"^vin {m.group(1)} index (\d+)$", out, re.M).group(1)))
                         for m in re.finditer(r"^vin (\d+) ([0-9a-f]{64})$", out, re.M)]}
    if kd.get("txid") != txid:
        raise Fail(f"block {height} tx {idx}: Bend txid {kd.get('txid')} != block leaf {txid}")
    res = {"pools": [], "t_in": "amounts_digest" in kd}
    for pool in ("orchard", "ironwood"):
        n = int(kd.get(f"{pool}.actions", "0"))
        if n == EMPTY_ACTIONS:
            continue
        sigs = sum(kd.get(f"{pool}.a{i}.spend_auth_ok") == "1" for i in range(n))
        if sigs != n or kd.get(f"{pool}.binding_ok") != "1":
            raise Fail(f"block {height} tx {idx} {pool}: spend-auth {sigs}/{n}, binding {kd.get(f'{pool}.binding_ok')}")
        proof = bytes.fromhex(kd[f"{pool}.proof"])
        inst = b"".join(bytes.fromhex(kd[f"{pool}.a{i}.instance[{j}]"]) for i in range(n) for j in range(10))
        bundle = d / f"bundle_{idx}_{pool}.bin"
        bundle.write_bytes(struct.pack("<III", n, 10, len(proof)) + proof + inst)
        res["pools"].append({
            "pool": pool, "n": n, "bundle": bundle, "anchor": kd[f"{pool}.anchor"],
            "nf": [kd[f"{pool}.a{i}.nf"] for i in range(n)],
            "cmx": [kd[f"{pool}.a{i}.cmx"] for i in range(n)],
        })
    return res


def verdict(name, pattern, *args, tries=3):
    """Run a verifier until it prints a verdict line matching `pattern` (group 1 is 0 or 1).

    Only an explicit `result 0` is a rejection. A crash, a runtime error (e.g. a heap
    reservation failing under memory pressure) or missing output is not a verdict: it is
    retried, and if it persists it is reported as a verifier error, never as an invalid proof.
    """
    out = ""
    for i in range(tries):
        out, _ = run(name, *args)
        m = re.search(pattern, out, re.M)
        if m:
            return int(m.group(1)), out
        prof(f"retry: {name} gave no verdict", 0)
        time.sleep(1 + 2 * i)
    raise Fail(f"verifier error: {name} gave no verdict after {tries} runs; last output: {out.strip()[-300:]!r}")


def halo2_check(bundles):
    """Every bundle's Halo 2 proof, batched; on a rejected batch, find the failing bundles.

    A bundle is declared invalid only if two independent Bend verifier builds (halo2_one and
    halo2_two) both print `result 0` for it.
    """
    for c in range(0, len(bundles), HALO2_CHUNK):
        chunk = bundles[c:c + HALO2_CHUNK]
        ok, _ = verdict("halo2_batch", r"^batch K \d+ result ([01])$", PARAMS, *chunk)
        if ok:
            continue
        one = pmap(lambda b: verdict("halo2_one", r"^result ([01])$", PARAMS, b)[0], [(b,) for b in chunk])
        suspects = [b for b, v in zip(chunk, one) if v == 0]
        two = pmap(lambda b: verdict("halo2_two", r"^result ([01])$", PARAMS, b)[0], [(b,) for b in suspects])
        bad = [f"{b.parent.name}/{b.name}" for b, v in zip(suspects, two) if v == 0]
        if not bad:
            raise Fail(f"verifier disagreement: batch of {len(chunk)} rejected, but no bundle is rejected by both "
                       f"single verifiers (halo2_one rejected {[f'{b.parent.name}/{b.name}' for b in suspects]})")
        raise Fail(f"Halo 2 batch of {len(chunk)} bundles rejected; failing bundles: {bad}")


def frontier_roots(cmx, counts, heights):
    """Append the window's Ironwood commitments; one root per block that adds any."""
    (WORK / "leaves.bin").write_bytes(b"".join(bytes.fromhex(x) for x in cmx))
    (WORK / "counts.bin").write_bytes(b"".join(struct.pack("<I", c) for c in counts))
    out, _ = run("frontier", STATE / "frontier.txt", WORK / "leaves.bin", WORK / "counts.bin", WORK / "frontier.new")
    roots = {heights[int(i)]: (int(s), r) for i, s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", out, re.M)}
    if sum(1 for c in counts if c) != len(roots):
        raise Fail(f"frontier: expected {sum(1 for c in counts if c)} roots, got {len(roots)}")
    return roots


def nullifiers_append(nfs):
    """nfb: none already spent, none repeated in the window, store intact; then appended."""
    if not nfs:
        return
    (WORK / "nf_new.bin").write_bytes(b"".join(bytes.fromhex(x) for x in nfs))
    out, _ = run("nfb", NFB, WORK / "nf_new.bin", "append")
    m = re.search(r"^nfb new (\d+) buckets \d+ old \d+ misrouted (\d+) old_dups (\d+) new_dups (\d+)$", out, re.M)
    if not (m and int(m.group(1)) == len(nfs) and m.groups()[1:] == ("0", "0", "0") and f"appended {len(nfs)}" in out):
        raise Fail(f"nullifier check: {out.strip()}")


# ------------------------------------------------------------------ one window

def window_head(headers, pcache):
    """Per-block and per-transaction checks, which need no committed state; the feeder runs
    them for the next window while the current one finishes (window_tail)."""
    T = {}

    def stage(name, t):
        T[name] = T.get(name, 0) + time.perf_counter() - t

    heights = [h for h, _, _ in headers]
    hfile, h0 = WIN / f"hdrs_{heights[0]}.bin", heights[0]  # the window's headers, which
    hfile.write_bytes(b"".join(r for _, _, r in headers))  # equihash verifies before commit
    t = time.perf_counter()
    blocks = pmap(check_block, [(h, hfile, h0) for h in heights])
    stage("block_main (wire, merkle)", t)

    t = time.perf_counter()
    jobs = [(h, i, txid) for h, txs in zip(heights, blocks) for i, v, txid in txs if v >= 5]
    res = pmap(tx_job, [(h, i, txid, WORK / "empty.ctx") for h, i, txid in jobs])
    stage("txx (wire, txid, sighash, sigs)", t)
    need = [k for k, r in enumerate(res) if "need" in r]
    if need:
        t = time.perf_counter()
        fetch_prevouts([o for k in need for o, _ in res[k]["need"]], pcache)
        stage("net: prevouts (lightwalletd)", t)
        t = time.perf_counter()
        for k in need:
            h, i, _ = jobs[k]
            (WIN / str(h) / f"{i}.ctx").write_bytes(prev_outputs(res[k]["need"], pcache))
        for k, r in zip(need, pmap(tx_job, [(*jobs[k], WIN / str(jobs[k][0]) / f"{jobs[k][1]}.ctx") for k in need])):
            res[k] = r
        stage("txx (wire, txid, sighash, sigs)", t)
    return {"blocks": blocks, "jobs": jobs, "res": res, "hfile": hfile, "h0": h0, "T": T}


def verify_window(headers, recv, pre, args, hcache, tamper):
    t0, T = time.perf_counter(), {}

    def stage(name, t):
        T[name] = T.get(name, 0) + time.perf_counter() - t

    heights = [h for h, _, _ in headers]
    t = time.perf_counter()
    check_headers([r for _, _, r in headers], heights)
    stage("PoW/difficulty (equihash)", t)

    live = heights[0] > args.live_from
    commits = {}
    if not live:  # catch-up: the sampled history-root oracle, checked before commit
        commits = {h: NET.submit(check_commitments, WIN / str(h), h, pre["hfile"], pre["h0"], hcache)
                   for h in heights if h % args.hist_every == 0}
    blocks, jobs, res = pre["blocks"], pre["jobs"], pre["res"]

    per_tx = dict(zip(((h, i) for h, i, _ in jobs), res))
    per_block, bundles, iron_nf, iron_cmx, counts = [], [], [], [], []
    for h, (_, hs, _), txs in zip(heights, headers, blocks):
        info = {"h": h, "hash": hs, "txs": len(txs), "shielded": 0, "actions": 0, "orchard_actions": 0,
                "skipped_v4": 0, "skipped_tin": 0, "anchors": 0, "anchor_list": []}
        block_cmx = []
        for i, v, txid in txs:
            if v < 5:
                info["skipped_v4"] += 1  # v4: transparent / Sapling / Sprout only, out of scope
                continue
            r = per_tx[(h, i)]
            info["skipped_tin"] += r["t_in"]
            for p in r["pools"]:
                info["shielded"] += 1
                bundles.append(p["bundle"])
                if p["pool"] == "ironwood":
                    info["actions"] += p["n"]
                    info["anchor_list"].append((txid, p["anchor"]))
                    iron_nf += p["nf"]
                    block_cmx += p["cmx"]
                else:
                    info["orchard_actions"] += p["n"]
        iron_cmx += block_cmx
        counts.append(len(block_cmx))
        per_block.append(info)

    if tamper[0] and bundles:  # flip one bit in the middle of the next proof, on disk
        b = bundles[0]
        data = bytearray(b.read_bytes())
        plen = struct.unpack_from("<I", data, 8)[0]
        data[12 + plen // 2] ^= 0x01
        b.write_bytes(bytes(data))
        tamper[0] = False
        log(f"    --tamper-next: flipped one bit of the proof in block {b.parent.name}, {b.name}")

    # Halo 2, the tree and the nullifier store are independent: run them at once. nfb appends
    # to the store; if anything else fails, the caller truncates the store back (load_state).
    t = time.perf_counter()
    f_halo = SIDE.submit(halo2_check, bundles) if bundles else None
    f_nf = SIDE.submit(nullifiers_append, iron_nf)
    f_tree = SIDE.submit(frontier_roots, iron_cmx, counts, heights)
    # Every parallel check finishes before any failure is raised, so that the caller's
    # truncation of the nullifier store never races an append still in progress.
    wait_all([f for f in (f_halo, f_nf, f_tree) if f])
    new_roots = f_tree.result()
    f_oracle = NET.submit(lwd_roots, [max(new_roots)]) if new_roots and not live else None

    # Anchors: each Ironwood bundle's anchor must be the tree root at the end of some
    # strictly earlier block (or the empty tree), including earlier blocks of this window.
    known = set()
    for b in per_block:
        for txid, a in b["anchor_list"]:
            if a not in ANCHORS and a not in known:
                raise Fail(f"block {b['h']} tx {txid[:16]}: Ironwood anchor {a[:16]} is not a root of any earlier block")
            b["anchors"] += 1
        if b["h"] in new_roots:
            known.add(new_roots[b["h"]][1])
    if f_halo:
        f_halo.result()
    f_nf.result()
    stage("Halo 2 + nullifiers + tree (parallel)", t)

    t = time.perf_counter()
    oracle = f_oracle.result() if f_oracle else {}
    bad = [h for h, r in oracle.items() if h in new_roots and new_roots[h][1] != r]
    if bad:
        raise Fail(f"Ironwood root mismatch vs chain at {bad}")
    commit_v = {h: f.result() for h, f in commits.items()}
    if any(v not in ("MATCH", "SKIPPED") for v in commit_v.values()):
        raise Fail(f"block commitments: {commit_v}")
    stage("oracle waits (tree root, history root)", t)

    # Commit: append-only files first (nfb already appended), then the frontier and headers,
    # then tip.json (atomic). A crash before tip.json is undone by load_state's truncation.
    t = time.perf_counter()
    with (STATE / "nf.bin").open("ab") as f:
        f.write(b"".join(bytes.fromhex(x) for x in iron_nf))
    with (STATE / "roots.txt").open("a") as f:
        for h in sorted(new_roots):
            f.write(f"{h} {new_roots[h][0]} {new_roots[h][1]}\n")
    atomic_write(STATE / "frontier.txt", (WORK / "frontier.new").read_bytes())
    atomic_write(STATE / "headers.bin", ((STATE / "headers.bin").read_bytes() + b"".join(r for _, _, r in headers))[-(DIFF_WINDOW + 1) * HDR:])
    new_tip = {"height": heights[-1], "hash": headers[-1][1], "nf_bytes": (STATE / "nf.bin").stat().st_size,
               "roots_bytes": (STATE / "roots.txt").stat().st_size, "nfb_bytes": nfb_lengths()}
    atomic_write(STATE / "tip.json", json.dumps(new_tip, indent=1).encode())
    snapshot(new_tip)
    ANCHORS.update(r for _, r in new_roots.values())
    stage("commit (state save)", t)

    total, now = time.perf_counter() - t0, time.time()
    for b in per_block:
        root = new_roots.get(b["h"])
        if not root:
            rtxt = "root unchanged"
        elif live:
            rtxt = "root deferred"
        else:
            rtxt = "root MATCH" if oracle.get(b["h"]) == root[1] else "root ok (window's last root MATCH)"
        cm = "deferred" if live else commit_v.get(b["h"], "SKIPPED")
        lat = f"  latency {now - recv[b['h']]:.2f} s" if live and b["h"] in recv else ""
        log(f"{b['h']:>9}  {b['hash'][:16]}  txs {b['txs']:>3}  shielded {b['shielded']:>3}  "
            f"ironwood actions {b['actions']:>3}  orchard actions {b['orchard_actions']:>2}  "
            f"PoW/diff PASS  merkle MATCH  commitments {cm:<8} sigs PASS  "
            f"Halo 2 {b['shielded']}/{b['shielded']} PASS  nullifiers PASS  "
            f"anchors {b['anchors']}/{b['anchors']}  {rtxt}{lat}" + not_checked(b))
    log(f"  window {heights[0]}..{heights[-1]}: {len(heights)} blocks, {len(bundles)} Halo 2 bundles, "
        f"{len(iron_nf)} nullifiers, {len(iron_cmx)} commitments, verified in {total:.1f} s "
        f"({len(heights) / total:.1f} blocks/s)")
    if args.profile:
        for k, v in pre["T"].items():
            log(f"    head    {k:<40} {v:8.2f} s  {v / len(heights) * 1000:8.1f} ms/block  (feeder, overlapped)")
        for k, v in T.items():
            log(f"    tail    {k:<40} {v:8.2f} s  {v / len(heights) * 1000:8.1f} ms/block")
        with PROF_LOCK:
            for k, (secs, calls) in sorted(PROF.items(), key=lambda kv: -kv[1][0]):
                log(f"    process {k:<40} {secs:8.2f} s  {calls:5d} calls (summed over workers)")
            PROF.clear()
    if live:  # oracle checks follow as soon as the oracles have the block
        for b in per_block:
            d = WORK / "deferred" / str(b["h"])
            d.mkdir(parents=True, exist_ok=True)
            raw = (WIN / str(b["h"]) / "block.bin").read_bytes()
            (d / "block.bin").write_bytes(raw)
            (d / "hdr.bin").write_bytes(raw[:HDR])
            DEFERRED.submit(deferred_checks, d, b["h"], new_roots.get(b["h"]), hcache)
    return new_tip, len(heights)


def deferred_checks(d, height, root, hcache):
    """Live blocks: the oracle-backed checks, as soon as the oracles have the block."""
    t = time.time()
    try:
        cm = check_commitments(d, height, d / "hdr.bin", height, hcache, wait=900)
        rt = "unchanged"
        if root:
            rt = "unavailable"
            for _ in range(40):
                got = lwd_roots([height]).get(height)
                if got:
                    rt = "MATCH" if got == root[1] else "MISMATCH"
                    break
                time.sleep(15)
    except Exception as e:  # noqa: a failure here must be reported, not lost in a thread
        cm, rt = f"error {e}", "?"
    log(f"  {height} oracle checks (+{time.time() - t:.0f} s): commitments {cm}, Ironwood root vs chain {rt}")
    if cm not in ("MATCH", "SKIPPED") or rt == "MISMATCH":
        DEFERRED_FAIL.append((height, f"commitments {cm}, root {rt}"))
    else:
        shutil.rmtree(d, ignore_errors=True)


def not_checked(b):
    """Everything a block contains that this follower does not validate, said explicitly."""
    parts = []
    if b["skipped_v4"]:
        parts.append(f"{b['skipped_v4']} v4 tx (transparent/Sapling)")
    if b["skipped_tin"]:
        parts.append(f"transparent inputs of {b['skipped_tin']} tx")
    if b["orchard_actions"]:
        parts.append("Orchard anchors+nullifiers")
    return f"  [not checked: {', '.join(parts)}]" if parts else ""


# ------------------------------------------------------------------ the feeder (transport, one window ahead)

def fetch_headers(height, hash_, batches, peer, timeout=180):
    """New headers after (height, hash), from the Bend P2P client (hashes computed in Bend).

    The Bend client has no network timeout of its own, so it runs under one here; a stalled
    or partial session yields no headers (the caller retries with another peer), never data.
    """
    out_dir = WORK / "p2p"
    shutil.rmtree(out_dir, ignore_errors=True)
    (out_dir / "out").mkdir(parents=True)
    t = time.perf_counter()
    try:
        r = subprocess.run([str(BIN / "zebend-p2p"), peer, "170190", str(height), hash_, str(batches),
                            str(height), hash_], cwd=out_dir, capture_output=True, text=True, timeout=timeout)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return [], f"zebend-p2p timed out after {timeout} s (peer {peer})"
    finally:
        prof("net: headers (zebend-p2p)", time.perf_counter() - t)
    hp, bp = out_dir / "out/heights.txt", out_dir / "out/headers.bin"
    if not (hp.exists() and bp.exists()):
        return [], out
    pairs = re.findall(r"^(\d+) ([0-9a-f]{64})$", hp.read_text(), re.M)
    raw = bp.read_bytes()
    if len(raw) % HDR or len(pairs) != len(raw) // HDR:
        return [], f"inconsistent header output: {len(pairs)} hashes, {len(raw)} bytes"
    return [(int(h), x, raw[i * HDR:(i + 1) * HDR]) for i, (h, x) in enumerate(pairs)], out


class Feeder(threading.Thread):
    """Two stages ahead of the consumer: this thread fetches headers (Bend P2P client) and
    blocks (swarm); a second thread runs window_head on each downloaded window. So window k+2
    downloads while k+1's per-tx checks run and k is finished and committed. Live: a peer's
    block announcement (inv) is fetched at once."""

    def __init__(self, tip, args, swarm, limit, hcache, pcache):
        super().__init__(daemon=True)
        self.hcache, self.pcache = hcache, pcache
        self.q, self.raw, self.halt = queue.Queue(maxsize=1), queue.Queue(maxsize=1), threading.Event()
        self.h, self.prev = tip["height"], tip["hash"]
        self.args, self.swarm, self.limit = args, swarm, limit
        self.pending, self.listener = [], None
        self.header = threading.Thread(target=self.heads, daemon=True)

    def start(self):
        super().start()
        self.header.start()

    def join(self, timeout=None):
        super().join(timeout)
        self.header.join(timeout)

    @staticmethod
    def _put(q, item, halt):
        while not halt.is_set():
            try:
                q.put(item, timeout=1)
                return True
            except queue.Full:
                pass
        return False

    def put(self, item):  # downloader -> head stage
        return self._put(self.raw, item, self.halt)

    def heads(self):
        while not self.halt.is_set():
            try:
                item = self.raw.get(timeout=1)
            except queue.Empty:
                continue
            if item[0] == "window":
                try:
                    item = (*item, window_head(item[1], self.pcache))
                except Fail as e:
                    item = ("fail", e)
                except Exception as e:  # transport (lightwalletd) during the head stage
                    item = ("error", e)
            self._put(self.q, item, self.halt)
            if item[0] != "window":
                return

    def run(self):
        try:
            while not self.halt.is_set() and self.limit != 0:
                if not self.pending:
                    for peer in [HEADER_PEER] + p2pblocks.KNOWN_PEERS[1:]:
                        self.pending, out = fetch_headers(self.h, self.prev, 13, peer)
                        if self.pending or ("timed out" not in out and "inconsistent" not in out):
                            break
                        log(f"  headers: {out.splitlines()[-1] if out else 'no output'}; trying another peer")
                    if not self.pending and "does not link to the previous hash" in out:
                        # Peers answer a locator they do not know from elsewhere: our tip is
                        # not on their chain (it lost a block race). Roll back and refetch.
                        self.put(("reorg",))
                        return
                    if not self.pending:
                        if not self.args.live:
                            break
                        self.listen()
                        continue
                    if self.pending[0][2][4:36][::-1].hex() != self.prev:
                        self.put(("reorg",))
                        return
                take = self.args.window if self.limit < 0 else min(self.args.window, self.limit)
                hs, self.pending = self.pending[:take], self.pending[take:]
                for h, _, _ in hs:  # the sampled history-root oracle, fetched ahead (slow API)
                    if h % self.args.hist_every == 0 and h <= self.args.live_from:
                        NET.submit(hist_root, h, self.hcache, True)
                recv = self.download(hs, self.prev)
                if not self.put(("window", hs, recv)):
                    return
                self.h, self.prev = hs[-1][0], hs[-1][1]
                if self.limit > 0:
                    self.limit -= len(hs)
            self.put(("done",))
        except Exception as e:  # transport trouble: the consumer restarts the feeder
            self.put(("error", e))

    def download(self, hs, prev):
        recv = {}
        for h, _, _ in hs:  # fresh per-height directories: nothing from an earlier attempt
            shutil.rmtree(WIN / str(h), ignore_errors=True)
            (WIN / str(h)).mkdir(parents=True)

        def sink(i, raw):
            (WIN / str(hs[i][0]) / "block.bin").write_bytes(raw)
            recv[hs[i][0]] = time.time()

        t = time.perf_counter()
        self.swarm.get([x for _, x, _ in hs], prev, sink)
        prof("net: blocks (swarm)", time.perf_counter() - t)
        return recv

    def listen(self):
        """Wait for the next block: a peer's inv, fetched at once by its announced hash.

        The announced hash is only used to ask for the block: Bend checks the block's header
        links to the verified tip (equihash: hash of the previous header, PoW, difficulty),
        and the next header's link to this one is checked the same way."""
        if self.listener is None:
            with self.swarm.lock:
                self.listener = self.swarm.idle.pop() if self.swarm.idle else None
            if self.listener is None:
                self.swarm.warm()
                time.sleep(5)
                return
            log(f"  live: listening for block announcements from {self.listener.ip}")
        until = time.time() + 120  # then ask the Bend P2P client, in case an inv was missed
        while time.time() < until and not self.halt.is_set():
            try:
                cmd, p = self.listener.recv()
            except (TimeoutError, socket.timeout):
                continue
            except (OSError, ConnectionError):
                self.listener.close()
                self.listener = None
                return
            if cmd != "inv":
                continue
            n, i = _cs(p, 0)
            for k in range(n):
                entry = p[i + 36 * k:i + 36 * k + 36]
                if struct.unpack_from("<I", entry, 0)[0] != p2pblocks.MSG_BLOCK:
                    continue
                self.listener.s.sendall(p2pblocks._frame("getdata", p2pblocks._varint(1) + entry))
                raw = self.await_block()
                if raw is None:
                    continue
                if raw[4:36][::-1].hex() != self.prev:
                    return  # not the next block (missed one, or a fork): ask the Bend P2P client
                h, hsh = self.h + 1, entry[4:][::-1].hex()
                shutil.rmtree(WIN / str(h), ignore_errors=True)
                (WIN / str(h)).mkdir(parents=True)
                (WIN / str(h) / "block.bin").write_bytes(raw)
                self.put(("window", [(h, hsh, raw[:HDR])], {h: time.time()}))
                self.h, self.prev = h, hsh
                return

    def await_block(self, timeout=20):
        until = time.time() + timeout
        while time.time() < until:
            try:
                cmd, p = self.listener.recv()
            except (TimeoutError, socket.timeout):
                continue
            if cmd == "block":
                return p
        return None


# ------------------------------------------------------------------ main

def main():
    global POOL, SIDE, NET, DEFERRED
    ap = argparse.ArgumentParser()
    ap.add_argument("--window", "--batch", type=int, default=200, help="blocks verified and committed together (catch-up)")
    ap.add_argument("--max-blocks", type=int, default=0, help="stop after this many blocks (0 = run forever)")
    ap.add_argument("--live", action="store_true", help="keep following the tip after catching up")
    ap.add_argument("--hist-every", type=int, default=20,
                    help="during catch-up, fetch the history-root oracle every N blocks (rate limits)")
    ap.add_argument("--jobs", type=int, default=14, help="parallel Bend processes for blocks and txs")
    ap.add_argument("--peers", type=int, default=8, help="peers to download blocks from")
    ap.add_argument("--profile", action="store_true", help="print per-stage timings after each window")
    ap.add_argument("--tamper-next", action="store_true", help="flip one bit of the next Halo 2 proof")
    args = ap.parse_args()
    POOL, SIDE, NET, DEFERRED = (ThreadPoolExecutor(args.jobs), ThreadPoolExecutor(3),
                                 ThreadPoolExecutor(6), ThreadPoolExecutor(4))
    WIN.mkdir(parents=True, exist_ok=True)
    (WORK / "empty.ctx").write_bytes(b"")
    tip = load_state()
    # Blocks above the chain tip seen at start are "live": oracle checks follow as soon as the
    # oracles have them. Catch-up blocks sample the history root every --hist-every blocks.
    m = re.search(r"tip (\d+)", run("follow-lwd", "tip")[0])
    args.live_from = int(m.group(1)) if (m and args.live) else 10**9
    log(f"zebend follow: state tip {tip['height']} {tip['hash'][:16]}…, "
        f"{(STATE / 'nf.bin').stat().st_size // 32:,} Ironwood nullifiers, {len(ANCHORS):,} known Ironwood roots; "
        f"window {args.window}, {args.jobs} jobs, chain tip {m.group(1) if m else '?'}")
    hcache, pcache, tamper = {}, {}, [args.tamper_next]
    swarm = p2pblocks.Swarm(log=log, n=args.peers, avoid={HEADER_PEER})
    done, t_start = 0, time.perf_counter()
    limit = args.max_blocks or -1
    feeder = Feeder(tip, args, swarm, limit, hcache, pcache)
    feeder.start()
    try:
        while True:
            if DEFERRED_FAIL:
                h, why = DEFERRED_FAIL[0]
                log(f"FAIL (oracle check, block {h}): {why}")
                feeder.halt.set()
                tip = rollback_to_below(h)
                log(f"  rolled back to {tip['height'] if tip else '? (no snapshot below it)'}")
                return 1
            try:
                item = feeder.q.get(timeout=5)
            except queue.Empty:
                continue
            if item[0] == "done":
                break
            if item[0] == "fail":
                raise item[1]
            if item[0] in ("error", "reorg"):
                if item[0] == "reorg":
                    log(f"reorg: next header does not link to tip {tip['height']}; rolling back one window")
                    tip = rollback_to_below(tip["height"])
                    if tip is None:
                        log("reorg deeper than the kept snapshots; stopping")
                        return 2
                else:
                    log(f"  transport: {item[1].__class__.__name__}: {item[1]}; restarting the feeder")
                    time.sleep(10)
                feeder.halt.set()
                feeder.join()  # it shares the swarm: let its download finish first
                feeder = Feeder(tip, args, swarm, (limit - done) if limit > 0 else -1, hcache, pcache)
                feeder.start()
                continue
            _, headers, recv, pre = item
            try:
                tip, n = verify_window(headers, recv, pre, args, hcache, tamper)
            except (ConnectionError, OSError, TimeoutError) as e:  # an oracle or lightwalletd call
                feeder.halt.set()
                tip = load_state()
                log(f"  transport during verification: {e.__class__.__name__}: {e}; retrying from tip {tip['height']}")
                time.sleep(10)
                feeder.halt.set()
                feeder.join()  # it shares the swarm: let its download finish first
                feeder = Feeder(tip, args, swarm, (limit - done) if limit > 0 else -1, hcache, pcache)
                feeder.start()
                continue
            for h, _, _ in headers:
                shutil.rmtree(WIN / str(h), ignore_errors=True)
            pre["hfile"].unlink(missing_ok=True)
            done += n
            if limit > 0 and done >= limit:
                break
    except Fail as e:
        feeder.halt.set()
        log(f"FAIL: {e}")
        load_state()  # undo any nfb append of the failed window
        log(f"  window NOT committed; state stays at tip {tip['height']}. Its inputs are in {WIN}")
        return 1
    feeder.halt.set()
    el = time.perf_counter() - t_start
    log(f"done: {done} blocks in {el:.0f} s ({done / el:.2f} blocks/s); tip {tip['height']}")
    if DEFERRED_FAIL or args.live:
        DEFERRED.shutdown(wait=True)
    if DEFERRED_FAIL:
        log(f"FAIL (oracle check): {DEFERRED_FAIL}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
