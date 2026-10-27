"""Run Python verifier hooks inside the long-lived node process (rules.HOOK_RUNNER).

A hook is still `hooks/<name> <list file>` (hooks/README); this only avoids starting a Python
interpreter and re-importing its modules for every call (measured: 20 ms for `python3 -c pass`,
~50 ms with the imports the hooks use, per hook per window). The hook's own code runs unchanged:
its source is compiled once (recompiled when the file changes) and executed per call as
`__main__` in fresh globals, with `sys.argv`, `sys.stdout`/`sys.stderr` and `print` bound to that
call only (several hooks run at the same time). Every check is still the Bend binaries the hook
starts. Exit status: 0, the SystemExit code, or 1 with the traceback on stderr (an exception is
reported exactly like a crashing subprocess: no verdict lines -> rules.VerifierError).

Only two shapes are run in-process (anything else falls back to a subprocess):
  * an executable Python file (shebang mentions python), e.g. hooks/orchard;
  * a /bin/sh wrapper whose only command is `exec python3 <file.py> "$@"` (or "$1"),
    e.g. hooks/transparent, hooks/sapling.
"""
import builtins, io, os, re, subprocess, sys, threading, traceback
from pathlib import Path

_CODE = {}   # path -> (mtime_ns, size, code object)
_LOCK = threading.Lock()
STATS = {"inproc": 0, "subprocess": 0}


def target(exe):
    """The Python file a hook executable runs, or None (run it as a subprocess)."""
    try:
        text = Path(exe).read_text(errors="replace")
    except OSError:
        return None
    lines = text.splitlines()
    if not lines:
        return None
    if lines[0].startswith("#!") and "python" in lines[0]:
        return Path(exe)
    if lines[0].strip() not in ("#!/bin/sh", "#!/bin/bash", "#!/bin/zsh"):
        return None
    cmds = [l.strip() for l in lines[1:] if l.strip() and not l.strip().startswith("#")]
    if len(cmds) != 1:
        return None
    m = re.fullmatch(r'exec\s+python3\s+(/\S+\.py)\s+"\$(?:@|1)"', cmds[0])
    return Path(m.group(1)) if m else None


def _code(path):
    st = path.stat()
    with _LOCK:
        c = _CODE.get(path)
        if c and c[0] == st.st_mtime_ns and c[1] == st.st_size:
            return c[2]
        code = compile(path.read_bytes(), str(path), "exec")
        _CODE[path] = (st.st_mtime_ns, st.st_size, code)
        return code


class _Sys:
    """`sys` as one hook call sees it: its own argv / stdout / stderr; the rest is the real sys."""

    def __init__(self, argv, out, err):
        self.argv, self.stdout, self.stderr = argv, out, err

    def __getattr__(self, k):
        return getattr(sys, k)


def _run(path, args):
    out, err = io.StringIO(), io.StringIO()
    wlock = threading.Lock()
    fake = _Sys([str(path)] + [str(a) for a in args], out, err)
    real_import = builtins.__import__

    def _import(name, globals=None, locals=None, fromlist=(), level=0):
        if name == "sys" and level == 0:
            return fake
        return real_import(name, globals, locals, fromlist, level)

    def _print(*a, sep=" ", end="\n", file=None, flush=False):
        f = out if file is None or file is fake.stdout else err if file is fake.stderr else file
        s = (sep if sep is not None else " ").join(map(str, a)) + (end if end is not None else "\n")
        if f is out or f is err:
            with wlock:
                f.write(s)
        else:
            f.write(s)

    bi = dict(builtins.__dict__)
    bi["__import__"], bi["print"] = _import, _print
    g = {"__name__": "__main__", "__file__": str(path), "__builtins__": bi}
    rc = 0
    try:
        exec(_code(path), g)
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
        if e.code is not None and not isinstance(e.code, int):
            err.write(str(e.code) + "\n")
    except BaseException:
        rc = 1
        err.write(traceback.format_exc())
    return rc, out.getvalue(), err.getvalue()


def run_hook(exe, lst, timeout):
    """rules.HOOK_RUNNER: CompletedProcess of `exe lst`, in-process when the hook allows it."""
    path = target(exe)
    if path is None:
        STATS["subprocess"] += 1
        return subprocess.run([str(exe), str(lst)], capture_output=True, text=True, timeout=timeout)
    STATS["inproc"] += 1
    box = {}
    t = threading.Thread(target=lambda: box.setdefault("r", _run(path, [lst])), daemon=True,
                         name=f"hook-{Path(exe).name}")
    t.start()
    t.join(timeout)
    if t.is_alive():
        raise subprocess.TimeoutExpired([str(exe), str(lst)], timeout)
    rc, so, se = box["r"]
    return subprocess.CompletedProcess([str(exe), str(lst)], rc, so, se)
