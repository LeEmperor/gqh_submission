"""Independent checks for the reproducible GQH fixture factory.

Run: python3 -m unittest discover -s tools/test_data_factory -v
"""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import random
import struct
import tempfile
import unittest

import factory
import check_ocaml
from model import ReferenceModel, decode_request, encode_request


SCENARIOS = (
    "constant", "constant_swapped", "rising_falling", "crossings",
    "boundaries", "random", "repeated_sessions",
)


def independent_answers(requests):
    """Use complete price histories, with no rolling window state or model calls."""
    history = {17: [], 34: []}
    held = {17: 0, 34: 0}
    for raw in requests:
        index, item1, price1, item2, price2 = struct.unpack(">HBHBH", raw)
        if index == 0:
            history = {17: [], 34: []}
            held = {17: 0, 34: 0}
        for item, price in ((item1, price1), (item2, price2)):
            prior = history[item]
            combined = prior + [price]
            if len(prior) >= 16:
                before = sum(prior[-16:]) // 16
                after = sum(combined[-16:]) // 16
                if prior[-1] <= before and price > after:
                    held[item] = 2
                elif prior[-1] >= before and price < after:
                    held[item] = 1
            history[item] = combined
        yield struct.pack(">HBBBBH", index, item1, held[item1], item2, held[item2], 0)


def records(directory):
    return [json.loads(line) for line in (directory / "fixture.jsonl").read_text().splitlines()]


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes()
            for p in directory.rglob("*") if p.is_file()}


class ProtocolAndModelTests(unittest.TestCase):
    def test_hand_checked_big_endian_bytes(self):
        self.assertEqual(encode_request(0, 17, 100, 34, 200).hex(), "00001100642200c8")
        self.assertEqual(encode_request(0x1234, 34, 65535, 17, 0).hex(), "123422ffff110000")
        self.assertEqual(decode_request(bytes.fromhex("123422ffff110000")),
                         (0x1234, 34, 65535, 17, 0))

    def test_constant_and_swapped_answers(self):
        model = ReferenceModel()
        for index in range(100):
            if index % 2:
                request = encode_request(index, 34, 200, 17, 100)
                expected = index.to_bytes(2, "big") + bytes.fromhex("220011000000")
            else:
                request = encode_request(index, 17, 100, 34, 200)
                expected = index.to_bytes(2, "big") + bytes.fromhex("110022000000")
            self.assertEqual(model.respond(request), expected)

    def test_hand_checked_crossings_and_held_actions(self):
        model = ReferenceModel()
        for index in range(16):
            self.assertEqual(model.respond(encode_request(index, 17, 100, 34, 200)),
                             index.to_bytes(2, "big") + bytes.fromhex("110022000000"))
        cases = (
            (16, 102, 198, "0010110222010000"),
            (17, 103, 197, "0011110222010000"),
            (18, 99, 201, "0012110122020000"),
            (19, 98, 202, "0013110122020000"),
        )
        for index, a, b, expected in cases:
            self.assertEqual(model.respond(encode_request(index, 17, a, 34, b)).hex(), expected)

    def test_floor_average_equal_is_not_a_crossing(self):
        for final, action in ((99, 0), (98, 1)):
            model = ReferenceModel()
            for index in range(16):
                model.respond(encode_request(index, 17, 100, 34, 200))
            self.assertEqual(model.respond(encode_request(16, 17, final, 34, 200))[3], action)

    def test_session_zero_resets_prices_and_actions(self):
        model = ReferenceModel()
        for index in range(16):
            model.respond(encode_request(index, 17, 100, 34, 200))
        self.assertEqual(model.respond(encode_request(16, 17, 102, 34, 198))[3:6],
                         bytes((2, 34, 1)))
        for index in range(16):
            self.assertEqual(model.respond(encode_request(index, 34, 65535, 17, 0)),
                             index.to_bytes(2, "big") + bytes.fromhex("220011000000"))

    def test_seeded_random_against_complete_history_oracle(self):
        rng = random.Random(20261002)
        request_bytes = []
        for session in range(2):
            for index in range(1000):
                a, b = rng.randrange(65536), rng.randrange(65536)
                slots = (17, a, 34, b) if index % 2 == 0 else (34, b, 17, a)
                request_bytes.append(struct.pack(">HBHBH", index, *slots))
        model = ReferenceModel()
        for request, expected in zip(request_bytes, independent_answers(request_bytes)):
            self.assertEqual(model.respond(request), expected)

    def test_rejects_invalid_fields_and_requests(self):
        invalid = (
            (-1, 17, 100, 34, 200), (65536, 17, 100, 34, 200),
            (0, 17, -1, 34, 200), (0, 17, 65536, 34, 200),
            (0, 17, 100, 34, -1), (0, 17, 100, 34, 65536),
            (0, 17, 100, 17, 200), (0, 0, 100, 34, 200),
        )
        for args in invalid:
            with self.subTest(args=args), self.assertRaises((ValueError, TypeError)):
                encode_request(*args)
        for raw in (b"", b"\0" * 7, b"\0" * 9,
                    bytes.fromhex("00001100641100c8"),
                    bytes.fromhex("00003300642200c8")):
            with self.subTest(raw=raw), self.assertRaises((ValueError, TypeError)):
                decode_request(raw)

    def test_model_rejects_skipped_index_without_consuming_packet(self):
        model = ReferenceModel()
        model.respond(encode_request(0, 17, 100, 34, 200))
        with self.assertRaises(ValueError):
            model.respond(encode_request(2, 17, 102, 34, 198))
        self.assertEqual(model.respond(encode_request(1, 17, 100, 34, 200)).hex(),
                         "0001110022000000")


class FactoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_same_settings_are_byte_identical(self):
        first, second = self.root / "first", self.root / "second"
        factory.generate(first, scenario="all", seed=42, packets=100)
        factory.generate(second, scenario="all", seed=42, packets=100)
        self.assertEqual(snapshot(first), snapshot(second))

    def test_all_scenarios_wire_answers_csv_and_metadata(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="all", seed=42, packets=100)
        self.assertEqual({p.name for p in output.iterdir() if p.is_dir()}, set(SCENARIOS))
        total = 0
        for scenario in SCENARIOS:
            directory = output / scenario
            rows = records(directory)
            sessions = 2 if scenario == "repeated_sessions" else 1
            self.assertEqual(len(rows), 100 * sessions)
            total += len(rows)
            metadata = json.loads((directory / "metadata.json").read_text())
            self.assertEqual(metadata["scenario"], scenario)
            self.assertEqual(metadata["seed"], 42)
            self.assertEqual(metadata["packets_per_session"], 100)
            self.assertEqual(metadata["sessions"], sessions)
            self.assertEqual(metadata["window_size"], 16)
            self.assertIn("format_version", metadata)
            self.assertIn("item_ids", metadata)
            self.assertIn("actions", metadata)
            expected = list(independent_answers([bytes.fromhex(r["request_hex"]) for r in rows]))
            for ordinal, (row, answer) in enumerate(zip(rows, expected)):
                self.assertEqual(set(row), {"session", "index", "request_hex", "expected_response_hex"})
                self.assertEqual((row["session"], row["index"]), divmod(ordinal, 100))
                self.assertEqual(len(row["request_hex"]), 16)
                self.assertEqual(len(row["expected_response_hex"]), 16)
                self.assertEqual(bytes.fromhex(row["expected_response_hex"]), answer)
            for session in range(sessions):
                filename = f"requests-session-{session}.csv"
                with (directory / filename).open(newline="") as source:
                    csv_rows = list(csv.DictReader(source))
                self.assertEqual(len(csv_rows), 100)
                self.assertIn(filename, metadata["sha256"])
                self.assertEqual(set(csv_rows[0]), {"index", "item1", "price1", "item2", "price2"})
                for row, fixture_row in zip(csv_rows, rows[session * 100:(session + 1) * 100]):
                    raw = struct.pack(">HBHBH", *(int(row[name]) for name in
                        ("index", "item1", "price1", "item2", "price2")))
                    self.assertEqual(raw.hex(), fixture_row["request_hex"])
            for filename, digest in metadata["sha256"].items():
                self.assertEqual(hashlib.sha256((directory / filename).read_bytes()).hexdigest(), digest)
            self.assertIn("fixture.jsonl", metadata["sha256"])
        self.assertEqual(total, 800)
        self.assertEqual(factory.verify(output)["records"], 800)

    def test_constant_and_alternating_fixtures_hand_checked(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="all", seed=42, packets=100)
        self.assertEqual(records(output / "constant")[0], {
            "session": 0, "index": 0,
            "request_hex": "00001100642200c8", "expected_response_hex": "0000110022000000",
        })
        self.assertEqual(records(output / "constant_swapped")[1], {
            "session": 0, "index": 1,
            "request_hex": "00012200c8110064", "expected_response_hex": "0001220011000000",
        })
        for scenario in ("constant", "constant_swapped"):
            for row in records(output / scenario):
                response = bytes.fromhex(row["expected_response_hex"])
                self.assertEqual((response[3], response[5]), (0, 0))

    def test_random_seed_changes_prices(self):
        a, b = self.root / "a", self.root / "b"
        factory.generate(a, scenario="random", seed=42, packets=100)
        factory.generate(b, scenario="random", seed=43, packets=100)
        self.assertNotEqual([r["request_hex"] for r in records(a / "random")],
                            [r["request_hex"] for r in records(b / "random")])

    def test_boundary_prices_and_reset_fixture(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="all", seed=42, packets=100)
        prices = set()
        for row in records(output / "boundaries"):
            raw = bytes.fromhex(row["request_hex"])
            decoded = struct.unpack(">HBHBH", raw)
            prices.update((decoded[2], decoded[4]))
        self.assertTrue({0, 65535}.issubset(prices))
        reset = records(output / "repeated_sessions")[100]
        self.assertEqual(reset["session"], 1)
        self.assertEqual(reset["index"], 0)
        self.assertEqual(reset["expected_response_hex"], "0000110022000000")

    def test_ramp_moves_each_item_in_both_directions(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="rising_falling", seed=42, packets=100)
        by_item = {17: [], 34: []}
        for row in records(output / "rising_falling"):
            _, item1, price1, item2, price2 = struct.unpack(">HBHBH", bytes.fromhex(row["request_hex"]))
            by_item[item1].append(price1)
            by_item[item2].append(price2)
        for item, prices in by_item.items():
            with self.subTest(item=item):
                differences = [later - earlier for earlier, later in zip(prices, prices[1:])]
                self.assertTrue(any(change > 0 for change in differences))
                self.assertTrue(any(change < 0 for change in differences))

    def test_repeated_session_clears_prior_nonzero_actions(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="repeated_sessions", seed=42, packets=100)
        rows = records(output / "repeated_sessions")
        prior_last = bytes.fromhex(rows[99]["expected_response_hex"])
        self.assertNotEqual(prior_last[3], 0)
        self.assertNotEqual(prior_last[5], 0)
        for row in rows[100:]:
            self.assertEqual(row["session"], 1)
            response = bytes.fromhex(row["expected_response_hex"])
            self.assertEqual((response[3], response[5]), (0, 0))

    def test_invalid_settings_do_not_leave_output(self):
        for number, kwargs in enumerate((
            {"scenario": "unknown"}, {"packets": 0}, {"packets": 65537},
            {"seed": "forty-two"},
        )):
            output = self.root / str(number)
            with self.assertRaises((ValueError, TypeError)):
                factory.generate(output, **kwargs)
            self.assertFalse(output.exists())

    def test_existing_output_is_preserved(self):
        output = self.root / "fixtures"
        output.mkdir()
        (output / "sentinel").write_text("keep me")
        with self.assertRaises(FileExistsError):
            factory.generate(output)
        self.assertEqual(snapshot(output), {"sentinel": b"keep me"})

    def test_verifier_catches_changed_action_even_with_updated_hash(self):
        output = self.root / "fixtures"
        factory.generate(output, scenario="constant", seed=42, packets=100)
        output = output / "constant"
        fixture = output / "fixture.jsonl"
        rows = records(output)
        rows[16]["expected_response_hex"] = "0010110222000000"
        fixture.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))
        metadata_path = output / "metadata.json"
        metadata = json.loads(metadata_path.read_text())
        metadata["sha256"]["fixture.jsonl"] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        metadata_path.write_text(json.dumps(metadata))
        with self.assertRaises(ValueError):
            factory.verify(output)


