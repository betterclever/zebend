#!/usr/bin/env python3
"""Reorder a Bend file's top-level blocks so every def sits below the defs it calls
(Bend requires callees above callers). Imports stay first, then types, then defs in
dependency order (stable otherwise). Comments directly above a block move with it."""
import re, sys

path = sys.argv[1]
lines = open(path).read().split("\n")
head, blocks, cur, pending = [], [], None, []
for ln in lines:
    top = ln and not ln[0].isspace()
    if top and ln.startswith("#"):
        pending.append(ln); continue
    if top and ln.startswith("import "):
        head += pending + [ln]; pending = []; continue
    if top and re.match(r"(def|type|law|@unsafe def)\b", ln):
        cur = {"lines": pending + [ln]}; pending = []; blocks.append(cur); continue
    if cur is not None:
        cur["lines"] += pending + [ln]; pending = []
    else:
        head += pending + [ln]; pending = []
for b in blocks:
    m = re.match(r"(?:@unsafe )?(def|type|law)\s+([\w.]+)", next(l for l in b["lines"] if not l.startswith("#")))
    b["kind"], b["name"] = m.group(1), m.group(2)
    while b["lines"] and b["lines"][-1].strip() == "":
        b["lines"].pop()
names = {b["name"] for b in blocks if b["kind"] == "def"}
for b in blocks:
    body = "\n".join(l for l in b["lines"][1:] if not l.lstrip().startswith("#"))
    b["deps"] = {n for n in re.findall(r"(?<![\w.])([A-Za-z_][\w.]*)\s*[(!]", body) if n in names and n != b["name"]}
types = [b for b in blocks if b["kind"] != "def"]
defs = [b for b in blocks if b["kind"] == "def"]
out, done, onstack = [], set(), set()
byname = {b["name"]: b for b in defs}
def visit(b):
    if b["name"] in done: return
    if b["name"] in onstack: sys.exit(f"order.py: mutual recursion through {b['name']}")
    onstack.add(b["name"])
    for d in sorted(b["deps"], key=lambda n: defs.index(byname[n])):
        visit(byname[d])
    onstack.discard(b["name"]); done.add(b["name"]); out.append(b)
for b in defs: visit(b)
while head and head[-1].strip() == "": head.pop()
text = "\n".join(head) + "\n\n" + "\n\n".join("\n".join(b["lines"]) for b in types + out) + "\n"
open(path, "w").write(text)
