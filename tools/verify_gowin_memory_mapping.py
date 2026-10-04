#!/usr/bin/env python3
"""Simulate an open-source mapped design with installed Gowin RAM models.

Logic cells use the pinned Yosys functional library. Memory cells use the
installed vendor's functional model, including its physical address decoding.
This is not a vendor-synthesized or postroute simulation. Source-level tests
remain necessary. No proprietary model bytes are copied to the result bundle.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module_pattern(name):
    return re.compile(r'^module\s+' + re.escape(name)
                      + r'\s*\(.*?^endmodule[^\n]*', re.M | re.S)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True,
                        help='run_open_gowin.py build directory')
    parser.add_argument('--suite', type=Path, required=True)
    parser.add_argument('--vendor-lib', type=Path, required=True)
    parser.add_argument('--bench', type=Path, required=True)
    parser.add_argument('--trace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--top', default='gqh_competition_top')
    parser.add_argument('--bench-top', default='competition_tb')
    parser.add_argument('--pass-marker', default='PASS:')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    result = {'status': 'running', 'scope':
              'Yosys mapped logic plus installed Gowin functional RAM models; '
              'poisoned RAM; not vendor synthesis, postroute timing, or board acceptance'}
    result['configuration'] = {
        key: str(value) if isinstance(value, Path) else value
        for key, value in vars(args).items()
    }
    try:
        mapped = args.build / 'synthesis.v'
        net = json.loads((args.build / 'synthesis.json').read_text())
        cells = net['modules'][args.top]['cells']
        supported = ['SP', 'SPX9', 'DPX9B']
        memory = {name: cell for name, cell in cells.items()
                  if cell['type'] in supported}
        unsupported = {cell['type'] for cell in cells.values()
                       if cell['type'].startswith(('DP', 'SDP', 'RAM'))
                       and cell['type'] not in supported}
        if unsupported or not memory:
            raise ValueError(f'Unsupported or missing memories: {unsupported}')
        yosys_lib = args.suite / 'share/yosys/gowin/cells_sim.v'
        vendor = args.vendor_lib.read_text()
        logic = yosys_lib.read_text()
        memories = []
        for kind in supported:
            matches = module_pattern(kind).findall(vendor)
            if len(matches) != 1:
                raise ValueError(f'Missing/ambiguous vendor primitive {kind}')
            memories.append(matches[0])
            logic, count = module_pattern(kind).subn('', logic)
            if count != 1 and not (kind == 'DPX9B' and count == 0):
                raise ValueError(f'Missing/ambiguous Yosys primitive {kind}')
        poison = ['  initial begin : poison_physical_memories', '    #1;']
        identities = {}
        for ordinal, (name, cell) in enumerate(sorted(memory.items())):
            if any(char.isspace() for char in name):
                raise ValueError('Unsupported cell name with whitespace')
            width_names = ['BIT_WIDTH_0', 'BIT_WIDTH_1'] if cell['type'] == 'DPX9B' else ['BIT_WIDTH']
            widths = [int(cell['parameters'][key], 2) for key in width_names]
            allowed = ([9, 18] if cell['type'] == 'DPX9B' else
                       [9, 18, 36] if cell['type'] == 'SPX9' else [1, 2, 4, 8, 16, 32])
            if any(width not in allowed for width in widths):
                raise ValueError(f'Unsupported RAM widths {widths}')
            bits = 16384 if cell['type'] == 'SP' else 18432
            poison.append(f'    for (integer k=0; k<{bits}; k=k+1)')
            poison.append(f'      dut.\\{name} .ram_MEM[k] = ((k*13 + {ordinal}*7) % 11) < 6;')
            identities[name] = {'primitive': cell['type'], 'widths': widths,
                                'poisoned_bits': bits, 'parameters': cell['parameters']}
        poison.append('  end')
        bench = args.bench.read_text()
        if bench.count('endmodule') != 1:
            raise ValueError('Smoke bench must have exactly one module')
        bench = bench.replace('endmodule', '\n'.join(poison) + '\nendmodule')
        bench_path = args.output / 'mapped_smoke_tb.v'
        bench_path.write_text(bench)
        inputs = {'mapped_rtl': mapped, 'synthesis_json': args.build / 'synthesis.json',
                  'vendor_library': args.vendor_lib, 'yosys_library': yosys_lib,
                  'original_bench': args.bench, 'trace': args.trace,
                  'poisoned_bench': bench_path, 'runner': Path(__file__)}
        result.update(inputs={name: {'path': str(path.resolve()), 'sha256': digest(path)}
                              for name, path in inputs.items()}, memories=identities)
        result['iverilog_version'] = subprocess.run(
            ['iverilog', '-V'], capture_output=True, text=True, check=True).stdout.splitlines()[0]
        with tempfile.TemporaryDirectory(prefix='gqh-vendor-ram-') as temp:
            runtime = Path(temp)
            (runtime / 'logic.v').write_text(logic)
            (runtime / 'memories.v').write_text('`timescale 1ns/1ps\n' + '\n'.join(memories))
            # Keep plusargs short: legacy benches have fixed-width path buffers.
            # The original trace is hash-bound above; these bytes are identical.
            shutil.copyfile(args.trace, runtime / 'trace.txt')
            commands = [
                ['iverilog', '-g2012', '-s', args.bench_top, '-o', str(runtime / 'sim'),
                 str(mapped), str(runtime / 'logic.v'), str(runtime / 'memories.v'), str(bench_path)],
                ['vvp', str(runtime / 'sim'), '+TRACE=' + str(runtime / 'trace.txt'),
                 '+LATENCY=' + str(runtime / 'latency.csv')]]
            result['commands'] = commands
            for index, command in enumerate(commands):
                with (args.output / f'{index}.log').open('w') as log:
                    subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT,
                                   timeout=args.timeout)
            if (runtime / 'latency.csv').exists():
                shutil.copyfile(runtime / 'latency.csv', args.output / 'unused_latency.csv')
        if args.pass_marker not in (args.output / '1.log').read_text():
            raise ValueError('Smoke simulation exited without a PASS marker')
        result['status'] = 'passed'
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result.update(status='failed', error=str(error))
    finally:
        (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'output': str(args.output)}))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
