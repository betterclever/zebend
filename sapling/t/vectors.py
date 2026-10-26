#!/usr/bin/env python3
"""Differential test of the Bend Jubjub layer against the Rust oracle's vectors
(../data/vectors/*.txt, written by sapling-oracle `vectors` from bls12_381, jubjub,
sapling-crypto and redjubjub). Runs t/vec_main, sig/sig_main (0 = per-signature mode) and
tree/tree_main e, and prints match counts per category.

  python3 vectors.py"""
import pathlib, struct, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
V = here.parent / "data/vectors"
W = here / "work"
W.mkdir(exist_ok=True)
Q = 0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000001
RJ = 0x0E7DB4EA6533AFA906673B0101343B00A6682093CCC81082D0970E5ED6F72CB7
results = []


def lines(name, tag=None):
    for l in open(V / name):
        if l.startswith("#") or not l.strip():
            continue
        p = l.split()
        if tag is None or p[0] == tag:
            yield p


def b(h):
    return bytes.fromhex(h)


def run_vec(op, recs):
    f = W / f"v_{op}.bin"
    f.write_bytes(b"".join(recs))
    out = subprocess.run([str(here / "vec_main"), op, str(f), str(len(recs))], capture_output=True, text=True).stdout
    return out.split("\n")[:len(recs)]


def report(name, ok, n, bad):
    results.append((name, ok, n))
    print(f"{name}: {ok}/{n}")
    for x in bad[:3]:
        print("   mismatch:", x)


def neg_hex(h):
    return ((Q - int.from_bytes(b(h), "little")) % Q).to_bytes(32, "little").hex()


# --- Fr (Jubjub base field) ---
rows = [r for r in lines("fr.txt") if len(r) == 8]
out = run_vec("fr", [b(r[0]) + b(r[1]) for r in rows])
ok, bad = 0, []
for r, o in zip(rows, out):
    a_, b_, add, sub, mul, sq, inv, rt = r
    p = o.split()
    inv_b = p[4] if int.from_bytes(b(a_), "little") % Q else "none"
    good = p[:4] == [add, sub, mul, sq] and inv_b == inv and (p[5] == rt or (rt != "none" and p[5] == neg_hex(rt)))
    ok += good
    if not good:
        bad.append((r, o))
report("Fr add/sub/mul/sqr/inv/sqrt (bls12_381::Scalar)", ok, len(rows), bad)

