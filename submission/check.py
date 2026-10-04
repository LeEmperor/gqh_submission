#!/usr/bin/env python3
"""Read-only submission identity check; optionally validate a completed board run."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board-run', type=Path, help='Completed serial-adder board-results directory')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'submission/manifest.json').read_text())
    for name, expected in manifest['sha256'].items():
        path = ROOT / name
        require(path.is_file(), f'Missing submission file: {name}')
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        require(actual == expected, f'Submission identity changed: {name}')
    print(f"PASS: {len(manifest['sha256'])} source/build/image/report hashes")

    verification = ROOT / 'serial_adder_approach/evidence/verification.json'
    if verification.exists():
        result = json.loads(verification.read_text())
        require(result.get('status') == 'PASS', 'Local verification has not passed')
        require(result['variants']['serial_lfsr']['rtl_sha256'] ==
                manifest['sha256'][manifest['rtl']], 'Local verification tested different RTL')
        print('PASS: completed local verification matches selected RTL')
    else:
        print('PENDING: complete local verification.json is not available')

    if args.board_run is None:
        print('PENDING: board evidence not checked; use --board-run PATH when complete')
        return 0

    folder = args.board_run.expanduser().resolve()
    summary = json.loads((folder / 'summary.json').read_text())
    require(summary.get('status') == 'PASS' and summary.get('pass_all') is True,
            'Board run is incomplete, failed, or prepared-only')
    require(summary.get('programmed_image_confirmed_by_user') is True,
            'Missing operator programming confirmation')
    require(summary.get('fs_sha256') == manifest['sha256'][manifest['bitstream']],
            'Board run records a different programming image')
    require(hashlib.sha256((folder / 'custom-fixture.jsonl').read_bytes()).hexdigest() ==
            summary['fixture']['sha256'], 'Board fixture identity changed')
    stages = summary['stages']
    for name in ['fresh-startup', 'quick', 'custom', 'legal-byte-pauses',
                 'populated-partial-request-reset', 'custom-after-reset',
                 'busy-fault-reset', 'framing-fault-reset']:
        require(stages.get(name, {}).get('pass') is True, f'Incomplete board stage: {name}')
    quick = (folder / 'quick/console.log').read_text()
    require('PASS' in quick.splitlines(), 'Quick test log has no PASS verdict')

    # Reuse the board validator's independent oracle to inspect the actual CSVs,
    # including warm-up response fields, rather than trusting a summary alone.
    spec = importlib.util.spec_from_file_location(
        'serial_board_validation', ROOT / 'serial_adder_approach/validate_board.py')
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    rounds = summary['rounds']
    require(isinstance(rounds, int) and rounds >= 1, 'Invalid board round count')
    normal, fullrange = [], []
    for index in range(1, rounds + 1):
        for kind, measurements in [('normal', normal), ('fullrange', fullrange)]:
            label = f'{kind}-{index:02d}'
            require(stages.get(label, {}).get('pass') is True, f'Incomplete stage: {label}')
            result = validator.check_robust(folder / label)
            if kind == 'normal':
                require(result['within_latency_limit'], f'{label}: local latency tier missed')
            measurements.append(result['mean_ms'])
    print(f'PASS: final-image board suite, {rounds} normal/full-range pairs')
    print(f'Normal mean RTTs (ms): {normal}')
    print(f'Full-range mean RTTs (ms): {fullrange}')
    print(f'Normal median of run means: {statistics.median(normal):.6f} ms')
    print('Local evidence only; official qualification and placement are judged independently.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
