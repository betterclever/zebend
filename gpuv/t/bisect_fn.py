# bisect_fn.py prog.c: find the INLINE helpers whose forced inlining crashes Apple's GPU
# compiler. A variant leaves a subset of INLINE definitions as plain `inline` (Metal may
# then keep them as calls) and asks --gpu-build whether the compiler survives.
import re, subprocess, sys, tempfile, os
src = open(sys.argv[1]).read()
CC = "/opt/homebrew/opt/llvm/bin/clang"
defs = [m.start() for m in re.finditer(r'^INLINE [^;{]*?\b(\w+)\(', src, re.M)]
names = [re.match(r'^INLINE [^;{]*?\b(\w+)\(', src[i:]).group(1) for i in defs]
d = tempfile.mkdtemp()
def ok(plain):  # plain: set of indices left as plain inline
    s = list(src); 
    out = src
    for i in sorted(plain, reverse=True):
        out = out[:defs[i]] + "INLINE_PLAIN" + out[defs[i] + len("INLINE"):]
    out = "#ifdef __METAL_VERSION__\n#define INLINE_PLAIN inline\n#else\n#define INLINE_PLAIN static inline\n#endif\n" + out
    c = os.path.join(d, "v.c"); b = os.path.join(d, "v")
    open(c, "w").write(out)
    if subprocess.run([CC, "-x", "objective-c", "-fobjc-arc", "-fmodules", "-DBEND_METAL=1", "-std=c11", "-O3", c, "-lpthread", "-lm", "-o", b], capture_output=True).returncode:
        sys.exit("host build failed")
    return subprocess.run([b, "+RTS", "--gpu-build"], capture_output=True).returncode == 0
print(len(names), "INLINE defs")
# Find a minimal set whose plain-ness makes the build pass (greedy halving).
cand = list(range(len(names)))
assert ok(set(cand)), "all plain still fails"
assert not ok(set()), "all forced passes"
while len(cand) > 1:
    h = cand[:len(cand) // 2]
    if ok(set(h)): cand = h
    elif ok(set(cand[len(cand) // 2:])): cand = cand[len(cand) // 2:]
    else: break
print("plain set that passes:", [names[i] for i in cand])
for i in cand:
    print(names[i], "alone plain ->", "OK" if ok({i}) else "FAIL")
