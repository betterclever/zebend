# Swapping in the faster `tv` (speed round 2)

`tv.new` is `tv2_main.bend` built with the same compiler and flags as `tv`
(`../../tools/heavy.sh ./build.sh tv2_main.bend tv.new`, fork `bend-fork`, branch `metal-spill`). It reads the same
ZTV1 files and prints the same `r <k> <verdicts>` lines. What changed and the test results are in
README.md, "Speed round 2".

`hook.py` starts a new `zcash/transparent/tv` process for every chunk of 200 transactions
(`subprocess.run([TV, path])`). A process that is already running keeps the binary it started
with. The next chunk execs whatever `zcash/transparent/tv` is at that moment. So an atomic rename
switches the hook over at its next window, and no hook restart is needed.

## Swap

```sh
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
# 1. sanity: the new binary agrees with the old one on a real file
./tv data/real/nu6_1_0.ztv > /tmp/tv_old.out && ./tv.new data/real/nu6_1_0.ztv > /tmp/tv_new.out && cmp /tmp/tv_old.out /tmp/tv_new.out && echo SAME
# 2. keep the old binary for rollback (a hard link, so the old inode stays valid for running processes)
ln -f tv tv.round1
# 3. atomic swap: rename(2) on the same filesystem; running tv processes are unaffected
cp tv.new tv.swap && chmod +x tv.swap && mv -f tv.swap tv
```

`tv.new` is kept so the swap can be repeated or compared later. Copying it to `tv.swap` first
means the `mv` is always a same-directory rename, which is atomic. A half-written `tv` is never
visible.

## Rollback

```sh
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
cp tv.round1 tv.swap && mv -f tv.swap tv
```

Here too the hook picks up the rolled-back binary at its next chunk.

## Check after the swap

- `python3 t/hook_test.py data/real/blossom_0.ztv 150` is the end-to-end hook test (real chunks → PASS, r-bit-flipped copies → FAIL). It gave 300 of 300 as expected with `tv.new` before the swap, through `secp2/t/hook_test_new.py`. On `nu6_1_0.ztv`, 7 tampered items stay PASS, exactly as with the old `tv` (see the README's hook section).
- `../../tools/heavy.sh python3 run_diff.py data/real` uses `./tv` by default and should report 0 mismatches over 131,146 inputs.
- In the node's hook log, verdict lines should keep the same `PASS` / `FAIL` mix. `FAIL tv produced no verdict` should not show up.
