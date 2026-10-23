#!/usr/bin/env python3
"""Dev helper: rerun `bend --check-only` and add `+` to a parameter that the checker
reports as "consumed more than once" (Data values reused), until clean or stuck."""
import re, subprocess, sys
path = sys.argv[1]
for _ in range(40):
    out = subprocess.run(["zsh", "-lc", f"BEND_NO_TELEMETRY=1 ~/.bend/bin/bend {path} --check-only 2>&1 | head -24"],
                         capture_output=True, text=True).stdout
    if "ALL PROOFS CHECK" in out:
        print("OK"); sys.exit(0)
    v = re.search(r"observed : ([A-Za-z_0-9]+) \(consumed more than once\)", out)
    f = re.search(r"Location: ([A-Za-z_0-9.]+)", out)
    if not v or not f:
        print(out); sys.exit(1)
    v, fn = v.group(1), f.group(1)
    s = open(path).read()
    i = s.index(f"def {fn}("); j = s.index("\n", i)
    new = re.sub(rf"([(,]\s*){v}:", rf"\g<1>+{v}:", s[i:j], count=1)
    if new == s[i:j]:
        print(out); sys.exit(1)
    print(f"+{v} in {fn}")
    open(path, "w").write(s[:i] + new + s[j:])
