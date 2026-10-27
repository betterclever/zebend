#!/usr/bin/env python3
"""zebend supervisor: one small process that keeps the node's daemons alive and says when
something is wrong. Standard library only; meant to run as ONE launchd user agent
(com.zebend.supervisor.plist, KeepAlive) with the pinned interpreter (make_venv.sh).

What it does, every --tick seconds (default 15):
  * starts each configured service (argv, cwd, env) with the pinned interpreter, stdout+stderr
    appended to its log file (O_APPEND, so rotation by copy+truncate is safe);
  * ADOPTS a service that is already running outside the supervisor (matched by its command
    line and cwd) instead of starting a second copy; adopted processes are watched, and
    restarted under the supervisor only once they have exited;
  * records every start / exit (exit code or signal, runtime, last log lines) in events.jsonl;
  * restarts dead services with exponential backoff (5 s .. 5 min, reset after 10 min up);
    alerts on a crash loop (> 5 exits in 30 min);
  * STALL alarm: a service's committed tip (meta 'tip' in its chain.sqlite, read-only) has not
    advanced for `stall_min` minutes while the network has moved on (verified headers above it);
    and a HEADERS alarm when the verified header chain itself has not grown for `headers_stall_min`;
  * STOPPED alarm: a watched process in state T (SIGSTOP / ^Z) for > 60 s; `resume_stopped`
    sends SIGCONT (supervised and adopted services only);
  * ORPHAN alarm: a process running a binary under the repo, reparented to launchd (ppid 1),
    not a service, above `orphan_cpu_pct` CPU for `orphan_min` minutes. Killed only if it
    matches `orphan_kill` regexes (never by default);
  * INTERPRETER alarm: a watched process whose executable no longer exists on disk (a brew
    upgrade removed the Cellar it runs from: any lazy import or sys.executable spawn will fail);
  * CODE alarm: a file listed in a service's `watch` globs changed while it was running (a live
    file edited under a daemon);
  * RSS per service (`max_rss_gb`: alert, and restart if `restart_on_rss`), free disk
    (`disk_min_gb` per path), free memory (`mem_min_free_pct`);
  * rotates every service log above `log_max_mb` (copy to .1 .. .N, then truncate in place).
Alerts go to alerts.jsonl, the supervisor log, a macOS notification, and optionally a webhook
(`ZEBEND_ALERT_WEBHOOK`: POST of the JSON line); the same alert repeats at most every 30 min.

usage: supervise.py run CONFIG.json        (foreground; what launchd runs)
       supervise.py status CONFIG.json     (table of services from the status file)
       supervise.py check CONFIG.json      (validate the config + interpreter, then exit)
"""
import fnmatch, glob, hashlib, json, os, re, shutil, signal, sqlite3, subprocess, sys, time
import urllib.request
from pathlib import Path

DEF = {"tick": 15, "disk_min_gb": 40, "mem_min_free_pct": 8, "log_max_mb": 64, "log_keep": 5,
       "orphan_cpu_pct": 90, "orphan_min": 30, "orphan_kill": [], "alert_repeat_min": 30,
       "headers_stall_min": 30, "resume_stopped": False, "notify": True, "stopped_s": 60}
BACKOFF_MIN, BACKOFF_MAX, RESET_AFTER = 5, 300, 600


def now():
    return time.time()


def ts():
    return time.strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------------ process table (ps)

def ps_table():
    """pid -> {ppid, stat, cpu, rss_kb, etime_s, comm, args}. One `ps` call per tick."""
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,stat=,%cpu=,rss=,etime=,comm=", "-ww"],
                         capture_output=True, text=True, timeout=30).stdout
    args = subprocess.run(["ps", "-A", "-o", "pid=,args=", "-ww"], capture_output=True, text=True, timeout=30).stdout
    amap = {}
    for line in args.splitlines():
        p = line.strip().split(None, 1)
        if p and p[0].isdigit():
            amap[int(p[0])] = p[1] if len(p) > 1 else ""
    t = {}
    for line in out.splitlines():
        p = line.split(None, 6)
        if len(p) < 7 or not p[0].isdigit():
            continue
        t[int(p[0])] = {"ppid": int(p[1]), "stat": p[2], "cpu": float(p[3]), "rss_kb": int(p[4]),
                        "etime_s": etime_s(p[5]), "comm": p[6], "args": amap.get(int(p[0]), "")}
    return t


