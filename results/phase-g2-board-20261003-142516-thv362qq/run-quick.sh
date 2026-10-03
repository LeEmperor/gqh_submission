#!/usr/bin/env bash
set -euo pipefail
G2_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$G2_SCRIPT_DIR/quick"
echo "Press/release board reset before this test; close serial terminals."
python3 -u 21_quick_uart_test.py 2>&1 | tee console.log
