#!/usr/bin/env python3
"""Run fixture unit tests, verify saved vectors, regenerate, (Python only)."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    args = parser.parse_args()
    tools = Path(__file__).resolve().parent
    project = tools.parents[1]
    def run(arguments: list[str]) -> None:
        print("Running: " + " ".join(arguments), flush=True)
        subprocess.run(arguments, cwd=project, check=True)
    try:
        run([sys.executable, "-m", "unittest", "discover", "-s", str(tools), "-p", "test_factory.py", "-v"])
        run([sys.executable, str(tools / "factory.py"), "--verify-dir", str(tools / "fixtures")])
        with tempfile.TemporaryDirectory(prefix="tickweave-fixture-check-") as temporary:
            fresh = Path(temporary) / "fixtures"
            run([sys.executable, str(tools / "factory.py"), "--output-dir", str(fresh),
                 "--scenario", "all", "--seed", "42", "--packets", "100"])
            saved = tools / "fixtures"
            expected_paths = sorted(path.relative_to(saved) for path in saved.rglob("*") if path.is_file())
            actual_paths = sorted(path.relative_to(fresh) for path in fresh.rglob("*") if path.is_file())
            if expected_paths != actual_paths or any((saved / path).read_bytes() != (fresh / path).read_bytes()
                                                     for path in expected_paths):
                raise ValueError("regenerated fixtures differ from saved seed-42 vectors")
            print("PASS: saved fixtures reproduce byte for byte", flush=True)
        print("PASS: all requested fixture checks completed", flush=True)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
