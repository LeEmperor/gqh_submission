#!/usr/bin/env python3
"""Auditable OPEN-SOURCE Gowin synthesis/P&R/packing; never official Gowin counts.

Uses a caller-supplied pinned OSS CAD Suite installation. No programming or
installation is performed. nextpnr receives the unchanged CST and explicit
27 MHz clock and supplied SDC. No suite GUI wrappers or HOME changes are used.
"""
import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
TOP = 'gqh_competition_top'
PART = 'GW2AR-LV18QN88C8/I7'
FAMILY = 'GW2A-18C'
FREQUENCY_MHZ = 27.0
PINS = {'sys_clk': 4, 'reset_btn': 87, 'uart_rx_i': 70, 'uart_tx_o': 69,
        'led0_n': 15, 'led1_n': 16}


class BuildError(RuntimeError):
    pass


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def finite_number(value, field):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise BuildError(f'Malformed/nonfinite {field}')
    return value


def parse_outputs(build):
    """Read native counts as-is; do not convert to vendor Logic/LUT qualification."""
    def load(name):
        path = build / name
        if not path.is_file() or not path.stat().st_size:
            raise BuildError(f'Missing/empty output: {name}')
        try:
            data = json.loads(path.read_text())
        except (ValueError, UnicodeError) as exc:
            raise BuildError(f'Malformed JSON output: {name}') from exc
        if not isinstance(data, dict):
            raise BuildError(f'Malformed JSON object output: {name}')
        return data
    synthesis = load('synthesis.json')
    modules = synthesis.get('modules', {})
    if not isinstance(modules, dict) or not isinstance(modules.get(TOP), dict):
        raise BuildError('Synthesized JSON does not contain the pinned competition top')
    cells = modules[TOP].get('cells')
    if not isinstance(cells, dict) or not cells:
        raise BuildError('Synthesized competition top contains no cells')
    types = Counter()
    for cell in cells.values():
        if not isinstance(cell, dict) or not isinstance(cell.get('type'), str):
            raise BuildError('Malformed synthesis cell type')
        types[cell['type']] += 1
    report = load('nextpnr-report.json')
    utilization = report.get('utilization')
    if not isinstance(utilization, dict) or not utilization:
        raise BuildError('Missing nextpnr utilization report')
    if not {'LUT4', 'ALU', 'DFF', 'BSRAM'}.issubset(utilization):
        raise BuildError('Missing required nextpnr LUT4/ALU/DFF/BSRAM resource counts')
    parsed = {}
    for resource, counts in utilization.items():
        if not isinstance(counts, dict):
            raise BuildError(f'Malformed utilization: {resource}')
        for field in ['used', 'available']:
            value = counts.get(field)
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise BuildError(f'Malformed utilization {resource}.{field}')
        if counts['used'] > counts['available']:
            raise BuildError(f'Over-capacity utilization: {resource}')
        parsed[resource] = {field: counts[field] for field in ['used', 'available']}
    fmax = report.get('fmax')
    if not isinstance(fmax, dict) or not fmax:
        raise BuildError('Missing nextpnr clock timing report')
    clocks = {}
    for clock, timing in fmax.items():
        if not isinstance(timing, dict):
            raise BuildError(f'Malformed clock timing: {clock}')
        achieved = finite_number(timing.get('achieved'), clock + '.achieved')
        constraint = finite_number(timing.get('constraint'), clock + '.constraint')
        if achieved <= 0 or constraint <= 0:
            raise BuildError(f'Invalid clock frequency: {clock}')
        clocks[clock] = {'achieved_mhz': achieved, 'constraint_mhz': constraint,
                         'meets_constraint': achieved >= constraint}
    if not all(abs(timing['constraint_mhz'] - FREQUENCY_MHZ) < 0.001 for timing in clocks.values()):
        raise BuildError('Clock report does not match the requested 27 MHz constraint')
    # Both the placed design and packed configuration must be real artifacts.
    placed = load('placed.json')
    # nextpnr's JSON writer renames the selected top module to literal "top".
    modules = placed.get('modules', {})
    if not isinstance(modules, dict) or set(modules) != {'top'} or not isinstance(modules['top'], dict):
        raise BuildError('Placed JSON does not contain nextpnr\'s single selected top')
    placed_top = modules['top']
    placed_cells = placed_top.get('cells', {})
    if not isinstance(placed_cells, dict) or not placed_cells:
        raise BuildError('Placed output has no cells')
    if any(not isinstance(cell, dict) or not isinstance(cell.get('type'), str)
           or not cell['type'] for cell in placed_cells.values()):
        raise BuildError('Malformed placed cell type')
    if any(not isinstance(cell.get('connections', {}), dict)
           or not isinstance(cell.get('attributes', {}), dict) for cell in placed_cells.values()):
        raise BuildError('Malformed placed cell connections or attributes')
    placed_types = Counter(cell['type'] for cell in placed_cells.values())
    if any(name in placed_types for name in ['BLOCKER_LUT', 'BLOCKER_FF']):
        raise BuildError('Placed output still contains temporary blocker cells; final routed output required')
    ports = placed_top.get('ports', {})
    if not isinstance(ports, dict) or set(ports) != set(PINS):
        raise BuildError('Placed JSON does not retain exactly the six competition ports')
    cst = (build / 'board.cst').read_text()
    declarations = re.findall(r'IO_LOC\s+"([^"]+)"\s+(\d+)\s*;', cst)
    declared_pins = {name: int(pin) for name, pin in declarations}
    if declared_pins != PINS or len(declarations) != len(PINS):
        raise BuildError('CST does not retain the pinned six competition board pins')
    bindings = {}
    for name, port in ports.items():
        if not isinstance(port, dict):
            raise BuildError('Malformed competition port: ' + name)
        direction = 'input' if name in ['sys_clk', 'reset_btn', 'uart_rx_i'] else 'output'
        bits = port.get('bits', [])
        if (port.get('direction') != direction or not isinstance(bits, list) or len(bits) != 1
                or isinstance(bits[0], bool) or not isinstance(bits[0], int)):
            raise BuildError('Malformed competition port: ' + name)
        cell_type, external_pin = ('IBUF', 'I') if direction == 'input' else ('OBUF', 'O')
        buffers = [(cell_name, cell) for cell_name, cell in placed_top.get('cells', {}).items()
                   if cell.get('type') == cell_type and cell.get('connections', {}).get(external_pin) == bits]
        if len(buffers) != 1:
            raise BuildError('Missing/ambiguous placed port buffer: ' + name)
        bel = buffers[0][1].get('attributes', {}).get('NEXTPNR_BEL')
        if not isinstance(bel, str) or not bel:
            raise BuildError('Missing/malformed placed port buffer BEL: ' + name)
        bindings[name] = {'constraint_package_pin': PINS[name], 'cell': buffers[0][0],
                          'placed_bel': bel}
    bitstream = build / 'competition.fs'
    if not bitstream.is_file() or not bitstream.stat().st_size:
        raise BuildError('Missing/empty packed bitstream')
    return {'measurement_flow': 'open_source_only',
            'official_gowin_logic': None, 'official_gowin_registers': None,
            'synthesis_cell_counts': dict(sorted(types.items())),
            'routed_cell_counts': dict(sorted(placed_types.items())),
            'nextpnr_utilization': parsed, 'nextpnr_clocks': clocks,
            'constrained_port_bindings': bindings,
            'meets_reported_clock_constraints': all(timing['meets_constraint'] for timing in clocks.values())}


