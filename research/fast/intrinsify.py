#!/usr/bin/env python3
"""Swap pure-Bend arithmetic helpers for hardware instructions in Bend's emitted C.

Bend 2 has only U32 integers. intrinsics.bend defines, in pure Bend:

    mulhi(a, b)       high 32 bits of a * b
    mach(a, b, c, d)  high 32 bits of a * b + c + d
    addc(x, y, z)     carry out of x + y + z
    subb(x, y, z)     borrows out of x - y - z

so their meaning is fixed by Bend's semantics. Bend compiles each such U32-only def into
an INLINE `spin_N(Env, Term* o, u32 r0, ...)` C function whose locals keep the Bend names
(`_al_0`, `_qs1_0`, `_wc2_0`, ...). This script finds every spin function with one of those
body shapes and replaces the body with the equivalent 64-bit expression. The same C file is
the Metal/CUDA source, where u64 is ulong.

The replacements must agree with the definitions on every input: t/intrinsics_diff.bend checks
edge cases plus 2^24 pseudo-random inputs per intrinsic, and also fails if a patch is broken.

Usage: intrinsify.py in.c out.c   (fails loudly if an intrinsic is not found)
"""
import re
import sys

SIG = re.compile(r"INLINE Term (spin_\d+)\(Env e, THR Term\* o((?:, u32 r\d+)+)\) \{\n")

SPECS = {
    "mulhi": (["U32_BIN(_al_0, *, _bl_0)", "U32_BIN(_ah_0, *, _bh_0)", "u32 _mid_0 ="],
              "(u64)(u32)(((u64)(u32){0} * (u64)(u32){1}) >> 32)"),
    "mach": (["u32 _qlo_0 =", "u32 _qs2_0 =", "u32 _qc2_0 ="],
             "(u64)(u32)(((u64)(u32){0} * (u64)(u32){1} + (u64)(u32){2} + (u64)(u32){3}) >> 32)"),
    "addc": (["u32 _ws1_0 =", "u32 _wc2_0 ="],
             "(u64)(u32)(((u64)(u32){0} + (u64)(u32){1} + (u64)(u32){2}) >> 32)"),
    "subb": (["u32 _ud1_0 =", "u32 _ub2_0 ="],
             "(u64)(u32)(0u - (u32)((((u64)(u32){0}) - (u64)(u32){1} - (u64)(u32){2}) >> 32))"),
}


def patch(src, required=()):
    out, pos, hits = [], 0, {}
    for m in SIG.finditer(src):
        start = m.end()
        end = src.index("  return 1;\n}\n", start)
        body = src[start:end]
        name = next((n for n, (marks, _) in SPECS.items() if all(k in body for k in marks)), None)
        if name is None:
            continue
        nargs = len(m.group(2).split(",")) - 1
        frame = re.match(r"  u32 wpoll = 0;\n" + "".join(rf"  u32 (_\w+?_\d+) = r{i};\n" for i in range(nargs)) + r"  WL_SPIN\n", body)
        if not frame or not body.endswith("  break;\n  }\n"):
            sys.exit(f"intrinsify: {m.group(1)} looks like {name} but its frame changed; refusing to patch")
        expr = SPECS[name][1].format(*frame.groups())
        out.append(src[pos:start] + frame.group(0) + f"    o[0] = {expr};\n  break;\n  }}\n")
        pos = end
        hits.setdefault(name, []).append(m.group(1))
    out.append(src[pos:])
    missing = [n for n in required if n not in hits]
    if missing or not hits:
        sys.exit(f"intrinsify: intrinsic(s) not found: {missing or 'any'} (inlined, unused, or Bend codegen changed?)")
    return "".join(out), hits


if __name__ == "__main__":
    src = open(sys.argv[1]).read()
    new, hits = patch(src, sys.argv[3].split(",") if len(sys.argv) > 3 else ())
    open(sys.argv[2], "w").write(new)
    print("intrinsify: " + "; ".join(f"{n} -> {', '.join(v)}" for n, v in hits.items()), file=sys.stderr)
