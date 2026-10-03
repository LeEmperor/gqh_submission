#!/usr/bin/env python3
"""Check the NONE-action diagnostic transport, not the competition algorithm."""
import argparse
import random
import struct
import sys
import time


def fixtures(count, seed):
    rng = random.Random(seed)
    boundaries = [0, 1, 0x7FFF, 0x8000, 0xFFFF]
    for n in range(count):
        index = n % 100  # Repeated logical sessions; transport simply echoes.
        first, second = (0x11, 0x22) if n % 2 == 0 else (0x22, 0x11)
        price1 = boundaries[n] if n < len(boundaries) else rng.randrange(65536)
        price2 = boundaries[-n-1] if n < len(boundaries) else rng.randrange(65536)
        request = struct.pack('>HBHBH', index, first, price1, second, price2)
        expected = struct.pack('>HBBBBBB', index, first, 0, second, 0, 0, 0)
        yield request, expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port', help='Serial device, e.g. /dev/ttyUSB0 or COM3')
    parser.add_argument('--count', type=int, default=100)
    parser.add_argument('--seed', type=lambda v: int(v, 0), default=0x57214720)
    parser.add_argument('--timeout', type=float, default=1.0, help='Response deadline in seconds')
    parser.add_argument('--byte-pause', type=float, default=0.0,
                        help='Pause between request bytes in seconds')
    args = parser.parse_args()
    if args.count < 1 or args.timeout <= 0 or args.byte_pause < 0:
        parser.error('count/timeout must be positive; byte-pause must be nonnegative')
    import serial
    elapsed = []
    with serial.Serial(args.port, baudrate=115200, bytesize=serial.EIGHTBITS,
                       parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
                       timeout=args.timeout, write_timeout=args.timeout,
                       xonxoff=False, rtscts=False, dsrdtr=False) as device:
        # Do not reset or discard input automatically: stale bytes are a failure.
        for n, (request, expected) in enumerate(fixtures(args.count, args.seed)):
            if device.in_waiting:
                raise RuntimeError(f'Unexpected bytes before request {n}; reset board and retry')
            start = time.monotonic()
            chunks = [bytes([b]) for b in request] if args.byte_pause else [request]
            for j, chunk in enumerate(chunks):
                if device.write(chunk) != len(chunk):
                    raise RuntimeError(f'Short write for request {n}')
                if args.byte_pause and j != len(chunks)-1:
                    time.sleep(args.byte_pause)
            device.flush()
            deadline = time.monotonic() + args.timeout
            response = bytearray()
            while len(response) < 8:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                device.timeout = remaining
                response.extend(device.read(8-len(response)))
            if bytes(response) != expected:
                raise RuntimeError(f'Request {n}: sent {request.hex()}, expected {expected.hex()}, '
                                   f'got {response.hex()} ({len(response)}/8 bytes)')
            elapsed.append(time.monotonic()-start)
        # Detect surplus output after the final response too.
        device.timeout = args.timeout
        extra = device.read(1)
        if extra:
            raise RuntimeError(f'Unexpected extra response data: {extra.hex()}')
    print(f'PASS: {args.count}/{args.count} transport responses; zero mismatches/timeouts; '
          f'mean {1000*sum(elapsed)/len(elapsed):.3f} ms, max {1000*max(elapsed):.3f} ms')
    print('Diagnostic NONE actions only; this is not an official algorithm PASS.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ImportError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
