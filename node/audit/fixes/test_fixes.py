#!/usr/bin/env python3
"""Each fix in fixes/staged, shown on the LIVE code (fixes/orig, copied 20:3x Oct 27) and on the
staged code, in throwaway trees (nothing live is touched; fake binaries stand in for the network
and the verifiers).

  F1  oracle hang: follow-lwd accepts the connection and never answers (seen in the audit
      replay: 20+ min, 0% CPU). orig: assumed.fetch never returns. staged: ConnectionError
      after ORACLE_TRIES x ORACLE_TIMEOUT; sync.py waits and retries instead of exiting.
  F2  shared hook work dir: orig: rules.WORK is the same for state/ and state-tip/.
  F2b hook hang: orig: run_hooks never returns. staged: VerifierError after HOOK_TIMEOUT.
  F2c hook crash/empty output: orig: RuleFail (sync exits: a halt on a valid block).
      staged: VerifierError (sync retries the window VERIFIER_RETRIES times).
  F2d hook files: orig: every window's .tx/.ctx/.json stay (2.2 GB after 10k blocks).
  F3a follow's roots.txt has a half-written last line: orig: ValueError (crash).
  F3b genesis instance without ironwood_roots.txt: orig: every Ironwood anchor SKIPPED, even
      an invalid one. staged: checked against follow's committed roots.
  F3c stale cache / follow behind: orig: a valid block is rejected ("not a root of an earlier
      block") because the max height in the cache comes from a branch follow abandoned.
      staged: SKIPPED (follow behind), then PASS once follow has the root.
usage: python3 test_fixes.py
"""
import json, os, shutil, signal, subprocess, sys, tempfile, textwrap, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIVE = HERE.parents[1]                 # bend-zcash/fullnode
PY = sys.executable
RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}", flush=True)


def tree(kind):
    """<tmp>/fullnode (kind's rules/sync/assumed + live headers/store) and <tmp>/follow/{bin,state}."""
    t = Path(tempfile.mkdtemp(prefix=f"fix_{kind}_"))
    fn = t / "fullnode"
    (fn / "state/hdr").mkdir(parents=True)
    for f in ("rules.py", "sync.py", "assumed.py"):
        shutil.copy(HERE / kind / f, fn / f)
    for f in ("headers.py", "store.py"):
        shutil.copy(LIVE / f, fn / f)
    (fn / "hooks").mkdir()
    (t / "node/follow/bin").mkdir(parents=True)
    (t / "node/follow/state").mkdir(parents=True)
    return t


