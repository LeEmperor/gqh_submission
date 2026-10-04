"""G2 pin-level oracle replay, complete hierarchy and production timing checks."""
from pathlib import Path
import collections
import csv
import hashlib
import json
import os
import random
import subprocess
import sys
import tempfile

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / 'test/engine/oracle'))
from model import ReferenceModel, decode_request, encode_request, ITEM_A, ITEM_B


def trace(path):
    model = ReferenceModel()
    rows = []
    coverage = collections.Counter()

    def add(request, saved=None):
        index, id1, p1, id2, p2 = decode_request(request)
        coverage['sessions'] += index == 0
        coverage['warmup' if index < 16 else 'scored'] += 1
        coverage['warmup_swaps' if index < 16 else 'steady_swaps'] += id1 == ITEM_B
        coverage['wraps'] += index >= 16 and index % 16 == 0
        previous = dict(model._actions)
        for item, price in [(id1, p1), (id2, p2)]:
            coverage['maximum_prices'] += price == 65535
            coverage['zero_prices'] += price == 0
            if index >= 16:
                window = model._windows[item]  # Only coverage; direct-window oracle supplies bytes.
                old_sum, new_sum = sum(window), sum(window[1:] + [price])
                coverage['previous_equality'] += window[-1] == old_sum // 16
                coverage['incoming_equality'] += price == new_sum // 16
                coverage['truncation'] += old_sum % 16 != 0 or new_sum % 16 != 0
        response = model.respond(request)
        if saved is not None:
            assert response == saved
        for item, action in [(id1, response[3]), (id2, response[5])]:
            coverage[f'action_{action}'] += 1
            coverage[f'held_{action}'] += index >= 16 and action == previous[item]
        rows.append(f'{request.hex()} {response.hex()}')

    oracle = ROOT / 'test/engine/oracle'
    provenance = json.loads((oracle / 'SOURCE.json').read_text())
    for entry in provenance['files']:
        if entry['unchanged']:
            assert hashlib.sha256((oracle / entry['local_path']).read_bytes()).hexdigest() == entry['upstream_sha256']
    for folder in sorted((oracle / 'fixtures').iterdir()):
        for line in (folder / 'fixture.jsonl').read_text().splitlines():
            r = json.loads(line)
            add(bytes.fromhex(r['request_hex']), bytes.fromhex(r['expected_response_hex']))
    assert len(rows) == 800
    directed = [
        [(100, 200)]*16 + [(102,198),(103,197),(99,201),(98,202)]*24,
        [(65535, 0)]*16 + [(65535,0),(0,65535),(1,65534),(65534,1)]*24,
        [(100,100)]*15 + [(115,85)] + [(101,99),(100,100),(100,100)]*32,
    ]
    for prices in directed:
        for index, (a, b) in enumerate(prices):
            add(encode_request(index, ITEM_B, b, ITEM_A, a) if index % 2 == 0
                else encode_request(index, ITEM_A, a, ITEM_B, b))
    for seed in [42, 65535]:
        rng = random.Random(seed)
        for index in range(129):
            a, b = rng.randrange(65536), rng.randrange(65536)
            add(encode_request(index, ITEM_B, b, ITEM_A, a) if rng.randrange(2)
                else encode_request(index, ITEM_A, a, ITEM_B, b))
    for required in ['warmup_swaps', 'steady_swaps', 'wraps', 'maximum_prices',
                     'zero_prices', 'held_1', 'held_2', 'previous_equality',
                     'incoming_equality', 'truncation']:
        assert coverage[required] > 0, required
    path.write_text('\n'.join(rows) + '\n')
    return dict(records=len(rows), supplied=800, coverage=dict(sorted(coverage.items())),
                trace_sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    protocol_variant = os.environ.get('HOPT_PROTOCOL', 'default')
    uart_variant = os.environ.get('HOPT_UART', 'default')
    packet_ram = protocol_variant == 'packet_ram'
    assert protocol_variant in ['default', 'packet_ram']
    assert uart_variant in ['default', 'rx_timer', 'tx_timer', 'both_timers']
    candidate_flags = (['-packet-ram'] if packet_ram else [])
    for name, flag in [('HOPT_RECORDS_IN_BRAM', '-records-in-bram'),
                       ('HOPT_BORROW_COMMAND', '-borrow-command'),
                       ('HOPT_DELTA_ARITHMETIC', '-delta-arithmetic'),
                       ('HOPT_DIFFERENCE_RELATION', '-difference-relation')]:
        if os.environ.get(name) == '1':
            candidate_flags.append(flag)
    variants = (['packet-ram'] if packet_ram else [])
    if uart_variant in ['rx_timer', 'both_timers']:
        candidate_flags += ['-rx-factored-timer']; variants += ['rx-factored-timer']
    if uart_variant in ['tx_timer', 'both_timers']:
        candidate_flags += ['-tx-factored-timer']; variants += ['tx-factored-timer']
    generator, cyclesim = [str(Path(p).resolve()) for p in sys.argv[1:3]]
    output = Path(sys.argv[3]).resolve() if len(sys.argv) >= 4 and sys.argv[3] != '-' else None
    # A separate delivered candidate lets H experiments retain production RTL
    # as their fallback. Without this argument, retain the production check.
    expected_rtl = Path(sys.argv[4]).resolve() if len(sys.argv) == 5 else ROOT / 'rtl/gqh_competition_top.v'
    env = dict(os.environ, DUNE_SOURCEROOT=str(ROOT), PYTHONDONTWRITEBYTECODE='1')
    def run(args):
        subprocess.run([str(a) for a in args], check=True, env=env)
    with tempfile.TemporaryDirectory(prefix='phase-g2-') as directory:
        tmp = Path(directory)
        packets = tmp / 'packets.txt'
        summary = trace(packets)
        run([cyclesim, packets, *variants])
        for variant in ([] if packet_ram or uart_variant != 'default' or os.environ.get('HOPT_ONLY_ENGINE') == '1' else ['controller-binary', 'controller-onehot',
                        'sequencer-binary', 'sequencer-onehot', 'rx-binary',
                        'rx-onehot', 'tx-binary', 'tx-onehot', 'tx-shift']):
            run([cyclesim, packets, variant])
        rtl = tmp / 'gqh_competition_top.v'
        run([generator, 'competition', *candidate_flags, '-output', rtl])
        first = rtl.read_bytes()
        run([generator, 'competition', *candidate_flags, '-output', rtl])
        assert first == rtl.read_bytes(), 'nondeterministic RTL'
        assert first == expected_rtl.read_bytes(), f'stale delivered RTL: {expected_rtl}'
        assert first.count(b'syn_ramstyle="block_ram"') == 1 + int(packet_ram) + int(os.environ.get('HOPT_RECORDS_IN_BRAM') == '1')
        assert b'(* syn_ramstyle="block_ram" *)\n    reg [15:0] engine_history[0:31]' in first
        net = tmp / 'net.json'
        run(['yosys', '-Q', '-q', '-p', f'read_verilog {rtl}; hierarchy -check -top gqh_competition_top; proc; opt_clean; check -assert; write_json {net}'])
        modules = json.loads(net.read_text())['modules']
        ports = modules['gqh_competition_top']['ports']
        expected = {'sys_clk': 'input', 'reset_btn': 'input', 'uart_rx_i': 'input',
                    'uart_tx_o': 'output', 'led0_n': 'output', 'led1_n': 'output'}
        assert {k: (v['direction'], len(v['bits'])) for k, v in ports.items()} == {k: (v, 1) for k, v in expected.items()}
        base_modules = {'gqh_competition_top', 'gqh_reset_release', 'gqh_heartbeat',
                        'gqh_uart_rx', 'gqh_uart_tx', 'gqh_update_engine'}
        protocol_modules = ({'gqh_packet_ram_controller'} if packet_ram else
                            {'gqh_request_decoder', 'gqh_transaction_controller', 'gqh_response_sequencer'})
        assert set(modules) == base_modules | protocol_modules
        if packet_ram:
            packet = modules['gqh_packet_ram_controller']
            memories = packet['memories']
            assert len(memories) == 1
            assert list(memories.values())[0]['width'] == 8
            assert list(memories.values())[0]['size'] == 8
            assert b'reg [7:0] request_packet[0:7]' in first
        exe = tmp / 'serial'
        engine = modules['gqh_update_engine']['netnames']
        if 'engine_digit' in engine:
            counter_bits = len(engine['engine_digit']['bits'])
            engine_variant = {2:'h3_serial8', 3:'h3_serial4',
                              4:'h3_serial2', 5:'h3_serial1'}[counter_bits]
        else:
            engine_variant = 'h2' if len(engine['engine_state']['bits']) == 2 else 'h3_compare'
        requested_engine = os.environ.get('HOPT_ENGINE')
        if requested_engine:
            assert requested_engine == engine_variant or {requested_engine, engine_variant} == {'h2','h3_shared20'}, 'engine schedule metadata mismatch'
        engine_defines = []
        if engine_variant == 'h3_compare':
            engine_defines = ['-DHOPT_ENGINE_RESULT_STATE=5']
        elif engine_variant.startswith('h3_serial'):
            digit_width = int(engine_variant.removeprefix('h3_serial'))
            assert digit_width in [8, 4, 2, 1]
            digits = (20 + digit_width - 1) // digit_width
            engine_defines = ['-DHOPT_ENGINE_RESULT_STATE=6',
                              f'-DHOPT_ENGINE_SERIAL_DIGITS={digits}']
        elif engine_variant not in ['h2', 'h3_shared20']:
            raise ValueError(f'unknown engine variant: {engine_variant}')
        run(['iverilog', '-g2012', *engine_defines, '-s', 'competition_tb', '-o', exe, rtl,
             ROOT / ('test/integration/packet_ram_tb.v' if packet_ram else 'test/integration/competition_tb.v')])
        run(['vvp', exe, f'+TRACE={packets}', f'+LATENCY={tmp / "latency.csv"}'])
        with (tmp / 'latency.csv').open() as latency_file:
            reader = csv.DictReader(latency_file)
            expected_endpoint = ('accept_to_first_tx_accept_cycles' if packet_ram
                                 else 'accept_to_response_valid_cycles')
            assert reader.fieldnames == ['index', expected_endpoint]
            samples = [(int(row['index']), int(row[expected_endpoint])) for row in reader]
        indices = [int(line[:4], 16) for line in packets.read_text().splitlines()]
        assert [index for index, _ in samples] == indices
        assert len(samples) == summary['records']
        assert all(0 < value < 1000 for _, value in samples)
        session_cycles = {value for index, value in samples if index == 0}
        other_cycles = {value for index, value in samples if index != 0}
        assert len(session_cycles) == len(other_cycles) == 1
        assert next(iter(session_cycles)) == next(iter(other_cycles)) + 2
        summary['latency'] = dict(endpoint=expected_endpoint,
                                  session_cycles=next(iter(session_cycles)),
                                  other_cycles=next(iter(other_cycles)),
                                  samples=len(samples))
        summary['rtl_sha256'] = hashlib.sha256(first).hexdigest()
        summary['timing'] = dict(core_hz=27000000, divisor=234, host_baud=115200, extra_gap=0)
        print(json.dumps(summary, indent=2), flush=True)
        if output:
            output.mkdir(parents=True, exist_ok=True)
            for file in [rtl, packets, tmp / 'latency.csv']:
                (output / file.name).write_bytes(file.read_bytes())
            (output / 'coverage.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('PASS G2: Cyclesim serial oracle, production-timing RTL serial, resets/faults, deterministic hierarchy and six ports')

if __name__ == '__main__':
    main()
