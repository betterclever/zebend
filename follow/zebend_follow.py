#!/usr/bin/env python3
"""zebend follow: follow Zcash mainnet live and validate each new block's shielded parts in Bend.

Every consensus check runs in a Bend binary (bin/):
  zebend-p2p   header sync over P2P; SHA-256d block hashes and prev links   (node/p2p)
  equihash     Equihash (200,9), hash <= target, links, difficulty          (blake3x/eqv3)
  block_main   merkle root, ZIP 244 auth root and block commitments         (node/block)
  txx          txid, ZIP 244 sighash, RedPallas spend-auth + binding sigs,
               Halo 2 public inputs, proof bytes, transparent outpoints     (follow/txx.bend over node/tx)
  halo2_batch  batched Orchard/Ironwood Halo 2 verification                 (perf3/v64)
  halo2_one    single-bundle verification, to pinpoint a failing batch      (perf3/v64)
  nf_check     Ironwood nullifier set: duplicates and membership            (validate/ over node/state)
  frontier     Ironwood note commitment tree frontier and per-block roots   (follow/frontier.bend)

This driver moves bytes between them and compares what they print. Its own logic is
transport (p2pblocks.py: block download; bin/follow-lwd: labelled oracle values) and
bookkeeping (state files, anchor set lookup, counting). It computes no hash, signature,
proof or tree. Data the driver locates for Bend (prevout amounts/scripts for the sighash)
can only make a check fail if wrong, never pass: Bend hashes it into the sighash that the
on-chain signatures must verify against.

Labelled oracle inputs:
  * hashLightClientRoot (ZIP 221 chain history root) for block commitments, from Blockchair;
    when unavailable (rate limits) the commitments check is reported as SKIPPED.
  * the chain's Ironwood tree root per block (lightwalletd GetTreeState), used only to
    cross-check the root Bend computed.
  * prevout transactions (lightwalletd GetTransaction), only for txs with transparent inputs.
Out of scope, reported as SKIPPED, never passed: transparent scripts and amounts, Sapling,
Sprout, coinbase/fee rules; Orchard (legacy pool) anchors and nullifiers (no Orchard state).

usage:
  zebend_follow.py [--batch N] [--max-blocks N] [--live] [--tamper-next] [--hist-every N]
"""
import argparse, json, os, re, shutil, struct, subprocess, sys, time, urllib.request
from pathlib import Path

import p2pblocks

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BIN = HERE / "bin"
STATE = HERE / "state"
WORK = HERE / "work"
PARAMS = ROOT / "halo2/verifier/data/params_g.bin"
HDR = 1487
DIFF_WINDOW = 28
SNAPSHOTS = 10
EMPTY_ACTIONS = 0


def log(*a):
    print(*a, flush=True)


def run(name, *args, cwd=None):
    t = time.perf_counter()
    r = subprocess.run([str(BIN / name), *map(str, args)], capture_output=True, text=True, cwd=cwd)
    return r.stdout + r.stderr, time.perf_counter() - t


# ------------------------------------------------------------------ persistent state

def load_state():
    tip = json.loads((STATE / "tip.json").read_text())
    # Crash consistency: append-only files are truncated back to the lengths recorded in
    # tip.json, which is replaced atomically last.
    for name, key in (("nf.bin", "nf_bytes"), ("roots.txt", "roots_bytes")):
        p = STATE / name
        if p.stat().st_size > tip[key]:
            with p.open("r+b") as f:
                f.truncate(tip[key])
    return tip


def atomic_write(path: Path, data: bytes):
    tmp = path.with_suffix(path.suffix + ".new")
    with tmp.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def anchor_set():
    return {l.split()[2] for l in (STATE / "roots.txt").read_text().splitlines()}


def snapshot(tip):
    d = STATE / "snapshots" / str(tip["height"])
    d.mkdir(parents=True, exist_ok=True)
    for n in ("tip.json", "headers.bin", "frontier.txt"):
        shutil.copy(STATE / n, d / n)
    snaps = sorted((STATE / "snapshots").iterdir(), key=lambda p: int(p.name))
    for old in snaps[:-SNAPSHOTS]:
        shutil.rmtree(old)


