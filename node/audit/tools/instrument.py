"""Apply the audit instrumentation (JSON-lines log of every FAIL/SKIPPED/missing verdict + hook
timing; AUDIT_CONTINUE=1 keeps going) to a code dir holding the STAGED rules.py/sync.py."""
import sys
d = sys.argv[1]
p = f"{d}/rules.py"; s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a[:60]
    s = s.replace(a, b, 1)
rep('''import headers
import store as S
''', '''import headers
import store as S

AUDIT_LOG = os.environ.get("AUDIT_LOG")
AUDIT_CONTINUE = os.environ.get("AUDIT_CONTINUE") == "1"


def audit(**kw):
    if AUDIT_LOG:
        with open(AUDIT_LOG, "a") as f:
            f.write(json.dumps(kw) + "\\n")
''')
rep('''        try:
            r = subprocess.run([str(exe), str(d / "list.txt")], capture_output=True, text=True, timeout=HOOK_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise''', '''        th = time.time()
        try:
            r = subprocess.run([str(exe), str(d / "list.txt")], capture_output=True, text=True, timeout=HOOK_TIMEOUT)
        except subprocess.TimeoutExpired:
            audit(kind="hook_TIMEOUT", hook=name, first=items[0][0], n=len(items))
            raise''')
rep('''        bad = [(k, v) for k, v in got.items() if v[0] == "FAIL"]
        if bad:
            raise RuleFail(f"hook {name}: {bad[:3]}")
        miss = [k for k in items if k not in got]
        if miss:
            raise''', '''        audit(kind="hook_run", hook=name, first=items[0][0], last=items[-1][0], n=len(items),
              secs=round(time.time() - th, 2), rc=r.returncode, stderr=r.stderr.strip()[-300:])
        bad = [(k, v) for k, v in got.items() if v[0] == "FAIL"]
        miss = [k for k in items if k not in got]
        for k, v in got.items():
            if v[0] != "PASS":
                t = by_h[k[0]]["txs"][k[1]]
                audit(kind="hook_" + v[0], hook=name, height=k[0], txidx=k[1], txid=t["txid"], v=t["v"],
                      reason=v[1], ins=len(t["ins"]), js=len(t["js"]), sap=t["sap"], size=t["size"])
        for k in miss:
            audit(kind="hook_MISSING", hook=name, height=k[0], txidx=k[1], rc=r.returncode, stderr=r.stderr.strip()[-300:])
        if AUDIT_CONTINUE:
            bad, miss = [], []
        if bad:
            raise RuleFail(f"hook {name}: {bad[:3]}")
        if miss:
            raise''')
rep('''    if mode == "full":
        if fails:''', '''    if mode == "full":
        for h, fs in fails:
            audit(kind="rule_FAIL", height=h, fails=fs)
        if fails and not AUDIT_CONTINUE:''')
open(p, "w").write(s)
p = f"{d}/sync.py"; s = open(p).read()
rep('''                anchor_checks(full, st, log, idx)
''', '''                try:
                    anchor_checks(full, st, log, idx)
                except Fail as e:
                    rules.audit(kind="anchor_FAIL", msg=str(e))
                    if not rules.AUDIT_CONTINUE:
                        raise
''')
rep('''                    except ConnectionError as e:
''', '''                    except ConnectionError as e:
                        rules.audit(kind="oracle_ERROR", msg=str(e))
''')
open(p, "w").write(s)
print("instrumented", d)
