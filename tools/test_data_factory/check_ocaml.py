#!/usr/bin/env python3
"""Compare Python fixture bytes with the OCaml streamer and its offline mock.

Each fixture session uses a fresh mock connection. This checks the Python
oracle against the OCaml implementation, including all eight response bytes;
it does not establish board correctness or same-connection session resets.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile


class CheckFailure(Exception):
    """An input or implementation failed the cross-language check."""


def packet(value: object, context: str) -> bytes:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-fA-F]{16}", value) is None:
        raise CheckFailure(f"{context}: expected exactly 16 hexadecimal characters")
    return bytes.fromhex(value)


def load_session_records(folder: Path, count: int) -> dict[int, list[dict]]:
    sessions: dict[int, list[dict]] = {}
    with (folder / "fixture.jsonl").open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            record = json.loads(line)
            context = f"{folder.name}, fixture line {line_number}"
            if not isinstance(record, dict):
                raise CheckFailure(f"{context}: fixture record must be an object")
            session, index = record.get("session"), record.get("index")
            if type(session) is not int or session < 0:
                raise CheckFailure(f"{context}: session must be a nonnegative integer")
            if type(index) is not int or not 0 <= index < count:
                raise CheckFailure(f"{context}: index is outside the configured session")
            request = packet(record.get("request_hex"), f"{context}, request")
            response = packet(record.get("expected_response_hex"), f"{context}, response")
            if int.from_bytes(request[:2], "big") != index:
                raise CheckFailure(f"{context}: request index differs from fixture index")
            if int.from_bytes(response[:2], "big") != index:
                raise CheckFailure(f"{context}: response index differs from fixture index")
            sessions.setdefault(session, []).append(record)
    if not sessions:
        raise CheckFailure(f"{folder.name}: empty fixture")
    if sorted(sessions) != list(range(len(sessions))):
        raise CheckFailure(f"{folder.name}: sessions must start at 0 and be consecutive")
    for session, records in sessions.items():
        if [record["index"] for record in records] != list(range(count)):
            raise CheckFailure(f"{folder.name}, session {session}: expected consecutive indices 0..{count - 1}")
    return sessions


def check_requests(path: Path, records: list[dict]) -> None:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["index", "item1", "price1", "item2", "price2"]:
            raise CheckFailure(f"{path}: incorrect request CSV header")
        rows = list(reader)
    if len(rows) != len(records):
        raise CheckFailure(f"{path}: {len(rows)} requests, expected {len(records)}")
    for row, record in zip(rows, records):
        try:
            encoded = struct.pack(">HBHBH", *(int(row[name]) for name in ("index", "item1", "price1", "item2", "price2")))
        except (ValueError, TypeError, struct.error) as exc:
            raise CheckFailure(f"{path}: invalid request fields: {exc}") from exc
        if encoded != packet(record["request_hex"], str(path)):
            raise CheckFailure(f"{path}, index {record['index']}: CSV and fixture request bytes differ")


def check_log(path: Path, records: list[dict], context: str) -> None:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        required = {"index", "request_hex", "response_hex", "status"}
        if not required.issubset(reader.fieldnames or []):
            raise CheckFailure(f"{context}: mock log is missing required columns")
        rows = list(reader)
    if len(rows) != len(records):
        raise CheckFailure(f"{context}: {len(rows)} log rows, expected {len(records)}")
    for row, expected in zip(rows, records):
        index = expected["index"]
        if row["index"] != str(index) or row["status"] != "OK":
            raise CheckFailure(f"{context}, index {index}: received index {row['index']}, status {row['status']}, error {row.get('error', '')}")
        for actual_column, expected_column in (("request_hex", "request_hex"), ("response_hex", "expected_response_hex")):
            actual = packet(row[actual_column], f"{context}, index {index}, {actual_column}")
            wanted = packet(expected[expected_column], f"{context}, index {index}, {expected_column}")
            if actual != wanted:
                raise CheckFailure(f"{context}, index {index}: {actual_column} {actual.hex()}, expected {wanted.hex()}")


def run(fixtures_dir: Path, project_dir: Path) -> tuple[int, int, int]:
    folders = sorted(path.parent for path in fixtures_dir.glob("*/metadata.json"))
    if not folders:
        raise CheckFailure(f"No scenario metadata found under {fixtures_dir}")
    if not (project_dir / "dune-project").is_file():
        raise CheckFailure(f"OCaml project not found at {project_dir}")
    total_sessions = total_packets = 0
    environment = dict(os.environ)
    environment.pop("DATABENTO_API_KEY", None)
    with tempfile.TemporaryDirectory(prefix="tickweave-python-check-") as temporary:
        for folder in folders:
            metadata = json.loads((folder / "metadata.json").read_text(encoding="utf-8"))
            count = metadata.get("packets_per_session")
            if type(count) is not int or not 1 <= count <= 65536:
                raise CheckFailure(f"{folder.name}: packets_per_session must be 1..65536")
            sessions = load_session_records(folder, count)
            for session, records in sorted(sessions.items()):
                requests = (folder / f"requests-session-{session}.csv").resolve()
                check_requests(requests, records)
                output = Path(temporary) / f"{folder.name}-session-{session}.csv"
                command = ["opam", "exec", "--", "dune", "exec", "tickweave-stream", "--",
                           "--source", "requests", "--input", str(requests),
                           "--packets", str(count), "--transport", "mock", "--output", str(output)]
                completed = subprocess.run(command, cwd=project_dir, env=environment,
                                           text=True, capture_output=True, timeout=max(120, count * 2))
                context = f"{folder.name}, session {session}"
                if completed.returncode != 0:
                    diagnostic = (completed.stderr + completed.stdout)[-4000:]
                    raise CheckFailure(f"{context}: OCaml streamer exited {completed.returncode}\n{diagnostic}")
                check_log(output, records, context)
                total_sessions += 1
                total_packets += count
            print(f"PASS {folder.name}: {len(sessions)} session(s), {len(sessions) * count} complete request/response pairs")
    return len(folders), total_sessions, total_packets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures-dir", required=True, type=Path)
    parser.add_argument("--project-dir", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        scenarios, sessions, packets = run(args.fixtures_dir.resolve(), args.project_dir.resolve())
    except (CheckFailure, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"PASS: {scenarios} scenarios, {sessions} sessions, {packets} packets; all eight request and response bytes match.")
    print("Offline mock only; each fixture session used a fresh connection. Same-connection reset and physical UART behavior require separate checks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
