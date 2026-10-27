#!/usr/bin/env python3
"""Reorder a Bend file's top-level defs/types so every definition precedes its users.
Bend requires callers below callees; this keeps each def's leading comment with it."""
import re, sys

def reorder(src):
    lines = src.split('\n')
    starts = [i for i, l in enumerate(lines) if re.match(r'(def|type) ', l)]
    bs = []
    for i in starts:
        j = i
        while j > 0 and lines[j - 1].startswith('#') and not lines[j - 1].startswith('# ---'):
            j -= 1
        bs.append(j)
    head = '\n'.join(lines[:bs[0]])
    blocks = ['\n'.join(lines[a:b]).rstrip('\n') + '\n' for a, b in zip(bs, bs[1:] + [len(lines)])]
    blocks = [re.sub(r'\n# -{5,}[^\n]*\n', '\n', b) for b in blocks]
    name = lambda b: re.search(r'^(?:def|type) ([A-Za-z0-9_.]+)', b, re.M).group(1)
    names = [name(b) for b in blocks]
    ctors = {}
    for b, n in zip(blocks, names):
        if re.search(r'^type ', b, re.M):
            for c in re.findall(r'^  ([A-Z][A-Za-z0-9]*)\{', b, re.M):
                ctors[c] = n
    dep = {}
    for b, n in zip(blocks, names):
        body = '\n'.join(l for l in b.split('\n') if not l.lstrip().startswith('#'))
        d = [m for m in names if m != n and re.search(r'(?<![\w.])' + re.escape(m) + r'(?![\w])', body)]
        d += [t for c, t in ctors.items() if t != n and re.search(r'(?<![\w.])' + c + r'\{', body)]
        dep[n] = d
    out, done = [], set()
    def visit(n, st=()):
        if n in done:
            return
        if n in st:
            sys.exit(f'cycle: {st + (n,)}')
        for d in dep[n]:
            visit(d, st + (n,))
        done.add(n)
        out.append(n)
    for n in names:
        visit(n)
    bm = dict(zip(names, blocks))
    return head.rstrip('\n') + '\n\n' + '\n'.join(bm[n] for n in out)

for p in sys.argv[1:]:
    out = reorder(open(p).read())
    open(p, 'w').write(out)
