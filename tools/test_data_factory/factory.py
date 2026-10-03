#!/usr/bin/env python3
"""Reproducible GQH request/expected-response fixtures. No third-party packages."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import random
import shutil
import sys

from model import ITEM_A, ITEM_B, ReferenceModel, decode_request, encode_request

SCENARIOS = (
    "constant", "constant_swapped", "rising_falling", "crossings",
    "boundaries", "random", "repeated_sessions",
)


def _settings(scenario: str) -> dict:
    return {
        "constant": {"prices": {"A": 100, "B": 200}, "slots": "A then B"},
        "constant_swapped": {"prices": {"A": 100, "B": 200}, "slots": "alternate"},
        "rising_falling": {"ramp_period": 64, "step": 10,
                           "base_prices": {"A": 1000, "B": 4000},
                           "offset_rule": "phase=index%64; offset=phase if phase<32 else 63-phase",
                           "price_rule": "A=1000+10*offset; B=4000-10*offset",
                           "slots": "alternate"},
        "crossings": {"warmup": {"A": 100, "B": 200},
                      "cycle_after_warmup": [[102, 198], [103, 197], [99, 201], [98, 202]],
                      "slots": "alternate"},
        "boundaries": {"warmup": {"A": 0, "B": 65535},
                       "cycle_after_warmup": [[65535, 0], [0, 65535], [1, 65534], [65534, 1]],
                       "slots": "alternate"},
        "random": {"engine": "Python random.Random(seed), getrandbits(16) twice then getrandbits(1)",
                   "slots": "seeded random"},
        "repeated_sessions": {"session_0": "crossings", "session_1": "constant",
                              "slots": "alternate", "reset": "index 0, same model instance"},
    }[scenario]


def _requests(scenario: str, seed: int, packets: int, session: int):
    rng = random.Random(seed)
    for index in range(packets):
        active = ("crossings" if session == 0 else "constant") if scenario == "repeated_sessions" else scenario
        swapped = scenario != "constant" and index % 2 == 1
        if active in ("constant", "constant_swapped"):
            a, b = 100, 200
        elif active == "rising_falling":
            phase = index % 64
            ramp = phase if phase < 32 else 63 - phase
            a, b = 1000 + 10 * ramp, 4000 - 10 * ramp
        elif active == "crossings":
            a, b = (100, 200) if index < 16 else ((102, 198), (103, 197), (99, 201), (98, 202))[(index-16) % 4]
        elif active == "boundaries":
            a, b = (0, 65535) if index < 16 else ((65535, 0), (0, 65535), (1, 65534), (65534, 1))[(index-16) % 4]
        else:
            a, b = rng.getrandbits(16), rng.getrandbits(16)
            swapped = bool(rng.getrandbits(1))
        yield encode_request(index, ITEM_B, b, ITEM_A, a) if swapped else encode_request(index, ITEM_A, a, ITEM_B, b)


def _sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _validate_settings(scenario: str, seed: int, packets: int) -> None:
    if scenario != "all" and scenario not in SCENARIOS:
        raise ValueError(f"unknown scenario: {scenario}")
    if type(seed) is not int:
        raise ValueError("seed must be an integer")
    if type(packets) is not int or not 1 <= packets <= 65536:
        raise ValueError("packets must be in 1..65536")


def generate(output_dir: Path, scenario: str = "all", seed: int = 42, packets: int = 100) -> None:
    """Create a new fixture set, preserving any existing output directory."""
    _validate_settings(scenario, seed, packets)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=False)
    try:
        for name in SCENARIOS if scenario == "all" else (scenario,):
            directory = output_dir / name
            directory.mkdir()
            sessions = 2 if name == "repeated_sessions" else 1
            model = ReferenceModel()  # Retain this instance across both sessions.
            files = ["fixture.jsonl"]
            with (directory / "fixture.jsonl").open("w", encoding="utf-8", newline="\n") as fixture:
                for session in range(sessions):
                    csv_name = f"requests-session-{session}.csv"
                    files.append(csv_name)
                    with (directory / csv_name).open("w", encoding="utf-8", newline="") as requests:
                        writer = csv.writer(requests, lineterminator="\n")
                        writer.writerow(["index", "item1", "price1", "item2", "price2"])
                        for index, request in enumerate(_requests(name, seed, packets, session)):
                            response = model.respond(request)
                            record = {"session": session, "index": index, "request_hex": request.hex(),
                                      "expected_response_hex": response.hex()}
                            fixture.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
                            writer.writerow(decode_request(request))
            metadata = {"format_version": 1, "scenario": name, "seed": seed,
                        "packets_per_session": packets, "sessions": sessions, "window_size": 16,
                        "item_ids": {"A": ITEM_A, "B": ITEM_B},
                        "actions": {"NONE": 0, "SELL": 1, "BUY": 2},
                        "price_unit": "unsigned 16-bit wire integer; no currency scaling",
                        "settings": _settings(name),
                        "sha256": {filename: _sha256(directory / filename) for filename in files}}
            (directory / "metadata.json").write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    except BaseException:
        shutil.rmtree(output_dir)
        raise


def verify(directory: Path) -> dict:
    """Check settings, hashes, sequence, raw bytes, oracle answers and CSV exports."""
    directory = Path(directory)
    if (directory / "metadata.json").is_file():
        directories = [directory]
    else:
        directories = sorted(path for path in directory.iterdir() if path.is_dir())
    if not directories:
        raise ValueError("no fixture scenarios found")
    totals = {"scenarios": 0, "sessions": 0, "records": 0}
    for path in directories:
        metadata = json.loads((path / "metadata.json").read_text(encoding="utf-8"))
        name, seed, packets = metadata["scenario"], metadata["seed"], metadata["packets_per_session"]
        _validate_settings(name, seed, packets)
        if name == "all":
            raise ValueError("each metadata file must identify one scenario")
        sessions = 2 if name == "repeated_sessions" else 1
        fixed = {"format_version": 1, "sessions": sessions, "window_size": 16,
                 "item_ids": {"A": 17, "B": 34}, "actions": {"NONE": 0, "SELL": 1, "BUY": 2},
                 "settings": _settings(name)}
        for key, value in fixed.items():
            if metadata.get(key) != value:
                raise ValueError(f"{path.name}: incorrect metadata {key}")
        files = ["fixture.jsonl"] + [f"requests-session-{s}.csv" for s in range(sessions)]
        if set(metadata["sha256"]) != set(files):
            raise ValueError(f"{path.name}: incorrect file manifest")
        for filename in files:
            if _sha256(path / filename) != metadata["sha256"][filename]:
                raise ValueError(f"{path.name}: SHA-256 mismatch for {filename}")
        model = ReferenceModel()
        with (path / "fixture.jsonl").open(encoding="utf-8") as fixture:
            for session in range(sessions):
                with (path / f"requests-session-{session}.csv").open(encoding="utf-8", newline="") as requests:
                    reader = csv.reader(requests)
                    if next(reader) != ["index", "item1", "price1", "item2", "price2"]:
                        raise ValueError("incorrect request CSV header")
                    for index, request in enumerate(_requests(name, seed, packets, session)):
                        line = fixture.readline()
                        if not line:
                            raise ValueError("fixture ended early")
                        record = json.loads(line)
                        wanted = {"session": session, "index": index, "request_hex": request.hex(),
                                  "expected_response_hex": model.respond(request).hex()}
                        if record != wanted:
                            raise ValueError(f"{path.name}: incorrect fixture session={session} index={index}")
                        if [int(cell) for cell in next(reader)] != list(decode_request(request)):
                            raise ValueError("request CSV disagrees with fixture")
                    if next(reader, None) is not None:
                        raise ValueError("extra request CSV rows")
            if fixture.readline():
                raise ValueError("extra fixture records")
        totals["scenarios"] += 1
        totals["sessions"] += sessions
        totals["records"] += sessions * packets
    return totals


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--output-dir", type=Path, help="New directory for generated fixtures")
    mode.add_argument("--verify-dir", type=Path, help="Existing set or scenario directory to validate")
    parser.add_argument("--scenario", choices=("all",) + SCENARIOS, default="all")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--packets", type=int, default=100)
    args = parser.parse_args()
    try:
        if args.output_dir:
            generate(args.output_dir, args.scenario, args.seed, args.packets)
            summary = verify(args.output_dir)
            print(f"Generated {args.output_dir}")
        else:
            summary = verify(args.verify_dir)
        print(f"PASS: {summary['scenarios']} scenarios, {summary['sessions']} sessions, {summary['records']} records")
        return 0
    except (OSError, ValueError, KeyError, StopIteration, TypeError) as error:
        print(f"Fixture check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
