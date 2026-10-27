#!/usr/bin/env python3
"""Bend's Sapling transaction layer (tx_main) on real mainnet transactions.

  python3 check_txs.py raw START COUNT [SLICE]   transactions START.. of ../data/sig_raw.bin
      (records: u32 height | txid 32 | u32 len | raw tx; txids as indexed by lightwalletd and
      re-checked by zcash_primitives in the oracle). Bend parses each tx, computes its txid,
      shielded sighash, description checks and every RedJubjub verdict. Compared: txid with
      the record's; sighash with the Rust oracle's (the msg field of ../data/sigs chunks,
      via manifest.txt) when available. v5 txs with transparent inputs are skipped (their
      sighash needs the spent outputs).
  python3 check_txs.py tamper START COUNT         byte flips in real v4 txs (see tamper())
  python3 check_txs.py sample                    the detailed sample ../data/txs (expected.txt,
      tx_N.bin, tx_N.ctx): txid, sighash, counts, valueBalance per tx
"""
import pathlib, struct, subprocess, sys, time

here = pathlib.Path(__file__).resolve().parent
D = here.parent / "data"
W = D / "tx_work"
W.mkdir(exist_ok=True)
HEAVY = str(here.parent.parent.parent / "tools/heavy.sh")


def read_raw(path, start, count):
    out = []
    with open(path, "rb") as f:
        i = 0
        while len(out) < count:
            hdr = f.read(40)
            if len(hdr) < 40:
                break
            h, = struct.unpack_from("<I", hdr, 0)
            txid = hdr[4:36]
            n, = struct.unpack_from("<I", hdr, 36)
            b = f.read(n)
            if len(b) < n:
                break
            if i >= start:
                out.append((h, txid, b, b""))
            i += 1
    return out


def has_tin(b):
    """v5: does the tx have transparent inputs? (header 4, vgid 4, branch 4, lock 4, expiry 4)"""
    k = b[20]
    if k == 0:
        return False
    if k < 253:
        n = k
    else:
        n = 1
    return n > 0 and not (b[21:53] == bytes(32) and b[53:57] == b"\xff\xff\xff\xff")


def run_bend(recs, tag, threads=None):
    f = W / f"txs_{tag}.bin"
    with open(f, "wb") as o:
        o.write(struct.pack("<I", len(recs)))
        for h, _, b, ctx in recs:
            o.write(struct.pack("<II", h, len(b)) + b + struct.pack("<I", len(ctx)) + ctx)
    cmd = [HEAVY, str(here / "tx_main"), str(f)]
    if threads:
        cmd += ["+RTS", "--threads", str(threads), "-RTS", "--RTS"]
    t = time.time()
    out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip().split("\n")
    lines = {int(l.split()[0]): l.split() for l in out if l and l[0].isdigit()}
    tot = [l for l in out if l.startswith("TOTAL")]
    return lines, (tot[0] if tot else "?"), time.time() - t


def sighashes_from_chunks():
    """txid(hex, record order) -> sighash hex (the msg field of its items) from the Rust chunks."""
    m = {}
    man = D / "sigs/manifest.txt"
    if not man.exists():
        return m
    rows = [l.split() for l in open(man) if l.strip() and not l.startswith("#")]
    by_chunk = {}
    for r in rows:
        by_chunk.setdefault(int(r[0]), []).append(r)
    for c, rs in by_chunk.items():
        blob = open(D / f"sigs/chunk_{c:04d}.bin", "rb").read()
        pos = 4
        for r in rs:
            kind, ncv = struct.unpack_from("<II", blob, pos)
            msg = blob[pos + 16 + 64: pos + 16 + 96]
            m[r[2]] = msg.hex()
            pos += 16 + 128 + 32 * ((ncv & 0xFFFF) + (ncv >> 16))
    return m


