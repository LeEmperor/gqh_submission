"""Elaborate and exercise the emitted transport; no hardware access."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path.cwd()
generator = str((root / sys.argv[1]).resolve())
env = dict(os.environ, DUNE_SOURCEROOT=str(root))
def run(args):
    subprocess.run(args, check=True, env=env)
with tempfile.TemporaryDirectory(prefix='gqh-transport-') as d:
    tmp = Path(d)
    rtl = tmp / 'gqh_transport_top.v'
    run([generator, 'transport', '-output', str(rtl)])
    first = rtl.read_bytes()
    run([generator, 'transport', '-output', str(rtl)])
    assert first == rtl.read_bytes(), 'nondeterministic RTL'
    assert first == (root / 'rtl/gqh_transport_top.v').read_bytes(), 'stale RTL'
    net = tmp / 'net.json'
    run(['yosys', '-Q', '-q', '-p', f'read_verilog {rtl}; hierarchy -check -top gqh_transport_top; proc; opt_clean; check -assert; write_json {net}'])
    ports = json.loads(net.read_text())['modules']['gqh_transport_top']['ports']
    expected = {'sys_clk': 'input', 'reset_btn': 'input', 'uart_rx_i': 'input',
                'uart_tx_o': 'output', 'led0_n': 'output', 'led1_n': 'output'}
    assert {k: (v['direction'], len(v['bits'])) for k, v in ports.items()} == {k: (v, 1) for k, v in expected.items()}
    exe = tmp / 'transport'
    run(['iverilog', '-g2012', '-s', 'transport_tb', '-o', str(exe), str(rtl), str(root / 'test/transport/transport_tb.v')])
    run(['vvp', str(exe)])
print('PASS: transport deterministic RTL, six ports and full hierarchy')
