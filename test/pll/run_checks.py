#!/usr/bin/env python3
"""Verify PLL configuration, lock/reset recovery and full-rate serial behavior.

The full serial replay uses an explicitly ideal PLL model (Verilator). The
separate vendor smoke test elaborates the real wrapper with Gowin's rPLL model
(Icarus). Neither is analog PLL characterization or board acceptance.
"""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('generator', type=Path)
    parser.add_argument('--vendor-lib', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    generator = args.generator.resolve()
    vendor = args.vendor_lib.resolve()
    assert vendor.is_file(), vendor
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    artifact = ROOT / 'gowin/pll270'
    rtl = artifact / 'gqh_competition_pll_top.v'
    wrapper = artifact / 'gowin_rpll_81.v'
    tests = ROOT / 'test/pll'

    def run(label, command):
        command = [str(x) for x in command]
        (out / (label + '.command.json')).write_text(json.dumps(command, indent=2) + '\n')
        with (out / (label + '.log')).open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=900)
        print('PASS', label, flush=True)

    with tempfile.TemporaryDirectory(prefix='pll-check-', dir=out) as tmp:
        tmp = Path(tmp)
        regenerated = tmp / 'regenerated.v'
        run('generate', [generator, 'competition-pll', '-output', regenerated])
        assert regenerated.read_bytes() == rtl.read_bytes()
        run('generate-again', [generator, 'competition-pll', '-output', regenerated])
        assert regenerated.read_bytes() == rtl.read_bytes()
        modules = lambda text: {name: body for body, name in
                               re.findall(r'(module (\w+)\b.*?endmodule)', text, re.S)}
        before = modules((ROOT / 'rtl/gqh_competition_bsram_lean_top.v').read_text())
        after = modules(rtl.read_text())
        for name in ['gqh_update_engine', 'gqh_packet_ram_controller', 'gqh_reset_release']:
            assert before[name] == after[name], name
        parameters = lambda text: dict(re.findall(r'defparam rpll_inst\.(\w+)\s*=\s*([^;]+);', text))
        original = parameters((artifact / 'ip-source/gowin_rpll.v').read_text())
        assert parameters(wrapper.read_text()) == original
        assert original['FCLKIN'] == '"27"' and original['IDIV_SEL'] == '0'
        assert original['FBDIV_SEL'] == '2' and original['ODIV_SEL'] == '8'
        assert '-multiply_by 3' in (artifact / 'pll81.sdc').read_text()

        reset_exe = tmp / 'reset'
        run('reset-compile', ['iverilog', '-g2012', '-s', 'pll_reset_tb', '-o', reset_exe,
                             rtl, tests / 'pll_model.v', tests / 'reset_tb.v'])
        run('reset', ['vvp', reset_exe])
        assert 'PASS PLL reset:' in (out / 'reset.log').read_text()
        vendor_exe = tmp / 'vendor'
        run('vendor-compile', ['iverilog', '-g2012', '-s', 'pll_vendor_tb', '-o', vendor_exe,
                              rtl, wrapper, vendor, tests / 'vendor_tb.v'])
        run('vendor', ['vvp', vendor_exe])
        assert 'PASS vendor rPLL model:' in (out / 'vendor.log').read_text()

        spec = importlib.util.spec_from_file_location('serial_vectors', ROOT / 'test/integration/run_checks.py')
        vectors = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(vectors)
        vectors.ROOT = ROOT
        packets = out / 'packets.txt'
        summary = vectors.trace(packets)
        obj = tmp / 'verilated'
        run('serial-compile', ['verilator', '--binary', '--timing', '-Wno-fatal', '-j', '2',
                              '--top-module', 'competition_tb', '--Mdir', obj,
                              '-DHOPT_PLL', '-DHOPT_NO_DIAGNOSTICS',
                              '-DHOPT_CORE_MHZ=81', '-DHOPT_UART_DIVISOR=702',
                              '-DHOPT_TOP=gqh_competition_pll_top', rtl,
                              tests / 'pll_model.v', ROOT / 'test/integration/packet_ram_tb.v'])
        run('serial', [obj / 'Vcompetition_tb', '+TRACE=' + str(packets),
                       '+LATENCY=' + str(out / 'latency.csv')])
        log = (out / 'serial.log').read_text()
        assert 'PASS: 1394 production-divisor serial oracle packets' in log
        assert 'RX/engine/TX reset recovery and LEDs off' in log
        with (out / 'latency.csv').open() as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == summary['records']
        assert [int(row['index']) for row in rows] == [int(line[:4], 16) for line in packets.read_text().splitlines()]
        for row in rows:
            assert int(row['accept_to_first_tx_accept_cycles']) == (18 if int(row['index']) == 0 else 16)
        summary.update(status='passed', rtl_sha256=digest(rtl), pll_wrapper_sha256=digest(wrapper),
                       vendor_library_sha256=digest(vendor), reference_hz=27000000,
                       core_hz=81000000, uart_divisor=702, host_baud=115200,
                       scope='Ideal-PLL full serial replay; stopped-clock lock/reset recovery; real wrapper plus vendor rPLL functional-model smoke; not board acceptance')
        (out / 'verification.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