def etime_s(s):
    d = 0
    if "-" in s:
        dd, s = s.split("-", 1)
        d = int(dd)
    parts = [int(x) for x in s.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    return d * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]


def proc_cwd(pid):
    try:
        out = subprocess.run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True,
                             timeout=15).stdout
        for l in out.splitlines():
            if l.startswith("n"):
                return l[1:]
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        return os.readlink(f"/proc/{pid}/cwd")  # Linux (tests)
    except OSError:
        return None


def exe_path(pid, row):
    """The executable a process runs. macOS `ps comm` gives the full path of the image."""
    try:
        return os.readlink(f"/proc/{pid}/exe")  # Linux
    except OSError:
        return row["comm"] if row["comm"].startswith("/") else None


def exe_missing(pid, row):
    p = exe_path(pid, row)
    if p is None:
        return False
    if p.endswith(" (deleted)"):
        return True
    return not os.path.exists(p)


def tree_rss_kb(table, root):
    kids = {}
    for pid, r in table.items():
        kids.setdefault(r["ppid"], []).append(pid)
    tot, stack = 0, [root]
    while stack:
        p = stack.pop()
        if p in table:
            tot += table[p]["rss_kb"]
            stack += kids.get(p, [])
    return tot


# ------------------------------------------------------------------ probes

def sqlite_tip(db):
    try:
        c = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=5)
        try:
            r = c.execute("SELECT v FROM meta WHERE k='tip'").fetchone()
        finally:
            c.close()
        return json.loads(r[0])["height"] if r else None
    except (sqlite3.Error, ValueError, KeyError, TypeError):
        return None


def headers_height(hashes_bin):
    try:
        return os.path.getsize(hashes_bin) // 32 - 1
    except OSError:
        return None


def mem_free_pct():
    try:
        out = subprocess.run(["memory_pressure", "-Q"], capture_output=True, text=True, timeout=15).stdout
        m = re.search(r"free percentage:\s*(\d+)%", out)
        if m:
            return int(m.group(1))
    except (OSError, subprocess.SubprocessError):
        pass
    try:  # Linux
        info = dict(l.split(":", 1) for l in open("/proc/meminfo"))
        return int(100 * int(info["MemAvailable"].split()[0]) / int(info["MemTotal"].split()[0]))
    except (OSError, KeyError, ValueError):
        return None


def files_digest(globs, base):
    h = hashlib.sha256()
    names = []
    for g in globs:
        names += glob.glob(g if os.path.isabs(g) else os.path.join(base, g))
    for n in sorted(set(names)):
        try:
            st = os.stat(n)
            h.update(f"{n}\0{st.st_size}\0{st.st_mtime_ns}\n".encode())
        except OSError:
            h.update(f"{n}\0gone\n".encode())
    return h.hexdigest(), sorted(set(names))


# ------------------------------------------------------------------ supervisor

class Service:
    def __init__(self, cfg, g):
        self.cfg, self.g = cfg, g
        self.name = cfg["name"]
        self.cwd = cfg.get("cwd", g["root"])
        self.log = Path(cfg["log"] if os.path.isabs(cfg["log"]) else os.path.join(g["root"], cfg["log"]))
        self.proc = None          # subprocess.Popen when supervised
        self.pid = None           # supervised or adopted pid
        self.adopted = False
        self.started = 0.0
        self.backoff = BACKOFF_MIN
        self.next_start = 0.0
        self.exits = []           # times of recent exits
        self.digest = None
        self.tip, self.tip_t = None, now()
        self.stopped_since = None

    def argv(self):
        py = self.g["python"]
        return [py if a == "{python}" else a for a in self.cfg["argv"]]

    def adopt_key(self):
        """What identifies this service in `ps args`: cfg 'match', else the argv after the
        interpreter, but only if it names a script (a bare '1000' must never adopt a stranger)."""
        if self.cfg.get("match"):
            return self.cfg["match"]
        tail = self.cfg["argv"][1:]
        if not any(a.endswith(".py") for a in tail):
            return None
        return " ".join(tail)

    def looks_like(self, row):
        k = self.adopt_key()
        if not k:
            return False
        a = row["args"]
        i = a.find(k)
        return i >= 0 and (i + len(k) == len(a) or a[i + len(k)] == " ") and (i == 0 or a[i - 1] == " ")

    def match(self, row, cwd):
        """Does a running process look like this service (adoption)? Same argv tail and cwd."""
        return self.looks_like(row) and (cwd is None or os.path.realpath(cwd) == os.path.realpath(self.cwd))


