#!/usr/bin/env python3
"""Generates the Zebra NU7 oracle vectors in ../data/vectors/ by driving target/release/nu7-oracle.

Run on the Mac:  python3 gen.py   (after `cargo build --release` in this directory).
Every random choice uses a fixed seed, so the outputs are reproducible.
"""
import json, os, random, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "target/release/nu7-oracle")
OUT = os.path.join(HERE, "../data/vectors")
os.makedirs(OUT, exist_ok=True)


def run(args, stdin=""):
    r = subprocess.run([BIN] + args, input=stdin, capture_output=True, text=True, check=True)
    return r.stdout


def write(name, text):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(text)


def heights_for(net, c):
    A = c["nu7_activation"]
    acts = c["activation_heights"]
    hs = set(range(A - 300, A + 301))
    for nu in ("Blossom", "Canopy", "Nu6", "Nu6_1"):
        hs.update(range(acts[nu] - 3, acts[nu] + 4))
    for h in c["height_for_halving_1_to_6"][:5]:
        if isinstance(h, int):
            hs.update(range(h - 3, h + 4))
    for fs in c["funding_streams"]:
        for e in (fs["start"], fs["end"]):
            hs.update(range(e - 3, e + 4))
    # Address-period boundaries (from `nu7-oracle boundaries`) between NU6.1 and the stream end.
    for line in run(["boundaries", net]).splitlines():
        b = json.loads(line)
        for x in b["boundaries"]:
            if acts["Nu6_1"] <= x < b["end"]:
                hs.update((x - 1, x, x + 1))
    r = c["nsm_reissuance_height"]
    if r:
        hs.update(range(r - 3, r + 4))
    rng = random.Random(f"zebra-heights-{net}")
    hs.update(rng.randint(1, 20_000_000) for _ in range(2000))
    hs.update(rng.randint(A, A + 3_000_000) for _ in range(1000))
    return sorted(h for h in hs if h >= 0)


FEES = list(range(31)) + [99, 100, 101, 999, 1000, 1001, 12345, 9999999, 10**8 + 1,
        2**32 - 1, 2**32, 2**40 + 7, 2**48 - 1, 2**48, 2**50, 2099999999999999, 2100000000000000]
BALANCES = [0, 1, 2, 7272727, 7272728, 10**8, 10**12, 36858445520, 21 * 10**12, 5 * 10**14,
            105 * 10**13, 21 * 10**14]


def chain_input(start_h, n, start_bits, interval, fixed):
    """Lines 'h t bits' for heights start_h..start_h+n-1; the first `fixed` lines give
    `start_bits`, later ones '?'. t(start_h) = 1760000000, t(h) = t(h-1) + interval(h)."""
    lines, t = [], 1_760_000_000
    for i in range(n):
        h = start_h + i
        if i:
            t += interval(h)
        lines.append(f"{h} {t} {start_bits if i < fixed else '?'}")
    return "\n".join(lines) + "\n"


def diffchain(net, name, inp):
    write(name + ".in", inp)
    write(name + ".jsonl", run(["diffchain", net], inp))


for net in ("mainnet", "testnet"):
    c = json.loads(run(["consts", net]))
    write(f"zebra_consts_{net}.json", json.dumps(c, indent=1, sort_keys=True) + "\n")
    A, R = c["nu7_activation"], c["nsm_reissuance_height"]

    hs = heights_for(net, c)
    hin = "\n".join(map(str, hs)) + "\n"
    write(f"heights_{net}.txt", hin)
    write(f"zebra_heights_{net}.jsonl", run(["heights", net], hin))

    rng = random.Random(f"zebra-fees-{net}")
    fees = FEES + [rng.randint(0, 2_100_000_000_000_000) for _ in range(500)]
    fin = "".join(f"{h} {f}\n" for h in (A - 1, A, A + 1, A + 10**6) for f in fees)
    write(f"zebra_fees_{net}.jsonl", run(["fees", net], fin))

    rng = random.Random(f"zebra-nsm-{net}")
    nhs = [R - 1, R, R + 1, R + 10**6, 30_000_000, A - 1, A, A + 1]
    pairs = [(h, b) for h in nhs for b in BALANCES]
    pairs += [(rng.choice([rng.randint(A, 30_000_000), rng.randint(R, R + 5)]),
               rng.randint(0, 2_100_000_000_000_000)) for _ in range(300)]
    write(f"zebra_nsm_{net}.jsonl", run(["nsm", net], "".join(f"{h} {b}\n" for h, b in pairs)))

