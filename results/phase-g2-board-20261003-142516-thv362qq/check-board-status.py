#!/usr/bin/env python3
"""Manual G2 fault/reset check; run by the board owner."""
import json
from pathlib import Path
import tempfile
import time

RUN = Path(__file__).resolve().parent
REQUEST = bytes.fromhex('00001100642200c8')
EXPECTED = bytes.fromhex('0000110022000000')


def confirm(prompt):
    return input(prompt + ' [y/n]: ').strip().lower() in ('y', 'yes')


def main():
    import serial
    port = json.loads((RUN / 'setup.json').read_text())['port']
    out = Path(tempfile.mkdtemp(prefix='status-', dir=RUN))
    evidence = {'port': port, 'test': 'manual busy-fault/button-reset recovery', 'pass': False}
    print('Results:', out)
    try:
        evidence['heartbeat_observed'] = confirm('Is LED0 blinking normally?')
        evidence['initial_reset_fault_off'] = confirm('Press/release S2/KEY2. Is LED1 OFF now?')
        assert evidence['heartbeat_observed'] and evidence['initial_reset_fault_off'], 'Initial board status failed'
        with serial.Serial(port, 115200, timeout=1) as uart:
            time.sleep(0.2)
            uart.reset_input_buffer()
            uart.write(REQUEST + b'\x99')
            response = uart.read(8)
            evidence['accepted_response_hex'] = response.hex()
            print('Accepted response:', response.hex())
            assert response == EXPECTED, 'Accepted response did not match'
            uart.write(REQUEST)
            blocked = uart.read(8)
            evidence['after_fault_response_hex'] = blocked.hex()
            assert blocked == b'', 'Sticky fault did not block subsequent request'
            evidence['fault_led_on'] = confirm('Is LED1 now ON and staying ON?')
            assert evidence['fault_led_on'], 'Fault LED did not latch'
            evidence['reset_fault_off'] = confirm('Press/release S2/KEY2 again. Is LED1 OFF?')
            assert evidence['reset_fault_off'], 'Reset did not clear fault LED'
            uart.write(REQUEST)
            recovered = uart.read(8)
            evidence['post_reset_response_hex'] = recovered.hex()
            print('After reset:', recovered.hex())
            assert recovered == EXPECTED, 'Fresh request failed after reset'
            assert uart.read(1) == b'', 'Unexpected extra output after recovery'
        evidence['pass'] = True
        print('PASS: observed heartbeat, sticky busy fault/LED, button reset and fresh response recovery')
    except BaseException as exc:
        evidence['error'] = f'{type(exc).__name__}: {exc}'
        raise
    finally:
        (out / 'summary.json').write_text(json.dumps(evidence, indent=2) + '\n')
        print('Saved:', out / 'summary.json')


if __name__ == '__main__':
    main()
