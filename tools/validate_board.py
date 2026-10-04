#!/usr/bin/env python3
"""One-command board validation; creates and reports its own results directory."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
REQUEST = bytes.fromhex('00001100642200c8')
RESPONSE = bytes.fromhex('0000110022000000')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def confirm(message):
    require(input(message + ' [y/N]: ').strip().lower() in ('y', 'yes'),
            'Required board observation was not confirmed')


def check_quick(console):
    require(re.search(r'^PASS\s*$', console, re.M) is not None,
            'Quick did not print PASS (exit zero alone is insufficient)')
    rows = re.findall(r'^idx=.*$', console, re.M)
    require(len(rows) == 21 and not any('MISMATCH' in row for row in rows),
            'Quick did not complete all 21 packets correctly')
    return dict(received=21, scored_packets=5)


def check_robust(folder, fullrange=False):
    suffix = '_fullrange' if fullrange else ''
    summary = (folder / f'trade_summary_100{suffix}.txt').read_text()
    for pattern in [r'Packets successfully received: 100', r'Correct packets: 84',
                    r'Correct individual actions: 168/168', r'Timeouts: 0']:
        require(re.search('^' + pattern + r'\s*$', summary, re.M),
                'Official summary failed: ' + pattern)
    with (folder / f'trade_results_100{suffix}.csv').open(newline='') as f:
        rows = list(csv.DictReader(f))
    require(len(rows) == 100 and [int(row['index']) for row in rows] == list(range(100)),
            'Official CSV is incomplete or out of order')
    require(all(row['status'] == ('IGNORED_WARMUP' if i < 16 else 'CORRECT')
                for i, row in enumerate(rows)), 'Official CSV contains failed packets')
    require(all(row['packet_correct'] == row['action1_correct'] == row['action2_correct'] == 'YES'
                for row in rows[16:]), 'Official CSV contains failed scored actions')
    mean = re.search(r'^Average successful round-trip latency: ([\d.]+) ms$', summary, re.M)
    require(mean is not None, 'Missing official latency')
    mean_ms = float(mean.group(1))
    if not fullrange:
        require(mean_ms <= 20.7825, f'Normal mean {mean_ms} ms exceeds 20.7825 ms')
    return dict(received=100, scored_packets=84, correct_actions=168,
                timeouts=0, official_mean_ms=mean_ms)


def check_custom(folder, planned):
    summaries = list(folder.glob('*.summary.json'))
    require(len(summaries) == 1, 'Expected one custom summary')
    summary = json.loads(summaries[0].read_text())
    require(summary['planned'] == summary['sent'] == summary['counts']['OK'] == planned,
            'Custom replay was incomplete or had mismatches')
    require(not summary['aborted'] and not summary['unsolicited_byte_events']
            and not summary['trailing_unsolicited_hex'], 'Custom replay had extra bytes or aborted')
    require(all(summary['counts'][key] == 0 for key in ['MISMATCH', 'SHORT', 'TIMEOUT']),
            'Custom replay contained errors')
    return dict(received=planned, counts=summary['counts'], latency=summary['latency'])


def make_fixture(run):
    # Reuse the independent direct-window integration vectors, without HDL tools.
    sys.path.insert(0, str(ROOT / 'test/engine/oracle'))
    spec = importlib.util.spec_from_file_location('board_integration_vectors',
                                                 ROOT / 'test/integration/run_checks.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.ROOT = ROOT
    packets = run / 'packets.txt'
    coverage = module.trace(packets)
    rows = []
    session = -1
    for line in packets.read_text().splitlines():
        request, response = line.split()
        index = int(request[:4], 16)
        if index == 0:
            session += 1
        rows.append(dict(session=session, index=index, request_hex=request,
                         expected_response_hex=response))
    # H2: all nine old/current relations at the FIRST scored update, plus
    # equality when the warm-up sum has remainder 15. Items swap during warm-up.
    from model import ReferenceModel, encode_request, ITEM_A, ITEM_B
    model = ReferenceModel()
    for last in [98, 100, 102, 99]:
        for incoming in [98, 100, 102]:
            session += 1
            prices = [(100, 200)] * 15 + [(last, 2*last), (incoming, 2*incoming)]
            for index, (a, b) in enumerate(prices):
                request = (encode_request(index, ITEM_B, b, ITEM_A, a) if index % 2 == 0
                           else encode_request(index, ITEM_A, a, ITEM_B, b))
                rows.append(dict(session=session, index=index, request_hex=request.hex(),
                                 expected_response_hex=model.respond(request).hex()))
    fixture = run / 'custom-fixture.jsonl'
    fixture.write_text(''.join(json.dumps(row) + '\n' for row in rows))
    (run / 'coverage.json').write_text(json.dumps(dict(integration=coverage,
        packets=len(rows), sessions=session+1, h2_boundary_sessions=12), indent=2) + '\n')
    return fixture, len(rows)


def prepare(run, port):
    for stage, path in [('quick', ROOT / 'tools/official/21_quick_uart_test.py'),
                        ('normal', ROOT / 'tools/official/22_robust_uart_test.py'),
                        ('fullrange', ROOT / 'tools/22_robust_uart_test_fullrange.py')]:
        source = path.read_bytes()
        edited, count = re.subn(rb'^PORT[^\S\r\n]*=[^\r\n]*',
            lambda _: ('PORT = ' + repr(port)).encode(), source, flags=re.M)
        require(count == 1, f'Expected one PORT setting in {path}')
        folder = run / stage
        folder.mkdir()
        (folder / path.name).write_bytes(edited)
    return make_fixture(run)


def run_logged(command, folder):
    folder.mkdir(exist_ok=True)
    (folder / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
    lines = []
    with (folder / 'console.log').open('w') as log:
        with subprocess.Popen(command, cwd=folder, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True) as process:
            for line in process.stdout:
                log.write(line)
                log.flush()
                lines.append(line)
            code = process.wait()
    require(code == 0, f'Test exited {code}; see {folder / "console.log"}')
    return ''.join(lines)


def uart_check(port, fault=False, no_heartbeat=False, no_fault_led=False):
    import serial
    with serial.Serial(port, 115200, timeout=0.2) as uart:
        time.sleep(0.2)
        require(not uart.read(max(1, uart.in_waiting)), 'Unsolicited UART bytes')
        uart.timeout = 1
        uart.write(REQUEST + (b'\x99' if fault else b''))
        response = uart.read(8)
        require(response == RESPONSE, f'Expected {RESPONSE.hex()}, received {response.hex()}')
        if fault:
            uart.write(REQUEST)
            require(uart.read(8) == b'', 'Busy fault did not block another request')
            if no_fault_led:
                confirm('Fault LED is disabled. Is LED1 still OFF?')
            else:
                confirm('LED1 should now be ON and staying ON. Is it?')
            led0 = 'OFF' if no_heartbeat else 'blinking again'
            confirm(f'Press/release S2 reset. Is LED1 OFF and LED0 {led0}?')
            uart.write(REQUEST)
            require(uart.read(8) == RESPONSE, 'Fresh request failed after fault reset')
        require(not uart.read(1), 'Unexpected extra UART output')
    return dict(exact_response=True, extra_bytes=False, fault_reset=fault)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', default='/dev/ttyUSB1')
    parser.add_argument('--label', default='H2', help='Candidate name, reusable for later stages')
    parser.add_argument('--fs', type=Path,
                        default=ROOT / 'test_proj2/test_proj2/impl/pnr/test_proj2.fs')
    parser.add_argument('--results-root', type=Path, default=ROOT / 'results')
    parser.add_argument('--smoke', action='store_true', help='Quick only; a screen, not full acceptance')
    parser.add_argument('--no-heartbeat', action='store_true',
                        help='Expect LED0 OFF for the H5 competition image')
    parser.add_argument('--no-fault-led', action='store_true',
                        help='Expect LED1 OFF; still test UART fault lockout and reset recovery')
    parser.add_argument('--prepare-only', action='store_true', help='Generate run files without serial access')
    args = parser.parse_args(argv)
    parent = args.results_root.expanduser().resolve()
    parent.mkdir(parents=True, exist_ok=True)
    label = re.sub(r'[^A-Za-z0-9_-]', '-', args.label)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    run = Path(tempfile.mkdtemp(prefix=f'board-{label}-{stamp}-', dir=parent))
    summary = dict(label=args.label, port=args.port, fs=str(args.fs.resolve()),
                   mode='smoke' if args.smoke else 'full', no_heartbeat=args.no_heartbeat,
                   no_fault_led=args.no_fault_led,
                   pass_all=False, stages={})
    led0 = 'OFF' if args.no_heartbeat else 'blinking'
    print(f'Results: {run}', flush=True)
    def stage(name, operation):
        print(f'Running {name} ...', flush=True)
        summary['stages'][name] = operation()
        (run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(f'PASS {name}', flush=True)
        if 'official_mean_ms' in summary['stages'][name]:
            print(f"  Mean round-trip latency: {summary['stages'][name]['official_mean_ms']:.3f} ms",
                  flush=True)
    def official(name):
        folder = run / name
        script = next(folder.glob('*.py'))
        console = run_logged([sys.executable, '-u', str(script)], folder)
        return check_quick(console) if name == 'quick' else check_robust(folder, name == 'fullrange')
    def custom(name):
        folder = run / name
        run_logged([sys.executable, '-u', str(ROOT / 'test/runner/replay.py'),
                    str(fixture), '--port', args.port, '--baud', '115200', '--timeout', '1',
                    '--stop-on-timeout', '--label', args.label, '--out-dir', str(folder)], folder)
        return check_custom(folder, planned)
    code = 1
    try:
        fixture, planned = prepare(run, args.port)
        if args.prepare_only:
            summary['prepared_only'] = True
            print('Prepared only; no serial access or board result.', flush=True)
            return 0
        if not args.smoke:
            confirm(f'Freshly programmed {args.fs.name}, WITHOUT button reset, '
                    f'with LED0 {led0} and LED1 OFF?')
            stage('startup', lambda: uart_check(args.port))
        confirm(f'Press/release S2 reset. LED0 {led0} and LED1 OFF?')
        stage('quick', lambda: official('quick'))
        if not args.smoke:
            confirm('Press/release S2 once before the normal/full-range pair. '
                    f'LED0 {led0} and LED1 OFF? Do not reset between the next tests.')
            # No reset/reprogramming between normal and full-range. Each sends
            # index zero, exercising logical session clear on the same image.
            stage('normal', lambda: official('normal'))
            stage('fullrange', lambda: official('fullrange'))
            stage('custom', lambda: custom('custom'))
            confirm(f'Histories are populated. Press/release S2 reset; LED0 {led0} and LED1 OFF?')
            stage('custom-after-reset', lambda: custom('custom-after-reset'))
            stage('fault-reset', lambda: uart_check(args.port, fault=True,
                                                  no_heartbeat=args.no_heartbeat,
                                                  no_fault_led=args.no_fault_led))
        summary['pass_all'] = True
        code = 0
        print('PASS ' + ('SMOKE ONLY — full validation still required' if args.smoke else
                        'FULL BOARD SUITE — official pair, boundaries, sessions, startup and reset'))
    except (Exception, KeyboardInterrupt) as exc:
        summary['error'] = f'{type(exc).__name__}: {exc}'
        print(f'FAIL: {exc}', file=sys.stderr)
    finally:
        (run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(f'Results saved: {run}', flush=True)
    return code


if __name__ == '__main__':
    sys.exit(main())
