#!/usr/bin/env python3
"""Interactive board checks for the 195-LC serial candidate; never programs it."""
import argparse
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path
import random
import re
import statistics
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / 'test/engine/oracle'))
from model import ReferenceModel, encode_request, ITEM_A, ITEM_B

OFFICIAL = {
    'quick': ROOT / 'tools/official/21_quick_uart_test.py',
    'normal': ROOT / 'tools/official/22_robust_uart_test.py',
    'fullrange': ROOT / 'tools/22_robust_uart_test_fullrange.py',
}
ACTIONS = {'NONE': 0, 'SELL': 1, 'BUY': 2}
LIMIT_MS = 16.626 * 1.25


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_robust(folder):
    """Check the actual CSV, including warm-up bytes the organizer ignores."""
    paths = list(folder.glob('trade_results*.csv'))
    require(len(paths) == 1, f'{folder}: missing/ambiguous official CSV')
    with paths[0].open(newline='') as source:
        rows = list(csv.DictReader(source))
    require(len(rows) == 100, f'{folder}: received {len(rows)}/100 rows')
    model = ReferenceModel()
    latencies = []
    for index, row in enumerate(rows):
        require(int(row['index']) == index, f'{folder}: index order')
        require(row['status'] == ('IGNORED_WARMUP' if index < 16 else 'CORRECT'),
                f'{folder}: index {index}: {row["status"]}')
        request = encode_request(index, int(row['tx_item1'], 16), int(row['tx_price1']),
                                 int(row['tx_item2'], 16), int(row['tx_price2']))
        expected = model.respond(request)
        received = (int(row['rx_index']).to_bytes(2, 'big')
                    + bytes([int(row['rx_item1'], 16), ACTIONS[row['rx_action1']],
                             int(row['rx_item2'], 16), ACTIONS[row['rx_action2']]])
                    + int(row['rx_reserved'], 16).to_bytes(2, 'big'))
        require(received == expected, f'{folder}: index {index} full response mismatch')
        latencies.append(float(row['latency_us']) / 1000)
    mean = statistics.mean(latencies)
    return {'pass': True, 'received': 100, 'scored_packets': 84, 'correct_actions': 168,
            'warmup_bytes_checked': True, 'timeouts': 0, 'mean_ms': mean,
            'median_packet_ms': statistics.median(latencies),
            'within_latency_limit': mean <= LIMIT_MS}