def run(t, code, env=None, timeout=30):
    """Run `code` in tree t; returns (status, output): status 'ok', 'raised', or 'HUNG'."""
    e = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", **(env or {}))
    p = subprocess.Popen([PY, "-c", textwrap.dedent(code)], cwd=t / "fullnode", env=e, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        return "HUNG", f"no result after {timeout} s"
    return ("ok" if p.returncode == 0 else "raised"), out.strip().splitlines()[-1] if out.strip() else ""


def exe(path, body):
    path.write_text("#!/bin/sh\n" + body + "\n")
    path.chmod(0o755)


# ---------------------------------------------------------------- F1
def f1():
    for kind in ("orig", "staged"):
        t = tree(kind)
        exe(t / "node/follow/bin/follow-lwd", "sleep 600")
        t0 = time.time()
        st, out = run(t, """
            import sys; sys.path.insert(0, ".")
            import assumed
            try:
                assumed.fetch(["ab" * 32], log=lambda *a: None)
            except ConnectionError as e:
                print("ConnectionError", e); sys.exit(3)
            """, env={"ZEBEND_ORACLE_TIMEOUT": "2", "ZEBEND_ORACLE_TRIES": "2"}, timeout=40)
        if kind == "orig":
            check("F1 orig: oracle hang blocks assumed.fetch (problem reproduced)", st == "HUNG", out)
        else:
            check("F1 staged: oracle hang -> ConnectionError after the retries", st == "raised" and "ConnectionError" in out,
                  f"{out} ({time.time() - t0:.0f} s)")
        shutil.rmtree(t)


# ---------------------------------------------------------------- F2
HOOK_SNIPPET = """
    import sys, struct; sys.path.insert(0, ".")
    import rules
    class St:
        def utxo(self, txid, vout): return (1000, b"\\x51", 1, False)
    def window(h):
        tx = bytes(10)
        raw = bytes(1487) + b"\\x01" + tx
        t = {"i": 0, "txid": "aa" * 32, "v": 5, "br": "77190ad9", "ins": [("bb" * 32, 0, 0)], "outs": [], "js": [],
             "sap": None, "orch": None, "iw": None, "cb": False, "size": 10}
        return [{"height": h, "txs": [t]}], {h: raw}
    import os
    for h in (100, 101):
        b, raw = window(h)
        try:
            rules.run_hooks(b, St(), raw, print)
        except Exception as e:
            print(type(e).__name__, "VerifierError" if type(e).__name__ == "VerifierError" else "", e); sys.exit(3)
    d = rules.WORK / "hooks" / "transparent"
    print("files", len([p for p in d.iterdir() if p.suffix in (".tx", ".ctx", ".json")]))
    """


def f2():
    for kind in ("orig", "staged"):
        t = tree(kind)
        st, out = run(t, """
            import sys, os; sys.path.insert(0, ".")
            os.environ["ZEBEND_STATE"] = "/x/state"; import importlib, rules; a = rules.WORK
            os.environ["ZEBEND_STATE"] = "/x/state-tip"; importlib.reload(rules); b = rules.WORK
            print("same" if a == b else "distinct", a, b)
            """)
        if kind == "orig":
            check("F2 orig: genesis and tip instances share the hook work dir (problem reproduced)", out.startswith("same"), out)
        else:
            check("F2 staged: per-instance hook work dir", out.startswith("distinct"), out)
        # F2b: hanging hook
        exe(t / "node/hooks/transparent", "sleep 600")
        st, out = run(t, HOOK_SNIPPET, env={"ZEBEND_HOOK_TIMEOUT": "2"}, timeout=20)
        if kind == "orig":
            check("F2b orig: a hanging hook blocks the window forever (problem reproduced)", st == "HUNG", out)
        else:
            check("F2b staged: hanging hook -> VerifierError (retryable)", "VerifierError" in out, out)
        # F2c: crashing hook (no output)
        exe(t / "node/hooks/transparent", "exit 1")
        st, out = run(t, HOOK_SNIPPET)
        if kind == "orig":
            check("F2c orig: hook crash = RuleFail, i.e. the node halts on a valid block (problem reproduced)",
                  out.startswith("RuleFail"), out)
        else:
            check("F2c staged: hook crash = VerifierError (sync retries the window)", "VerifierError" in out, out)
        # F2d: files kept per window
        exe(t / "node/hooks/transparent",
            'while read p; do h=$(basename "$p" | cut -d_ -f1); i=$(basename "$p" | cut -d_ -f2); echo "verdict $h $i PASS"; done < "$1"')
        st, out = run(t, HOOK_SNIPPET)
        n = int(out.split()[-1]) if out.startswith("files") else -1
        if kind == "orig":
            check("F2d orig: hook files of every window are kept (problem reproduced)", n == 6, out)
        else:
            check("F2d staged: only the current window's hook files exist", n == 3, out)
        shutil.rmtree(t)


# ---------------------------------------------------------------- F3
ANCHOR_SNIPPET = """
    import sys, json; sys.path.insert(0, ".")
    import sync
    from pathlib import Path
    class St: dir = Path("{state}")
    class Idx:
        n = 10**7
        def display(self, h): return "%064x" % h
    full = [{{"height": h, "txs": [{{"txid": "cc" * 32, "anchors": {{"ironwood": [a], "orchard": [], "sapling": [], "sprout": []}}}}]}}
            for h, a in {blocks}]
    try:
        try:
            sync.anchor_checks(full, St(), print, Idx())
        except TypeError:
            sync.anchor_checks(full, St(), print)
    except sync.Fail as e:
        print("Fail", e); sys.exit(3)
    except Exception as e:
        print("CRASH", type(e).__name__, e); sys.exit(4)
    """


def follow_state(t, roots, tip, extra=b""):
    data = "".join(f"{h} 1 {r}\n" for h, r in roots).encode()
    (t / "node/follow/state/roots.txt").write_bytes(data + extra)
    (t / "node/follow/state/tip.json").write_text(json.dumps({"height": tip, "hash": "%064x" % tip, "roots_bytes": len(data)}))


def R(h, branch="a"):
    return (branch * 2 + "%062x" % h)[:64]


def f3():
    for kind in ("orig", "staged"):
        # (a) half-written last line in follow's roots.txt; the snapshot lacks the anchor
        t = tree(kind)
        sd = t / "state"
        sd.mkdir()
        (sd / "ironwood_roots.txt").write_text("".join(f"{h} 1 {R(h)}\n" for h in range(100, 103)))
        follow_state(t, [(h, R(h)) for h in range(100, 108)], 107, extra=b"108 1")
        st, out = run(t, ANCHOR_SNIPPET.format(state=sd, blocks=[(108, R(105))]))
        if kind == "orig":
            check("F3a orig: half-written roots.txt line crashes the anchor check (problem reproduced)", "CRASH" in out, out)
        else:
            check("F3a staged: only follow's committed roots are read; valid anchor PASS", st == "ok" and "1/1 PASS" in out, out)
        shutil.rmtree(t)
        # (b) no snapshot (genesis instance): an INVALID anchor
        t = tree(kind)
        sd = t / "state"
        sd.mkdir()
        follow_state(t, [(h, R(h)) for h in range(100, 108)], 107)
        st, out = run(t, ANCHOR_SNIPPET.format(state=sd, blocks=[(106, R(103)), (107, "ee" * 32)]))
        if kind == "orig":
            check("F3b orig: genesis instance SKIPs every Ironwood anchor, even an invalid one (problem reproduced)",
                  st == "ok" and "SKIPPED" in out and "ironwood 2" in out, out)
        else:
            check("F3b staged: genesis instance checks Ironwood anchors against follow's roots (invalid one fails)",
                  out.startswith("Fail"), out)
        shutil.rmtree(t)
        # (c) stale cache: the snapshot holds roots of an abandoned branch up to 110; follow rolled
        #     back to 104 and has not yet computed the new branch's root of block 106
        t = tree(kind)
        sd = t / "state"
        sd.mkdir()
        (sd / "ironwood_roots.txt").write_text("".join(f"{h} 1 {R(h, 'b' if h >= 105 else 'a')}\n" for h in range(100, 111)))
        follow_state(t, [(h, R(h)) for h in range(100, 105)], 104)
        st, out = run(t, ANCHOR_SNIPPET.format(state=sd, blocks=[(108, R(106, "c"))]))
        if kind == "orig":
            check("F3c orig: valid block rejected while follow is behind on a new branch (problem reproduced)",
                  out.startswith("Fail"), out)
        else:
            check("F3c staged: follow behind -> SKIPPED (reported), no false reject", st == "ok" and "follow behind" in out, out)
            follow_state(t, [(h, R(h)) for h in range(100, 105)] + [(105, R(105, "c")), (106, R(106, "c")), (107, R(107, "c"))], 107)
            st, out = run(t, ANCHOR_SNIPPET.format(state=sd, blocks=[(108, R(106, "c"))]))
            check("F3c staged: once follow has the root, the anchor PASSes", st == "ok" and "1/1 PASS" in out, out)
        shutil.rmtree(t)


if __name__ == "__main__":
    for f in (f1, f2, f3):
        try:
            f()
        except Exception as e:
            check(f.__name__, False, repr(e))
    bad = [n for n, ok in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} PASS" + (f"; FAIL: {bad}" if bad else ""))
    sys.exit(1 if bad else 0)
