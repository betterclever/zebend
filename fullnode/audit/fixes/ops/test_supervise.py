#!/usr/bin/env python3
"""Tests for supervise.py, each reproducing one of the Oct 27 incidents on throwaway processes.

  1 crash        a daemon that dies (exit 3) is restarted; the exit code and last log lines are
                 recorded in events.jsonl; an alert is raised
  2 stall        committed tip (chain.sqlite meta 'tip') frozen while the verified headers grow
  3 stopped      a daemon left in SIGSTOP is reported (and resumed with resume_stopped)
  4 orphan       a CPU-burning process under the repo, reparented to launchd/init, is reported
  5 interpreter  the executable a daemon runs is deleted under it (brew upgrade)
  6 code         a watched source file is edited while the daemon runs
  7 rotation     a log over the limit is rotated; the daemon keeps appending to the new file
  8 adopt        a daemon already running outside the supervisor is adopted, not duplicated
  9 disk/mem     low free disk / memory alarms (probes injected)
usage: python3 test_supervise.py    (macOS or Linux; ~1 min; only touches a temp directory)
"""
import json, os, shutil, signal, sqlite3, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import supervise as SV

PY = os.path.realpath(sys.executable)
RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}", flush=True)


def mk(tmp, services, **g):
    conf = {"global": dict({"python": PY, "root": str(tmp), "repo": str(tmp), "tick": 1, "notify": False,
                            "alert_repeat_min": 0, "stopped_s": 1, "orphan_min": 0, "orphan_cpu_pct": 50,
                            "headers": str(tmp / "hashes.bin")}, **g),
            "services": services}
    p = tmp / "conf.json"
    p.write_text(json.dumps(conf))
    return SV.Supervisor(p)


def ticks(sup, n, sleep=1.0):
    for _ in range(n):
        sup.tick()
        time.sleep(sleep)


def alerts(sup, prefix):
    p = sup.dir / "alerts.jsonl"
    return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else [] and prefix


def has_alert(sup, prefix):
    return [a for a in alerts(sup, prefix) if a["key"].startswith(prefix)]


def events(sup):
    p = sup.dir / "events.jsonl"
    return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []


def script(tmp, name, body):
    p = tmp / name
    p.write_text(body)
    return str(p)


def stop_all(sup):
    for s in sup.services:
        if s.pid:
            try:
                os.kill(s.pid, signal.SIGCONT)
                os.kill(s.pid, signal.SIGKILL)
            except OSError:
                pass
        if s.proc:
            s.proc.wait()


def t_crash(tmp):
    sc = script(tmp, "crash.py", "import time,sys\nprint('working', flush=True)\ntime.sleep(1)\nprint('FAIL: hook sapling: unsupported-joinsplit', flush=True)\nsys.exit(3)\n")
    sup = mk(tmp, [{"name": "crashy", "argv": ["{python}", "-u", sc], "log": "crashy.log"}])
    SV.BACKOFF_MIN = 1
    for s in sup.services:
        s.backoff = 1
    ticks(sup, 8)
    ev = events(sup)
    exits = [e for e in ev if e.get("event") == "exit"]
    starts = [e for e in ev if e.get("event") == "start"]
    check("crash: exit code 3 recorded", any(e.get("exit") == 3 for e in exits), f"{len(exits)} exits")
    check("crash: last log line recorded", any("unsupported-joinsplit" in " ".join(e.get("last_log", [])) for e in exits))
    check("crash: restarted", len(starts) >= 2, f"{len(starts)} starts")
    check("crash: alert raised", bool(has_alert(sup, "exit:crashy")))
    stop_all(sup)


def mkdb(path, tip):
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT)")
    db.execute("INSERT OR REPLACE INTO meta VALUES('tip', ?)", (json.dumps({"height": tip, "hash": "00"}),))
    db.commit()
    db.close()


