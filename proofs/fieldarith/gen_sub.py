#!/usr/bin/env python3
"""Generate the proof that zcash/halo2/lib/fp.bend's `sub` is subtraction mod p.

Writes subcore.bend (sub_core: the 16-limb assembly, generic in the base K = 1 + m
and every limb) and subproof.bend (sub_ok_proof: Fp.sub itself). The structure of
fp.bend's sub is checked against the expected chain first. Run gen_add.py first
(defs.bend, addcore.bend's vcong / hbk / qk are shared).
"""
import os
import re
import gen_add as GA

HERE = GA.HERE
N = GA.N
tn, horner, fp, val, Q, QM = GA.tn, GA.horner, GA.fp, GA.val, GA.Q, GA.QM


def read_sub(plimbs):
    src = open(GA.FP).read()
    body = src[src.index("def sub(a: Fp, b: Fp) -> Fp:"):src.index("# 1 if a == b else 0")]
    lets = [(n, re.sub(r"\s+", " ", e)) for n, e in re.findall(r"\+(v\d+) = \((.*) : U32\)", body)]
    exp = []
    v = 0

    def new(ex):
        nonlocal v
        v += 1
        exp.append(("v%d" % v, ex))
        return "v%d" % v
    d, e = [], None
    for i in range(N):
        w = new("a0 + 65536 - b0") if i == 0 else new("a%d + 65536 - b%d - %s" % (i, i, e))
        d.append(new("%s .&. 65535" % w))
        e = new("1 - (%s >> 16n)" % w)
    mk = new("0 - %s" % e)
    r, k = [], None
    for i in range(N):
        if i == 0:
            u = new("%s + (%d .&. %s)" % (d[0], plimbs[0], mk))
        else:
            u = new("%s + (%d .&. %s) + %s" % (d[i], plimbs[i], mk, k))
        r.append(new("%s .&. 65535" % u))
        k = new("%s >> 16n" % u)
    assert lets == exp, "fp.bend's sub is not the expected chain"
    ret = re.search(r"\n  Fp\{(.*)\}\n", body).group(1).split(", ")
    assert ret == r, ret


def terms(plimbs):
    lets = []

    def let(name, ex):
        lets.append((name, ex))
        return name
    d, es, ws = [], [None], []
    for i in range(N):
        if i == 0:
            w = let("w0", "U32.sub(U32.add(a0, 65536), b0)")
        else:
            w = let("w%d" % i, "U32.sub(U32.sub(U32.add(a%d, 65536), b%d), %s)" % (i, i, es[i]))
        ws.append(w)
        d.append(let("d%d" % i, "U32.and(%s, 65535)" % w))
        es.append(let("e%d" % (i + 1), "U32.sub(1, U32.shrn(%s, 16n))" % w))
    mk = let("mk", "U32.sub(0, %s)" % es[N])
    r, ks, us, qs = [], [None], [], []
    for i in range(N):
        q = "U32.and(%d, mk)" % plimbs[i]
        qs.append(q)
        if i == 0:
            u = let("u0", "U32.add(d0, %s)" % q)
        else:
            u = let("u%d" % i, "U32.add(U32.add(d%d, %s), %s)" % (i, q, ks[i]))
        us.append(u)
        r.append(let("r%d" % i, "U32.and(%s, 65535)" % u))
        ks.append(let("k%d" % (i + 1), "U32.shrn(%s, 16n)" % u))
    return lets, d, es, ws, qs, r, ks, us


