#!/usr/bin/env bash
set -euo pipefail
G2_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
G2_CUSTOM_RUN="$(mktemp -d "$G2_SCRIPT_DIR/custom-XXXXXXXX")"
echo "Leave the competition image running. This fixture sends 13 sessions on one connection."
echo "Results: $G2_CUSTOM_RUN"
python3 -u /home/wayne/devel/jane/gqh_submission/test/runner/replay.py "$G2_SCRIPT_DIR/custom-fixture.jsonl" --port /dev/ttyUSB1 --baud 115200 --timeout 1 --stop-on-timeout --label G2-direct27MHz-div234-gap0 --out-dir "$G2_CUSTOM_RUN" 2>&1 | tee "$G2_CUSTOM_RUN/console.log"
