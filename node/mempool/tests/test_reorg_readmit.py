#!/usr/bin/env python3
"""Reorg re-admission, test_reorg.py style, on a COPY of the tip state (never the live one).

  1. copy state-tip (SQLite backup API + leaf logs + Ironwood root snapshot) -> tip T;
     the blocks T-N+1..T are fetched (rpc.py getblock, Bend-checked) and written as a spool
  2. a test mempool instance runs on the copy (no P2P; its block cache is filled from the
     spool's blocks, each checked by Bend blockdelta against the state's block hash); it is
     preloaded with the live mempool's transactions (sendrawtransaction to the TEST instance
     only, nothing is broadcast)
  3. the copy is rolled back N blocks with the undo data (store.Store.rollback_to) -> the
     mempool sees the tip go down: REORG, the disconnected blocks' transactions must be
     re-admitted (validated again against the rolled-back state), except those whose Ironwood
     anchor is the root after a disconnected block (not a root of an earlier block any more);
     then N more blocks: also every mempool tx anchored to a newly disconnected block must leave
  4. the same blocks are re-applied by sync.py (on the copy) -> the re-admitted transactions
     must leave the mempool as mined, and the preloaded ones must still be there

usage: python3 tests/test_reorg_readmit.py [N=3]
"""
import json, os, shutil, sqlite3, struct, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MP = HERE.parent
FN = MP.parent
sys.path.insert(0, str(MP))
import txcheck as X

N = int(sys.argv[1]) if len(sys.argv) > 1 else 3
W = MP / "work" / "reorg"
COPY, SPOOL, BLK = W / "state", W / "spool", W / "blocks"
RPC_PORT, P2P_PORT = 18241, 18240


def rpc(port, method, *params, timeout=300):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode(),
        headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=timeout))
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["result"]


def wait(cond, secs, what):
    t = time.time()
    while time.time() - t < secs:
        try:
            v = cond()
            if v:
                return v
        except Exception:
            pass
        time.sleep(1)
    raise TimeoutError(what)


def headsync():
    """fullnode's committed sync.py and the modules it imports, runnable on a copy."""
    w = MP / "work"
    d = w / "headsync"
    if d.exists():
        shutil.rmtree(d)
    (d / "state").mkdir(parents=True)
    for f in ("sync.py", "store.py", "rules.py", "headers.py", "assumed.py", "checkpoints.py"):
        (d / f).write_bytes(subprocess.run(["git", "show", f"HEAD:node/{f}"], cwd=str(FN), capture_output=True,
                                           check=True).stdout)
    for name, target in (("bin", "../../../bin"), ("hooks", "../../../hooks"), ("checkpoints", "../../../checkpoints"),
                         ("bend", "../../../bend")):
        (d / name).symlink_to(target)
    (d / "state" / "hdr").symlink_to("../../../../state/hdr")
    for name, target in (("node", "../../../zcash"), ("follow", "../../follow")):  # headers.py/assumed.py: HERE.parent
        if not (w / name).exists():
            (w / name).symlink_to(target)
    return d


