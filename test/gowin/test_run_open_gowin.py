import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('run_open_gowin', ROOT / 'tools/run_open_gowin.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
FIXTURE = Path(__file__).with_name('fixtures') / 'h1-nextpnr-summary.json'


def fake_design():
    cells = {'logic': {'type': 'LUT4'}, 'history': {'type': 'DPB'}}
    ports = {}
    for bit, name in enumerate(runner.PINS):
        direction = 'input' if name in ['sys_clk', 'reset_btn', 'uart_rx_i'] else 'output'
        cell_type, pin = ('IBUF', 'I') if direction == 'input' else ('OBUF', 'O')
        ports[name] = {'direction': direction, 'bits': [bit]}
        cells[name] = {'type': cell_type, 'connections': {pin: [bit]},
                       'attributes': {'NEXTPNR_BEL': 'X0Y0/IOB' + str(bit)}}
    return {'ports': ports, 'cells': cells}


class ParserTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='open gowin with spaces ')
        self.directory = Path(self.temp.name)
        (self.directory / 'synthesis.json').write_text(json.dumps({'modules': {runner.TOP: fake_design()}}))
        (self.directory / 'placed.json').write_text(json.dumps({'modules': {'top': fake_design()}}))
        (self.directory / 'nextpnr-report.json').write_text(FIXTURE.read_text())
        (self.directory / 'competition.fs').write_bytes(b'real fixture placeholder')
        (self.directory / 'board.cst').write_text((ROOT / 'constraints/19_tang_nano_20k.cst').read_text())

    def tearDown(self):
        self.temp.cleanup()

    def mutate_report(self, callback):
        path = self.directory / 'nextpnr-report.json'
        report = json.loads(path.read_text())
        callback(report)
        path.write_text(json.dumps(report))

    def test_real_h1_utilization_stays_open_source_only(self):
        resources = runner.parse_outputs(self.directory)
        self.assertEqual(resources['nextpnr_utilization']['LUT4']['used'], 599)
        self.assertEqual(resources['nextpnr_utilization']['ALU']['used'], 162)
        self.assertEqual(resources['nextpnr_utilization']['DFF']['used'], 375)
        self.assertEqual(resources['nextpnr_utilization']['BSRAM']['used'], 1)
        self.assertIsNone(resources['official_gowin_logic'])
        self.assertEqual(len(resources['constrained_port_bindings']), 6)
        self.assertTrue(resources['meets_reported_clock_constraints'])

    def test_missing_report_is_error(self):
        (self.directory / 'nextpnr-report.json').unlink()
        with self.assertRaisesRegex(runner.BuildError, 'Missing'):
            runner.parse_outputs(self.directory)

    def test_malformed_utilization_is_error(self):
        self.mutate_report(lambda r: r['utilization']['LUT4'].update(used='599'))
        with self.assertRaisesRegex(runner.BuildError, 'utilization'):
            runner.parse_outputs(self.directory)

    def test_missing_individual_resource_is_error(self):
        self.mutate_report(lambda r: r['utilization'].pop('ALU'))
        with self.assertRaisesRegex(runner.BuildError, 'Missing required'):
            runner.parse_outputs(self.directory)

    def test_nonfinite_timing_is_error(self):
        self.mutate_report(lambda r: r['fmax']['controller.clock'].update(achieved=float('nan')))
        with self.assertRaisesRegex(runner.BuildError, 'nonfinite'):
            runner.parse_outputs(self.directory)

    def test_wrong_clock_is_error(self):
        self.mutate_report(lambda r: r['fmax']['controller.clock'].update(constraint=270))
        with self.assertRaisesRegex(runner.BuildError, '27 MHz'):
            runner.parse_outputs(self.directory)

    def test_timing_failure_is_reported_without_claiming_pass(self):
        self.mutate_report(lambda r: r['fmax']['controller.clock'].update(achieved=20))
        resources = runner.parse_outputs(self.directory)
        self.assertFalse(resources['meets_reported_clock_constraints'])

    def test_empty_bitstream_is_error(self):
        (self.directory / 'competition.fs').write_bytes(b'')
        with self.assertRaisesRegex(runner.BuildError, 'bitstream'):
            runner.parse_outputs(self.directory)

    def test_changed_board_pin_is_error(self):
        cst = self.directory / 'board.cst'
        cst.write_text(cst.read_text().replace('"sys_clk" 4', '"sys_clk" 5'))
        with self.assertRaisesRegex(runner.BuildError, 'board pins'):
            runner.parse_outputs(self.directory)

    def test_missing_placed_pin_binding_is_error(self):
        path = self.directory / 'placed.json'
        placed = json.loads(path.read_text())
        placed['modules']['top']['cells']['uart_tx_o']['attributes'].pop('NEXTPNR_BEL')
        path.write_text(json.dumps(placed))
        with self.assertRaisesRegex(runner.BuildError, 'port buffer BEL'):
            runner.parse_outputs(self.directory)

    def test_null_port_bits_are_a_parser_error(self):
        path = self.directory / 'placed.json'
        placed = json.loads(path.read_text())
        placed['modules']['top']['ports']['sys_clk']['bits'] = None
        path.write_text(json.dumps(placed))
        with self.assertRaisesRegex(runner.BuildError, 'Malformed competition port'):
            runner.parse_outputs(self.directory)

    def test_null_cell_connections_are_a_parser_error(self):
        path = self.directory / 'placed.json'
        placed = json.loads(path.read_text())
        placed['modules']['top']['cells']['uart_tx_o']['connections'] = None
        path.write_text(json.dumps(placed))
        with self.assertRaisesRegex(runner.BuildError, 'connections or attributes'):
            runner.parse_outputs(self.directory)

    def test_null_cell_attributes_are_a_parser_error(self):
        path = self.directory / 'placed.json'
        placed = json.loads(path.read_text())
        placed['modules']['top']['cells']['uart_tx_o']['attributes'] = None
        path.write_text(json.dumps(placed))
        with self.assertRaisesRegex(runner.BuildError, 'connections or attributes'):
            runner.parse_outputs(self.directory)

    def test_temporary_blockers_cannot_count_as_final_report(self):
        path = self.directory / 'placed.json'
        placed = json.loads(path.read_text())
        placed['modules']['top']['cells']['temporary'] = {'type': 'BLOCKER_LUT'}
        path.write_text(json.dumps(placed))
        with self.assertRaisesRegex(runner.BuildError, 'temporary blocker'):
            runner.parse_outputs(self.directory)


