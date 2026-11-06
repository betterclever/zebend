#!/usr/bin/env bash
# variant.sh CHUNK C NAME: build v/NAME with msm_par chunk_terms = CHUNK and the large-chunk window width = C
set -euo pipefail
cd "$(dirname "$0")/.."
cp lib/msm_par.bend /tmp/msm_par.keep.$$
trap 'cp /tmp/msm_par.keep.$$ lib/msm_par.bend; rm -f /tmp/msm_par.keep.$$' EXIT
python3 - "$1" "$2" <<'PY'
import re,sys
p='lib/msm_par.bend'; s=open(p).read()
s=re.sub(r'(def chunk_terms\(\) -> Nat:\n  )\d+n', r'\g<1>'+sys.argv[1]+'n', s)
s=re.sub(r'sel_u\(Nat.is_lt\(m, 1024n\), 7, \d+\)', 'sel_u(Nat.is_lt(m, 1024n), 7, '+sys.argv[2]+')', s)
open(p,'w').write(s)
PY
grep -A1 "def chunk_terms" lib/msm_par.bend | tail -1; grep -o "1024n), 7, [0-9]*" lib/msm_par.bend
./build.sh v/batch_main.bend "v/$3"
