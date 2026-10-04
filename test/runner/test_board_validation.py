"""Board-free checks for the encompassing wrapper's pass/fail decisions."""
import contextlib
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import validate_board as board


class BoardValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def robust_files(self):
        (self.folder / 'trade_summary_100.txt').write_text(
            'Packets successfully received: 100\nCorrect packets: 84\n'
            'Correct individual actions: 168/168\nTimeouts: 0\n'
            'Average successful round-trip latency: 16.800 ms\n')
        fields = ['index', 'status', 'packet_correct', 'action1_correct', 'action2_correct']
        with (self.folder / 'trade_results_100.csv').open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(dict(index=i, status='IGNORED_WARMUP' if i < 16 else 'CORRECT',
                packet_correct='' if i < 16 else 'YES', action1_correct='' if i < 16 else 'YES',
                action2_correct='' if i < 16 else 'YES') for i in range(100))

    def test_quick_requires_actual_pass_and_all_packets(self):
        text = ''.join(f'idx={i} | OK\n' for i in range(21)) + 'PASS\n'
        self.assertEqual(board.check_quick(text)['received'], 21)
        for bad in [text.replace('PASS', '1 MISMATCH(ES)'), 'PASS\n',
                    text.replace('idx=16 | OK', 'idx=16 | MISMATCH')]:
            with self.assertRaises(RuntimeError):
                board.check_quick(bad)

    def test_official_summary_and_csv_must_both_pass(self):
        self.robust_files()
        self.assertEqual(board.check_robust(self.folder)['correct_actions'], 168)
        p = self.folder / 'trade_results_100.csv'
        p.write_text(p.read_text().replace('CORRECT', 'WRONG_ACTION1', 1))
        with self.assertRaises(RuntimeError):
            board.check_robust(self.folder)

    def test_zero_exit_summary_cannot_hide_timeouts_or_wrong_counts(self):
        for original, replacement in [('Timeouts: 0', 'Timeouts: 1'),
                                      ('Correct packets: 84', 'Correct packets: 83'),
                                      ('received: 100', 'received: 99'),
                                      ('actions: 168/168', 'actions: 167/168')]:
            self.robust_files()
            p = self.folder / 'trade_summary_100.txt'
            p.write_text(p.read_text().replace(original, replacement))
            with self.assertRaises(RuntimeError):
                board.check_robust(self.folder)

    def test_normal_latency_limit_is_checked(self):
        self.robust_files()
        p = self.folder / 'trade_summary_100.txt'
        p.write_text(p.read_text().replace('16.800', '20.900'))
        with self.assertRaises(RuntimeError):
            board.check_robust(self.folder)

    def test_preparation_changes_only_port_and_preserves_line_endings(self):
        fixture, planned = board.prepare(self.folder, 'COM42')
        self.assertEqual(planned, 1598)
        for stage, source in [('quick', ROOT / 'tools/official/21_quick_uart_test.py'),
                              ('normal', ROOT / 'tools/official/22_robust_uart_test.py'),
                              ('fullrange', ROOT / 'tools/22_robust_uart_test_fullrange.py')]:
            original = source.read_bytes()
            patched = (self.folder / stage / source.name).read_bytes()
            normalize = lambda b: board.re.sub(rb'^PORT[^\S\r\n]*=[^\r\n]*', b'PORT', b, flags=board.re.M)
            self.assertEqual(normalize(original), normalize(patched))
        self.assertTrue(fixture.is_file())
        coverage = json.loads((self.folder / 'coverage.json').read_text())
        self.assertEqual(coverage['sessions'], 25)

    def test_generated_fixture_passes_existing_fake_runner_and_fault_fails(self):
        fixture, planned = board.make_fixture(self.folder)
        command = [sys.executable, str(ROOT / 'test/runner/replay.py'), str(fixture), '--fake']
        good = self.folder / 'good'
        result = subprocess.run(command + ['--out-dir', str(good)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(board.check_custom(good, planned)['received'], 1598)
        bad = self.folder / 'bad'
        result = subprocess.run(command + ['--inject', 'wrong_action@16', '--out-dir', str(bad)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        with self.assertRaises(RuntimeError):
            board.check_custom(bad, planned)

    def test_full_sequence_has_no_prompt_between_normal_and_fullrange(self):
        events = []
        def confirm(message):
            events.append('prompt')
        def run(command, folder):
            events.append(folder.name)
            return 'console'
        with mock.patch.object(board, 'confirm', side_effect=confirm), \
             mock.patch.object(board, 'uart_check', side_effect=lambda *a, **kw: events.append('uart') or {}), \
             mock.patch.object(board, 'run_logged', side_effect=run), \
             mock.patch.object(board, 'check_quick', return_value={}), \
             mock.patch.object(board, 'check_robust', return_value={}), \
             mock.patch.object(board, 'check_custom', return_value={}), \
             contextlib.redirect_stdout(io.StringIO()):
            code = board.main(['--results-root', str(self.folder)])
        self.assertEqual(code, 0)
        i = events.index('normal')
        self.assertEqual(events[i:i+3], ['normal', 'fullrange', 'custom'])
        [run] = self.folder.iterdir()
        summary = json.loads((run / 'summary.json').read_text())
        self.assertTrue(summary['pass_all'])
        self.assertEqual(list(summary['stages']),
                         ['startup', 'quick', 'normal', 'fullrange', 'custom',
                          'custom-after-reset', 'fault-reset'])

    def test_failed_quick_stops_the_suite_and_saves_failure(self):
        with mock.patch.object(board, 'confirm'), \
             mock.patch.object(board, 'uart_check', return_value={}), \
             mock.patch.object(board, 'run_logged', return_value='No PASS'), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = board.main(['--results-root', str(self.folder)])
        self.assertEqual(code, 1)
        [run] = self.folder.iterdir()
        summary = json.loads((run / 'summary.json').read_text())
        self.assertFalse(summary['pass_all'])
        self.assertEqual(list(summary['stages']), ['startup'])
        self.assertIn('Quick did not print PASS', summary['error'])

    def test_unsolicited_bytes_fail_custom_summary(self):
        summary = dict(planned=1, sent=1, counts=dict(OK=1, MISMATCH=0, SHORT=0, TIMEOUT=0),
                       aborted=None, unsolicited_byte_events=1, trailing_unsolicited_hex='', latency={})
        (self.folder / 'fake.summary.json').write_text(json.dumps(summary))
        with self.assertRaises(RuntimeError):
            board.check_custom(self.folder, 1)


if __name__ == '__main__':
    unittest.main()