@contextmanager
def build_lock(path):
    with path.open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise BuildError('Another open-source build holds the lock') from exc
        yield


def run_program(argv, cwd, environment, log, timeout):
    """Bound each process group; never kill by image name or unrelated PID."""
    with log.open('wb') as output:
        process = subprocess.Popen(argv, cwd=cwd, env=environment, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            except ProcessLookupError:
                pass
            raise BuildError(f'Process exceeded {timeout:.3f}s: {argv[0]}') from exc
    if code:
        raise BuildError(f'Tool failed with exit status {code}: {argv[0]}')


def suite_environment(suite):
    environment = os.environ.copy()
    environment['PATH'] = str(suite / 'bin') + os.pathsep + environment.get('PATH', '')
    environment['LD_LIBRARY_PATH'] = str(suite / 'lib') + os.pathsep + environment.get('LD_LIBRARY_PATH', '')
    environment['PYTHONHOME'] = str(suite)
    environment['PYTHONNOUSERSITE'] = '1'
    environment['GHDL_PREFIX'] = str(suite / 'lib/ghdl')
    environment['TCL_LIBRARY'] = str(suite / 'lib/tcl8.6')
    environment['TK_LIBRARY'] = str(suite / 'lib/tk8.6')
    environment['LC_ALL'] = 'C'
    environment.pop('PYTHONPATH', None)
    return environment


def tool_commands(suite):
    loader = suite / 'lib/ld-linux-x86-64.so.2'
    prefix = [str(loader), '--inhibit-cache', '--inhibit-rpath', '',
              '--library-path', str(suite / 'lib')]
    native = {name: suite / 'libexec' / name for name in ['yosys', 'nextpnr-himbaechel', 'gowin_pack']}
    dependencies = {'loader': loader, 'python': suite / 'libexec/python3.11',
                    'chipdb': suite / 'share/nextpnr/himbaechel/gowin/chipdb-GW2A-18C.bin'}
    commands = {name: prefix + [str(native[name])] for name in ['yosys', 'nextpnr-himbaechel']}
    commands['gowin_pack'] = prefix + [str(dependencies['python']), str(native['gowin_pack'])]
    return native, dependencies, commands


def build(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    working = output / 'build'
    working.mkdir()
    manifest = {'candidate': args.candidate, 'parent': args.parent,
                'measurement_flow': 'open_source_only', 'official_gowin_measurement': False,
                'status': 'in_progress', 'board_acceptance': 'pending',
                'verification_status': args.verification_status,
                'started_utc': datetime.now(timezone.utc).isoformat(),
                'part': PART, 'family': FAMILY, 'top': TOP,
                'frequency_mhz': FREQUENCY_MHZ, 'seed': 1,
                'sdc_handling': 'unchanged supplied SDC passed to nextpnr --sdc',
                'timeout_seconds': args.timeout, 'source_id': args.source_id}
    start = time.monotonic()
    commands = []
    def save():
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        (output / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    save()
    try:
        suite = args.oss_root.resolve()
        native, dependencies, tools = tool_commands(suite)
        for name, path in {**native, **dependencies}.items():
            if not path.is_file() or (name != 'chipdb' and not os.access(path, os.X_OK)):
                raise BuildError(f'Missing executable in pinned suite: {path}')
        environment = suite_environment(suite)
        manifest['environment_overrides'] = {
            'PATH_prepend': str(suite / 'bin'), 'LD_LIBRARY_PATH_prepend': str(suite / 'lib'),
            'PYTHONHOME': str(suite), 'PYTHONNOUSERSITE': '1', 'PYTHONPATH': 'removed',
            'GHDL_PREFIX': str(suite / 'lib/ghdl'), 'TCL_LIBRARY': str(suite / 'lib/tcl8.6'),
            'TK_LIBRARY': str(suite / 'lib/tk8.6'), 'LC_ALL': 'C'}
        manifest['toolchain'] = {'root': str(suite), 'identity': args.toolchain_identity,
                                'executables': {name: {'path': str(path), 'sha256': sha256(path)}
                                                for name, path in {**native, **dependencies}.items()},
                                'invocation': 'bundled loader/libexec binaries; headless, GUI wrapper omitted'}
        manifest['runner_sha256'] = sha256(Path(__file__))
        sources = {'competition.v': args.rtl, 'board.cst': args.cst, 'clock.sdc': args.sdc}
        evidence = json.loads(args.verification_evidence.read_text()) if args.verification_evidence else None
        if evidence is not None:
            if not isinstance(evidence, dict) or evidence.get('rtl_sha256') != sha256(args.rtl):
                raise BuildError('Verification evidence does not match the candidate RTL SHA-256')
            sources['verification-evidence.json'] = args.verification_evidence
            manifest['verification_evidence'] = evidence
        elif args.verification_status == 'locally_verified':
            raise BuildError('Locally verified builds require --verification-evidence tied to RTL SHA-256')
        manifest['inputs'] = {}
        for name, source in sources.items():
            shutil.copyfile(source, working / name)
            manifest['inputs'][name] = {'source': str(source.resolve()), 'sha256': sha256(working / name)}
        if evidence is not None:
            captured_evidence = json.loads((working / 'verification-evidence.json').read_text())
            if (not isinstance(captured_evidence, dict)
                    or captured_evidence != evidence
                    or evidence['rtl_sha256'] != manifest['inputs']['competition.v']['sha256']):
                raise BuildError('Verification evidence or RTL changed while inputs were captured')
        script = ('read_verilog competition.v\n'
                  f'synth_gowin -family gw2a -top {TOP}\n'
                  'check -assert\n'
                  'write_json synthesis.json\n'
                  'write_verilog -noattr synthesis.v\n'
                  'tee -o synthesis-stat.json stat -json\n')
        (working / 'synthesis.ys').write_text(script)
        manifest['synthesis_script_sha256'] = sha256(working / 'synthesis.ys')
        with build_lock(args.lock):
            probes = [('yosys-version', tools['yosys'] + ['-V']),
                      ('yosys-synth-help', tools['yosys'] + ['-Q', '-T', '-p', 'help synth_gowin']),
                      ('nextpnr-version', tools['nextpnr-himbaechel'] + ['--version']),
                      ('nextpnr-help', tools['nextpnr-himbaechel'] + ['--help']),
                      ('pack-help', tools['gowin_pack'] + ['--help'])]
            for name, argv in probes:
                remaining = min(30, args.timeout - (time.monotonic() - start))
                if remaining <= 0:
                    raise BuildError('Overall build timeout expired before ' + name)
                commands.append({'step': name, 'argv': argv, 'cwd': str(working), 'timeout_seconds': remaining})
                save()
                run_program(argv, working, environment, working / (name + '.log'), remaining)
            help_text = (working / 'yosys-synth-help.log').read_text(errors='replace')
            if '-family' not in help_text or 'gw2a' not in help_text:
                raise BuildError('Pinned Yosys does not advertise synth_gowin -family gw2a')
            manifest['toolchain']['version_logs'] = {name: sha256(working / (name + '.log')) for name, _ in probes}
            manifest['toolchain']['reported_versions'] = {
                name: (working / (name + '.log')).read_text(errors='replace').strip()
                for name in ['yosys-version', 'nextpnr-version']}
            apycula = list((suite / 'lib/python3.11/site-packages').glob('apycula-*.dist-info/METADATA'))
            if len(apycula) != 1:
                raise BuildError('Missing or ambiguous bundled Apycula version metadata')
            metadata = apycula[0].read_text()
            version = re.search(r'^Version: (.+)$', metadata, re.M)
            if not version:
                raise BuildError('Apycula version metadata malformed')
            manifest['toolchain']['reported_versions']['apycula'] = version[1]
            manifest['toolchain']['apycula_metadata_sha256'] = sha256(apycula[0])
            stages = [('synthesis', tools['yosys'] + ['-s', 'synthesis.ys']),
                      ('place-route', tools['nextpnr-himbaechel'] + ['--device', PART,
                                       '--json', 'synthesis.json', '--write', 'placed.json',
                                       '--freq', '27', '--sdc', 'clock.sdc', '--seed', '1', '--threads', '1',
                                       '--report', 'nextpnr-report.json', '--detailed-timing-report',
                                       '--vopt', 'family=' + FAMILY, '--vopt', 'cst=board.cst']),
                      ('pack', tools['gowin_pack'] + ['-d', FAMILY, '-o', 'competition.fs', 'placed.json'])]
            for name, argv in stages:
                remaining = args.timeout - (time.monotonic() - start)
                if remaining <= 0:
                    raise BuildError('Overall build timeout expired before ' + name)
                commands.append({'step': name, 'argv': argv, 'cwd': str(working), 'timeout_seconds': remaining})
                save()
                run_program(argv, working, environment, working / (name + '.log'), remaining)
            for name, identity in manifest['inputs'].items():
                if sha256(working / name) != identity['sha256']:
                    raise BuildError('Input changed during build: ' + name)
            try:
                resources = parse_outputs(working)
            except (TypeError, AttributeError) as exc:
                raise BuildError('Malformed tool output structure: ' + str(exc)) from exc
            manifest.update(status='open_source_screened', resources=resources,
                            bitstream_sha256=sha256(working / 'competition.fs'))
    except (BuildError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        manifest.update(status='invalid', error=str(exc))
    finally:
        try:
            manifest['input_verification'] = {
                name: bool((working / name).is_file() and sha256(working / name) == identity['sha256'])
                for name, identity in manifest.get('inputs', {}).items()}
            if not all(manifest['input_verification'].values()):
                manifest.update(status='invalid', error=manifest.get('error', 'Captured input hash mismatch'))
            manifest['output_hashes'] = {str(path.relative_to(working)): sha256(path)
                                         for path in working.rglob('*') if path.is_file()}
        except OSError as exc:
            manifest.update(status='invalid', collection_error=str(exc))
        if manifest['status'] == 'invalid':
            manifest.pop('resources', None)
        manifest['elapsed_seconds'] = round(time.monotonic() - start, 3)
        manifest['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save()
    print(json.dumps(manifest, indent=2))
    return 0 if manifest['status'] == 'open_source_screened' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--parent', required=True)
    parser.add_argument('--rtl', type=Path, required=True)
    parser.add_argument('--cst', type=Path, default=ROOT / 'constraints/19_tang_nano_20k.cst')
    parser.add_argument('--sdc', type=Path, default=ROOT / 'constraints/tang_nano_20k.sdc')
    parser.add_argument('--oss-root', type=Path, required=True)
    parser.add_argument('--toolchain-identity', required=True, help='Pinned OSS release plus archive SHA-256')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verification-status', required=True,
                        choices=['locally_verified', 'historical_accepted', 'unverified'])
    parser.add_argument('--verification-evidence', type=Path)
    parser.add_argument('--source-id')
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--lock', type=Path, default=Path('/tmp/gqh-open-gowin-build.lock'))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', args.candidate):
        parser.error('Invalid candidate ID')
    if not 1 <= args.timeout <= 900:
        parser.error('Timeout must be between 1 and 900 seconds')
    return build(args)


if __name__ == '__main__':
    sys.exit(main())
