#!/usr/bin/env bash
# vlib.bend = zc.bend (Fp, from gpu-scan) + b2.bend (BLAKE2b, generated) + vtail.bend (verifier runtime)
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_b2.py > b2.bend
{ cat zc.bend; grep -v '^import Base' b2.bend; cat vtail.bend; } > vlib.bend
