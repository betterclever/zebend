#!/usr/bin/env python3
"""wlprof.py file.sample: attribute every sample to its nearest Bend function frame
(WL_FID_*: the work-loop body of a Bend def, with its inlined spin_* helpers) or to the
runtime (term_drop, rfc_wrap, span_fade, heap_*), from macOS `sample` call graphs."""
import re, sys
from collections import defaultdict
pat = re.compile(r"^([\s+!:|]*?)(\d+) (\S+)")
lines = open(sys.argv[1]).read().split("\n")
started = False; stack = []; nodes = []
for l in lines:
    if l.startswith("Call graph:"): started = True; continue
    if not started: continue
    if l.startswith("Total number") or l.startswith("Sort by"): break
    m = pat.match(l)
    if not m: continue
    d = len(m.group(1)); n = int(m.group(2)); name = m.group(3)
    while stack and stack[-1][0] >= d: stack.pop()
    parent = stack[-1][2] if stack else None
    idx = len(nodes); nodes.append([name, n, parent, 0])
    if parent is not None: nodes[parent][3] += n
    stack.append((d, name, idx))
self_ = defaultdict(int); tot = 0
RT = ("term_drop", "rfc_wrap", "span_fade", "heap_", "WL_SPIN")
for i, (name, n, parent, child) in enumerate(nodes):
    s = n - child
    if s <= 0: continue
    if name in ("__psynch_cvwait", "swtch_pri", "__workq_kernreturn", "start_wqthread", "thread_start", "_pthread_start", "__ulock_wait2"): continue
    # walk up to a WL_FID or runtime frame
    j = i; lab = None
    while j is not None:
        nm = nodes[j][0]
        if any(nm.startswith(r) for r in RT): lab = "RUNTIME:" + nm; break
        if nm.startswith("WL_FID_"): lab = re.sub(r"_[kj]\d+$", "", nm[7:]); break
        j = nodes[j][2]
    self_[lab or "other:" + name] += s; tot += s
for k, v in sorted(self_.items(), key=lambda kv: -kv[1])[:45]:
    print(f"{v:7d} {100*v/tot:5.1f}% {k}")
print("total", tot)