def rollback(depth):
    """Restore the snapshot `depth` committed batches back (simple reorg rule)."""
    snaps = sorted((STATE / "snapshots").iterdir(), key=lambda p: int(p.name))
    if len(snaps) <= depth:
        return None
    d = snaps[-1 - depth]
    for n in ("headers.bin", "frontier.txt"):
        shutil.copy(d / n, STATE / n)
    atomic_write(STATE / "tip.json", (d / "tip.json").read_bytes())
    for newer in snaps[len(snaps) - depth:]:
        shutil.rmtree(newer)
    return load_state()


# ------------------------------------------------------------------ helpers

def cs_len(n):
    return 1 if n < 0xfd else 3 if n <= 0xffff else 5


def kv(text):
    return dict(l.split(" ", 1) for l in text.splitlines() if " " in l)


def hist_root(height, cache):
    """ZIP 221 chain history root (labelled oracle: Blockchair), internal byte order."""
    if height in cache:
        return cache[height]
    url = f"https://api.blockchair.com/zcash/raw/block/{height}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "zebend-follow"})
        d = json.load(urllib.request.urlopen(req, timeout=30))
        c = d["data"][str(height)]["decoded_raw_block"]["chainhistoryroot"]
        cache[height] = bytes.fromhex(c)[::-1]
    except Exception as e:  # rate limit, block not indexed yet, network
        cache[height] = None
        log(f"    (history root for {height} unavailable: {e.__class__.__name__}; commitments SKIPPED)")
    return cache[height]


def prev_outputs(outpoints, cache):
    """Amounts and scriptPubKeys of spent transparent outputs (transport: lightwalletd).

    Wrong data here can only make the sighash wrong, so the on-chain signatures would fail.
    """
    need = sorted({o for o, _ in outpoints if o not in cache})
    if need:
        out, _ = run("follow-lwd", "rawtx", *need)
        for m in re.finditer(r"^rawtx ([0-9a-f]{64}) height \d+ hex ([0-9a-f]+)$", out, re.M):
            cache[m.group(1)] = bytes.fromhex(m.group(2))
    amounts, scripts = b"", b""
    for txid, n in outpoints:
        vout = tx_vouts(cache[txid])[n]
        amounts += struct.pack("<q", vout[0])
        scripts += bytes([len(vout[1])]) if len(vout[1]) < 0xfd else b"\xfd" + struct.pack("<H", len(vout[1]))
        scripts += vout[1]
    return struct.pack("<I", len(amounts)) + amounts + struct.pack("<I", len(scripts)) + scripts


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
    """Transparent outputs (value, script) of a v4/v5/v6 transaction (routing only)."""
    ver = struct.unpack_from("<I", raw, 0)[0] & 0x7fffffff
    i = 8 if ver == 4 else 20  # v4: header, groupid; v5+: + branch, locktime, expiry
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


def prefetch_prevouts(txs, pcache):
    """One lightwalletd call for every transparent prevout a batch needs (transport only)."""
    need = set()
    for idx, v, txid, raw in txs:
        if v < 5:
            continue
        tfile, cfile = WORK / "pre.bin", WORK / "pre.ctx"
        tfile.write_bytes(raw)
        cfile.write_bytes(b"")
        out, _ = run("txx", tfile, cfile)
        if "amounts_digest " in out:
            need |= {m for m in re.findall(r"^vin \d+ ([0-9a-f]{64})$", out, re.M) if m not in pcache}
    if need:
        out, _ = run("follow-lwd", "rawtx", *sorted(need))
        for m in re.finditer(r"^rawtx ([0-9a-f]{64}) height \d+ hex ([0-9a-f]+)$", out, re.M):
            pcache[m.group(1)] = bytes.fromhex(m.group(2))


# ------------------------------------------------------------------ one batch

class Fail(Exception):
    pass


