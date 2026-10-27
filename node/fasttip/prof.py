"""Per-stage timing of the tip pipeline, by wrapping functions of sync.py / rules.py / store.py /
trees.py / history.py with timers. Wrapping only measures: every wrapped function is called
with the same arguments and its result or exception is passed through unchanged.

install(sync_module, out_path) -> Prof. Each committed window becomes one JSON line in out_path:
  {"first", "last", "t_commit", "stages": {stage: seconds}, "procs": {binary: [seconds, runs]}}
Stages (critical path of one window, wall clock, measured where they run):
  blockdelta, checkpoint, prefetch, trees, anchors, rules_engine, hooks (+ hook:<name>), history,
  resolve, commit (writer round trip), and for fasttip: header (Bend header checks of pushed
  blocks), fetch (inv -> block received).
"""
import functools, json, threading, time

_LOCK = threading.Lock()


class Prof:
    def __init__(self, out):
        self.out = out
        self.cur = {}        # stage -> seconds, for the window being processed
        self.procs = {}      # binary -> [seconds, runs]
        self.windows = []
        self.t_pick = None
        self.on_commit = []  # callbacks(rec), e.g. tipsync's per-block latency log

    def add(self, stage, secs):
        with _LOCK:
            self.cur[stage] = self.cur.get(stage, 0.0) + secs

    def proc(self, name, secs):
        with _LOCK:
            e = self.procs.setdefault(name, [0.0, 0])
            e[0] += secs
            e[1] += 1

    def committed(self, first, last, extra=None):
        with _LOCK:
            rec = {"first": first, "last": last, "t_commit": time.time(),
                   "stages": {k: round(v, 4) for k, v in self.cur.items()},
                   "procs": {k: [round(v[0], 4), v[1]] for k, v in self.procs.items()}}
            if extra:
                rec.update(extra)
            if self.t_pick is not None:
                rec["t_pick"] = self.t_pick
                rec["pick_to_commit"] = round(rec["t_commit"] - self.t_pick, 4)
                self.t_pick = None
            self.cur, self.procs = {}, {}
        self.windows.append(rec)
        for cb in self.on_commit:
            try:
                cb(rec)
            except Exception as e:  # noqa: measurement must never affect the node
                print(f"fasttip prof callback: {e!r}", flush=True)
        if self.out:
            with open(self.out, "a") as f:
                f.write(json.dumps(rec) + "\n")
        return rec


def _wrap(obj, name, stage, prof):
    fn = getattr(obj, name)

    @functools.wraps(fn)
    def w(*a, **k):
        t = time.perf_counter()
        try:
            return fn(*a, **k)
        finally:
            prof.add(stage, time.perf_counter() - t)
    setattr(obj, name, w)


class _SubprocessProxy:
    """Stands in for the `subprocess` module inside one module: run() is timed per binary."""

    def __init__(self, real, prof, prefix=""):
        self._real, self._prof, self._prefix = real, prof, prefix

    def __getattr__(self, k):
        return getattr(self._real, k)

    def run(self, args, *a, **k):
        t = time.perf_counter()
        try:
            return self._real.run(args, *a, **k)
        finally:
            name = str(args[0]).rsplit("/", 1)[-1]
            self._prof.proc(self._prefix + name, time.perf_counter() - t)


def install(sync, out):
    """Wrap the stages of an imported sync module (and the modules it uses)."""
    import rules, store, trees, history, subprocess
    prof = Prof(out)
    _wrap(sync, "run_blockdelta", "blockdelta", prof)
    _wrap(sync, "checkpoint_checks", "checkpoint", prof)
    _wrap(sync, "anchor_checks", "anchors", prof)
    _wrap(store.Store, "prefetch", "prefetch", prof)
    _wrap(store.Store, "resolve_window", "resolve", prof)
    _wrap(trees.Trees, "advance", "trees", prof)
    _wrap(history.History, "run", "history", prof)
    _wrap(rules, "run_rules", "rules_engine", prof)
    _wrap(rules, "run_hooks", "hooks", prof)
    if hasattr(rules, "_exec_hook"):  # patched rules.py: time each hook (subprocess or in-process)
        e0 = rules._exec_hook

        def exec_hook(name, *a, **k):
            t = time.perf_counter()
            try:
                return e0(name, *a, **k)
            finally:
                prof.add(f"hook:{name}", time.perf_counter() - t)
        rules._exec_hook = exec_hook
    for m in (rules, trees, history, sync):
        m.subprocess = _SubprocessProxy(subprocess, prof)
    # t_pick: when sync started reading the window that got blocks (spool or BLOCK_SOURCE): the
    # start of its processing; t_commit - t_pick is the validate + commit time of the window
    p0 = sync.prepare

    def prepare(*a, **k):
        t = time.time()
        r = p0(*a, **k)
        if r and r[0]:
            prof.t_pick = t
        return r
    sync.prepare = prepare

    # commit: Writer.commit(last, ...) .. Writer.result() is the writer round trip; the window is
    # "committed" when result() returns (sync.finish logs "committed tip").
    W = store.Writer
    c0, r0 = W.commit, W.result

    def commit(self, last, last_hash, extra):
        self._ft_last, self._ft_t = last, time.perf_counter()
        return c0(self, last, last_hash, extra)

    def result(self):
        v = r0(self)
        prof.add("commit", time.perf_counter() - getattr(self, "_ft_t", time.perf_counter()))
        prof.committed(None, getattr(self, "_ft_last", None))
        return v
    W.commit, W.result = commit, result
    return prof
