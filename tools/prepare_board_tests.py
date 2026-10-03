#!/usr/bin/env python3
"""Prepare a fresh board-test run without opening a serial device."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shlex
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="UART port, e.g. /dev/ttyUSB1 or COM6")
    parser.add_argument("--results-root", type=Path, default=ROOT / "results",
                        help="Parent directory for the new run (default: repository results/)")
    args = parser.parse_args()
    if not args.port.strip() or any(ord(c) < 32 for c in args.port):
        parser.error("port must be nonempty and contain no control characters")

    inputs = ["rtl/gqh_competition_top.v", "constraints/19_tang_nano_20k.cst",
              "constraints/tang_nano_20k.sdc"]
    # Read and validate everything before creating the run directory.
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
              for name in inputs}
    copies = {}
    for kind, name in [("quick", "21_quick_uart_test.py"),
                       ("robust", "22_robust_uart_test.py")]:
        source = (ROOT / "tools/official" / name).read_bytes()
        replacement = ("PORT = " + repr(args.port)).encode("utf-8")
        edited, count = re.subn(rb"^PORT[^\S\r\n]*=.*$",
                               lambda _: replacement, source, flags=re.M)
        if count != 1:
            raise ValueError(f"Expected exactly one PORT setting in {name}")
        copies[kind] = (name, edited)

    parent = args.results_root.expanduser().resolve()
    parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    run = Path(tempfile.mkdtemp(prefix=f"phase-g2-board-{stamp}-", dir=parent))
    (run / "inputs.sha256").write_text(
        "".join(f"{digest}  {name}\n" for name, digest in hashes.items()))
    (run / "setup.json").write_text(json.dumps({
        "repository": str(ROOT), "port": args.port, "baud": 115200,
        "prepared_at": datetime.now().astimezone().isoformat(), "inputs_sha256": hashes,
        "note": "Preparation only; synthesis, programming and board tests are manual.",
    }, indent=2) + "\n")

    for kind, (name, edited) in copies.items():
        folder = run / kind
        folder.mkdir()
        (folder / name).write_bytes(edited)
        # Resolve relative to the launcher, so the result directory can be moved.
        launcher = run / f"run-{kind}.sh"
        launcher.write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'G2_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\n'
            f'cd -- "$G2_SCRIPT_DIR/{kind}"\n'
            'echo "Press/release board reset before this test; close serial terminals."\n'
            f'python3 -u {shlex.quote(name)} 2>&1 | tee console.log\n')
        launcher.chmod(0o755)

    (run / "README.txt").write_text(
        f"Prepared for UART port {args.port}. Requires Python 3 and pyserial.\n"
        "Reset the board before each test. Run run-quick.sh, then run-robust.sh.\n"
        "Require quick PASS; robust 84/84 packets, 168/168 actions, zero timeouts.\n"
        "Exit status alone does not prove PASS. Each launcher overwrites its console.log;\n"
        "prepare a fresh directory for a retry to preserve prior evidence.\n"
        "Archive the programmed .fs, its hash, and Gowin reports with this run.\n")
    print(f"Prepared: {run}\nUART port: {args.port}\n")
    print("Reset the board, then run the quick test:")
    print(f"  bash {shlex.quote(str(run / 'run-quick.sh'))}")
    print("Reset again, then run the robust test:")
    print(f"  bash {shlex.quote(str(run / 'run-robust.sh'))}")
    print("Require quick PASS and robust 84/84 packets, 168/168 actions, zero timeouts.")
    print("Official repository scripts were preserved; no serial device was opened.")


if __name__ == "__main__":
    main()
