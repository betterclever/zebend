"""Shared loader / evaluator for the extract dumps (halo2/constraints/extract)."""
import json

P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001


def load(path):
    d = json.load(open(path))
    return d


def ev(e, sel, fix, adv, ins):
    """Evaluate an expression tree. sel(s), fix(col,rot,q), adv(col,rot,q), ins(col,rot,q)."""
    t = e[0]
    if t == "c":
        return int(e[1], 16)
    if t == "s":
        return sel(e[1])
    if t == "f":
        return fix(e[1], e[2], e[3])
    if t == "a":
        return adv(e[1], e[2], e[3])
    if t == "i":
        return ins(e[1], e[2], e[3])
    if t == "-":
        return (-ev(e[1], sel, fix, adv, ins)) % P
    if t == "+":
        return (ev(e[1], sel, fix, adv, ins) + ev(e[2], sel, fix, adv, ins)) % P
    if t == "*":
        return ev(e[1], sel, fix, adv, ins) * ev(e[2], sel, fix, adv, ins) % P
    if t == "k":
        return ev(e[1], sel, fix, adv, ins) * int(e[2], 16) % P
    raise ValueError(t)


def leaves(e, acc):
    t = e[0]
    if t in ("a", "f", "i", "s"):
        acc.add(tuple(e[:3]) if t != "s" else ("s", e[1]))
    elif t in ("-",):
        leaves(e[1], acc)
    elif t in ("+", "*"):
        leaves(e[1], acc); leaves(e[2], acc)
    elif t == "k":
        leaves(e[1], acc)
    return acc