def check_headers(tip, new_raw, new_heights):
    hfile = WORK / "hdrs.bin"
    hfile.write_bytes((STATE / "headers.bin").read_bytes()[-DIFF_WINDOW * HDR:] + b"".join(new_raw))
    n = DIFF_WINDOW + len(new_raw)
    out, secs = run("equihash", hfile, n, n, 4, "+RTS", "--gpu", "off", "-RTS")
    got = dict((k, (int(a), int(b))) for k, a, b in re.findall(
        r"^(equihash valid|hash <= target|prev-hash links|difficulty \(nBits == expected\)) (\d+)/(\d+)", out, re.M))
    want = {"equihash valid": n, "hash <= target": n, "prev-hash links": n - 1, "difficulty (nBits == expected)": len(new_raw)}
    bad = {k: v for k, v in got.items() if v != (want[k], want[k])}
    if len(got) != 4 or bad:
        raise Fail(f"headers {new_heights[0]}..{new_heights[-1]}: {got}")
    return hfile, new_heights[0] - DIFF_WINDOW, secs


def check_block(height, raw, hfile, h0, hcache, want_hist):
    (WORK / "block.bin").write_bytes(raw)
    hist = hist_root(height, hcache) if want_hist else None
    (WORK / "block.hist").write_bytes(hist or bytes(32))
    out, secs = run("block_main", WORK / "block.bin", WORK / "block.hist", height, hfile, h0)
    txs = [(int(i), int(v), int(n), t) for i, v, n, t in
           re.findall(r"^tx (\d+) v(\d+) bytes (\d+) txid ([0-9a-f]{64})", out, re.M)]
    merkle = re.search(r"^merkle \S+ (MATCH|MISMATCH)", out, re.M)
    vh = re.search(r"^verified_header (MATCH|MISMATCH)", out, re.M)
    cm = re.search(r"^commitments \S+ (MATCH|MISMATCH)", out, re.M)
    commit = (cm.group(1) if cm else "missing") if hist else "SKIPPED"
    if not (merkle and merkle.group(1) == "MATCH" and vh and vh.group(1) == "MATCH" and commit in ("MATCH", "SKIPPED")):
        raise Fail(f"block {height}: merkle {merkle and merkle.group(1)} header {vh and vh.group(1)} commitments {commit}")
    off = HDR + cs_len(len(txs))
    out_txs = []
    for i, v, n, txid in txs:
        out_txs.append((i, v, txid, raw[off:off + n]))
        off += n
    if off != len(raw):
        raise Fail(f"block {height}: tx lengths from Bend do not tile the block")
    return out_txs, commit, secs


