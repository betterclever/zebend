#!/bin/zsh
# determinism.sh BIN RUNS [M]: runs a GPU binary (MSM mode M, default 0) RUNS times at leaf sizes 1 and 4 on three
# chunks plus a tampered one and checks that verdicts and digests are identical bit for bit.
# Run under ../../tools/heavy.sh.
cd ${0:a:h}
bin=$1; runs=${2:-20}; m=${3:-0}
for L in 1 4; do
  : > data/det_$L.txt
  for i in {1..$runs}; do
    ./$bin $((m ? 8 : 11)) $L $m data/chunk_0010.bin data/chunk_0012.bin data/chunk_0100.bin data/tamper_s_5.bin +RTS --gpu on -RTS | grep -v leaves | sed -E 's/ ms [0-9]+ prep_ms [0-9]+//; s/verify_ms [0-9]+ sigs_per_s [0-9]+//' > data/det_run.txt
    cat data/det_run.txt >> data/det_$L.txt
    echo "L=$L run $i: $(md5 -q data/det_run.txt)"
  done
done
./batch_main 11 data/chunk_0010.bin data/chunk_0012.bin data/chunk_0100.bin data/tamper_s_5.bin | sed -E 's/ ms [0-9]+ prep_ms [0-9]+//; s/verify_ms [0-9]+ sigs_per_s [0-9]+//' > data/det_cpu.txt
echo "CPU reference: $(md5 -q data/det_cpu.txt)"
