"""Board-free checks that failures cannot become a green validation summary."""
import csv
import json
from pathlib import Path
import tempfile
import unittest

import validate_board as board


class ValidationChecks(unittest.TestCase):
    def write_csv(self, folder, mutate=lambda rows: None):
        model = board.ReferenceModel()
        rows = []
        action_names = {v: k for k, v in board.ACTIONS.items()}
        for index in range(100):
            a, b = (65535, 0) if index % 2 else (0, 65535)
            req = board.encode_request(index, board.ITEM_A, a, board.ITEM_B, b)
            rsp = model.respond(req)
            rows.append({'index': index, 'status': 'IGNORED_WARMUP' if index < 16 else 'CORRECT',
                         'tx_item1': '0x11', 'tx_item2': '0x22', 'tx_price1': a, 'tx_price2': b,
                         'rx_index': index, 'rx_item1': '0x11', 'rx_item2': '0x22',
                         'rx_action1': action_names[rsp[3]], 'rx_action2': action_names[rsp[5]],
                         'rx_reserved': '0x0000', 'latency_us': '16000'})
        keys = list(rows[0])
        mutate(rows)
        with (folder / 'trade_results_100.csv').open('w', newline='') as target:
            writer = csv.DictWriter(target, fieldnames=keys)
            writer.writeheader(); writer.writerows(rows)

    def test_full_good_csv(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as tmp:
            folder = Path(tmp)
            self.write_csv(folder)
            result = board.check_robust(folder)
            self.assertEqual(result['received'], 100)
            self.assertEqual(result['mean_ms'], 16)
            self.assertTrue(result['within_latency_limit'])

    def test_bad_warmup_scored_timeout_reserved_and_missing_rows(self):
        corruptions = [lambda r: r[0].update(rx_action1='BUY'),
                       lambda r: r[20].update(rx_action1='NONE'),
                       lambda r: r[99].update(status='TIMEOUT'),
                       lambda r: r[8].update(rx_reserved='0x0001'),
                       lambda r: r.pop()]
        for corrupt in corruptions:
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory(dir='/tmp/opencode') as tmp:
                folder = Path(tmp)
                self.write_csv(folder, corrupt)
                with self.assertRaises(RuntimeError):
                    board.check_robust(folder)

    def test_slow_functionally_correct_run_is_not_qualified(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as tmp:
            folder = Path(tmp)
            self.write_csv(folder, lambda rows: [r.update(latency_us='30000') for r in rows])
            self.assertFalse(board.check_robust(folder)['within_latency_limit'])

    def test_fixture_sessions_and_extremes(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as tmp:
            path = Path(tmp) / 'fixture.jsonl'
            result = board.make_fixture(path, 1234)
            model = board.ReferenceModel()
            rows = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(rows), result['packets'])
            self.assertGreater(result['packets'], 2500)
            self.assertGreater(result['sessions'], 20)
            for row in rows:
                self.assertEqual(model.respond(bytes.fromhex(row['request_hex'])).hex(),
                                 row['expected_response_hex'])


if __name__ == '__main__':
    unittest.main()