def gen_core():
    K = "K"
    a = ["a%d" % i for i in range(N)]
    b = ["b%d" % i for i in range(N)]
    p = ["p%d" % i for i in range(N)]
    d = ["d%d" % i for i in range(N)]
    r = ["r%d" % i for i in range(N)]
    e = [None] + ["e%d" % i for i in range(1, N + 1)]
    k = [None] + ["k%d" % i for i in range(1, N + 1)]
    q = ["U32.and(%s, U32.sub(0, e%d))" % (p[i], N) for i in range(N)]
    A, B, P, Dd, Rr = ([tn(x) for x in xs] for xs in (a, b, p, d, r))
    Qq = [tn(x) for x in q]
    E = [None] + [tn(x) for x in e[1:]]
    Kk = [None] + [tn(x) for x in k[1:]]
    VA, VB, VP = val(K, a), val(K, b), val(K, p)
    goal = "{%s == Nat.mod(Nat.add(%s, Nat.sub(%s, %s)), %s) : Nat}" % (val(K, r), VA, VP, VB, VP)
    params = ["+K: Nat", "+m: Nat", "+hK: {K == 1n+m : Nat}"]
    params += ["+%s: U32" % x for x in a + b + p + d + e[1:] + r + k[1:]]
    hyps = ["+hs0: {Nat.add(Nat.add(%s, %s), 0n) == Nat.add(%s, Nat.mul(%s, %s)) : Nat}" % (Dd[0], B[0], A[0], E[1], K)]
    for i in range(1, N):
        hyps.append("+hs%d: {Nat.add(Nat.add(%s, %s), %s) == Nat.add(%s, Nat.mul(%s, %s)) : Nat}" % (i, Dd[i], B[i], E[i], A[i], E[i + 1], K))
    hyps.append("+ht0: {Nat.add(%s, Nat.mul(%s, %s)) == Nat.add(%s, %s) : Nat}" % (Rr[0], Kk[1], K, Dd[0], Qq[0]))
    for i in range(1, N):
        hyps.append("+ht%d: {Nat.add(%s, Nat.mul(%s, %s)) == Nat.add(Nat.add(%s, %s), %s) : Nat}" % (i, Rr[i], Kk[i + 1], K, Dd[i], Qq[i], Kk[i]))
    hyps.append("+lk: L.Le(%s, 1n)" % Kk[N])
    hyps.append("+le: L.Le(%s, 1n)" % E[N])
    hyps += ["+lr%d: L.Le(%s, m)" % (i, Rr[i]) for i in range(N)]
    hyps += ["+ld%d: L.Le(%s, m)" % (i, Dd[i]) for i in range(N)]
    hyps.append("+lta: L.Le(1n+%s, %s)" % (VA, VP))
    hyps.append("+ltb: L.Le(1n+%s, %s)" % (VB, VP))

    XA, XB, XP, XD, XT, XQ = (horner(xs, K) for xs in (A, B, P, Dd, Rr, Qq))
    R, RM = Q(K, 0), QM(K, 0)
    chainS = "{Nat.add(Nat.add(%s, %s), 0n) == Nat.add(%s, Nat.mul(%s, %s)) : Nat}" % (XD, XB, XA, E[N], R)
    chainT = "{Nat.add(%s, Nat.mul(%s, %s)) == Nat.add(Nat.add(%s, %s), 0n) : Nat}" % (XT, Kk[N], R, XD, XQ)
    out = ["import Base",
           "import ../../zcash/halo2/lib/fp.bend as Fp",
           "import ../field/natlemmas.bend as N",
           "import ../prims/natlib.bend as L",
           "import ./u32sem.bend as S",
           "import ./glue.bend as G",
           "import ./subglue.bend as SG",
           "import ./defs.bend as D",
           "import ./addcore.bend as AC",
           "",
           "# GENERATED by gen_sub.py. Do not edit.",
           ""]
    cparams = params + hyps + ["+cs: %s" % chainS, "+ct: %s" % chainT, "+hR: {%s == 1n+%s : Nat}" % (R, RM),
                               "+bt: L.Le(%s, %s)" % (XT, RM), "+bd: L.Le(%s, %s)" % (XD, RM), "ce: S.Is01(%s)" % e[N]]
    out.append("def cases(%s) -> %s:" % (", ".join(cparams), goal))
    out.append("  match ce:")
    for name, lit, lemma, tgt, fin in (("Inl", "0", "SG.qz", ["0"] * N, "fins0"), ("Inr", "1", "SG.qo", p, "fins1")):
        out.append("    case %s{+he}:" % name)
        vq = "AC.vcong(K, %s, %s, %s)" % (", ".join(q), ", ".join(tgt), ", ".join("%s(%s, e%d, he)" % (lemma, p[i], N) for i in range(N)))
        tgtv = "0n" if lit == "0" else XP
        hT = "Equal.trans(Nat, Nat.add(%s, Nat.mul(%s, %s)), Nat.add(Nat.add(%s, %s), 0n), Nat.add(Nat.add(%s, %s), 0n), ct, Equal.cong(Nat, Nat, z => Nat.add(Nat.add(%s, z), 0n), %s, %s, %s))" % (
            XT, Kk[N], R, XD, XQ, XD, tgtv, XD, XQ, tgtv, vq)
        tnq = "Equal.cong(U32, Nat, z => U32.to_nat(z), e%d, %s, he)" % (N, lit)
        ev = "%sn" % lit
        hS = "Equal.trans(Nat, Nat.add(Nat.add(%s, %s), 0n), Nat.add(%s, Nat.mul(%s, %s)), Nat.add(%s, Nat.mul(%s, %s)), cs, Equal.cong(Nat, Nat, z => Nat.add(%s, Nat.mul(z, %s)), %s, %s, %s))" % (
            XD, XB, XA, E[N], R, XA, ev, R, XA, R, E[N], ev, tnq)
        if fin == "fins0":
            out.append("      SG.fins0(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, hR, lk, bd, lta, ltb)" % (XT, XD, XP, XA, XB, R, RM, Kk[N], hS, hT))
        else:
            out.append("      SG.fins1(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, hR, lk, bt, bd, lta, ltb)" % (XT, XD, XP, XA, XB, R, RM, Kk[N], hS, hT))
    out.append("")
    out.append("law sub_core:")
    for x in params + hyps:
        out.append("  for %s" % x)
    out.append("  " + goal)
    out.append("")
    names = [x.split(":")[0].lstrip("+").strip() for x in params + hyps]
    out.append("def sub_core(%s):" % ", ".join(names))
    prev = "G.base_sub(%s)" % E[N]
    for j in range(N - 1, -1, -1):
        ej = E[j] if j > 0 else "0n"
        prev = "G.ch_sub(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, hs%d)" % (
            K, Dd[j], horner(Dd, K, j + 1), B[j], horner(B, K, j + 1), A[j], horner(A, K, j + 1), ej, E[j + 1], Q(K, j + 1), E[N], prev, j)
        out.append("  +cs%d = %s" % (j, prev))
        prev = "cs%d" % j
    prev = "G.base_add(%s)" % Kk[N]
    for j in range(N - 1, -1, -1):
        h2 = "ht%d" % j
        cj = Kk[j] if j > 0 else "0n"
        if j == 0:
            h2 = "Equal.trans(Nat, Nat.add(%s, Nat.mul(%s, %s)), Nat.add(%s, %s), Nat.add(Nat.add(%s, %s), 0n), ht0, Equal.sym(Nat, Nat.add(Nat.add(%s, %s), 0n), Nat.add(%s, %s), N.add_zero_r(Nat.add(%s, %s))))" % (
                Rr[0], Kk[1], K, Dd[0], Qq[0], Dd[0], Qq[0], Dd[0], Qq[0], Dd[0], Qq[0], Dd[0], Qq[0])
        prev = "G.ch_add(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % (
            K, Rr[j], horner(Rr, K, j + 1), Dd[j], horner(Dd, K, j + 1), Qq[j], horner(Qq, K, j + 1), cj, Kk[j + 1], Q(K, j + 1), Kk[N], prev, h2)
        out.append("  +ct%d = %s" % (j, prev))
        prev = "ct%d" % j
    for nm, xs, lname in (("bt", Rr, "lr"), ("bd", Dd, "ld")):
        prev = "(0n, {==})"
        for j in range(N - 1, -1, -1):
            prev = "AC.hbk(K, m, hK, %s, %s, %s, %s%d, %s)" % (xs[j], horner(xs, K, j + 1), QM(K, j + 1), lname, j, prev)
            out.append("  +%s%d = %s" % (nm, j, prev))
            prev = "%s%d" % (nm, j)
    prev = "{==}"
    for j in range(N - 1, -1, -1):
        prev = "AC.qk(K, m, hK, %s, %s, %s)" % (Q(K, j + 1), QM(K, j + 1), prev)
        out.append("  +hq%d = %s" % (j, prev))
        prev = "hq%d" % j
    out.append("  cases(%s, cs0, ct0, hq0, bt0, bd0, S.classify(e%d, le))" % (", ".join(names), N))
    out.append("")
    return "\n".join(out)


