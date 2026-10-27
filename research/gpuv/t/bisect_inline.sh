#!/bin/zsh
# bisect_inline.sh prog.c: rebuild the emitted C with variants of the Metal inline macros and
# report whether Apple's GPU compiler (at --gpu-build) accepts each.
src=$1; d=$(mktemp -d)
CC=/opt/homebrew/opt/llvm/bin/clang
try() {
  name=$1; shift
  python3 - "$src" "$d/$name.c" "$@" <<'PY'
import sys
s=open(sys.argv[1]).read()
for a in sys.argv[3:]:
    old,new=a.split('=>',1); assert old in s, old; s=s.replace(old,new,1)
open(sys.argv[2],'w').write(s)
PY
  $CC -x objective-c -fobjc-arc -fmodules -DBEND_METAL=1 -std=c11 -O3 $d/$name.c -lpthread -lm -o $d/$name 2>/dev/null || { echo "$name: host build failed"; return; }
  if $d/$name +RTS --gpu-build 2>$d/$name.err; then echo "$name: OK"; else echo "$name: FAIL $(head -c 150 $d/$name.err)"; fi
}
AI='inline __attribute__((always_inline))'
try all
try inline_plain "#define INLINE  $AI=>#define INLINE  inline"
try far_noinline "#define FAR     static INLINE=>#define FAR     static __attribute__((noinline))"
try outline_plain "#define OUTLINE static INLINE=>#define OUTLINE static"
rm -rf $d