def t_stall(tmp):
    db = tmp / "chain.sqlite"
    mkdb(db, 100)
    (tmp / "hashes.bin").write_bytes(bytes(32 * 101))
    sc = script(tmp, "idle.py", "import time\nwhile True: time.sleep(1)\n")
    sup = mk(tmp, [{"name": "tipsync", "argv": ["{python}", "-u", sc], "log": "tipsync.log",
                    "progress": {"db": str(db), "headers": str(tmp / "hashes.bin"), "stall_min": 0.05, "behind_min": 2}}],
             headers_stall_min=0.05)
    ticks(sup, 2)
    check("stall: no alert while not behind", not has_alert(sup, "stall:"))
    (tmp / "hashes.bin").write_bytes(bytes(32 * 106))  # the network moved on by 5 blocks
    ticks(sup, 5)
    check("stall: alert when tip frozen and headers ahead", bool(has_alert(sup, "stall:tipsync")))
    mkdb(db, 105)
    n = len(has_alert(sup, "stall:"))
    sup.last_alert.clear()
    ticks(sup, 1)
    check("stall: no new alert once the tip advances", len(has_alert(sup, "stall:")) == n)
    ticks(sup, 5)
    check("headers: alert when the header chain stops growing", bool(has_alert(sup, "headers")))
    stop_all(sup)


def t_stopped(tmp):
    sc = script(tmp, "idle2.py", "import time\nwhile True: time.sleep(1)\n")
    sup = mk(tmp, [{"name": "susp", "argv": ["{python}", "-u", sc], "log": "susp.log"}], resume_stopped=True)
    ticks(sup, 1)
    pid = sup.services[0].pid
    os.kill(pid, signal.SIGSTOP)
    ticks(sup, 4)
    check("stopped: SIGSTOPped daemon reported", bool(has_alert(sup, "stopped:susp")))
    st = SV.ps_table()[pid]["stat"]
    check("stopped: resumed with SIGCONT (resume_stopped)", not st.startswith("T"), f"state now {st}")
    stop_all(sup)


def t_orphan(tmp):
    # double fork so the burner is reparented to launchd / init (ppid 1)
    burner = script(tmp, "burn.py", "import time\nt=time.time()\nwhile time.time()-t<30: pass\n")
    subprocess.run([PY, "-c", f"import subprocess,sys; subprocess.Popen([{PY!r}, {burner!r}], start_new_session=True)"])
    sup = mk(tmp, [])
    time.sleep(3)
    ticks(sup, 2)
    hits = has_alert(sup, "orphan:")
    check("orphan: CPU-burning orphan under the repo reported", bool(hits), hits[0]["msg"][:80] if hits else "")
    for a in hits:
        try:
            os.kill(int(a["key"].split(":")[1]), signal.SIGKILL)
        except OSError:
            pass


def t_interp(tmp):
    # A framework Python re-execs into Python.app, so `ps comm` shows the Cellar path (that is
    # what the live daemons show: .../Cellar/python@3.15/3.15.0/...). Here a copied plain
    # executable stands in for the Cellar binary that a brew upgrade deletes.
    exe = tmp / "cellar_binary"
    (tmp / "s.c").write_text("#include <unistd.h>\nint main(){sleep(1000);return 0;}\n")
    if not shutil.which("cc") or subprocess.run(["cc", "-o", str(exe), str(tmp / "s.c")]).returncode:
        check("interpreter: SKIPPED (no C compiler to build a stand-in binary)", False)
        return
    sup = mk(tmp, [{"name": "oldpy", "argv": [str(exe), "1000"], "log": "oldpy.log"}])
    ticks(sup, 2)
    started = sup.services[0].pid is not None and sup.services[0].proc.poll() is None
    check("interpreter: no alert while the executable exists", started and not has_alert(sup, "interp:"))
    exe.unlink()  # "brew upgrade" removes the Cellar under the running daemon
    ticks(sup, 2)
    check("interpreter: deleted executable under a running daemon reported", bool(has_alert(sup, "interp:oldpy")))
    stop_all(sup)
    # and on this machine right now: which processes run from a deleted interpreter?
    stale = [(pid, r["comm"]) for pid, r in SV.ps_table().items() if "/Cellar/python" in r["comm"] and SV.exe_missing(pid, r)]
    print("      processes on this machine running a deleted Cellar interpreter:", [(p, r["args"][:60]) for p, r in
          SV.ps_table().items() if (p, r["comm"]) in stale])


