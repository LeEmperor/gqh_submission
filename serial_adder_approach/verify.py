"""Run from any directory. Uses the existing independent direct-window oracle."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / 'test/engine/oracle'))
from model import ReferenceModel, encode_request, decode_request, ITEM_A, ITEM_B


def main():
    evidence = HERE / 'evidence'
    evidence.mkdir(exist_ok=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', DUNE_SOURCEROOT=str(ROOT))
    with (evidence / 'verification.log').open('w') as log:
        def run(args):
            args = [str(a) for a in args]
            print('+', ' '.join(args), flush=True)
            result = subprocess.run(args, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            print(result.stdout, end='', flush=True)
            log.write('+ ' + ' '.join(args) + '\n' + result.stdout)
            log.flush()
            result.check_returncode()

        with tempfile.TemporaryDirectory(prefix='serial-adder-', dir='/tmp/opencode') as tmp:
            tmp = Path(tmp)
            run(['opam', 'exec', '--switch=5.2.0+ox', '--', 'dune', 'exec',
                 'serial_adder_approach/generate.exe', '--', tmp])
            for name in ['gqh_serial_top.v', 'gqh_serial_engine_only_top.v', 'serial_engine_test.v']:
                assert (tmp / name).read_bytes() == (HERE / name).read_bytes(), f'stale RTL: {name}'

            # Reuse the production serial trace builder: 800 pristine fixture
            # packets plus full-range, equality/truncation, swap, wrap sessions.
            spec = importlib.util.spec_from_file_location('serial_checks', ROOT / 'test/integration/run_checks.py')
            checks = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(checks)
            checks.ROOT = ROOT
            packets = evidence / 'packets.txt'
            summary = checks.trace(packets)

            # Add thousands of full-range commands cheaply at the engine port,
            # checking the actual stored sum and relation as well as the action.
            requests = [bytes.fromhex(line.split()[0]) for line in packets.read_text().splitlines()]
            rng = random.Random(0x53455249)
            for session in range(12):
                for index in range(257):
                    a, b = rng.randrange(65536), rng.randrange(65536)
                    if session == 0: a = b = 65535
                    if session == 1: a = b = 0
                    if session == 2: a, b = (65535, 0) if index % 2 else (0, 65535)
                    requests.append(encode_request(index, ITEM_A, a, ITEM_B, b) if rng.randrange(2)
                                    else encode_request(index, ITEM_B, b, ITEM_A, a))
            oracle = ReferenceModel()
            rows = []
            for request in requests:
                index, id1, p1, id2, p2 = decode_request(request)
                response = oracle.respond(request)
                for slot, (item, price, action) in enumerate([(id1, p1, response[3]), (id2, p2, response[5])]):
                    total = sum(oracle._windows[item])
                    rows.append(f'{int(index == 0 and slot == 0)} {int(item == ITEM_B)} '
                                f'{int(index < 16)} {price} {index % 16} {action} {total} '
                                f'{int(price < total // 16)} {int(price > total // 16)}')
            engine_trace = evidence / 'engine-commands.txt'
            engine_trace.write_text('\n'.join(rows) + '\n')
            run(['iverilog', '-g2012', '-s', 'engine_tb', '-o', tmp / 'engine',
                 HERE / 'serial_engine_test.v', HERE / 'engine_tb.v'])
            run(['vvp', tmp / 'engine', f'+TRACE={engine_trace}'])
            run(['iverilog', '-g2012', '-s', 'tx_tb', '-o', tmp / 'tx',
                 HERE / 'gqh_serial_top.v', HERE / 'tx_tb.v'])
            run(['vvp', tmp / 'tx'])

            summary['engine_samples'] = len(rows)
            summary['variants'] = {}
            for variant, name in [('serial_lfsr', 'gqh_serial_top.v'),
                                  ('serial_engine_only', 'gqh_serial_engine_only_top.v')]:
                rtl = HERE / name
                net = tmp / f'{variant}.json'
                run(['yosys', '-Q', '-q', '-p',
                     f'read_verilog {rtl}; hierarchy -check -top gqh_competition_top; '
                     f'proc; opt_clean; check -assert; write_json {net}'])
                modules = json.loads(net.read_text())['modules']
                ports = modules['gqh_competition_top']['ports']
                expected = {'sys_clk': 'input', 'reset_btn': 'input', 'uart_rx_i': 'input',
                            'uart_tx_o': 'output', 'led0_n': 'output', 'led1_n': 'output'}
                assert {k: (v['direction'], len(v['bits'])) for k, v in ports.items()} == {
                    k: (v, 1) for k, v in expected.items()}
                assert ports['led0_n']['bits'] == ports['led1_n']['bits'] == ['1']
                memories = modules['gqh_update_engine']['memories']
                assert {k: (v['size'], v['width']) for k, v in memories.items()} == {
                    'serial_history': (512, 1), 'serial_sums': (64, 1), 'serial_metadata': (2, 4)}
                assert rtl.read_text().count('syn_ramstyle="block_ram"') == 4
                exe = tmp / variant
                run(['iverilog', '-g2012', '-DHOPT_NO_DIAGNOSTICS',
                     '-DHOPT_ENGINE_RESULT_STATE=3', '-DHOPT_ENGINE_SERIAL_DIGITS=20',
                     '-s', 'competition_tb', '-o', exe, rtl,
                     ROOT / 'test/integration/packet_ram_tb.v'])
                run(['vvp', exe, f'+TRACE={packets}', f'+LATENCY={evidence / (variant + "-latency.csv")}'])
                summary['variants'][variant] = {'rtl': name,
                    'rtl_sha256': hashlib.sha256(rtl.read_bytes()).hexdigest()}
            summary['timing'] = {'core_hz': 27000000, 'clocks_per_bit': 234, 'extra_gap': 0}
            summary['status'] = 'PASS'
            (evidence / 'verification.json').write_text(json.dumps(summary, indent=2) + '\n')
            print('PASS: both serial candidates; see evidence/verification.json', flush=True)


if __name__ == '__main__':
    main()
