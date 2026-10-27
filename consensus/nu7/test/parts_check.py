#!/usr/bin/env python3
"""Parallel parts of the proposed rules.py: predicted_delta (7 pools, NU7 lockbox/NSM) must match what bin/rules_nu7 prints, so no part is rerun (rules.STATS["reruns"] == 0). Window 3,522,461..3,522,490 in 6 parts."""
import os, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]; NU7 = ROOT/"consensus/nu7"
os.environ.setdefault("ZEBEND_RULES_BIN", str(NU7/"bin/rules_nu7"))
sys.path[:0] = [str(NU7/"wiring"), str(ROOT/"fullnode"), str(ROOT/"fullnode/rules")]
import rules
from test_rules import TestStore, delta, DATA
hs = list(range(3522461, 3522491))
raw = {h: (DATA/f"{h}.bin").read_bytes() for h in hs}
blocks = delta(raw)
st = TestStore(); st.fetch([p for b in blocks for t in b["txs"] for (p,_,_) in t["ins"]])
from concurrent.futures import ThreadPoolExecutor
pools = {n: 10**15 for n in rules.POOL_NAMES}; pools["nsm"] = 0
with ThreadPoolExecutor(6) as ex:
    res = rules.run_rules(blocks, st, raw, pools, jobs=6, ex=ex)
print("STATS", rules.STATS, "fails", sum(len(r.get("fails", [])) for r in res.values()))