def raw(start, count, slice_=2000):
    recs = read_raw(D / "sig_raw.bin", start, count)
    v56 = (b"\x05\x00\x00\x80", b"\x06\x00\x00\x80")
    skipped = [r for r in recs if r[2][:4] in v56 and has_tin(r[2])]
    recs = [r for r in recs if not (r[2][:4] in v56 and has_tin(r[2]))]
    rust_sh = sighashes_from_chunks()
    st = dict(n=0, v4=0, v5=0, txid=0, sh_cmp=0, sh_ok=0, cons=0, sa=0, sa_ok=0, bd=0, bd_ok=0)
    feat = dict(v4_joinsplit=0, v4_tin=0, v4_spends_ge2=0, v4_outputs_ge3=0)
    for _, _, b, _ in recs:
        if b[:4] == b"\x04\x00\x00\x80":
            q = v4_pos(b)
            feat["v4_joinsplit"] += q["nj"] > 0
            feat["v4_tin"] += q["nvin"] > 0
            feat["v4_spends_ge2"] += q["ns"] >= 2
            feat["v4_outputs_ge3"] += q["no"] >= 3
    bad = []
    t_bend = 0.0
    for k in range(0, len(recs), slice_):
        part = recs[k:k + slice_]
        lines, tot, dt = run_bend(part, f"{start + k}")
        t_bend += float(tot.split(" ms ")[1]) / 1000 if " ms " in tot else 0
        for i, (h, txid, b, _) in enumerate(part):
            p = lines.get(i)
            st["n"] += 1
            if p is None:
                bad.append(("no output", h, txid.hex()))
                continue
            _, ver, btxid, bsh, ns, no, vlo, vhi, cons, nj, verd = (p + [""])[:11]
            st["v" + ver] = st.get("v" + ver, 0) + 1
            if btxid in (txid.hex(), txid[::-1].hex()):
                st["txid"] += 1
            else:
                bad.append(("txid", h, txid.hex(), btxid))
            key = txid.hex()
            if key in rust_sh or txid[::-1].hex() in rust_sh:
                st["sh_cmp"] += 1
                want = rust_sh.get(key, rust_sh.get(txid[::-1].hex()))
                if want == bsh:
                    st["sh_ok"] += 1
                else:
                    bad.append(("sighash", h, key, bsh, want))
            st["cons"] += cons == "1"
            nsa = int(ns)
            st["sa"] += nsa
            st["sa_ok"] += verd[:nsa].count("1")
            if int(ns) + int(no) > 0:
                st["bd"] += 1
                st["bd_ok"] += verd[nsa:nsa + 1] == "1"
        print(f"..{start + k + len(part)}: {st}", flush=True)
    print(f"txs {st['n']} (v4 {st['v4']}, v5 {st['v5']}; skipped {len(skipped)} v5 with transparent inputs)")
    print(f"txid match {st['txid']}/{st['n']}; sighash == Rust {st['sh_ok']}/{st['sh_cmp']} (compared where a Rust chunk has the tx)")
    print(f"description checks pass {st['cons']}/{st['n']}; spend-auth sigs valid under Bend's own sighash {st['sa_ok']}/{st['sa']}; binding {st['bd_ok']}/{st['bd']}")
    print(f"Bend time (tx_main, parse+txid+sighash+checks+single-sig verification) {t_bend:.1f} s")
    print(f"coverage: {feat}")
    for x in bad[:10]:
        print("  BAD", x)


def sample():
    S = D / "txs"
    rows = [l.split() for l in open(S / "expected.txt") if l.strip() and not l.startswith("#")]
    recs = []
    for r in rows:
        n = r[0]
        ctxp = S / f"tx_{n}.ctx"
        recs.append((int(r[1]), None, (S / f"tx_{n}.bin").read_bytes(), ctxp.read_bytes() if ctxp.exists() else b""))
    lines, tot, dt = run_bend(recs, "sample")
    ok = dict(txid=0, sighash=0, counts=0, vb=0, cons=0)
    sigs = dict(sa=0, sa_ok=0, bd=0, bd_ok=0)
    bad = []
    for i, r in enumerate(rows):
        p = lines.get(i)
        if p is None:
            bad.append(("no output", r[0]))
            continue
        _, ver, btxid, bsh, ns, no, vlo, vhi, cons, nj, verd = (p + [""])[:11]
        n, h, v, br, txid, sh, ens, eno, evb = r[:9]
        ok["txid"] += btxid in (txid, bytes.fromhex(txid)[::-1].hex())
        ok["sighash"] += bsh == sh
        ok["counts"] += (ns, no) == (ens, eno)
        vb = int(vlo) | (int(vhi) << 32)
        vb = vb - (1 << 64) if vb >= 1 << 63 else vb
        ok["vb"] += vb == int(evb)
        ok["cons"] += cons == "1"
        sigs["sa"] += int(ns)
        sigs["sa_ok"] += verd[:int(ns)].count("1")
        if int(ns) + int(no) > 0:
            sigs["bd"] += 1
            sigs["bd_ok"] += verd[int(ns):int(ns) + 1] == "1"
        if bsh != sh or btxid not in (txid, bytes.fromhex(txid)[::-1].hex()):
            bad.append((n, v, btxid, txid, bsh, sh))
    print(f"sample txs {len(rows)}: " + ", ".join(f"{k} {v}/{len(rows)}" for k, v in ok.items()) + f"; {tot}")
    print(f"RedJubjub under Bend's sighash: spend-auth {sigs['sa_ok']}/{sigs['sa']}, binding {sigs['bd_ok']}/{sigs['bd']}")
    for b in bad[:10]:
        print("  BAD", b)