class Supervisor:
    def __init__(self, conf_path):
        self.conf_path = Path(conf_path)
        c = json.loads(self.conf_path.read_text())
        self.g = dict(DEF, **c.get("global", {}))
        self.g.setdefault("root", str(self.conf_path.parent))
        self.dir = Path(self.g.get("dir", os.path.join(self.g["root"], "supervisor")))
        self.dir.mkdir(parents=True, exist_ok=True)
        self.services = [Service(s, self.g) for s in c["services"] if s.get("enabled", True)]
        self.last_alert = {}
        self.orphan_seen = {}
        self.hdr_n, self.hdr_t = None, now()
        self.stop = False
        self.fns = {"ps": ps_table, "cwd": proc_cwd, "mem": mem_free_pct, "disk": shutil.disk_usage}

    # -------------------------------------------------- output
    def log(self, *a):
        line = ts() + " " + " ".join(str(x) for x in a)
        print(line, flush=True)

    def event(self, **kw):
        kw["ts"] = ts()
        with open(self.dir / "events.jsonl", "a") as f:
            f.write(json.dumps(kw) + "\n")

    def alert(self, key, msg, **kw):
        t = now()
        if t - self.last_alert.get(key, 0) < self.g["alert_repeat_min"] * 60:
            return False
        self.last_alert[key] = t
        rec = dict(kw, ts=ts(), key=key, msg=msg)
        with open(self.dir / "alerts.jsonl", "a") as f:
            f.write(json.dumps(rec) + "\n")
        self.log("ALERT", key, msg)
        if self.g["notify"] and sys.platform == "darwin":
            try:
                subprocess.run(["osascript", "-e", f'display notification {json.dumps(msg[:200])} with title "zebend: {key}"'],
                               timeout=10, capture_output=True)
            except (OSError, subprocess.SubprocessError):
                pass
        hook = os.environ.get("ZEBEND_ALERT_WEBHOOK") or self.g.get("webhook")
        if hook:
            try:
                urllib.request.urlopen(urllib.request.Request(hook, json.dumps(rec).encode(),
                                                              {"Content-Type": "application/json"}), timeout=10)
            except OSError:
                pass
        return True

    # -------------------------------------------------- lifecycle
    def check_python(self):
        py = self.g["python"]
        if not os.path.isabs(py) or not os.path.exists(py):
            raise SystemExit(f"pinned interpreter {py!r} is not an existing absolute path (run make_venv.sh)")
        want = self.g.get("python_version")
        got = subprocess.run([py, "-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        if want and got != want:
            raise SystemExit(f"pinned interpreter {py} is {got}, config wants {want}")
        return got

    def start(self, s):
        s.log.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(s.log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        env = dict(os.environ)
        env.update({"PYTHONDONTWRITEBYTECODE": "1", "BEND_NO_TELEMETRY": "1", "PYTHONUNBUFFERED": "1"})
        env.update({k: str(v) for k, v in s.cfg.get("env", {}).items()})
        os.write(fd, f"=== {ts()} supervisor: start {' '.join(s.argv())}\n".encode())
        try:
            s.proc = subprocess.Popen(s.argv(), cwd=s.cwd, env=env, stdout=fd, stderr=fd, stdin=subprocess.DEVNULL,
                                      start_new_session=True)
        finally:
            os.close(fd)
        s.pid, s.adopted, s.started = s.proc.pid, False, now()
        s.digest = files_digest(s.cfg.get("watch", []), self.g["root"])[0]
        s.tip_t = now()
        self.event(service=s.name, event="start", pid=s.pid, argv=s.argv())
        self.log(f"started {s.name} pid {s.pid}")

    def tail(self, s, n=8):
        try:
            with open(s.log, "rb") as f:
                f.seek(max(0, os.path.getsize(s.log) - 4096))
                return f.read().decode(errors="replace").splitlines()[-n:]
        except OSError:
            return []

    def reap(self, s, table):
        """Has the service's process gone? Record how it ended."""
        if s.pid is None:
            return
        if s.proc is not None:
            rc = s.proc.poll()
            if rc is None:
                return
            how = {"exit": rc} if rc >= 0 else {"signal": signal.Signals(-rc).name if -rc in signal.Signals._value2member_map_ else -rc}
        else:
            if s.pid in table:
                return
            how = {"exit": "unknown (adopted process)"}
        up = now() - s.started
        last = self.tail(s)
        self.event(service=s.name, event="exit", pid=s.pid, runtime_s=round(up), last_log=last, **how)
        self.log(f"{s.name} pid {s.pid} ended {how} after {up:.0f} s; last log: {last[-1:] }")
        s.exits = [t for t in s.exits if now() - t < 1800] + [now()]
        if up > RESET_AFTER:
            s.backoff = BACKOFF_MIN
        s.next_start = now() + s.backoff
        s.backoff = min(BACKOFF_MAX, s.backoff * 2)
        s.proc, s.pid = None, None
        bad = how.get("exit") not in (0,)
        if bad:
            self.alert(f"exit:{s.name}", f"{s.name} exited {how}; last log: {' | '.join(last[-3:])}", service=s.name)
        if len(s.exits) > 5:
            self.alert(f"crashloop:{s.name}", f"{s.name}: {len(s.exits)} exits in 30 min (backoff {s.backoff} s)")

    def adopt(self, s, table):
        mine = {x.pid for x in self.services if x.pid}
        for pid, row in table.items():
            if pid in mine or pid == os.getpid():
                continue
            if s.looks_like(row) and s.match(row, self.fns["cwd"](pid)):
                s.pid, s.adopted, s.started, s.proc = pid, True, now() - row["etime_s"], None
                s.digest = files_digest(s.cfg.get("watch", []), self.g["root"])[0]
                self.event(service=s.name, event="adopt", pid=pid, args=row["args"])
                self.log(f"adopted running {s.name} pid {pid}")
                return True
        return False

    # -------------------------------------------------- checks
    def check_service(self, s, table):
        if s.pid is None:
            if not self.adopt(s, table) and s.cfg.get("restart", "always") != "never" and now() >= s.next_start:
                self.start(s)
            return
        row = table.get(s.pid)
        if row is None:
            return
        # stopped (SIGSTOP / ^Z): any T in the tree's main process
        if row["stat"].startswith("T"):
            s.stopped_since = s.stopped_since or now()
            if now() - s.stopped_since > self.g["stopped_s"]:
                self.alert(f"stopped:{s.name}", f"{s.name} pid {s.pid} is STOPPED (state {row['stat']}) for "
                           f"{now() - s.stopped_since:.0f} s", service=s.name)
                if self.g["resume_stopped"]:
                    os.kill(s.pid, signal.SIGCONT)
                    self.event(service=s.name, event="sigcont", pid=s.pid)
        else:
            s.stopped_since = None
        if exe_missing(s.pid, row):
            self.alert(f"interp:{s.name}", f"{s.name} pid {s.pid} runs an executable that no longer exists on disk "
                       f"({exe_path(s.pid, row)}): restart it in a controlled way", service=s.name)
        rss = tree_rss_kb(table, s.pid) / 2 ** 20
        lim = s.cfg.get("max_rss_gb")
        if lim and rss > lim:
            self.alert(f"rss:{s.name}", f"{s.name} RSS {rss:.1f} GB > {lim} GB", service=s.name)
            if s.cfg.get("restart_on_rss"):
                self.terminate(s, "rss")
        if s.cfg.get("watch"):
            d, names = files_digest(s.cfg["watch"], self.g["root"])
            if s.digest and d != s.digest:
                self.alert(f"code:{s.name}", f"code watched by {s.name} changed on disk while it runs "
                           f"({len(names)} files): restart it deliberately or revert the edit", service=s.name)
        p = s.cfg.get("progress")
        if p:
            self.check_progress(s, p)

    def check_progress(self, s, p):
        tip = sqlite_tip(p["db"])
        net = headers_height(p["headers"]) if p.get("headers") else None
        if tip is None:
            return
        if s.tip is None or tip > s.tip:
            s.tip, s.tip_t = tip, now()
            return
        if tip < s.tip:  # rollback (reorg) is progress too
            s.tip, s.tip_t = tip, now()
            return
        idle = (now() - s.tip_t) / 60
        behind = (net - tip) if net is not None else None
        if idle >= p.get("stall_min", 20) and (behind is None or behind >= p.get("behind_min", 2)):
            self.alert(f"stall:{s.name}", f"{s.name}: committed tip {tip} unchanged for {idle:.0f} min while the "
                       f"verified headers are at {net} ({behind} blocks ahead); last log: "
                       f"{' | '.join(self.tail(s, 3))}", service=s.name, tip=tip, net=net)

    def check_headers(self):
        hb = self.g.get("headers")
        if not hb:
            return
        n = headers_height(hb)
        if n is None:
            return
        if self.hdr_n is None or n != self.hdr_n:
            self.hdr_n, self.hdr_t = n, now()
            return
        idle = (now() - self.hdr_t) / 60
        if idle >= self.g["headers_stall_min"]:
            self.alert("headers", f"verified header chain stuck at {n} for {idle:.0f} min (tiphdr / live.py / peers?)")

    def check_orphans(self, table):
        mine = set()
        for s in self.services:
            if s.pid:
                stack = [s.pid]
                while stack:
                    p = stack.pop()
                    mine.add(p)
                    stack += [q for q, r in table.items() if r["ppid"] == p]
        repo = self.g.get("repo", self.g["root"])
        seen = {}
        for pid, r in table.items():
            if pid in mine or r["ppid"] != 1 or repo not in r["args"] or r["cpu"] < self.g["orphan_cpu_pct"]:
                continue
            first = self.orphan_seen.get(pid, now())
            seen[pid] = first
            mins = (now() - first) / 60
            if mins >= self.g["orphan_min"]:
                killed = False
                if any(re.search(rx, r["args"]) for rx in self.g["orphan_kill"]):
                    try:
                        os.kill(pid, signal.SIGTERM)
                        killed = True
                        self.event(event="orphan_kill", pid=pid, args=r["args"])
                    except OSError:
                        pass
                self.alert(f"orphan:{pid}", f"orphan pid {pid} at {r['cpu']:.0f}% CPU for {mins:.0f}+ min "
                           f"(up {r['etime_s'] // 60} min): {r['args'][:160]}{' (SIGTERM sent)' if killed else ''}")
        self.orphan_seen = seen

    def check_system(self):
        for path in self.g.get("disk_paths", [self.g["root"]]):
            try:
                free = self.fns["disk"](path).free / 1e9
            except OSError:
                continue
            if free < self.g["disk_min_gb"]:
                self.alert(f"disk:{path}", f"free disk at {path}: {free:.0f} GB < {self.g['disk_min_gb']} GB")
        m = self.fns["mem"]()
        if m is not None and m < self.g["mem_min_free_pct"]:
            self.alert("mem", f"free memory {m}% < {self.g['mem_min_free_pct']}%")

    def rotate(self, path):
        lim = self.g["log_max_mb"] * 2 ** 20
        try:
            if path.stat().st_size <= lim:
                return False
        except OSError:
            return False
        keep = self.g["log_keep"]
        for k in range(keep - 1, 0, -1):
            a, b = path.with_name(f"{path.name}.{k}"), path.with_name(f"{path.name}.{k + 1}")
            if a.exists():
                a.replace(b)
        shutil.copyfile(path, path.with_name(path.name + ".1"))
        with open(path, "r+b") as f:  # writers use O_APPEND: they continue at the new end
            f.truncate(0)
        self.event(event="rotate", log=str(path))
        return True

    def terminate(self, s, why):
        if s.pid is None:
            return
        try:
            os.kill(s.pid, signal.SIGTERM)
            self.event(service=s.name, event="sigterm", pid=s.pid, why=why)
        except OSError:
            pass

    # -------------------------------------------------- main loop
    def tick(self):
        table = self.fns["ps"]()
        for s in self.services:
            self.reap(s, table)
        for s in self.services:
            self.check_service(s, table)
        for s in self.services:
            self.rotate(s.log)
        for extra in self.g.get("rotate", []):
            self.rotate(Path(extra))
        self.check_headers()
        self.check_orphans(table)
        self.check_system()
        self.write_status(table)

    def write_status(self, table):
        st = []
        for s in self.services:
            r = table.get(s.pid) if s.pid else None
            st.append({"name": s.name, "pid": s.pid, "adopted": s.adopted, "up_s": round(now() - s.started) if s.pid else 0,
                       "stat": r["stat"] if r else None, "cpu": r["cpu"] if r else None,
                       "rss_gb": round(tree_rss_kb(table, s.pid) / 2 ** 20, 2) if r else None,
                       "tip": s.tip, "tip_age_min": round((now() - s.tip_t) / 60, 1) if s.tip is not None else None,
                       "exits_30min": len([t for t in s.exits if now() - t < 1800])})
        tmp = self.dir / "status.json.tmp"
        tmp.write_text(json.dumps({"ts": ts(), "headers": self.hdr_n, "services": st}, indent=1))
        tmp.replace(self.dir / "status.json")

    def run(self):
        v = self.check_python()
        self.log(f"supervisor up: {len(self.services)} services, python {self.g['python']} ({v})")
        self.event(event="supervisor_start", python=self.g["python"], version=v)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, lambda *_: setattr(self, "stop", True))
        while not self.stop:
            try:
                self.tick()
            except Exception as e:  # the supervisor itself must not die on a probe error
                self.log("tick error:", repr(e))
            for _ in range(int(self.g["tick"])):
                if self.stop:
                    break
                time.sleep(1)
        self.shutdown()

    def shutdown(self):
        """Stop supervised children (not adopted ones): SIGTERM, wait stop_timeout, then SIGKILL."""
        for s in self.services:
            if s.proc is not None and s.proc.poll() is None:
                self.terminate(s, "supervisor shutdown")
        for s in self.services:
            if s.proc is not None:
                try:
                    s.proc.wait(timeout=s.cfg.get("stop_timeout", 120))
                except subprocess.TimeoutExpired:
                    s.proc.kill()
                self.event(service=s.name, event="exit", pid=s.pid, exit=s.proc.returncode, why="supervisor shutdown")
        self.event(event="supervisor_stop")


def status(conf):
    sup = Supervisor(conf)
    p = sup.dir / "status.json"
    if not p.exists():
        print("no status yet")
        return
    d = json.loads(p.read_text())
    print(f"{d['ts']}  verified headers {d['headers']}")
    print(f"{'service':16} {'pid':>7} {'how':8} {'up':>8} {'st':4} {'cpu':>6} {'rssGB':>6} {'tip':>9} {'tipage':>7} {'exits':>5}")
    for s in d["services"]:
        print(f"{s['name']:16} {s['pid'] or '-':>7} {'adopted' if s['adopted'] else 'owned':8} {s['up_s']:>8} "
              f"{s['stat'] or '-':4} {s['cpu'] if s['cpu'] is not None else '-':>6} {s['rss_gb'] or '-':>6} "
              f"{s['tip'] if s['tip'] is not None else '-':>9} {s['tip_age_min'] if s['tip_age_min'] is not None else '-':>7} "
              f"{s['exits_30min']:>5}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("run", "status", "check"):
        sys.exit(__doc__)
    if sys.argv[1] == "run":
        Supervisor(sys.argv[2]).run()
    elif sys.argv[1] == "status":
        status(sys.argv[2])
    else:
        print("python", Supervisor(sys.argv[2]).check_python(), "OK")
