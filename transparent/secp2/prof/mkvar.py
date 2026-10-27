#!/usr/bin/env python3
"""Profiling variants of tv2 (stubbed stages) for the per-stage time split.
  v0 baseline, v1 ECDSA verify -> True (decode kept), v2 decode+verify -> True,
  v3 sighash+decode+verify -> True, v4 no script interpretation (every input "1"),
  v5 v4 + no wire validation (txv)."""
import pathlib, re
T = pathlib.Path(__file__).resolve().parents[2]
P = T / "secp2/prof"
core = (T / "script2/core.bend").read_text()
core = core.replace("import ../", "import ../../").replace("import ./", "import ../../script2/")
interp = (T / "script2/interp.bend").read_text().replace("import ../", "import ../../")
main = (T / "tv2_main.bend").read_text()
main = main.replace("import ../", "import ../../../").replace("import ./", "import ../../")
main = main.replace("../../script2/core.bend", "./script2/core.bend").replace("../../script2/interp.bend", "./script2/interp.bend")

V1 = ("      E.verify(q, r, s, h)", "      G.Af{qx, _} = q\n      E.is_odd(qx) || True{}")
def var(k):
    c, i, m = core, interp, main
    if k >= 1:
        assert V1[0] in c; c = c.replace(*V1)
    if k >= 2:
        c = c.replace("      ecdsa_q(E.decode(pk), r, s, h)", "      U32.is_eq(U.head0(h), U.head0(pk)) || True{}")
    if k >= 3:
        c = c.replace("ecdsa_h(SH.sighash(tx, nin, script, spk, amount, ht), pk, r, s)", "ecdsa_h(Some{[1]}, pk, r, s)")
    if k >= 4:
        m = m.replace("+v = I.verify_input(flags, SH.in_script(inp), spk, ctx)", "+v = U.is_empty(spk) || True{}")
    if k >= 5:
        m = m.replace("tx_valid(V.valid(tx), tx,", "tx_valid(True{}, tx,")
    m = m.replace("./script2/core.bend", f"./core_v{k}.bend").replace("./script2/interp.bend", f"./interp_v{k}.bend")
    i = i.replace("./core.bend", f"./core_v{k}.bend")
    (P / f"core_v{k}.bend").write_text(c); (P / f"interp_v{k}.bend").write_text(i); (P / f"main_v{k}.bend").write_text(m)
for k in range(6):
    var(k)