def make_fixture(path, seed):
    """Direct-window expectations, extremes, equality, stale/short sessions."""
    requests = [bytes.fromhex(line.split()[0])
                for line in (HERE / 'evidence/packets.txt').read_text().splitlines()]
    rng = random.Random(seed)
    profiles = [
        [(65535, 65535)] * 65,
        [(0, 0)] * 65,
        [(0, 65535), (65535, 0)] * 65,
        [(100, 100)] * 15 + [(115, 85)] + [(101, 99), (100, 100)] * 40,
    ]
    # Interrupt warm-up at several points, then start new index-zero sessions.
    profiles += [[(rng.randrange(65536), rng.randrange(65536)) for _ in range(n)]
                 for n in [1, 7, 15, 16, 17, 257, 257, 257, 257]]
    for prices in profiles:
        for index, (a, b) in enumerate(prices):
            requests.append(encode_request(index, ITEM_B, b, ITEM_A, a) if rng.randrange(2)
                            else encode_request(index, ITEM_A, a, ITEM_B, b))
    model = ReferenceModel()
    rows, session = [], -1
    for request in requests:
        index = int.from_bytes(request[:2], 'big')
        session += index == 0
        rows.append({'session': session, 'index': index, 'request_hex': request.hex(),
                     'expected_response_hex': model.respond(request).hex()})
    path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
    return {'packets': len(rows), 'sessions': session + 1, 'seed': seed, 'sha256': digest(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port', help='UART port, usually /dev/ttyUSB1 or COM6')
    parser.add_argument('--fs', type=Path, default=HERE / 'evidence/serial_lfsr/gqh_serial.fs',
                        help='The actual .fs you manually programmed; recorded and SHA-256 hashed')
    parser.add_argument('--rounds', type=int, default=5, help='Normal/full-range pairs (default: 5)')
    parser.add_argument('--seed', type=lambda s: int(s, 0), default=0x1955EED)
    parser.add_argument('--results-root', type=Path, default=HERE / 'board_results')
    parser.add_argument('--prepare-only', action='store_true', help='Prepare inputs without opening the port')
    args = parser.parse_args()
    if args.rounds < 1 or not args.port.strip() or any(ord(c) < 32 for c in args.port):
        parser.error('rounds must be >= 1 and port must be a nonempty single-line name')
    args.fs = args.fs.expanduser().resolve()
    if not args.fs.is_file():
        parser.error(f'bitstream not found: {args.fs}; use --fs /path/to/programmed.fs')
    args.results_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    run = Path(tempfile.mkdtemp(prefix=f'board-serial195-{stamp}-', dir=args.results_root)).resolve()
    summary = {'label': 'serial195', 'port': args.port, 'fs': str(args.fs),
               'fs_sha256': digest(args.fs), 'rounds': args.rounds,
               'started_at': datetime.now().astimezone().isoformat(),
               'programming': 'user confirmation only; no readback',
               'latency_limit_ms': LIMIT_MS, 'pass_all': False, 'stages': {}}
    def save():
        (run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    def record(stage, result):
        summary['stages'][stage] = result
        save()
        print(f'PASS {stage}', flush=True)
    def prompt(text):
        input('\n' + text + '\nPress Enter when done (Ctrl-C to stop): ')
    def command(command_args, folder):
        folder.mkdir(parents=True, exist_ok=True)
        with (folder / 'console.log').open('w') as log:
            result = subprocess.run([str(x) for x in command_args], cwd=folder,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=300)
        output = (folder / 'console.log').read_text()
        print(output[-2500:], flush=True)
        require(result.returncode == 0, f'command failed; see {folder / "console.log"}')
        return output
    def official(kind, label):
        folder = run / label
        folder.mkdir()
        source = OFFICIAL[kind].read_bytes()
        edited, count = re.subn(rb'^PORT[^\S\r\n]*=.*$',
                                lambda _: ('PORT = ' + repr(args.port)).encode(), source, flags=re.M)
        require(count == 1, f'{kind}: expected exactly one PORT assignment')
        script = folder / OFFICIAL[kind].name
        script.write_bytes(edited)
        output = command([sys.executable, '-u', script], folder)
        if kind == 'quick':
            require(re.search(r'^PASS\s*$', output, re.M) is not None, 'quick: no PASS verdict')
            require(len(re.findall(r'^idx=', output, re.M)) == 21, 'quick: not 21 responses')
            result = {'pass': True, 'received': 21}
        else:
            result = check_robust(folder)
        result.update(source_sha256=hashlib.sha256(source).hexdigest(), copy_sha256=digest(script))
        record(label, result)
        return result
    def replay(label):
        folder = run / label
        command([sys.executable, '-u', ROOT / 'test/runner/replay.py', run / 'custom-fixture.jsonl',
                 '--port', args.port, '--out-dir', folder, '--label', 'serial195', '--stop-on-timeout'], folder)
        paths = list(folder.glob('*.summary.json'))
        require(len(paths) == 1, f'{label}: missing custom summary')
        result = json.loads(paths[0].read_text())
        record(label, {'pass': True, 'summary': result})

    try:
        summary['fixture'] = make_fixture(run / 'custom-fixture.jsonl', args.seed)
        summary['official_sources'] = {kind: {'path': str(path), 'sha256': digest(path)}
                                       for kind, path in OFFICIAL.items()}
        save()
        print(f'Results: {run}\nBitstream: {args.fs}\nSHA-256: {summary["fs_sha256"]}', flush=True)
        if args.prepare_only:
            summary['status'] = 'prepared_only'
            save()
            print('Prepared only: no serial port opened; no board PASS claimed.')
            return 0
        try:
            import serial
        except ImportError:
            raise RuntimeError('Install pyserial: python3 -m pip install pyserial') from None

        def open_port():
            ser = serial.Serial(args.port, 115200, timeout=1.0, write_timeout=1.0)
            time.sleep(0.2)
            stale = ser.read(ser.in_waiting)
            if stale:
                ser.close()
                raise RuntimeError(f'Unsolicited bytes on port open: {stale.hex()}')
            return ser
        def silent(ser, duration=0.1):
            old = ser.timeout
            ser.timeout = duration
            unexpected = ser.read(1)
            ser.timeout = old
            require(not unexpected, f'unexpected extra/lockout byte: {unexpected.hex()}')
        def exchange(ser, request, expected, pause=0):
            if pause:
                for byte in request:
                    ser.write(bytes([byte])); ser.flush(); time.sleep(pause)
            else:
                ser.write(request); ser.flush()
            response = ser.read(8)
            require(response == expected, f'request {request.hex()}: got {response.hex()}, wanted {expected.hex()}')
            silent(ser, 0.03)
        first = encode_request(0, ITEM_A, 65535, ITEM_B, 0)
        first_response = ReferenceModel().respond(first)
        def reset_and_recover(ser):
            prompt('Press and release the board RESET button. Both LEDs should remain off. Do not reprogram.')
            time.sleep(0.2)
            silent(ser)
            exchange(ser, first, first_response)

        prompt('Program the .fs shown above into SRAM, then close the programmer and serial terminals.\n'
               'Leave this fresh programming state intact: do not press RESET yet. Both LEDs should be off.')
        summary['programmed_image_confirmed_by_user'] = True
        with open_port() as ser:
            exchange(ser, first, first_response)
        record('fresh-startup', {'pass': True, 'exact_response': True, 'extra_bytes': False})
        official('quick', 'quick')
        normal, fullrange = [], []
        print('\nDo not reset or reprogram during the following normal/full-range pairs.', flush=True)
        for index in range(1, args.rounds + 1):
            normal.append(official('normal', f'normal-{index:02d}'))
            # No prompts, reset, programming, or other traffic between these runs.
            fullrange.append(official('fullrange', f'fullrange-{index:02d}'))
        summary['latency'] = {
            'normal_median_of_means_ms': statistics.median(r['mean_ms'] for r in normal),
            'fullrange_median_of_means_ms': statistics.median(r['mean_ms'] for r in fullrange),
            'rounds': args.rounds,
            'all_means_within_limit': all(r['within_latency_limit'] for r in normal + fullrange)}
        save()
        replay('custom')

        with open_port() as ser:
            model = ReferenceModel()
            for index in range(33):
                request = encode_request(index, ITEM_B, (65535 if index%2 else 0), ITEM_A, index*1999)
                exchange(ser, request, model.respond(request), pause=0.002 if index%4==0 else 0)
            record('legal-byte-pauses', {'pass': True, 'packets': 33, 'pause_seconds': 0.002})
            # Reset with populated history AND a partly collected next request.
            ser.write(encode_request(33, ITEM_A, 99, ITEM_B, 55)[:4]); ser.flush()
            silent(ser)
            reset_and_recover(ser)
            record('populated-partial-request-reset', {'pass': True})
        replay('custom-after-reset')

        with open_port() as ser:
            # Extra byte arrives while the accepted packet's response is busy.
            ser.write(first + b'\x99'); ser.flush()
            require(ser.read(8) == first_response, 'busy-input fault lost accepted response')
            silent(ser)
            ser.write(first); ser.flush(); silent(ser, 1.0)
            reset_and_recover(ser)
            record('busy-fault-reset', {'pass': True, 'accepted_response_completed': True})
            ser.break_condition = True
            try:
                time.sleep(0.02)
            finally:
                ser.break_condition = False
            time.sleep(0.02)
            ser.write(first); ser.flush(); silent(ser, 1.0)
            reset_and_recover(ser)
            record('framing-fault-reset', {'pass': True})
        require(summary['latency']['all_means_within_limit'],
                f'Functional checks passed, but at least one official mean exceeds {LIMIT_MS:.4f} ms')
        summary['pass_all'] = True
        summary['status'] = 'PASS'
        print(f'\nBOARD VALIDATION PASS\nResults: {run}\nSummary: {run / "summary.json"}', flush=True)
        return 0
    except (Exception, KeyboardInterrupt) as exc:
        summary['status'] = 'ABORTED' if isinstance(exc, KeyboardInterrupt) else 'FAIL'
        summary['error'] = f'{type(exc).__name__}: {exc}'
        print(f'\n{summary["status"]}: {summary["error"]}\nResults preserved: {run}', file=sys.stderr)
        return 1
    finally:
        summary['finished_at'] = datetime.now().astimezone().isoformat()
        save()


if __name__ == '__main__':
    sys.exit(main())