def check_tx(height, idx, txid, raw, pcache, tamper):
    tfile, cfile = WORK / f"tx{idx}.bin", WORK / f"tx{idx}.ctx"
    tfile.write_bytes(raw)
    cfile.write_bytes(b"")
    out, secs = run("txx", tfile, cfile)
    d = kv(out)
    if "amounts_digest" in d:  # transparent inputs: Bend needs the spent outputs for ZIP 244
        outs = [(m.group(2), int(re.search(rf"^vin {m.group(1)} index (\d+)$", out, re.M).group(1)))
                for m in re.finditer(r"^vin (\d+) ([0-9a-f]{64})$", out, re.M)]
        cfile.write_bytes(prev_outputs(outs, pcache))
        out, s2 = run("txx", tfile, cfile)
        secs += s2
        d = kv(out)
    if d.get("txid") != txid:
        raise Fail(f"block {height} tx {idx}: Bend txid {d.get('txid')} != block leaf {txid}")
    res = {"pools": [], "secs": secs, "t_in": "amounts_digest" in d}
    for pool in ("orchard", "ironwood"):
        n = int(d.get(f"{pool}.actions", "0"))
        if n == EMPTY_ACTIONS:
            continue
        sigs = sum(d.get(f"{pool}.a{i}.spend_auth_ok") == "1" for i in range(n))
        if sigs != n or d.get(f"{pool}.binding_ok") != "1":
            raise Fail(f"block {height} tx {idx} {pool}: spend-auth {sigs}/{n}, binding {d.get(f'{pool}.binding_ok')}")
        proof = bytes.fromhex(d[f"{pool}.proof"])
        if tamper[0]:
            proof = bytearray(proof)
            proof[len(proof) // 2] ^= 0x01
            proof = bytes(proof)
            tamper[0] = False
            log(f"    --tamper-next: flipped one bit of {pool} proof in tx {txid[:16]} (block {height})")
        inst = b"".join(bytes.fromhex(d[f"{pool}.a{i}.instance[{j}]"]) for i in range(n) for j in range(10))
        bundle = WORK / f"bundle_{height}_{idx}_{pool}.bin"
        bundle.write_bytes(struct.pack("<III", n, 10, len(proof)) + proof + inst)
        res["pools"].append({
            "pool": pool, "n": n, "bundle": bundle, "anchor": d[f"{pool}.anchor"],
            "nf": [d[f"{pool}.a{i}.nf"] for i in range(n)],
            "cmx": [d[f"{pool}.a{i}.cmx"] for i in range(n)],
        })
    return res


def run_batch(tip, headers, peer, hcache, pcache, args, tamper):
    t0 = time.perf_counter()
    heights = [h for h, _, _ in headers]
    hfile, h0, t_hdr = check_headers(tip, [r for _, _, r in headers], heights)
    blocks = peer.blocks([hs for _, hs, _ in headers], tip["hash"])
    anchors = anchor_set()
    checked = []
    for k, (h, hs, _) in enumerate(headers):
        want_hist = h > args.live_from or (h % args.hist_every == 0)
        checked.append(check_block(h, blocks[k], hfile, h0, hcache, want_hist))
    prefetch_prevouts([t for txs, _, _ in checked for t in txs], pcache)
    per_block, bundles, iron_nf, iron_cmx, counts = [], [], [], [], []
    for k, (h, hs, _) in enumerate(headers):
        txs, commit, t_blk = checked[k]
        info = {"h": h, "hash": hs, "txs": len(txs), "commit": commit, "shielded": 0, "actions": 0,
                "orchard_actions": 0, "skipped_v4": 0, "skipped_tin": 0, "anchors": 0, "ms": 0}
        block_cmx = []
        for idx, v, txid, raw in txs:
            if v < 5:
                info["skipped_v4"] += 1  # v4: transparent / Sapling / Sprout only, out of scope
                continue
            r = check_tx(h, idx, txid, raw, pcache, tamper)
            info["skipped_tin"] += r["t_in"]
            for p in r["pools"]:
                info["shielded"] += 1
                bundles.append(p["bundle"])
                if p["pool"] == "ironwood":
                    info["actions"] += p["n"]
                    info.setdefault("anchor_list", []).append((txid, p["anchor"]))
                    iron_nf += p["nf"]
                    block_cmx += p["cmx"]
                else:
                    info["orchard_actions"] += p["n"]
        iron_cmx += block_cmx
        counts.append(len(block_cmx))
        per_block.append(info)

    # Halo 2: one batch for every Orchard-protocol bundle in these blocks.
    t = time.perf_counter()
    if bundles:
        out, _ = run("halo2_batch", PARAMS, *bundles)
        if not re.search(r"^batch K \d+ result 1$", out, re.M):
            bad = [b.name for b in bundles if not re.search(r"^result 1$", run("halo2_one", PARAMS, b)[0], re.M)]
            raise Fail(f"Halo 2 batch of {len(bundles)} bundles rejected; failing bundles: {bad}")
    t_halo2 = time.perf_counter() - t

    # Nullifiers: no Ironwood nullifier may already be in the set or repeat within the batch.
    t = time.perf_counter()
    nf_new = b"".join(bytes.fromhex(x) for x in iron_nf)
    if nf_new:
        allf, q = WORK / "nf_all.bin", WORK / "nf_new.bin"
        allf.write_bytes((STATE / "nf.bin").read_bytes() + nf_new)
        q.write_bytes(nf_new)
        out, _ = run("nf_check", allf, q)
        dups = re.search(r"duplicates (\d+)", out)
        occ = re.findall(r"^nf [0-9a-f]+ member (\w+) occurrences (\d+)", out, re.M)
        if not dups or dups.group(1) != "0" or len(occ) != len(iron_nf) or any(m != "yes" or c != "1" for m, c in occ):
            raise Fail(f"nullifier check: duplicates {dups and dups.group(1)}, {sum(c != '1' for _, c in occ)} reused")
    t_nf = time.perf_counter() - t

    # Tree: append this batch's Ironwood commitments, one root per block.
    t = time.perf_counter()
    (WORK / "leaves.bin").write_bytes(b"".join(bytes.fromhex(x) for x in iron_cmx))
    (WORK / "counts.bin").write_bytes(b"".join(struct.pack("<I", c) for c in counts))
    out, _ = run("frontier", STATE / "frontier.txt", WORK / "leaves.bin", WORK / "counts.bin", WORK / "frontier.new")
    new_roots = {heights[int(i)]: (int(s), r) for i, s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", out, re.M)}
    if sum(1 for c in counts if c) != len(new_roots):
        raise Fail(f"frontier: expected {sum(1 for c in counts if c)} roots, got {len(new_roots)}")
    t_tree = time.perf_counter() - t

    # Anchors: each Ironwood bundle's anchor must be the tree root at the end of some
    # strictly earlier block (or the empty tree), including earlier blocks of this batch.
    known = set(anchors)
    for b in per_block:
        for txid, a in b.get("anchor_list", []):
            if a not in known:
                raise Fail(f"block {b['h']} tx {txid[:16]}: Ironwood anchor {a[:16]} is not a root of any earlier block")
            b["anchors"] += 1
        if b["h"] in new_roots:
            known.add(new_roots[b["h"]][1])

    # Cross-check (labelled oracle): the chain's own Ironwood root at those heights.
    oracle = {}
    if new_roots:
        out, _ = run("follow-lwd", "tree", *sorted(new_roots))
        oracle = {int(h): r for h, _, r in re.findall(r"^height (\d+) size (\d+) root ([0-9a-f]{64})$", out, re.M)}
        bad = [h for h, (_, r) in new_roots.items() if h in oracle and oracle[h] != r]
        if bad:
            raise Fail(f"Ironwood root mismatch vs chain at {bad}")

    # Commit: append-only files first, then the frontier and headers, then tip.json (atomic).
    with (STATE / "nf.bin").open("ab") as f:
        f.write(nf_new)
    with (STATE / "roots.txt").open("a") as f:
        for h in sorted(new_roots):
            f.write(f"{h} {new_roots[h][0]} {new_roots[h][1]}\n")
    atomic_write(STATE / "frontier.txt", (WORK / "frontier.new").read_bytes())
    atomic_write(STATE / "headers.bin", ((STATE / "headers.bin").read_bytes() + b"".join(r for _, _, r in headers))[-(DIFF_WINDOW + 1) * HDR:])
    new_tip = {"height": heights[-1], "hash": headers[-1][1],
               "nf_bytes": (STATE / "nf.bin").stat().st_size, "roots_bytes": (STATE / "roots.txt").stat().st_size}
    atomic_write(STATE / "tip.json", json.dumps(new_tip, indent=1).encode())
    snapshot(new_tip)

    total = time.perf_counter() - t0
    for b in per_block:
        root = new_roots.get(b["h"])
        rtxt = ("root " + ("MATCH" if oracle.get(b["h"]) == root[1] else "unchecked")) if root else "root unchanged"
        log(f"{b['h']:>9}  {b['hash'][:16]}  txs {b['txs']:>3}  shielded {b['shielded']:>2}  "
            f"ironwood actions {b['actions']:>3}  orchard actions {b['orchard_actions']:>2}  "
            f"PoW/diff PASS  merkle MATCH  commitments {b['commit']:<8} sigs PASS  "
            f"anchors {b['anchors']}/{b['anchors']}  {rtxt}" + not_checked(b))
    log(f"  batch {heights[0]}..{heights[-1]}: {len(heights)} blocks, {len(bundles)} Halo 2 bundles, "
        f"{len(iron_nf)} nullifiers, {len(iron_cmx)} commitments in {total:.1f} s "
        f"(headers {t_hdr:.2f} s, Halo 2 {t_halo2:.2f} s, nullifiers {t_nf:.2f} s, tree {t_tree:.2f} s)")
    return new_tip, len(heights), total


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


def fetch_headers(tip, batches):
    """New headers after the tip, from the Bend P2P client (hashes computed in Bend)."""
    out_dir = WORK / "p2p"
    shutil.rmtree(out_dir, ignore_errors=True)
    (out_dir / "out").mkdir(parents=True)
    out, _ = run("zebend-p2p", "-", 170190, tip["height"], tip["hash"], batches, tip["height"], tip["hash"], cwd=out_dir)
    hp = out_dir / "out/heights.txt"
    if not hp.exists():
        return [], out
    lines = hp.read_text().split()
    raw = (out_dir / "out/headers.bin").read_bytes()
    hs = [(int(lines[2 * i]), lines[2 * i + 1], raw[i * HDR:(i + 1) * HDR]) for i in range(len(raw) // HDR)]
    return hs, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=25, help="blocks validated and committed together")
    ap.add_argument("--max-blocks", type=int, default=0, help="stop after this many blocks (0 = run forever)")
    ap.add_argument("--live", action="store_true", help="keep following the tip after catching up")
    ap.add_argument("--hist-every", type=int, default=20,
                    help="during catch-up, fetch the history-root oracle every N blocks (rate limits)")
    ap.add_argument("--tamper-next", action="store_true", help="flip one bit of the next Halo 2 proof in memory")
    args = ap.parse_args()
    WORK.mkdir(exist_ok=True)
    tip = load_state()
    # Blocks above the chain tip seen at start are "live": every one gets the history-root
    # oracle. Catch-up blocks sample it every --hist-every blocks (oracle rate limits).
    m = re.search(r"tip (\d+)", run("follow-lwd", "tip")[0])
    args.live_from = int(m.group(1)) if (m and args.live) else 10**9
    log(f"zebend follow: state tip {tip['height']} {tip['hash'][:16]}…, "
        f"{(STATE / 'nf.bin').stat().st_size // 32:,} Ironwood nullifiers, "
        f"{len(anchor_set()):,} known Ironwood roots")
    peer, hcache, pcache, tamper = None, {}, {}, [args.tamper_next]
    done, t_start = 0, time.perf_counter()
    pending = []  # headers fetched (and hashed) by the Bend P2P client, not yet validated
    while True:
        try:
            if not pending or pending[0][2][4:36][::-1].hex() != tip["hash"]:
                pending, p2p_out = fetch_headers(tip, 1)
                if pending and pending[0][2][4:36][::-1].hex() != tip["hash"]:
                    log(f"reorg: next header does not link to tip {tip['height']}; rolling back one batch")
                    pending = []
                    tip = rollback(1)
                    if tip is None:
                        log("reorg deeper than the kept snapshots; stopping")
                        return 2
                    continue
            headers = pending[:args.batch]
            if args.max_blocks:
                headers = headers[:args.max_blocks - done]
            if not headers:
                if not args.live or (args.max_blocks and done >= args.max_blocks):
                    break
                time.sleep(15)
                continue
            if peer is None:
                peer = p2pblocks.connect(log)
            tip, n, secs = run_batch(tip, headers, peer, hcache, pcache, args, tamper)
            pending = pending[n:]
            done += n
            if args.max_blocks and done >= args.max_blocks:
                break
        except Fail as e:
            log(f"FAIL: {e}")
            log("  batch NOT committed; state stays at tip "
                f"{tip['height']}. Quarantined inputs are in {WORK}")
            return 1
        except (OSError, ConnectionError, LookupError, TimeoutError) as e:
            log(f"  transport: {e.__class__.__name__}: {e}; reconnecting to another peer")
            if peer:
                peer.close()
                p2pblocks.KNOWN_PEERS.remove(peer.ip) if peer.ip in p2pblocks.KNOWN_PEERS else None
            peer = None
            time.sleep(3)
    el = time.perf_counter() - t_start
    log(f"done: {done} blocks in {el:.0f} s ({done / el:.2f} blocks/s); tip {tip['height']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
