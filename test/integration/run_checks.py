"""G2 pin-level oracle replay, complete hierarchy and production timing checks."""
from pathlib import Path
import collections
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
        run([cyclesim, packets])
        rtl = tmp / 'gqh_competition_top.v'
        run([generator, 'competition', '-output', rtl])
        first = rtl.read_bytes()
        run([generator, 'competition', '-output', rtl])
        assert first == rtl.read_bytes(), 'nondeterministic RTL'
        assert first == expected_rtl.read_bytes(), f'stale delivered RTL: {expected_rtl}'
        assert first.count(b'(* syn_ramstyle="block_ram" *)') == 1
        assert b'(* syn_ramstyle="block_ram" *)\n    reg [15:0] engine_history[0:31]' in first
        net = tmp / 'net.json'
        run(['yosys', '-Q', '-q', '-p', f'read_verilog {rtl}; hierarchy -check -top gqh_competition_top; proc; opt_clean; check -assert; write_json {net}'])
        modules = json.loads(net.read_text())['modules']
        ports = modules['gqh_competition_top']['ports']
        expected = {'sys_clk': 'input', 'reset_btn': 'input', 'uart_rx_i': 'input',
                    'uart_tx_o': 'output', 'led0_n': 'output', 'led1_n': 'output'}
        assert {k: (v['direction'], len(v['bits'])) for k, v in ports.items()} == {k: (v, 1) for k, v in expected.items()}
        assert set(modules) == {'gqh_competition_top', 'gqh_reset_release', 'gqh_heartbeat',
                               'gqh_uart_rx', 'gqh_uart_tx', 'gqh_request_decoder',
                               'gqh_transaction_controller', 'gqh_update_engine', 'gqh_response_sequencer'}
        exe = tmp / 'serial'
        run(['iverilog', '-g2012', '-s', 'competition_tb', '-o', exe, rtl,
             ROOT / 'test/integration/competition_tb.v'])
        run(['vvp', exe, f'+TRACE={packets}', f'+LATENCY={tmp / "latency.csv"}'])
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
