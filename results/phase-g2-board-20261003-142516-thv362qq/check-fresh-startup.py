#!/usr/bin/env python3
"""User-run startup/identity check immediately after programming, without reset."""
import hashlib
import json
from pathlib import Path
import tempfile
import time

RUN = Path(__file__).resolve().parent
ROOT = RUN.parents[1]
DEFAULT_FS = ROOT / 'test_proj1/test_proj1/impl/pnr/test_proj1.fs'


def yes(prompt):
    return input(prompt + ' [y/n]: ').strip().lower() in ('y', 'yes')


def choice(prompt, options, default=None):
    while True:
        reply = input(prompt + ': ').strip().lower()
        if not reply and default:
            return default
        if reply in options:
            return reply
        print('Please enter one of:', ', '.join(options))


def main():
    import serial
    out = Path(tempfile.mkdtemp(prefix='startup-', dir=RUN))
    evidence = {'test': 'fresh configuration without button reset', 'startup_pass': False}
    print('Results:', out)
    print('Run immediately after programming. Do NOT press reset before this check.')
    try:
        evidence['fresh_configuration_without_reset'] = yes('Have you just programmed the image WITHOUT pressing reset afterward?')
        assert evidence['fresh_configuration_without_reset'], 'Reprogram, then run again without pressing reset'
        print('Default programmed file:', DEFAULT_FS)
        text = input('Exact .fs you programmed (Enter for that file): ').strip()
        fs = Path(text).expanduser() if text else DEFAULT_FS
        if not fs.is_absolute():
            fs = ROOT / fs
        fs = fs.resolve()
        evidence['programmed_fs_reported_by_user'] = str(fs)
        evidence['programmed_fs_sha256'] = hashlib.sha256(fs.read_bytes()).hexdigest()
        evidence['programming_mode_reported_by_user'] = choice('Programming destination (sram or flash)', ('sram', 'flash'))
        archived = RUN / 'gowin-build-observed/impl/pnr/test_proj1.fs'
        evidence['matches_archived_bitstream'] = evidence['programmed_fs_sha256'] == hashlib.sha256(archived.read_bytes()).hexdigest()
        print('Bitstream SHA-256:', evidence['programmed_fs_sha256'])
        print('Matches archived build:', evidence['matches_archived_bitstream'])
        evidence['startup_heartbeat_observed'] = yes('Is LED0 blinking normally without a button reset?')
        evidence['startup_fault_led_off'] = yes('Is LED1 OFF?')
        assert evidence['startup_heartbeat_observed'] and evidence['startup_fault_led_off'], 'Startup LED checks failed'
        port = json.loads((RUN / 'setup.json').read_text())['port']
        evidence['port'] = port
        print('Checking startup UART at 115200 on', port)
        with serial.Serial(port, 115200, timeout=0.2) as uart:
            # Preserve any unsolicited bytes instead of silently clearing them.
            time.sleep(0.2)
            unsolicited = uart.read(max(1, uart.in_waiting))
            evidence['unsolicited_startup_hex'] = unsolicited.hex()
            assert not unsolicited, 'Unsolicited startup output'
            uart.timeout = 1
            uart.write(bytes.fromhex('00001100642200c8'))
            response = uart.read(8)
            evidence['startup_response_hex'] = response.hex()
            print('Startup response:', response.hex())
            assert response == bytes.fromhex('0000110022000000'), 'Incorrect or missing startup response'
            extra = uart.read(1)
            evidence['extra_response_hex'] = extra.hex()
            assert not extra, 'Unexpected extra response byte'
        evidence['startup_pass'] = True
        print('PASS: fresh configuration, heartbeat, LED1 off, exact startup response, no surplus output')
        print('A serial read cannot directly measure the electrical TX idle level.')
        print('If measured with a meter/scope, record whether TX stays high while idle.')
        evidence['physical_tx_idle_observation'] = choice('TX idle (high, low, or unmeasured; Enter = unmeasured)', ('high', 'low', 'unmeasured'), 'unmeasured')
        print('\nArchived whole-design review: 475 total logic, 379 registers, SSRAM history.')
        print('Analyzed 27 MHz setup/hold paths have zero reported violations.')
        print('PR1014 remains: generic clock input routing can add delay/skew.')
        print('Full review:', RUN / 'gowin-build-observed/REVIEW.md')
        evidence['archived_clock_timing_review_acknowledged'] = yes('Have you reviewed those reports and the retained PR1014 caveat?')
        pending = []
        if not evidence['matches_archived_bitstream']:
            pending.append('Matching reports/source for the newly identified bitstream')
        if evidence['physical_tx_idle_observation'] != 'high':
            pending.append('Physical idle-high TX confirmation')
        if not evidence['archived_clock_timing_review_acknowledged']:
            pending.append('Clock-routing/timing review')
        evidence['remaining_checks'] = pending
        if pending:
            print('Remaining:', '; '.join(pending))
        else:
            print('All requested observations recorded; supply this summary for final acceptance review.')
    except BaseException as exc:
        evidence['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        (out / 'summary.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print('Saved:', out / 'summary.json')


if __name__ == '__main__':
    main()
