#!/bin/zsh
# Rebuild everything from mainnet and check it. Runs on macOS (Metal) with Bend 2.0.38.
set -e
cd "$(dirname "$0")"
export BEND_NO_TELEMETRY=1
B=~/.bend/bin/bend
(cd oracle && cargo build --release -q \
  && ./target/release/state-oracle consts \
  && ./target/release/state-oracle sync 3428143 ${TO:-3528268} \
  && ./target/release/state-oracle trees 3428200 3448142 3468142 3488142 3508142 ${TO:-3528268} \
  && ./target/release/state-oracle roots)
python3 gen_consts.py oracle/out/sinsemilla_consts.txt consts.bend
python3 gen_inputs.py
$B PROOF.bend --verdict
$B t/crh_test.bend -o t/crh_test && ./t/crh_test
$B tree_main.bend -o tree_main && ./tree_main out/cmx.bin gpu && ./tree_main out/cmx.bin tree
$B nf_main.bend -o nf_main && ./nf_main out/nf.bin
