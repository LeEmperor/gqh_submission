"""Local HDL checks only: never opens a serial port or invokes Gowin."""
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path.cwd()
generator = str((root / sys.argv[1]).resolve())
env = dict(os.environ, DUNE_SOURCEROOT=str(root))
expected_hashes = {
    'constraints/19_tang_nano_20k.cst': '2ac1e8bc9e282f8000a94c79f766123333b67a2cd29910ad2cba90a7554d6f5e',
    'tools/official/21_quick_uart_test.py': '4a9990ff06d90517f973b7e27bd2e8e59a844d7c4a7270c9591a0ab527a77fb5',
    'tools/official/22_robust_uart_test.py': '9aa45b8e51b698e2abf96c22ae1c493a79a5fd434bf55421f7e28048167a3f60',
}
for path, digest in expected_hashes.items():
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, path

def run(args, **kwargs):
    subprocess.run(args, check=True, env=env, **kwargs)

with tempfile.TemporaryDirectory(prefix='gqh-hdl-') as directory:
    tmp = Path(directory)
    for target, top in [('bringup', 'gqh_top'), ('history-probe', 'history_probe')]:
        path = tmp / (top + '.v')
        run([generator, target, '-output', str(path)], cwd=tmp)
        first = path.read_bytes()
        run([generator, target, '-output', str(path)], cwd=tmp)
        assert first == path.read_bytes(), 'non-deterministic generation'
        assert first == (root / 'rtl' / path.name).read_bytes(), 'stale deliverable'
        assert b'`include' not in first
        assert bool(re.search(rb'reg[^;\n]* = ', first)) == (top == 'gqh_top')
        netlist = tmp / (top + '.json')
        run(['yosys', '-Q', '-q', '-p',
             f'read_verilog {path}; hierarchy -check -top {top}; proc; opt_clean; check -assert; write_json {netlist}'])
        ports = json.loads(netlist.read_text())['modules'][top]['ports']
        expected = ({'sys_clk': ('input', 1), 'reset_btn': ('input', 1),
                     'uart_rx_i': ('input', 1), 'uart_tx_o': ('output', 1),
                     'led0_n': ('output', 1), 'led1_n': ('output', 1)}
                    if top == 'gqh_top' else
                    {'clock': ('input', 1), 'write_enable': ('input', 1),
                     'write_address': ('input', 5), 'write_data': ('input', 16),
                     'read_address': ('input', 5), 'read_data': ('output', 16)})
        assert {k: (v['direction'], len(v['bits'])) for k, v in ports.items()} == expected
        run(['iverilog', '-g2012', '-s', top, '-o', str(tmp / top), str(path)])
        tb = 'bringup_tb' if top == 'gqh_top' else 'history_tb'
        executable = tmp / tb
        run(['iverilog', '-g2012', '-s', tb, '-o', str(executable),
             str(path), str(root / ('test/' + tb + '.v'))])
        run(['vvp', str(executable)])
print('PASS: official checksums, deterministic deliverables, exact ports, complete HDL elaboration')
