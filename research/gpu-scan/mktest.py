#!/usr/bin/env python3
"""Writes t/stage_test.bend: checks every pipeline stage against vectors/out/debug.txt."""
dbg = [l.split() for l in open("vectors/out/debug.txt")]
ivk = bytes.fromhex(dbg[0][1])
W = lambda b: [int.from_bytes(b[4*i:4*i+4], "little") for i in range(8)]
u8w = lambda b: "Z.U8w{" + ", ".join(map(str, W(b))) + "}"
fe = lambda b: "Z.F{" + ", ".join(str(int.from_bytes(b[2*i:2*i+2], "little")) for i in range(16)) + "}"
sc = "Z.Sc{" + ", ".join(map(str, W(ivk))) + "}"
src = ['''import Base
import ./zcrypto.bend as Z

def eqw(a: Z.U8w, b: Z.U8w) -> U32:
  Z.U8w{a0, a1, a2, a3, a4, a5, a6, a7} = a
  Z.U8w{b0, b1, b2, b3, b4, b5, b6, b7} = b
  +x = ((a0 .^. b0) .|. (a1 .^. b1) .|. (a2 .^. b2) .|. (a3 .^. b3) .|. (a4 .^. b4) .|. (a5 .^. b5) .|. (a6 .^. b6) .|. (a7 .^. b7) : U32)
  Bool.to_u32(U32.is_eq(x, 0))

def dec_y(d: Z.Dec) -> Z.F:
  Z.Dec{_, q} = d
  Z.Aff{_, y} = q
  Z.from_mont(y)

def dec_q(d: Z.Dec) -> Z.Aff:
  Z.Dec{_, q} = d
  q

def r(name: String, v: U32) -> String:
  name ++ "=" ++ U32.show(v) ++ " "
''']
body = []
for l in dbg:
    if l[0] == "gen":
        gx, gy = bytes.fromhex(l[2]), bytes.fromhex(l[4])
    if l[0] == "ivk*gen":
        kx, ky = bytes.fromhex(l[2]), bytes.fromhex(l[4])
        enc = bytearray(kx); enc[31] |= (ky[0] & 1) << 7
        body.append(f'r("ivkG", eqw(Z.encode(Z.smul({sc}, Z.Aff{{Z.to_mont({fe(gx)}), Z.to_mont({fe(gy)})}})), {u8w(enc)}))')
for l in dbg:
    if l[0] != "rec":
        continue
    i = l[1]
    kv = dict(zip(l[3::2], l[4::2]))
    epk, y, ct4, shared, key, ks4 = (bytes.fromhex(kv[k]) for k in ("epk", "epk_y", "ct4", "shared", "key", "ks4"))
    lead = int(kv["lead"], 16)
    body.append(f'r("y{i}", Z.fis_eq(dec_y(Z.decompress({u8w(epk)})), {fe(y)}))')
    body.append(f'r("shared{i}", eqw(Z.encode(Z.smul({sc}, dec_q(Z.decompress({u8w(epk)})))), {u8w(shared)}))')
    body.append(f'r("key{i}", eqw(Z.u8w_kdf({u8w(shared)}, {u8w(epk)}), {u8w(key)}))')
    body.append(f'r("ks{i}", Bool.to_u32(U32.is_eq(Z.ks_w0({u8w(key)}), {int.from_bytes(ks4, "little")})))')
    body.append(f'r("flag{i}", Bool.to_u32(U32.is_eq(Z.check({sc}, Z.Rec{{{u8w(epk)}, {int.from_bytes(ct4, "little")}}}), {1 if lead == 3 else 0})))')
src.append("def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(" + " ++ ".join(body) + ")\n")
open("t/stage_test.bend", "w").write("\n".join(src))