class OfflineLogCheckerTests(unittest.TestCase):
    """Exercise response failures without starting a process or serial connection."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "mock.csv"
        self.fixture = [{
            "session": 0, "index": 0,
            "request_hex": "00001100642200c8",
            "expected_response_hex": "0000110022000000",
        }]

    def tearDown(self):
        self.temp.cleanup()

    def write_log(self, response="0000110022000000", status="OK"):
        with self.path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=("index", "request_hex", "response_hex", "status"))
            writer.writeheader()
            writer.writerow({"index": 0, "request_hex": "00001100642200c8",
                             "response_hex": response, "status": status})

    def test_accepts_hand_checked_complete_response(self):
        self.write_log()
        check_ocaml.check_log(self.path, self.fixture, "hand-checked constant fixture")

    def test_rejects_wrong_action(self):
        self.write_log(response="0000110222000000")
        with self.assertRaises(check_ocaml.CheckFailure):
            check_ocaml.check_log(self.path, self.fixture, "deliberately wrong action")

    def test_rejects_seven_byte_response(self):
        self.write_log(response="00001100220000")
        with self.assertRaises(check_ocaml.CheckFailure):
            check_ocaml.check_log(self.path, self.fixture, "deliberately short response")

    def test_rejects_timeout_with_empty_response(self):
        self.write_log(response="", status="TIMEOUT")
        with self.assertRaises(check_ocaml.CheckFailure):
            check_ocaml.check_log(self.path, self.fixture, "deliberate timeout")


if __name__ == "__main__":
    unittest.main()
