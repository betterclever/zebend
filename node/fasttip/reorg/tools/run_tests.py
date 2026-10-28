#!/usr/bin/env python3
"""Lab driver (reorg tests): for each case build a lab (mklab.sh: APFS clone of a golden state,
copies of the code under test), prepare it (labctl.py), play the scenario (scenario.py), and
compare the final state digest (node/fasttip/tools/digest.py) with a fresh sync of the winning
chain (the reference), or with the state before the scenario for the ignore/refuse cases.

  run_tests.py --root <lab dir> CASE...      (cases: A A_rev A2 A3 B2 B3 C0 C1 C2 C3 E
                                              D_cut D_extra D_switch D_rollback D_reapply)
Inputs under --root: blocks/<h>.bin (real blocks 3532920..3532970), blocks/stale_5714cf.bin (the real
stale 3532945), g944 (state at 3532944, canonical), golden (clone of node/state, tip 3533115),
canon_hdrs_3532380_3533120.bin, ref_digest_957.txt (digest of the reference).
"""
import argparse, json, os, re, signal, subprocess, sys, time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[3]
PY = sys.executable
F = 3532944


def sh(cmd, **k):
    r = subprocess.run(cmd, capture_output=True, text=True, **k)
    if r.returncode:
        raise RuntimeError(f"{cmd}: {r.stdout[-1500:]} {r.stderr[-1500:]}")
    return r.stdout


def digest(state, since):
    out = sh([PY, str(REPO / "node/fasttip/tools/digest.py"), str(state), "--since", str(since)])
    return re.search(r"DIGEST (\w+)", out).group(1), out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("cases", nargs="+")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    res_dir = REPO / "node/fasttip/reorg/results"
    res_dir.mkdir(exist_ok=True)
    ref = re.search(r"DIGEST (\w+)", (root / "ref_digest_957.txt").read_text()).group(1)
    summary = []
    for case in a.cases:
        lab = root / f"lab_{case}"
        node = lab / "node"
        lc = [PY, str(TOOLS / "labctl.py"), "--lab", str(node)]
        gold = "golden" if case == "E" else "g944"
        sh([str(TOOLS / "mklab.sh"), str(lab), str(root / gold), "new"])
        blocks = root / "blocks"
        # ---- preparation (lab state before the scenario)
        if case in ("B2", "C2"):
            sh(lc + ["setidx", str(F + 2), "--gold", str(root / "golden")])
            sh(lc + ["apply", str(F + 1), str(F + 2), "--blocks", str(blocks)])
            sh(lc + ["relabel", str(F + 1), str(F + 2)] + (["--harder", "4"] if case == "C2" else []))
        elif case == "B3":
            sh(lc + ["setidx", str(F + 3), "--gold", str(root / "golden")])
            sh(lc + ["apply", str(F + 1), str(F + 3), "--blocks", str(blocks)])
            sh(lc + ["relabel", str(F + 1), str(F + 3)])
        elif case == "C0":
            sh(lc + ["setidx", str(F + 1), "--gold", str(root / "golden")])
            sh(lc + ["apply", str(F + 1), str(F + 1), "--blocks", str(blocks)])
        elif case in ("C1",):
            sh(lc + ["setidx", str(F + 3), "--gold", str(root / "golden")])
            sh(lc + ["apply", str(F + 1), str(F + 3), "--blocks", str(blocks)])
        elif case == "C3":
            sh(lc + ["setidx", str(F + 1), "--gold", str(root / "golden")])
            sh(lc + ["apply", str(F + 1), str(F + 1), "--blocks", str(blocks)])
        elif case == "E":
            tip = json.loads(sh(["sqlite3", str(node / "state/chain.sqlite"), "SELECT v FROM meta WHERE k='tip'"]))["height"]
            sh(lc + ["cutidx", str(tip)])
            sh(lc + ["relabel", "3532501", str(tip)])
        since = 3532935
        hold_case = case in ("C2", "E")
        before = digest(node / "state", since if case != "E" else 3532400)[0] if hold_case else None
        # ---- scenario
        scen = [PY, "-u", str(TOOLS / "scenario.py"), "--lab", str(node), "--case", case, "--blocks", str(blocks),
                "--stale", str(blocks / "stale_5714cf.bin"), "--canon-hdrs", str(root / "canon_hdrs_3532380_3533120.bin")]
        logf = res_dir / f"{case}.log"
        env = dict(os.environ, BEND_NO_TELEMETRY="1")
        crash = {"D_cut": "after_hashes_cut", "D_extra": "after_extra", "D_switch": "after_switch"}.get(case)
        if crash:
            env["ZEBEND_REORG_CRASH"] = crash
        kill_at = {"D_rollback": r"REORG: tip \d+ is no longer", "D_reapply": r"committed tip 3532950"}.get(case)
        t0 = time.time()
        with open(logf, "w") as lf:
            p = subprocess.Popen(scen, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env, cwd=node)
            killed = None
            for line in p.stdout:
                lf.write(line)
                if kill_at and killed is None and re.search(kill_at, line):
                    os.kill(p.pid, signal.SIGKILL)
                    killed = time.time() - t0
                    lf.write(f"=== run_tests: SIGKILL sent to pid {p.pid} on /{kill_at}/ ===\n")
            rc = p.wait()
            result = None
            if case.startswith("D"):
                lf.write(f"=== run_tests: first run exit {rc} ({'SIGKILL' if rc == -9 else 'not killed'}); restarting ===\n")
                lf.flush()
                r2 = subprocess.run(scen + ["--resume"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                    env=dict(os.environ, BEND_NO_TELEMETRY="1"), cwd=node)
                lf.write(r2.stdout)
                out = r2.stdout
                rc2 = r2.returncode
            else:
                out = logf.read_text()
                rc2 = rc
        m = re.findall(r"^RESULT (.*)$", logf.read_text(), re.M)
        result = json.loads(m[-1]) if m else {"ok": False, "error": "no RESULT line"}
        if hold_case:
            after = digest(node / "state", since if case != "E" else 3532400)[0]
            same, want = after == before, "unchanged"
        else:
            after, dout = digest(node / "state", since)
            (res_dir / f"{case}.digest").write_text(dout)
            same, want = after == ref, "== reference"
        row = {"case": case, "ok": bool(result.get("ok")) and same and (rc2 == 0), "digest": after[:16], "digest " + want: same,
               "first_exit": rc if case.startswith("D") else None,
               **{k: result.get(k) for k in ("announce_to_switch_s", "announce_to_commit_s", "decide_s", "held_s",
                                             "refused_after_s", "resume_to_tip_s", "final_tip", "error", "mock")},
               "stats": {k: v for k, v in (result.get("stats") or {}).items() if k in ("forks seen", "reorgs", "forks ignored",
                                                                                        "reorgs refused", "header fails", "fork probes")}}
        summary.append(row)
        print(json.dumps(row), flush=True)
        with open(res_dir / "summary.jsonl", "a") as f:
            f.write(json.dumps(row) + "\n")
    print("ALL PASS" if all(r["ok"] for r in summary) else "SOME FAILED")


if __name__ == "__main__":
    main()
