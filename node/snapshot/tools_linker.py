#!/usr/bin/env python3
"""Hard-link every chunk that appears in a live spool into our own spool directory, so a
snapshot-started test instance can replay blocks the live instance consumes (and deletes).
Read-only towards the live instance: it only creates links in DST. usage: tools_linker.py SRC DST"""
import os, sys, time
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
seen = {}
while True:
    try:
        for n in os.listdir(src):
            if n.endswith(".blk"):
                p = os.path.join(src, n)
                try:
                    sz = os.stat(p).st_size
                except FileNotFoundError:
                    continue
                q = os.path.join(dst, n)
                if not os.path.exists(q):
                    try:
                        os.link(p, q)
                        print(time.strftime("%H:%M:%S"), "linked", n, sz, flush=True)
                    except (FileNotFoundError, FileExistsError):
                        pass
    except FileNotFoundError:
        pass
    time.sleep(0.3)
