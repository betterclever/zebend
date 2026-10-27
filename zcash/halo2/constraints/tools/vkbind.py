"""Bind an extracted constraint system to the verifying key zcash/halo2/verifier actually uses.

usage: vkbind.py DUMP.vk.json VERIFIER.bend

The extractor writes DUMP.vk.json from orchard's VerifyingKey::build(version), whose pinned
representation it has shown equal to the VK rebuilt from the dump's own layout (vk_match).
zcash/halo2/verifier's generated verifier (orchard_dyn_fast.bend: post-NU6.3,
orchard_dyn_nu62.bend, orchard_dyn_prenu62.bend) hard-codes the same VK: its fixed
commitments VK_FIXED<i>, permutation commitments VK_PERM<i>, and the transcript_repr scalar
absorbed right after the instance commitments (L.bab_scalar after L.inst_comms). Those
verifiers accept the sampled mainnet bundles of their era (zcash/halo2/verifier/README.md), so
equality here means the dump is the deployed circuit of that era.
"""
import json, re, sys
P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
RINV = pow(2 ** 256, -1, P)
vk = json.load(open(sys.argv[1]))
src = open(sys.argv[2]).read()
pt = re.compile(r"Fq\.from_words\(Wd\.W\{([\d, ]+)\}\), Fq\.from_words\(Wd\.W\{([\d, ]+)\}\)")
def defs(prefix):
    out = {}
    for m in re.finditer(rf"^def {prefix}(\d+)\(\) -> L\.BP:\n  (.*)$", src, re.M):
        p = pt.search(m.group(2))
        out[int(m.group(1))] = [p.group(1), p.group(2)]
    return [out[i] for i in sorted(out)]
fixed, perm = defs("VK_FIXED"), defs("VK_PERM")
m = re.search(r"L\.inst_comms\(.*\n.*\n  \+(st\d+) = L\.pl_st.*\n  \+st\d+ = L\.bab_scalar\(\1, (K\d+)\(\)\)", src)
k = m.group(2)
limbs = [int(x) for x in re.search(rf"^def {k}\(\) -> L\.BF:\n  L\.BF0\{{Fp\.Fp\{{([\d, ]+)\}}\}}", src, re.M).group(1).split(",")]
repr_bend = sum(l << (16 * i) for i, l in enumerate(limbs)) * RINV % P
ok_f = fixed == vk["fixed_commitments"]
ok_p = perm == vk["permutation_commitments"]
ok_r = repr_bend == int(vk["transcript_repr"], 16)
print(f"{sys.argv[1].split('/')[-1]} vs {sys.argv[2].split('/')[-1]}: fixed commitments {len(fixed)}/{len(vk['fixed_commitments'])} "
      f"{'EQUAL' if ok_f else 'DIFFER'}; permutation commitments {len(perm)}/{len(vk['permutation_commitments'])} "
      f"{'EQUAL' if ok_p else 'DIFFER'}; transcript_repr {'EQUAL' if ok_r else 'DIFFER'} (0x{repr_bend:064x})")
sys.exit(0 if ok_f and ok_p and ok_r else 1)
