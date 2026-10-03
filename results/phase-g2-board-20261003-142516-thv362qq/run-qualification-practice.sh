#!/usr/bin/env bash
set -euo pipefail
G2_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
G2_PAIR_RUN="$(mktemp -d "$G2_SCRIPT_DIR/qualification-XXXXXXXX")"
mkdir "$G2_PAIR_RUN/normal" "$G2_PAIR_RUN/fullrange"
cp "$G2_SCRIPT_DIR/qualification-inputs/normal.py" "$G2_PAIR_RUN/normal/22_robust_uart_test.py"
cp "$G2_SCRIPT_DIR/qualification-inputs/fullrange.py" "$G2_PAIR_RUN/fullrange/22_robust_uart_test_fullrange.py"
echo "Results: $G2_PAIR_RUN"
echo "Running normal robust, then full-range practice. Do not reset or reprogram between them."
(cd "$G2_PAIR_RUN/normal" && python3 -u 22_robust_uart_test.py 2>&1 | tee console.log)
(cd "$G2_PAIR_RUN/fullrange" && python3 -u 22_robust_uart_test_fullrange.py 2>&1 | tee console.log)
echo "Inspect BOTH summaries: 100 responses, 84/84 packets, 168/168 actions, zero timeouts."