def cs(b, p):
    k = b[p]
    if k < 253:
        return k, p + 1
    if k == 253:
        return int.from_bytes(b[p + 1:p + 3], "little"), p + 3
    if k == 254:
        return int.from_bytes(b[p + 1:p + 5], "little"), p + 5
    return int.from_bytes(b[p + 1:p + 9], "little"), p + 9


def v4_pos(b):
    """Positions in a v4 tx (Python, only to choose which byte to flip)."""
    n, p = cs(b, 8)
    for _ in range(n):
        p += 36
        l, p = cs(b, p)
        p += l + 4
    n, p = cs(b, p)
    for _ in range(n):
        p += 8
        l, p = cs(b, p)
        p += l
    vb = p + 8
    nvin, _ = cs(b, 8)
    ns, sp = cs(b, p + 16)
    no, op = cs(b, sp + 384 * ns)
    nj, _ = cs(b, op + 948 * no)
    return dict(vb=vb, ns=ns, sp=sp, no=no, op=op, nj=nj, nvin=nvin)


def tamper(start, count):
    """Negative tests on real v4 txs with >= 1 spend and >= 1 output: (a) one byte of the
    first output's encCiphertext, (b) one byte of spend 0's signature s, (c) valueBalance + 1."""
    recs = [r for r in read_raw(D / "sig_raw.bin", start, count) if r[2][:4] == b"\x04\x00\x00\x80"]
    cases = []
    for h, txid, b, _ in recs:
        q = v4_pos(b)
        if q["ns"] < 1 or q["no"] < 1:
            continue
        a = bytearray(b); a[q["op"] + 96 + 17] ^= 1
        c = bytearray(b); c[q["sp"] + 320 + 40] ^= 1
        d = bytearray(b); d[q["vb"]] = (d[q["vb"]] + 1) & 255
        cases += [("enc", h, txid, bytes(a), q), ("sig0", h, txid, bytes(c), q), ("vb", h, txid, bytes(d), q)]
    orig, _, _ = run_bend([(h, t, b, b"") for h, t, b, _ in recs], "tamper_orig")
    osh = {orig[i][2]: orig[i][3] for i in orig}
    lines, _, _ = run_bend([(h, t, b, b"") for _, h, t, b, _ in cases], "tamper")
    ok = {"enc": 0, "sig0": 0, "vb": 0}
    tot = {"enc": 0, "sig0": 0, "vb": 0}
    for i, (kind, h, txid, b, q) in enumerate(cases):
        p = lines[i]
        btxid, bsh, verd = p[2], p[3], p[10]
        tot[kind] += 1
        changed_id = btxid not in (txid.hex(), txid[::-1].hex())
        if kind in ("enc", "vb"):
            good = changed_id and "1" not in verd
        else:
            good = changed_id and verd[0] == "0" and "0" not in verd[1:]
        ok[kind] += good
    for k in ok:
        print(f"tamper {k}: {ok[k]}/{tot[k]} behave as expected")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "tamper":
        tamper(int(a[1]), int(a[2]))
    elif a[0] == "raw":
        raw(int(a[1]), int(a[2]), int(a[3]) if len(a) > 3 else 2000)
    else:
        sample()
