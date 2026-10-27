#!/usr/bin/env python3
"""Bend vs official verdicts, record by record.

  python3 diff.py [SET...] [--threads N]    (default sets: real tamper)

Runs verify_main (verify_raw_main for *_raw sets: Bend computes the public inputs) on data/<SET>.bin (all records in one process) and compares each verdict
with data/official_<SET>.txt (groth16::verify_proof after Proof::read, as sapling-crypto).
"""
import os, re, subprocess, sys, time
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, 'data')
args = sys.argv[1:]
threads = '18'
if '--threads' in args:
    i = args.index('--threads'); threads = args[i + 1]; del args[i:i + 2]
batch = None   # --batch CHUNK: batch_main (batch verification, per-proof fallback on failure)
if '--batch' in args:
    i = args.index('--batch'); batch = args[i + 1]; del args[i:i + 2]
sets = args or ['real', 'tamper']
TAGS = {0: 'real', 1: 'random bit flip', 2: 'A sign flip', 3: 'input + 1', 4: 'A<->C swap', 5: 'A off-subgroup',
        6: 'B off-subgroup', 7: 'B sign flip', 8: 'A x >= p', 9: 'A = infinity', 10: 'other proof',
        11: 'cv bit flip', 12: 'rk/epk bit flip', 13: 'rk/epk = identity', 14: 'anchor/cmu >= r', 15: 'nf/cmu bit flip'}
RAW_TAGS = {3: 'anchor/cmu + 1'}  # Sprout records: 3 cm1 bit, 11 rt bit, 12 seed bit, 13 pubkey bit, 14 mac1 bit, 15 vpub_old + 1
total_bad = 0
for s in sets:
    off = [l.split() for l in open(os.path.join(D, f'official_{s}.txt')) if not l.startswith('#')]
    t = time.time()
    raw = s.endswith('_raw')
    exe = 'batch_main' if batch else ('verify_raw_main' if raw else 'verify_main')
    vks = [os.path.join(D, 'vk_spend.bin'), os.path.join(D, 'vk_output.bin'), os.path.join(D, 'vk_sprout.bin')]
    out = subprocess.run([os.path.join(HERE, exe)] + vks + [os.path.join(D, f'{s}.bin')] + ([batch] if batch else []) + ['+RTS', '--threads', threads, '-RTS'],
                         capture_output=True, text=True).stdout
    wall = time.time() - t
    v = re.search(r'verdicts (\d*)', out).group(1)  # 1 valid, 0 decode reject, 2 pairing reject
    m = re.search(r'n (\d+) valid (\d+) ms (\d+)', out)
    bm = re.search(r'chunks (\d+) failed (\d+)', out)
    if len(v) != len(off):
        print(f'{s}: Bend returned {len(v)} verdicts for {len(off)} records'); total_bad += 1; continue
    by = Counter(); dis = Counter(); valid = Counter(); kinds = Counter(); rdis = Counter(); reasons = Counter()
    kdis = Counter()
    bad = []
    for (idx, kind, tag, ver, h, txid, di, reason), b in zip(off, v):
        by[int(tag)] += 1; kinds[kind] += 1
        valid[int(tag)] += int(ver)
        reasons[(int(tag), reason)] += 1
        if str(int(b == '1')) != ver:
            dis[int(tag)] += 1; bad.append(idx); kdis[kind] += 1
        if b != reason:
            rdis[int(tag)] += 1
    total_bad += len(bad) + sum(rdis.values())
    print(f'{s}: {len(off)} records ({kinds["0"]} spend, {kinds["1"]} output, {kinds["2"]} Sprout JoinSplit); official valid {sum(valid.values())}, '
          f'Bend valid {v.count("1")}; agree {len(off) - len(bad)}/{len(off)}, disagree {len(bad)}; '
          f'stage disagree {sum(rdis.values())}; Bend {exe} {m.group(3)} ms at {threads} threads ({int(m.group(3)) / len(off):.2f} ms/proof), process {wall:.1f}s'
          + (f'; chunks of {batch}: {bm.group(1)}, batch equation failed in {bm.group(2)} (kind-batches)' if bm else ''))
    if 'real' not in s:
        for tg in sorted(by):
            name = (RAW_TAGS.get(tg) if raw else None) or TAGS.get(tg, '?')
            print(f'   tag {tg:2d} {name:18s} {by[tg]:6d} records, official valid {valid[tg]}, rejected: '
                  + (f'fields {reasons[(tg, "3")]} / ' if raw else '')
                  + f'decode {reasons[(tg, "0")]} / pairing {reasons[(tg, "2")]}; disagree {dis[tg]} (stage {rdis[tg]})')
    if bad:
        print('   first disagreements:', bad[:10])
sys.exit(1 if total_bad else 0)
