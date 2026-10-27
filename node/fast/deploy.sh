#!/bin/zsh
# fast/deploy.sh: install node/fast into node/. Two phases; run them yourself.
#
#   ./deploy.sh check     verify: live files still equal what research/fast/ was built against
#                         (fast/orig/MD5SUMS), fast/bin present; changes nothing
#   ./deploy.sh bins      phase A, safe while sync.py instances run: atomically replace
#                         bin/blockdelta and bin/rules (cp to .new + mv: a running process
#                         keeps the old inode; the next window execs the new file). Both
#                         binaries are drop-ins for the CURRENT sync.py/rules.py: same CLI,
#                         byte-identical output (research/fast/README.md). Old ones kept as *.pre-fast.
#   ./deploy.sh py        phase B, at a window boundary with the sync instances STOPPED:
#                         sync.py, rules.py (+ the Bend sources, for the record). Then
#                         restart the instances as usual.
#   ./deploy.sh rollback  restore every *.pre-fast file (bins atomically; stop sync first
#                         if phase B was applied).
set -e
F=${0:A:h}
N=${F:h}
cd $N
inst() {  # inst SRC DST: back up DST once, then atomic replace
  [ -e $2 ] && [ ! -e $2.pre-fast ] && cp -p $2 $2.pre-fast
  cp $1 $2.new && mv -f $2.new $2
  echo "  installed $2"
}
fixsrc() {  # fixsrc SRC DST: research/fast/ sources sit one level deeper: ../../../X -> ../../X
  mkdir -p ${2:h}
  [ -e $2 ] && [ ! -e $2.pre-fast ] && cp -p $2 $2.pre-fast
  sed -e 's#\.\./\.\./\.\./#../../#g' $1 > $2.new && mv -f $2.new $2
  echo "  installed $2"
}
case $1 in
  check)
    (cd $N && md5 -r sync.py store.py rules.py rules/rules.bend bend/delta.bend bend/parse.bend bend/zip244.bend \
      | awk '{print $1"  "$2}' | diff - $F/orig/MD5SUMS) && echo "live sources unchanged since research/fast/ was cut: OK"
    cmp -s bin/blockdelta $F/orig/blockdelta && cmp -s bin/rules $F/orig/rules && echo "live binaries = fast/orig: OK"
    ls -la $F/bin/blockdelta $F/bin/rules
    ;;
  bins)
    $0 check
    inst $F/bin/blockdelta bin/blockdelta
    inst $F/bin/rules bin/rules
    ;;
  py)
    $0 check || true
    inst $F/sync.py sync.py
    inst $F/rules.py rules.py
    fixsrc $F/bend/delta.bend bend/delta.bend
    fixsrc $F/bend/zip244.bend bend/zip244.bend
    fixsrc $F/bend/pts.bend bend/pts.bend
    fixsrc $F/bend/sha.bend bend/sha.bend
    fixsrc $F/bend/t_pts.bend bend/t_pts.bend
    fixsrc $F/bend/gpu_variant.py bend/gpu_variant.py
    fixsrc $F/wire/blk.bend wire/blk.bend
    fixsrc $F/wire/txv.bend wire/txv.bend
    fixsrc $F/rules/rules.bend rules/rules.bend
    ;;
  rollback)
    for f in bin/blockdelta bin/rules sync.py rules.py bend/delta.bend bend/zip244.bend rules/rules.bend; do
      [ -e $f.pre-fast ] && cp -p $f.pre-fast $f.new && mv -f $f.new $f && echo "  restored $f"
    done
    ;;
  *)
    sed -n 2,20p $0
    ;;
esac
