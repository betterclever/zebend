# check_sha.py: sha256_arr (mode a) and the live list SHA-256 (mode l) vs hashlib, SHA-256d of
# random messages of every length 0..300 plus a few large ones.
import hashlib, os, subprocess, sys, tempfile
b = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hash_bench")
bad = n = 0
with tempfile.TemporaryDirectory() as d:
    for L in list(range(0, 301)) + [4095, 4096, 4097, 65536 + 55, 1 << 20]:
        p = os.path.join(d, "m"); m = os.urandom(L); open(p, "wb").write(m)
        want = hashlib.sha256(hashlib.sha256(m).digest()).hexdigest()
        for mode in "al":
            got = subprocess.run([b, p, mode, "1"], capture_output=True, text=True).stdout.strip()
            n += 1
            if got != want:
                bad += 1; print("MISMATCH", L, mode, got, want)
print(f"{n} checks, {bad} mismatches")
