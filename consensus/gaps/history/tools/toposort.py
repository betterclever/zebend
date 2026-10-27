#!/usr/bin/env python3
"""Reorder a Bend 2 file's top-level defs so each def comes after the defs it calls
(the forked compiler rejects forward references). Comments directly above a def move with it."""
import re, sys
p = sys.argv[1]
lines = open(p).read().split('\n')
# find top-level starts
starts = [i for i, l in enumerate(lines) if re.match(r'(def|type) ', l)]
# extend each start upward over contiguous comment lines
blk_starts = []
for i in starts:
    j = i
    while j > 0 and lines[j-1].startswith('#'):
        j -= 1
    blk_starts.append(j)
head = '\n'.join(lines[:blk_starts[0]])
blocks = []
for k, j in enumerate(blk_starts):
    e = blk_starts[k+1] if k+1 < len(blk_starts) else len(lines)
    blocks.append('\n'.join(lines[j:e]).rstrip('\n'))
def name(b):
    return re.search(r'^(?:def|type) ([A-Za-z0-9_.]+)', b, re.M).group(1)
names = [name(b) for b in blocks]
deps = {}
for b, n in zip(blocks, names):
    hdr = re.sub(r'"[^"]*"', '', '\n'.join(l.split('#')[0] for l in b.split('\n')))
    deps[n] = {m for m in names if m != n and re.search(r'(?<![\w.])' + re.escape(m) + r'(?![\w])', hdr)}
order, done = [], set()
def visit(n, stack=()):
    if n in done:
        return
    if n in stack:
        if n != stack[-1]:
            print('cycle:', stack, n, file=sys.stderr)
        return
    for d in sorted(deps[n], key=names.index):
        visit(d, stack + (n,))
    done.add(n); order.append(n)
for n in names:
    visit(n)
bm = dict(zip(names, blocks))
open(p, 'w').write(head.rstrip('\n') + '\n\n' + '\n\n'.join(bm[n] for n in order) + '\n')