class ProcessTests(unittest.TestCase):
    def test_process_timeout_terminates_only_its_group(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            process = Mock(pid=4321)
            process.wait.side_effect = [subprocess.TimeoutExpired(['tool'], 1), 0]
            with patch.object(runner.subprocess, 'Popen', return_value=process), \
                 patch.object(runner.os, 'killpg') as kill:
                with self.assertRaisesRegex(runner.BuildError, 'exceeded'):
                    runner.run_program(['tool'], directory, {}, directory / 'log', 1)
            kill.assert_called_once_with(4321, signal.SIGTERM)

    def test_tool_failure_is_error(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            with self.assertRaisesRegex(runner.BuildError, 'exit status 3'):
                runner.run_program([sys.executable, '-c', 'raise SystemExit(3)'],
                                   directory, os.environ.copy(), directory / 'log', 5)

    def test_paths_with_spaces_are_argv_not_shell(self):
        with tempfile.TemporaryDirectory(prefix='open gowin spaces ') as temp:
            directory = Path(temp)
            runner.run_program([sys.executable, '-c', 'import sys; print(sys.argv[1])', str(directory)],
                               directory, os.environ.copy(), directory / 'log', 5)
            self.assertEqual((directory / 'log').read_text().strip(), str(directory))

    def test_no_gui_wrapper_or_home_override(self):
        suite = Path('/suite with spaces')
        _, _, commands = runner.tool_commands(suite)
        self.assertIn(str(suite / 'libexec/nextpnr-himbaechel'), commands['nextpnr-himbaechel'])
        self.assertNotIn(str(suite / 'bin/nextpnr-himbaechel'), commands['nextpnr-himbaechel'])
        self.assertEqual(runner.suite_environment(suite).get('HOME'), os.environ.get('HOME'))

    def test_python_import_path_is_isolated(self):
        with patch.dict(os.environ, {'PYTHONPATH': '/unrelated/pytest/packages'}):
            self.assertNotIn('PYTHONPATH', runner.suite_environment(Path('/suite')))


class ManifestTests(unittest.TestCase):
    def make_args(self, directory):
        suite = directory / 'suite'
        native, dependencies, _ = runner.tool_commands(suite)
        for path in [*native.values(), *dependencies.values()]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'fake tool or database')
            path.chmod(0o755)
        metadata = suite / 'lib/python3.11/site-packages/apycula-0.34.dist-info/METADATA'
        metadata.parent.mkdir(parents=True)
        metadata.write_text('Name: Apycula\nVersion: 0.34\n')
        rtl = directory / 'candidate.v'
        rtl.write_text('module gqh_competition_top; endmodule\n')
        return SimpleNamespace(output=directory / 'evidence', candidate='candidate', parent='H1',
                               verification_status='historical_accepted', verification_evidence=None,
                               source_id='test', timeout=10, oss_root=suite,
                               toolchain_identity='test-fixture', rtl=rtl,
                               cst=ROOT / 'constraints/19_tang_nano_20k.cst',
                               sdc=ROOT / 'constraints/tang_nano_20k.sdc', lock=directory / 'lock')

    def test_failed_tool_preserves_inputs_and_no_resource_measurement(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(Path(temp))
            with patch.object(runner, 'run_program', side_effect=runner.BuildError('tool failure')), \
                 patch('builtins.print'):
                self.assertEqual(runner.build(args), 1)
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertEqual(manifest['status'], 'invalid')
            self.assertEqual(manifest['error'], 'tool failure')
            self.assertNotIn('resources', manifest)
            self.assertTrue(all(manifest['input_verification'].values()))
            self.assertEqual(runner.sha256(args.output / 'build/competition.v'), runner.sha256(args.rtl))

    def test_mismatched_verification_evidence_is_rejected_before_tools(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(Path(temp))
            args.verification_status = 'locally_verified'
            args.verification_evidence = Path(temp) / 'verification.json'
            args.verification_evidence.write_text(json.dumps({'rtl_sha256': 'different'}))
            with patch.object(runner, 'run_program') as run, patch('builtins.print'):
                self.assertEqual(runner.build(args), 1)
            run.assert_not_called()
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertIn('does not match', manifest['error'])

    def test_changed_input_is_retained_after_failed_tool(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(Path(temp))
            def fail(argv, cwd, environment, log, timeout):
                (cwd / 'competition.v').write_bytes(b'changed')
                raise runner.BuildError('tool failure')
            with patch.object(runner, 'run_program', side_effect=fail), patch('builtins.print'):
                self.assertEqual(runner.build(args), 1)
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertFalse(manifest['input_verification']['competition.v'])
            self.assertEqual(manifest['status'], 'invalid')

    def test_unexpected_parser_type_error_finalizes_invalid_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(Path(temp))
            def fake_run(argv, cwd, environment, log, timeout):
                log.write_text('-family gw2a\n')
            with patch.object(runner, 'run_program', side_effect=fake_run), \
                 patch.object(runner, 'parse_outputs', side_effect=TypeError('bad port shape')), \
                 patch('builtins.print'):
                self.assertEqual(runner.build(args), 1)
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertEqual(manifest['status'], 'invalid')
            self.assertIn('Malformed tool output structure', manifest['error'])
            self.assertNotIn('resources', manifest)
            self.assertIn('finished_utc', manifest)


if __name__ == '__main__':
    unittest.main()