def gen_proof(plimbs):
    lets, d, es, ws, qs, r, ks, us = terms(plimbs)
    a = ["a%d" % i for i in range(N)]
    b = ["b%d" % i for i in range(N)]
    pl = [str(x) for x in plimbs]
    goal = "{D.val(65536n, Fp.sub(a, b)) == Nat.mod(Nat.add(D.val(65536n, a), Nat.sub(D.val(65536n, %s), D.val(65536n, b))), D.val(65536n, %s)) : Nat}" % (fp(pl), fp(pl))
    out = ["import Base",
           "import ../../zcash/halo2/lib/fp.bend as Fp",
           "import ../prims/natlib.bend as L",
           "import ../prims/hi.bend as H",
           "import ./u32bits.bend as UB",
           "import ./u32sem.bend as S",
           "import ./subglue.bend as SG",
           "import ./steps.bend as St",
           "import ./defs.bend as D",
           "import ./subcore.bend as SC",
           "",
           "# GENERATED by gen_sub.py. Do not edit.",
           "",
           "def sub_ok_proof(a: Fp.Fp, b: Fp.Fp, +ca: D.Canon(a), +cb: D.Canon(b)) -> %s:" % goal,
           "  match a:",
           "    case Fp.Fp{%s}:" % ", ".join("+" + x for x in a),
           "      match b:",
           "        case Fp.Fp{%s}:" % ", ".join("+" + x for x in b)]

    def unpack(var, pre, lt):
        lines = ["  (+%sl, +%s) = %s" % (pre, lt, var)]
        cur = "%sl" % pre
        for i in range(N - 2):
            lines.append("  (+%s%d, +%sr%d) = %s" % (pre, i, pre, i, cur))
            cur = "%sr%d" % (pre, i)
        lines.append("  (+%s%d, +%s%d) = %s" % (pre, N - 2, pre, N - 1, cur))
        return lines
    body = unpack("ca", "la", "lta") + unpack("cb", "lb", "ltb")
    body += ["  +%s = %s" % (n, ex) for n, ex in lets]
    for i in range(N):
        if i == 0:
            body.append("  +hs0 = St.sub0_eq(a0, b0, la0, lb0)")
            body.append("  +he1 = St.sub0_bo(a0, b0, la0, lb0)")
        else:
            body.append("  +hs%d = St.sub_eq(a%d, b%d, %s, la%d, lb%d, he%d)" % (i, i, i, es[i], i, i, i))
            body.append("  +he%d = St.sub_bo(a%d, b%d, %s, la%d, lb%d, he%d)" % (i + 1, i, i, es[i], i, i, i))
        body.append("  +ld%d = UB.low16_le(%s)" % (i, ws[i]))
    for i in range(N):
        body.append("  +lq%d = H.le_trans(U32.to_nat(%s), U32.to_nat(%s), 65535n, SG.and_le(%s, mk), S.lit16(%s, {==}))" % (i, qs[i], pl[i], pl[i], pl[i]))
        if i == 0:
            body.append("  +ht0 = St.add0_eq(d0, %s, ld0, lq0)" % qs[0])
            body.append("  +hk1 = St.add0_hi(d0, %s, ld0, lq0)" % qs[0])
        else:
            body.append("  +ht%d = St.add_eq(d%d, %s, %s, ld%d, lq%d, hk%d)" % (i, i, qs[i], ks[i], i, i, i))
            body.append("  +hk%d = St.add_hi(d%d, %s, %s, ld%d, lq%d, hk%d)" % (i + 1, i, qs[i], ks[i], i, i, i))
        body.append("  +lr%d = UB.low16_le(%s)" % (i, us[i]))
    args = ["65536n", "65535n", "{==}"] + a + b + pl + d + es[1:] + r + ks[1:]
    args += ["hs%d" % i for i in range(N)] + ["ht%d" % i for i in range(N)]
    args += ["hk%d" % N, "he%d" % N] + ["lr%d" % i for i in range(N)] + ["ld%d" % i for i in range(N)] + ["lta", "ltb"]
    rhs = "Nat.mod(Nat.add(D.val(65536n, %s), Nat.sub(D.val(65536n, %s), D.val(65536n, %s))), D.val(65536n, %s))" % (fp(a), fp(pl), fp(b), fp(pl))
    body.append("  %%Equal.sym(Nat, D.val(65536n, Fp.sub(%s, %s)), D.val(65536n, %s), {==}) : {_ == %s : Nat}" % (fp(a), fp(b), fp(r), rhs))
    body.append("  SC.sub_core(%s)" % ", ".join(args))
    out += ["        " + x for x in body]
    out.append("")
    return "\n".join(out)


def main():
    _, plimbs = GA.read_add()
    read_sub(plimbs)
    open(os.path.join(HERE, "subcore.bend"), "w").write(gen_core())
    open(os.path.join(HERE, "subproof.bend"), "w").write(gen_proof(plimbs))
    print("ok")


if __name__ == "__main__":
    main()
