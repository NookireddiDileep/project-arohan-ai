#!/usr/bin/env bash
# AI-01 exercise runner: no GPU, no cluster needed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== A100 80GB, 8B model, FP16 =="
python3 "$here/roofline.py"

echo
echo "== Same GPU, 8B model, 4-bit weights =="
python3 "$here/roofline.py" --bytes-per-param 0.5
