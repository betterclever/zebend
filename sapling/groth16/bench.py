#!/usr/bin/env python3
"""Timing, Bend vs Rust, on the same record set (default data/real.bin), 1 and 18 threads,
REPS interleaved repetitions; prints medians. Run under ../../heavy.sh.

  python3 bench.py [SET] [REPS]
"""
import os, re, statistics, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, 'data')
S = sys.argv[1] if len(sys.argv) > 1 else 'real'
REPS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
setp = os.path.join(D, f'{S}.bin')
vk = [os.path.join(D, 'vk_spend.bin'), os.path.join(D, 'vk_output.bin'), os.path.join(D, 'vk_sprout.bin')]
res = {}
def add(k, v): res.setdefault(k, []).append(v)
load = os.getloadavg()
for rep in range(REPS):
    for th in ('1', '18'):
        out = subprocess.run([os.path.join(HERE, 'oracle/target/release/groth16-oracle'), 'bench', setp, th, '1'], capture_output=True, text=True).stdout
        n = int(re.search(r'n=(\d+)', out).group(1))
        for name, pat in (('rust single', r'rust single .* ([\d.]+)s ='), ('rust batch (verify_multicore)', r'rust batch\(verify_multicore\) .* ([\d.]+)s ='),
                          ('rust batch (chunks of 128)', r'rust batch\(chunks of 128, verify\) .* ([\d.]+)s =')):
            add((name, th), float(re.search(pat, out).group(1)))
        for name, exe, extra in (('bend single (verify_main)', 'verify_main', []), ('bend batch (batch_main, chunks of 128)', 'batch_main', ['128'])):
            out = subprocess.run([os.path.join(HERE, exe)] + vk + [setp] + extra + ['+RTS', '--threads', th, '-RTS'], capture_output=True, text=True).stdout
            m = re.search(r'n (\d+) valid (\d+) ms (\d+)', out)
            assert m and m.group(1) == m.group(2) == str(n), out[-300:]
            add((name, th), int(m.group(3)) / 1000)
print(f'set {S}: {n} proofs; {REPS} reps; load average at start {load[0]:.1f}, end {os.getloadavg()[0]:.1f}')
print(f'{"":42s} {"1 thread":>22s} {"18 threads":>22s}')
for name in ('rust single', 'bend single (verify_main)', 'rust batch (verify_multicore)', 'rust batch (chunks of 128)', 'bend batch (batch_main, chunks of 128)'):
    cells = []
    for th in ('1', '18'):
        t = statistics.median(res[(name, th)])
        cells.append(f'{1e3 * t / n:.3f} ms ({n / t:,.0f}/s)')
    print(f'{name:42s} {cells[0]:>22s} {cells[1]:>22s}')
