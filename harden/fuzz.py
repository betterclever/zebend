#!/usr/bin/env python3
"""Differential fuzz driver: Bend (./fz) vs the Rust oracle's verdicts.

  python3 fuzz.py MODE [--src NAME] [--limit N] [--jobs J] [--chunk-cases C] [--chunk-bytes B]

Reads data/NAME.cases/.expect/.kinds (NAME defaults to MODE, minus an _old suffix), splits the
cases into chunks, runs `./fz MODE chunk count` on each in parallel under /usr/bin/time -l,
and compares line by line. Reports totals, mismatches grouped by mutation kind, crashes
(non-zero exit or missing lines), throughput and the peak RSS of any chunk.
"""
import argparse, collections, os, re, struct, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, limit):
    raw = open(f'{HERE}/data/{name}.cases', 'rb').read()
    exp = open(f'{HERE}/data/{name}.expect').read().split('\n')
    kinds = open(f'{HERE}/data/{name}.kinds').read().split('\n')
    cases, i = [], 0
    while i < len(raw) and len(cases) < limit:
        (n,) = struct.unpack_from('<I', raw, i)
        cases.append(raw[i:i + 4 + n])
        i += 4 + n
    return cases, exp[:len(cases)], kinds[:len(cases)]


def chunks(cases, max_cases, max_bytes):
    out, cur, size = [], [], 0
    for idx, c in enumerate(cases):
        if cur and (len(cur) >= max_cases or size + len(c) > max_bytes):
            out.append(cur)
            cur, size = [], 0
        cur.append(idx)
        size += len(c)
    if cur:
        out.append(cur)
    return out


def run_chunk(mode, path, count, timeout):
    t = time.time()
    p = subprocess.run(['/usr/bin/time', '-l', f'{HERE}/fz', mode, path, str(count)],
                       capture_output=True, timeout=timeout)
    rss = re.search(rb'(\d+)\s+maximum resident set size', p.stderr)
    return p.returncode, p.stdout.decode(errors='replace'), int(rss.group(1)) if rss else 0, time.time() - t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode')
    ap.add_argument('--src')
    ap.add_argument('--limit', type=int, default=10**9)
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--chunk-cases', type=int, default=2000)
    ap.add_argument('--chunk-bytes', type=int, default=4_000_000)
    ap.add_argument('--timeout', type=int, default=360)
    ap.add_argument('--show', type=int, default=3)
    a = ap.parse_args()
    name = a.src or a.mode.removesuffix('_old')
    cases, exp, kinds = load(name, a.limit)
    groups = chunks(cases, a.chunk_cases, a.chunk_bytes)
    cdir = f'{HERE}/data/chunks'
    os.makedirs(cdir, exist_ok=True)
    jobs = []
    for k, g in enumerate(groups):
        path = f'{cdir}/{a.mode}_{k}.bin'
        with open(path, 'wb') as f:
            for i in g:
                f.write(cases[i])
        jobs.append((g, path))

    got = [None] * len(cases)
    crashes, peak, t0 = [], 0, time.time()

    def work(job):
        g, path = job
        try:
            rc, out, rss, dt = run_chunk(a.mode, path, len(g), a.timeout)
        except subprocess.TimeoutExpired:
            return g, path, 'timeout', [], 0
        os.remove(path)
        return g, path, rc, out.split('\n'), rss

    with ThreadPoolExecutor(a.jobs) as ex:
        for g, path, rc, lines, rss in ex.map(work, jobs):
            peak = max(peak, rss)
            if rc != 0 or len(lines) < len(g):
                crashes.append((path, rc, len(lines), len(g)))
            for j, i in enumerate(g):
                got[i] = lines[j] if j < len(lines) else '<missing>'
    dt = time.time() - t0

    by_kind = collections.Counter()
    examples = collections.defaultdict(list)
    for i, (g, e) in enumerate(zip(got, exp)):
        if g != e:
            by_kind[kinds[i]] += 1
            if len(examples[kinds[i]]) < a.show:
                examples[kinds[i]].append((i, e, g, len(cases[i]) - 4))
    acc = sum(1 for e in exp if not e.startswith('0'))
    mism = sum(by_kind.values())
    print(f'{a.mode}: {len(cases)} cases ({acc} accepted by the reference) in {len(groups)} chunks, '
          f'{dt:.1f}s ({len(cases) / dt:.0f}/s), peak RSS {peak / 2**20:.1f} MiB, '
          f'{mism} mismatches, {len(crashes)} crashed chunks')
    if mism:
        conf = collections.Counter((e.split(' ')[0], g.split(' ')[0]) for g, e in zip(got, exp) if g != e)
        print('  rust->bend verdicts on mismatches: ' +
              ', '.join(f'{r}->{b}: {n}' for (r, b), n in conf.most_common()))
    for path, rc, nl, ng in crashes[:5]:
        print(f'  CRASH {os.path.basename(path)}: rc={rc} lines={nl}/{ng}')
    for k, n in by_kind.most_common():
        print(f'  {k}: {n}')
        for i, e, g, ln in examples[k]:
            print(f'    case {i} ({ln} B): rust={e!r} bend={g!r}')
    sys.exit(1 if mism or crashes else 0)


if __name__ == '__main__':
    main()