def main():
    out = {"N": N}
    if W.exists():
        shutil.rmtree(W)
    for d in (COPY / "leaves", SPOOL, BLK):
        d.mkdir(parents=True)
    src = FN / "state-tip"
    s = sqlite3.connect(f"file:{src / 'chain.sqlite'}?mode=ro", uri=True)
    d = sqlite3.connect(str(COPY / "chain.sqlite"))
    s.backup(d)
    d.close()
    s.close()
    for p in (src / "leaves").iterdir():
        shutil.copy(p, COPY / "leaves" / p.name)
    shutil.copy(src / "ironwood_roots.txt", COPY / "ironwood_roots.txt")
    db = sqlite3.connect(str(COPY / "chain.sqlite"))
    T = json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])["height"]
    hashes = {h: db.execute("SELECT hash FROM blk WHERE height=?", (h,)).fetchone()[0].hex() for h in range(T - 2 * N, T + 1)}
    db.close()
    print(f"copy at tip {T}; blocks {T - N + 1}..{T} will be disconnected, then {T - 2 * N + 1}..{T - N}")
    out["T"] = T
    # the blocks, from rpc.py (fetched over P2P by verified hash and Bend-checked there), checked again here
    recs, disc, anchors = [], {}, {}
    for h in range(T - 2 * N + 1, T + 1):
        raw = bytes.fromhex(rpc(18233, "getblock", str(h), 0))
        p = X.tmp("rb.bin")
        p.write_bytes(X.window_bytes([(h, raw)]))
        b = X.parse_delta(X.run(X.BIN_FN / "blockdelta", p).stdout)[0]
        p.unlink()
        assert b["hash"] == hashes[h] and b["merkle"] == "MATCH", f"block {h} failed the Bend check"
        (BLK / f"{h}.bin").write_bytes(raw)
        recs.append(struct.pack("<II", h, len(raw)) + raw)
        disc[h] = [t["txid"] for t in b["txs"] if not t["cb"]]
        for t in b["txs"]:
            anchors[t["txid"]] = t["anchors"]["ironwood"]
    (SPOOL / f"{T - 2 * N + 1}.blk").write_bytes(b"".join(recs))
    out["disconnected_txs"] = {h: len(v) for h, v in disc.items()}
    print("non-coinbase txs per disconnected block:", out["disconnected_txs"])
    # 2. the test mempool on the copy
    log = open(W / "mempool.log", "w")
    env = dict(os.environ, BEND_NO_TELEMETRY="1")
    m = subprocess.Popen([sys.executable, "-u", str(MP / "mempool.py"), "--state", str(COPY), "--data", str(W / "mdata"),
                          "--journal", str(W / "journal.jsonl"), "--port", str(P2P_PORT), "--rpc-port", str(RPC_PORT),
                          "--no-seeds", "--no-listen", "--cache-blocks", str(2 * N + 2), "--block-dir", str(BLK),
                          "--poll", "1"], stdout=log, stderr=subprocess.STDOUT, env=env)
    try:
        wait(lambda: rpc(RPC_PORT, "getmempoolinfo") is not None, 60, "test mempool rpc")
        cache = wait(lambda: (lambda c: c if all(h in c for h in range(T - 2 * N + 1, T + 1)) else None)(
            rpc(RPC_PORT, "getmempoolstats")["block_cache"]), 120, "block cache")
        print("test mempool block cache:", cache)
        live = rpc(18234, "getrawmempool")
        pre, pre_anchor = [], {}
        for t in live:
            try:
                r = rpc(RPC_PORT, "sendrawtransaction", rpc(18234, "getrawtransaction", t, 0))
                pre.append(r)
                pre_anchor[t] = rpc(RPC_PORT, "getrawtransaction", t, 1).get("ironwood", {}).get("anchor")
            except RuntimeError as e:
                print(f"  preload {t[:12]}: not admitted on the copy: {e}")
        before = set(rpc(RPC_PORT, "getrawmempool"))
        out["preloaded"] = len(before)
        print(f"preloaded {len(before)} of {len(live)} live mempool txs into the test mempool")
        # 3. roll the copy back N blocks
        sys.path.insert(0, str(FN))
        import store
        st = store.Store(COPY)
        st.rollback_to(T - N)
        st.close()
        print(f"copy rolled back to {T - N}")
        want = [t for h in sorted(disc) if h > T - N for t in disc[h]]
        wait(lambda: rpc(RPC_PORT, "getmempoolstats")["tip"] == T - N, 60, "mempool sees the rollback")
        wait(lambda: rpc(RPC_PORT, "getmempoolstats")["queued"] == 0 and
             all(any(t == j.get("txid") for j in map(json.loads, open(W / "journal.jsonl"))) for t in want), 300,
             "re-admission results")
        time.sleep(2)
        jr = [json.loads(l) for l in open(W / "journal.jsonl")]
        res = {}
        for j in jr:
            if j.get("txid") in want and str(j.get("source", "")).startswith("reorg"):
                res[j["txid"]] = (j["status"], j.get("reason"))
        after_rb = set(rpc(RPC_PORT, "getrawmempool"))
        readmitted = [t for t in want if t in after_rb]
        out["readmit"] = {"txs": len(want), "admitted": len(readmitted),
                          "not_admitted": {t: res.get(t) for t in want if t not in after_rb},
                          "preloaded_still_in": len(before & after_rb)}
        print(f"after rollback: {len(readmitted)}/{len(want)} disconnected-block txs re-admitted; "
              f"{len(before & after_rb)}/{len(before)} preloaded txs still in the mempool")
        for t, v in out["readmit"]["not_admitted"].items():
            print(f"  not re-admitted {t[:16]}: {v}")
        roots = {}
        for l in (FN.parent / "node/follow/state/roots.txt").read_text().splitlines():
            f = l.split()
            if len(f) == 3:
                roots.setdefault(f[2], int(f[0]))
        # 3b. a deeper reorg: N more blocks. Mempool txs anchored to a root after a newly
        # disconnected block must leave the mempool (an anchor is a root of an EARLIER block of the
        # chain); the newly disconnected blocks' txs are re-admitted unless anchored the same way.
        st = store.Store(COPY)
        st.rollback_to(T - 2 * N)
        st.close()
        print(f"copy rolled back further, to {T - 2 * N}")
        want2 = [t for h in sorted(disc) if h <= T - N for t in disc[h]]
        wait(lambda: rpc(RPC_PORT, "getmempoolstats")["tip"] == T - 2 * N, 60, "mempool sees the 2nd rollback")
        wait(lambda: rpc(RPC_PORT, "getmempoolstats")["queued"] == 0 and
             all(any(t == j.get("txid") for j in map(json.loads, open(W / "journal.jsonl"))) for t in want2), 300,
             "re-admission results (2nd)")
        time.sleep(2)
        after_b = set(rpc(RPC_PORT, "getrawmempool"))
        anch_b = {t: rpc(RPC_PORT, "getrawtransaction", t, 1).get("ironwood", {}).get("anchor") for t in after_b}
        bad_b = [t for t, x in anch_b.items() if x and roots.get(x, 0) > T - 2 * N]
        jr = [json.loads(l) for l in open(W / "journal.jsonl")]
        rm_anchor = [j["txid"] for j in jr if j.get("event") == "removed" and "Ironwood anchor" in j.get("reason", "")]
        newer2 = {t for t in want2 if any(roots.get(x, 0) > T - 2 * N for x in anchors.get(t, []))}
        readm2 = [t for t in want2 if t in after_b]
        out["deeper"] = {"to": T - 2 * N, "disconnected_txs": len(want2), "readmitted": len(readm2),
                         "anchored_in_disconnected": len(newer2),
                         "removed_from_mempool_by_anchor_recheck": len(rm_anchor),
                         "mempool_txs_anchored_above_tip": bad_b}
        print(f"after the 2nd rollback: {len(readm2)}/{len(want2)} newly disconnected txs re-admitted "
              f"({len(newer2)} anchored to a disconnected block); {len(rm_anchor)} mempool txs removed by the anchor "
              f"re-check; mempool txs anchored above the tip: {len(bad_b)}")
        # 4. re-apply the same blocks with sync.py on the copy. The working-tree sync.py/rules.py are
        # being edited by another agent (their ctx format can be ahead of bin/rules), so the committed
        # (git HEAD) versions are run, from a directory that links fullnode's bin/, hooks/, ...
        hs = headsync()
        r = subprocess.run([sys.executable, str(hs / "sync.py"), "--keep-spool", "--to", str(T), "--window", "10"],
                           env=dict(env, ZEBEND_STATE=str(COPY), ZEBEND_SPOOL=str(SPOOL)), capture_output=True,
                           text=True, timeout=900, cwd=str(hs))
        last = (r.stdout.strip().splitlines() or [r.stderr[-300:]])[-1]
        print("sync.py re-apply:", last)
        out["reapply"] = last
        wait(lambda: rpc(RPC_PORT, "getmempoolstats")["tip"] == T, 120, "mempool sees the re-applied tip")
        time.sleep(3)
        final = set(rpc(RPC_PORT, "getrawmempool"))
        jr = [json.loads(l) for l in open(W / "journal.jsonl")]
        mined = {j["txid"] for j in jr if j.get("event") == "removed" and j.get("reason") == "mined"}
        inpool_b = set(readm2) | (set(readmitted) & after_b)
        out["after_reapply"] = {"disconnected_txs_in_mempool_before": len(inpool_b),
                                "removed_as_mined": len([t for t in inpool_b if t in mined and t not in final]),
                                "disconnected_still_in_mempool": [t for t in inpool_b if t in final],
                                "preloaded_still_in": len(before & final), "preloaded": len(before)}
        print(f"after re-apply to {T}: {out['after_reapply']['removed_as_mined']}/{len(inpool_b)} disconnected-block "
              f"txs in the mempool removed as mined; {len(before & final)}/{len(before)} preloaded txs still in the mempool")
        # A tx whose Ironwood anchor is the tree root after a DISCONNECTED block is not valid at the
        # rolled-back tip (an anchor must be a root of an earlier block of the chain): it must be
        # rejected, not re-admitted. Root heights: follow's Bend-computed roots.
        newer = {t for t in want if any(roots.get(x, 0) > T - N for x in anchors.get(t, []))}
        out["anchor_in_disconnected_block"] = sorted(newer)
        print(f"{len(newer)} disconnected-block txs have an Ironwood anchor of a disconnected block (must not be re-admitted)")
        not_in = [t for t in want if t not in after_rb]
        pre_newer = {t for t, x in pre_anchor.items() if x and roots.get(x, 0) > T - N and t in before}
        out["preloaded_anchor_in_disconnected_block"] = sorted(pre_newer)
        print(f"{len(pre_newer)} preloaded txs have an Ironwood anchor of a disconnected block (must leave the mempool)")
        pre_newer2 = {t for t, x in pre_anchor.items() if x and roots.get(x, 0) > T - 2 * N and t in before}
        deps = {j["txid"] for j in jr if j.get("event") == "removed" and j.get("reason", "").startswith("dependent")}
        out["preloaded_removed"] = {"anchored_to_disconnected_block": len(pre_newer2 & (before - final)),
                                    "dependent_of_removed": len(((before - final) - pre_newer2) & deps),
                                    "other": sorted((before - final) - pre_newer2 - deps)}
        print(f"preloaded txs removed: {out['preloaded_removed']}")
        ok = (set(not_in) == newer and before & after_rb == before - pre_newer
              and not bad_b and set(want2) - after_b >= newer2
              and out["after_reapply"]["removed_as_mined"] == len(inpool_b)
              and pre_newer2 <= before - final
              and (before - final) - pre_newer2 <= deps)  # a child of a removed tx leaves with it
        if set(want2) - after_b - newer2:
            print("  2nd rollback, not re-admitted for another reason:",
                  {t[:16]: [j.get("reason") for j in jr if j.get("txid") == t][-1:] for t in set(want2) - after_b - newer2})
        out["verdict"] = "PASS" if ok else "FAIL (see details)"
        print("REORG RE-ADMIT TEST", out["verdict"])
    finally:
        m.terminate()
        m.wait(10)
        (HERE / "results").mkdir(exist_ok=True)
        (HERE / "results" / "reorg.json").write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