# --- Fs (Jubjub scalar field) ---
rows = list(lines("fs.txt", "wide"))
out = run_vec("fs", [b(r[1]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.strip() != r[2]]
report("Fs from_bytes_wide (jubjub::Fr)", len(rows) - len(bad), len(rows), bad)
rows = list(lines("fs.txt", "arith"))
out = run_vec("fsa", [b(r[1]) + b(r[2]) for r in rows])
ok, bad = 0, []
for r, o in zip(rows, out):
    p = o.split()
    inv_b = p[3] if int.from_bytes(b(r[1]), "little") % RJ else "none"
    good = p[:3] == r[3:6] and inv_b == r[6]
    ok += good
    if not good:
        bad.append((r, o))
report("Fs add/mul/neg/inv (jubjub::Fr)", ok, len(rows), bad)

# --- points ---
rows = list(lines("points.txt", "decode"))
out = run_vec("dec", [b(r[1]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.strip() != r[2]]
report("decode, ZIP 216 (AffinePoint::from_bytes)", len(rows) - len(bad), len(rows), bad)
nz = sum(1 for r in rows if r[2] == "none")
print(f"   ({nz} of them rejected by Rust; {sum(1 for r in rows if r[2] != r[3])} differ between ZIP 216 and pre-ZIP 216)")
rows = list(lines("points.txt", "add"))
out = run_vec("add", [b(r[1]) + b(r[2]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.split()[:2] != r[3:5]]
report("add P+Q, double 2P", len(rows) - len(bad), len(rows), bad)
rows = list(lines("points.txt", "mul"))
out = run_vec("mul", [b(r[1]) + b(r[2]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.strip() != r[3]]
report("scalar mul [k]P", len(rows) - len(bad), len(rows), bad)
rows = list(lines("points.txt", "order"))
out = run_vec("add", [b(r[1]) + b(r[1]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.split()[2:4] != [r[2], r[3]]]
report("[8]P and is_small_order", len(rows) - len(bad), len(rows), bad)
out = run_vec("mul", [b(r[1]) + RJ.to_bytes(32, "little") for r in rows])
ident = (1).to_bytes(32, "little").hex()
bad = [(r, o) for r, o in zip(rows, out) if (o.strip() == ident) != (r[4] == "1")]
report("is_torsion_free ([r_J]P == 0)", len(rows) - len(bad), len(rows), bad)
rows = list(lines("points.txt", "torsion"))
out = run_vec("add", [b(r[3]) + b(r[3]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.split()[3:4] != ["1"]]
report("the 8 small-order points decode and are small-order", len(rows) - len(bad), len(rows), bad)

# --- constants and empty roots ---
sys.path.insert(0, str(here.parent / "jubjub"))
import jj
g = jj.gens()
names = {"SPENDING_KEY_GENERATOR": "G_SPENDAUTH", "VALUE_COMMITMENT_VALUE_GENERATOR": "V_CV",
         "VALUE_COMMITMENT_RANDOMNESS_GENERATOR": "R_CV"}
for i in range(6):
    names[f"PEDERSEN_HASH_GENERATORS[{i}]"] = f"PH{i}"
cs = {r[0]: r for r in lines("consts.txt")}
bad = [k for k, v in names.items() if [g[v][0].to_bytes(32, "little").hex(), g[v][1].to_bytes(32, "little").hex()] != cs[k][1:3]]
report("generators used by Bend (jj.py GroupHash) = sapling_crypto constants", len(names) - len(bad), len(names), bad)
d_ok = cs["EDWARDS_D"][1] == jj.D.to_bytes(32, "little").hex()
report("Jubjub d", int(d_ok), 1, [] if d_ok else [cs["EDWARDS_D"]])
er = [r for r in lines("consts.txt", "EMPTY_ROOT")]
out = subprocess.run([str(here.parent / "tree/tree_main"), "e"], capture_output=True, text=True).stdout.split("\n")
got = {int(l.split()[1]): l.split()[2] for l in out if l.startswith("empty")}
bad = [r for r in er if got.get(int(r[1])) != r[2]]
report("empty Sapling roots, levels 0..32 (Bend tree_main e)", len(er) - len(bad), len(er), bad)

# --- Merkle hash ---
rows = list(lines("merkle.txt", "merkle"))
out = run_vec("mh", [int(r[1]).to_bytes(32, "little") + b(r[2]) + b(r[3]) for r in rows])
bad = [(r, o) for r, o in zip(rows, out) if o.strip() != r[4]]
report("MerkleCRH^Sapling (Pedersen hash)", len(rows) - len(bad), len(rows), bad)

# --- RedJubjub ---
rows = [r for r in lines("sig.txt") if r[0] in ("spendauth", "binding")]
items = []
for r in rows:
    kind = 0 if r[0] == "spendauth" else 2
    items.append(struct.pack("<4I", kind, 0, 0, 0) + b(r[2]) + b(r[3]) + b(r[4]) + b(r[1]))
f = W / "v_sig.bin"
f.write_bytes(struct.pack("<I", len(items)) + b"".join(items))
out = subprocess.run([str(here.parent / "sig/sig_main"), "0", str(f)], capture_output=True, text=True).stdout
vs = out.split("verdicts ")[1].split()[0]
bad = [(r, v) for r, v in zip(rows, vs) if v != r[5]]
nt = sum(1 for r in rows if len(r) > 6)
report(f"RedJubjub single verify ({len(rows) - nt} honest + {nt} tampered; {sum(r[5] == '0' for r in rows)} invalid per Rust)", len(rows) - len(bad), len(rows), bad)
out = subprocess.run([str(here.parent / "sig/sig_main"), "11", str(f)], capture_output=True, text=True).stdout
inv = set(int(x) for x in out.split("invalid")[1].split("\n")[0].split())
want = set(i for i, r in enumerate(rows) if r[5] == "0")
report("RedJubjub batch + bisection: invalid set == Rust's", int(inv == want), 1, [] if inv == want else [sorted(inv ^ want)[:10]])

tot = sum(n for _, _, n in results)
okt = sum(o for _, o, _ in results)
print(f"TOTAL {okt}/{tot}")
