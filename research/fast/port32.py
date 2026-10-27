#!/usr/bin/env python3
"""Copies the curve / MSM / Halo 2 verifier modules into research/fast/ on top of fp32/fq32.

Only two mechanical changes: import paths are redirected to research/fast/'s modules, and the
16-limb field literals the verifier generator embedded (Fp.Fp{l0..l15}, Montgomery form)
become 8-limb ones. R = 2^256 in both representations, so a constant converts exactly by
joining limb pairs: w_i = l_{2i} | l_{2i+1} << 16.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
FAST = ROOT / "research/fast"

LIB = ["vesta.bend", "pallas.bend", "msm.bend", "msm_fast.bend", "fixed.bend"]
VER = ["vlib.bend", "b2.bend", "orchard_dyn.bend", "orchard_dyn_fast.bend",
       "bundle_main.bend", "bundle_main_fast.bend", "verify_entry.bend"]

LIT = re.compile(r"\b(Fp|Fq)\{((?:\s*\d+\s*,){15}\s*\d+\s*)\}")


def join_limbs(m):
    l = [int(x) for x in m.group(2).split(",")]
    return f"{m.group(1)}{{" + ", ".join(str(l[2 * i] | (l[2 * i + 1] << 16)) for i in range(8)) + "}"


def port(src, rules):
    for old, new in rules:
        src = src.replace(old, new)
    return LIT.sub(join_limbs, src)


lib_rules = [("import ./words.bend as", "import ../../../zcash/halo2/lib/words.bend as"),
             ("import ./fq.bend as", "import ../../fq32.bend as"),
             ("import ./fp.bend as", "import ../../fp32.bend as")]
ver_rules = [("import words.bend as", "import ../../../zcash/halo2/lib/words.bend as"),
             ("import fp.bend as", "import ../../fp32.bend as"),
             ("import fq.bend as", "import ../../fq32.bend as"),
             ("import ../../lib/", "import ../../lib32/")]

(FAST / "lib32").mkdir(exist_ok=True)
(FAST / "v32").mkdir(exist_ok=True)
for f in LIB:
    (FAST / "lib32" / f).write_text(port((ROOT / "zcash/halo2/lib" / f).read_text(), lib_rules))
for f in VER:
    (FAST / "v32" / f).write_text(port((ROOT / "zcash/halo2/verifier" / f).read_text(), ver_rules))
n = sum(len(LIT.findall((ROOT / "zcash/halo2/verifier" / f).read_text())) for f in VER)
print(f"ported {len(LIB)} lib + {len(VER)} verifier modules; converted {n} field literals")
