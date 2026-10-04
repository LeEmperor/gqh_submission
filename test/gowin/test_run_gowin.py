"""Auditable report extraction and runner failure tests; no vendor process starts."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('run_gowin', ROOT / 'tools/run_gowin.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
ARCHIVE = Path(__file__).resolve().parent / 'fixtures/vendor-g2'


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gowin test with spaces ')
        self.directory = Path(self.temp.name)
        for subdir, pattern in [('impl/pnr', '*.rpt.txt'), ('impl/pnr', '*_tr_content.html'),
                                ('impl/gwsynthesis', '*_syn.rpt.html'), ('impl/pnr', '*.log')]:
            target = self.directory / subdir
            target.mkdir(parents=True, exist_ok=True)
            for source in (ARCHIVE / subdir).glob(pattern):
                shutil.copyfile(source, target / source.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_archived_counts_include_summary_luts_and_actual_total_logic(self):
        result = runner.parse_reports(self.directory)
        self.assertEqual((result['logic'], result['registers'], result['synthesis_luts']),
                         (475, 379, 351))
        self.assertEqual((result['bsram'], result['ssram']), (0, 8))
        self.assertEqual(result['worst_setup_slack_ns'], 24.535)
        self.assertEqual(result['warning_codes'], ['PR1014'])

    def test_missing_report_is_error(self):
        next(self.directory.glob('impl/pnr/*.rpt.txt')).unlink()
        with self.assertRaises(runner.BuildError):
            runner.parse_reports(self.directory)

    def test_malformed_count_is_error(self):
        report = next(self.directory.glob('impl/pnr/*.rpt.txt'))
        report.write_text(report.read_text().replace('475/20736', 'bad/20736'))
        with self.assertRaisesRegex(runner.BuildError, 'Logic'):
            runner.parse_reports(self.directory)

    def test_duplicate_report_is_error(self):
        report = next(self.directory.glob('impl/pnr/*.rpt.txt'))
        shutil.copyfile(report, report.with_name('stale.rpt.txt'))
        with self.assertRaises(runner.BuildError):
            runner.parse_reports(self.directory)

    def test_missing_timing_count_is_error(self):
        report = next(self.directory.glob('impl/pnr/*_tr_content.html'))
        report.write_text(report.read_text().replace('Numbers of Hold Violated Endpoints', 'absent'))
        with self.assertRaisesRegex(runner.BuildError, 'Hold'):
            runner.parse_reports(self.directory)

    def test_malformed_memory_count_is_error(self):
        report = next(self.directory.glob('impl/pnr/*.rpt.txt'))
        report.write_text(report.read_text().replace('--SSRAM(RAM16)            | 8',
                                                   '--SSRAM(RAM16)            | bad'))
        with self.assertRaises(runner.BuildError):
            runner.parse_reports(self.directory)

    def test_nonfinite_timing_is_error(self):
        report = next(self.directory.glob('impl/pnr/*_tr_content.html'))
        report.write_text(report.read_text().replace('<td>24.535</td>', '<td>nan</td>'))
        with self.assertRaisesRegex(runner.BuildError, 'malformed'):
            runner.parse_reports(self.directory)


class ExecutionTests(unittest.TestCase):
    def test_timeout_kills_only_started_process_tree(self):
        with tempfile.TemporaryDirectory(prefix='gowin spaces ') as temp:
            stage = Path(temp)
            with patch.object(runner, 'windows_path', side_effect=lambda p: 'C:/folder with spaces/' + Path(p).name), \
                 patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 124, b'timeout')):
                with self.assertRaisesRegex(runner.BuildError, 'process tree'):
                    runner.execute_job(Path('gw_sh.exe'), stage, 1, stage / 'commands.json')
            command = json.loads((stage / 'commands.json').read_text())['powershell']
            self.assertIn('taskkill.exe /PID $job.Id /T /F', command)
            self.assertNotIn('/IM', command)
            self.assertIn("'C:/folder with spaces/gw_sh.exe'", command)
            argv = json.loads((stage / 'commands.json').read_text())['argv']
            self.assertIn('-File', argv)
            self.assertNotIn('-EncodedCommand', argv)
            self.assertNotIn('-ExecutionPolicy', argv)

    def test_failed_tool_is_error(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = Path(temp)
            with patch.object(runner, 'windows_path', return_value='C:/temp'), \
                 patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, b'license error')):
                with self.assertRaisesRegex(runner.BuildError, 'exit status 1'):
                    runner.execute_job(Path('tool'), stage, 900, stage / 'commands.json')
            self.assertEqual((stage / 'launcher.log').read_bytes(), b'license error')

    def test_missing_native_exit_status_is_error(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = Path(temp)
            with patch.object(runner, 'windows_path', return_value='C:/temp'), \
                 patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'')):
                with self.assertRaisesRegex(runner.BuildError, 'numeric zero'):
                    runner.execute_job(Path('tool'), stage, 900, stage / 'commands.json')

    def test_recorded_success_cannot_hide_missing_tool(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = Path(temp)
            (stage / 'job-status.txt').write_text('0')
            with patch.object(runner, 'windows_path', return_value='C:/temp'), \
                 patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'')):
                with self.assertRaisesRegex(runner.BuildError, 'disappeared'):
                    runner.execute_job(stage / 'absent.exe', stage, 900, stage / 'commands.json')

    def test_outer_watchdog_uses_recorded_pid_only(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = Path(temp)
            (stage / 'windows-job.json').write_text(json.dumps(
                {'pid': 1234, 'start_ticks': '9876', 'executable': 'C:/gw_sh.exe'}))
            with patch.object(runner, 'windows_path', return_value='C:/gw_sh.exe'), \
                 patch.object(runner.subprocess, 'run', side_effect=[
                     subprocess.TimeoutExpired(['powershell'], 31, output=b'hung'),
                     subprocess.CompletedProcess([], 0, b'killed')]) as call:
                with self.assertRaisesRegex(runner.BuildError, 'watchdog'):
                    runner.execute_job(Path('tool'), stage, 1, stage / 'commands.json')
            cleanup = call.call_args_list[1].args[0][-1]
            self.assertIn('/PID 1234 /T /F', cleanup)
            self.assertIn('StartTime.ToUniversalTime().Ticks', cleanup)
            self.assertIn('$recordedJob.Path', cleanup)
            self.assertEqual((stage / 'launcher.log').read_bytes(), b'hung')

    def test_cleanup_refuses_a_different_executable_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = Path(temp)
            (stage / 'windows-job.json').write_text(json.dumps(
                {'pid': 1234, 'start_ticks': '9876', 'executable': 'C:/unrelated.exe'}))
            with patch.object(runner, 'windows_path', return_value='C:/gw_sh.exe'), \
                 patch.object(runner.subprocess, 'run') as call:
                runner.cleanup_recorded_job(Path('gw_sh.exe'), stage)
            call.assert_not_called()
            self.assertIn('no process killed', (stage / 'watchdog-cleanup.log').read_text())

    def test_lock_prevents_concurrent_job(self):
        with tempfile.TemporaryDirectory() as temp:
            lock = Path(temp) / 'lock'
            with runner.build_lock(lock):
                with self.assertRaisesRegex(runner.BuildError, 'Another Gowin'):
                    with runner.build_lock(lock):
                        self.fail('Concurrent job acquired the lock')

    def test_tcl_quoting_protects_substitutions_and_spaces(self):
        value = 'C:/folder with spaces/$x[exec nope]"\\line'
        self.assertEqual(runner.tcl_quote(value),
                         '"C:/folder with spaces/\\$x\\[exec nope\\]\\"\\\\line"')


class ManifestTests(unittest.TestCase):
    def check_failed_build(self, mutate_input=False, copy_failure=False):
        with tempfile.TemporaryDirectory(prefix='gowin failure spaces ') as temp:
            directory = Path(temp)
            tool = directory / 'tool.exe'
            tool.write_bytes(b'fake tool')
            args = SimpleNamespace(
                output=directory / 'failed evidence', candidate='failure', parent='baseline',
                verification_status='historical_accepted', verification_evidence=None,
                timeout=1, tool=tool, settings=ROOT / 'gowin/competition-options.json',
                tcl=ROOT / 'gowin/competition.tcl', rtl=ROOT / 'rtl/gqh_competition_top.v',
                cst=ROOT / 'constraints/19_tang_nano_20k.cst',
                sdc=ROOT / 'constraints/tang_nano_20k.sdc', lock=directory / 'lock', source_id='test')
            def fail_job(tool, stage, timeout, command_log):
                if mutate_input:
                    (stage / 'competition.v').write_bytes(b'mutated input')
                raise runner.BuildError('vendor failure')
            original_copytree = runner.shutil.copytree
            def collect(*args, **kwargs):
                if copy_failure:
                    raise PermissionError('collection denied')
                return original_copytree(*args, **kwargs)
            with patch.object(runner, 'local_path', return_value=directory / 'windows temp'), \
                 patch.object(runner, 'windows_path', side_effect=lambda p: 'C:/' + Path(p).name), \
                 patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'C:/temp')), \
                 patch.object(runner, 'execute_job', side_effect=fail_job), \
                 patch.object(runner.shutil, 'copytree', side_effect=collect), \
                 patch('builtins.print'):
                result = runner.build(args)
            self.assertEqual(result, 1)
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertEqual(manifest['status'], 'invalid')
            self.assertEqual(manifest['error'], 'vendor failure')
            self.assertNotIn('resources', manifest)
            self.assertEqual(manifest['staged_input_verification']['competition.v'], not mutate_input)
            if copy_failure:
                self.assertEqual(manifest['collection_error'], 'collection denied')
            elif not mutate_input:
                self.assertEqual(runner.digest(args.output / 'build/competition.v'), runner.digest(args.rtl))
            self.assertIn('finished_utc', manifest)

    def test_failed_build_preserves_inputs_and_has_no_measurement(self):
        self.check_failed_build()

    def test_collection_failure_finalizes_invalid_manifest(self):
        self.check_failed_build(copy_failure=True)

    def test_changed_inputs_are_recorded_even_after_failure(self):
        self.check_failed_build(mutate_input=True)

    def test_verification_evidence_rejects_different_rtl(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            evidence = directory / 'verification.json'
            evidence.write_text(json.dumps({'rtl_sha256': 'wrong'}))
            args = SimpleNamespace(
                output=directory / 'evidence', candidate='bad-proof', parent='baseline',
                verification_status='locally_verified', verification_evidence=evidence,
                timeout=1, tool=directory / 'tool', settings=ROOT / 'gowin/competition-options.json',
                rtl=ROOT / 'rtl/gqh_competition_top.v', cst=Path('unused'), sdc=Path('unused'),
                tcl=Path('unused'))
            with patch('builtins.print'):
                self.assertEqual(runner.build(args), 1)
            manifest = json.loads((args.output / 'manifest.json').read_text())
            self.assertIn('not tied', manifest['error'])


if __name__ == '__main__':
    unittest.main()
