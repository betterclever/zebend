#!/bin/zsh
# gate_batch.sh N: N runs each of the GPU batch on 1024 real bundles (must print result 1)
# and on 1023 real + 1 tampered (must print result 0); det.sh compares outputs bit for bit.
R=/Users/betterclever/projects/zecathon/zebend; cd $R/proofsets/data/chunks
P=$R/halo2/verifier/data/params_g.bin
F=(${(f)"$(ls | head -16 | while read c; do ls $c | sed "s|^|$c/|"; done)"})
B=(${F[1,1023]} $R/halo2/verifier/data/bundles/tx_3.ironwood.bad.bin)
$R/gpuv/t/det.sh $1 $R/gpuv/v/batch_g $P $F +RTS --gpu 6GB
$R/gpuv/t/det.sh $1 $R/gpuv/v/batch_g $P $B +RTS --gpu 6GB