# ---- Synthetic difficulty chains.
cm = json.loads(open(os.path.join(OUT, "zebra_consts_mainnet.json")).read())
A = cm["nu7_activation"]
PRE, POST = [75, 60, 90, 75, 80, 70], [25, 20, 30, 25, 27, 23]
n = 1801  # heights A-300 ..= A+1500
for suffix, post in (("", lambda h: POST[(h - A) % 6]), ("_slow75", lambda h: 75),
                     ("_fast8", lambda h: 8)):
    iv = lambda h, post=post: PRE[h % 6] if h < A else post(h)
    diffchain("mainnet", f"zebra_diffchain_mainnet_synth{suffix}",
              chain_input(A - 300, n, "1c0a1b2c", iv, 120))

ct = json.loads(open(os.path.join(OUT, "zebra_consts_testnet.json")).read())
TA = ct["nu7_activation"]
# Min-difficulty gaps: Zebra uses 6*75 = 450 s before NU7 and 18*25 = 450 s after
# (network_upgrade.rs:530), and compares `gap > threshold` (network_upgrade.rs:569).
SPECIAL = {TA - 150: 449, TA - 140: 450, TA - 130: 451, TA - 120: 900, TA - 110: 901, TA - 20: 1000,
           TA: 451, TA + 1: 450, TA + 30: 449, TA + 60: 450, TA + 90: 451, TA + 150: 900,
           TA + 200: 901, TA + 250: 1200, TA + 251: 451, TA + 400: 452}
def tiv_base(h):
    return PRE[h % 6] if h < TA else POST[(h - TA) % 6]
def tiv(h):
    if h in SPECIAL:
        return SPECIAL[h]
    return PRE[h % 6] if h < TA else POST[(h - TA) % 6]
diffchain("testnet", "zebra_diffchain_testnet_synth", chain_input(TA - 300, 1001, "1c0a1b2c", tiv, 120))
# Second testnet chain: one min-difficulty block (451 s) only after NU7, and a 450 s gap at A,
# so most of the post-NU7 chain is away from the PoW limit.
SPECIAL2 = {TA: 450, TA + 100: 449, TA + 300: 451, TA + 301: 450}
diffchain("testnet", "zebra_diffchain_testnet_synth_post",
          chain_input(TA - 300, 1001, "1c0a1b2c", lambda h: SPECIAL2.get(h) or tiv_base(h), 120))

# ---- Zakura's chain D and D2 (crates/zakura-consensus/tests/nu7_diff_dump.rs, difficulty_chain),
# reproduced on public Testnet (scenario testnet-real): heights A-200..=A+300, first 29 blocks
# fixed bits, t(start) = 1760000000.
ZPRE = [37, 75, 90, 60, 150, 20, 25, 25, 10, 500, 75, 30]
ZPOST = [12, 25, 30, 20, 50, 25, 8, 40, 25, 480, 25, 460]
diffchain("testnet", "zebra_diffchain_testnet_zakuraD",
          chain_input(TA - 200, 501, "1f07ffff", lambda h: ZPRE[h % 12] if h < TA else ZPOST[h % 12], 29))
ZPRE2 = [60, 90, 75, 70, 80, 75, 65, 85, 75, 72, 78, 75]
ZPOST2 = [20, 30, 25, 23, 27, 25, 22, 28, 25, 24, 26, 25]
def d2(h, a=TA):
    if h < a:
        return 225 if a - 100 <= h < a - 60 else 25 if a - 60 <= h < a - 30 else ZPRE2[h % 12]
    return 75 if a + 100 <= h < a + 150 else 8 if a + 150 <= h < a + 200 else ZPOST2[h % 12]
diffchain("testnet", "zebra_diffchain_testnet_zakuraD2", chain_input(TA - 200, 501, "1d00ffff", d2, 29))
print("done")
