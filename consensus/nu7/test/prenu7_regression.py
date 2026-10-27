#!/usr/bin/env python3
"""Pre-NU7 regression of the NU7 build: fullnode/rules' own suites (test_rules.py: 94 real
blocks of every era; tamper_rules.py: 16 tampered blocks) run against the PROPOSED rules.py
(consensus/nu7/wiring/rules.py) and bin/rules_nu7 (consensus/nu7/rules/rules_nu7.bend).
usage: prenu7_regression.py test_rules|tamper_rules"""
import os, runpy, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
NU7 = ROOT / "consensus/nu7"
os.environ.setdefault("ZEBEND_RULES_BIN", str(NU7 / "bin/rules_nu7"))
sys.path[:0] = [str(NU7 / "wiring"), str(ROOT / "fullnode"), str(ROOT / "fullnode/rules")]
import rules
assert Path(rules.__file__).parent == NU7 / "wiring", rules.__file__
name = sys.argv[1]
sys.argv = [name] + sys.argv[2:]
runpy.run_path(str(ROOT / "fullnode/rules" / f"{name}.py"), run_name="__main__")