def t_code(tmp):
    src = tmp / "code" / "rules.py"
    src.parent.mkdir()
    src.write_text("x = 1\n")
    sc = script(tmp, "idle4.py", "import time\nwhile True: time.sleep(1)\n")
    sup = mk(tmp, [{"name": "coded", "argv": ["{python}", "-u", sc], "log": "coded.log", "watch": ["code/*.py"]}])
    ticks(sup, 2)
    check("code: no alert before an edit", not has_alert(sup, "code:"))
    time.sleep(0.01)
    src.write_text("x = 2  # an agent edits a live file\n")
    ticks(sup, 1)
    check("code: edit of a watched file while running reported", bool(has_alert(sup, "code:coded")))
    stop_all(sup)


def t_rotate(tmp):
    sc = script(tmp, "chatty.py", "import time\ni=0\nwhile True:\n    print('x'*200, i, flush=True); i+=1\n    time.sleep(0.001)\n")
    sup = mk(tmp, [{"name": "chatty", "argv": ["{python}", "-u", sc], "log": "chatty.log"}], log_max_mb=0.05, log_keep=3)
    ticks(sup, 6)
    log = tmp / "chatty.log"
    r1 = log.with_name("chatty.log.1")
    size_ok = log.stat().st_size < 4 * 0.05 * 2 ** 20
    check("rotation: rotated copies exist", r1.exists() and log.with_name("chatty.log.2").exists())
    check("rotation: live log stays bounded", size_ok, f"{log.stat().st_size} B")
    head = log.read_bytes()[:64]
    check("rotation: writer continues at the start of the truncated file (no NUL hole)", b"\0" not in head)
    check("rotation: at most log_keep copies", not log.with_name("chatty.log.4").exists())
    stop_all(sup)


def t_adopt(tmp):
    sc = script(tmp, "already.py", "import time\nwhile True: time.sleep(1)\n")
    ext = subprocess.Popen([PY, "-u", sc, "--every", "60"], cwd=tmp)
    time.sleep(1)
    sup = mk(tmp, [{"name": "live", "cwd": str(tmp), "argv": ["{python}", "-u", sc, "--every", "60"], "log": "live.log"}])
    ticks(sup, 2)
    s = sup.services[0]
    check("adopt: running daemon adopted, no second copy", s.adopted and s.pid == ext.pid, f"pid {s.pid} vs {ext.pid}")
    ext.kill()
    ext.wait()
    ticks(sup, 3)
    check("adopt: restarted under the supervisor once it died", s.pid is not None and not s.adopted)
    stop_all(sup)


def t_sys(tmp):
    sup = mk(tmp, [], disk_min_gb=10, mem_min_free_pct=10)
    sup.fns["disk"] = lambda p: shutil._ntuple_diskusage(100e9, 95e9, 5e9)
    sup.fns["mem"] = lambda: 4
    ticks(sup, 1, 0)
    check("disk: low free disk reported", bool(has_alert(sup, "disk:")))
    check("mem: low free memory reported", bool(has_alert(sup, "mem")))


if __name__ == "__main__":
    for t in (t_crash, t_stall, t_stopped, t_orphan, t_interp, t_code, t_rotate, t_adopt, t_sys):
        tmp = Path(tempfile.mkdtemp(prefix=f"sv_{t.__name__}_"))
        try:
            t(tmp)
        except Exception as e:
            check(t.__name__, False, f"exception {e!r}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    bad = [n for n, ok in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} PASS" + (f"; FAIL: {bad}" if bad else ""))
    sys.exit(1 if bad else 0)
