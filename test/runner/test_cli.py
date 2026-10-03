import csv
import json
from pathlib import Path

import pytest

import replay
from fixture import load_fixture
from replay import main, unique_output_paths
from transport import FakeTransport, fake_replies

EXAMPLE = Path(__file__).resolve().parent / "examples" / "quick_test_vectors.json"


def run_cli(tmp_path, *extra):
    code = main([str(EXAMPLE), "--fake", "--out-dir", str(tmp_path), *extra])
    [csv_path] = tmp_path.glob("custom-runner_*.csv")
    [summary_path] = tmp_path.glob("custom-runner_*.summary.json")
    rows = list(csv.DictReader(csv_path.open()))
    return code, rows, json.loads(summary_path.read_text())


def test_example_fixture_row16_was_hand_checked():
    # Index 16, slots swapped: B 100->60 under avg 100->97 = SELL; A 50->80 over avg 50->51 = BUY.
    row16 = json.loads(EXAMPLE.read_text())["records"][16]
    assert row16["request_hex"] == "001022003c110050"
    assert row16["expected_response_hex"] == "0010220111020000"


def test_clean_fake_run_passes_and_exits_zero(tmp_path, capsys):
    code, rows, summary = run_cli(tmp_path)

    assert code == 0
    assert len(rows) == 21
    assert {r["status"] for r in rows} == {"OK"}
    assert summary["runner"] == "custom-runner"
    assert summary["counts"] == {"OK": 21, "MISMATCH": 0, "SHORT": 0, "TIMEOUT": 0}
    assert "custom-runner" in capsys.readouterr().out


def test_injected_faults_are_caught_and_exit_nonzero(tmp_path, capsys):
    code, rows, summary = run_cli(
        tmp_path,
        "--inject", "wrong_action@16", "--inject", "short@18", "--inject", "timeout@20",
    )

    assert code == 1
    assert [r["status"] for r in rows[15:]] == ["OK", "MISMATCH", "OK", "SHORT", "OK", "TIMEOUT"]
    assert summary["counts"] == {"OK": 18, "MISMATCH": 1, "SHORT": 1, "TIMEOUT": 1}
    assert summary["scored_counts"] == {"OK": 2, "MISMATCH": 1, "SHORT": 1, "TIMEOUT": 1}
    assert summary["transport"] == {
        "kind": "fake", "faults": {"16": "wrong_action", "18": "short", "20": "timeout"},
    }
    assert summary["fixture"]["metadata"]["settings"]["swapped_indices"] == [16, 19, 20]
    out = capsys.readouterr().out
    assert "MISMATCH" in out and "SHORT" in out and "TIMEOUT" in out


def test_stop_on_timeout_ends_the_run_at_the_first_failed_response(tmp_path):
    code, rows, summary = run_cli(tmp_path, "--inject", "short@18", "--stop-on-timeout")

    assert code == 1
    assert len(rows) == 19
    assert rows[-1]["status"] == "SHORT"
    assert summary["sent"] == 19
    assert summary["planned"] == 21


def test_label_goes_into_the_file_names_and_summary(tmp_path):
    main([str(EXAMPLE), "--fake", "--out-dir", str(tmp_path), "--label", "txgap 2"])

    [summary_path] = tmp_path.glob("custom-runner_quick_test_vectors_txgap-2_*.summary.json")
    assert json.loads(summary_path.read_text())["label"] == "txgap 2"


@pytest.mark.parametrize("argv", [
    [str(EXAMPLE)],                                             # neither --port nor --fake
    [str(EXAMPLE), "--fake", "--port", "COM6"],                 # both
    [str(EXAMPLE), "--port", "COM6", "--inject", "short@1"],    # faults need the fake
    [str(EXAMPLE), "--fake", "--inject", "short"],              # missing @ROW
    [str(EXAMPLE), "--fake", "--inject", "short@99"],           # row past the fixture
    [str(EXAMPLE), "--fake", "--timeout", "0"],                 # timeout must be positive
])
def test_bad_arguments_exit_with_usage_error(argv, tmp_path):
    with pytest.raises(SystemExit) as exc:
        main([*argv, "--out-dir", str(tmp_path)])
    assert exc.value.code == 2
    assert not list(tmp_path.iterdir())


def test_bad_fixture_exits_with_usage_error(tmp_path, capsys):
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps([{"index": 0, "request_hex": "00", "expected_response_hex": "00"}]))

    with pytest.raises(SystemExit) as exc:
        main([str(bad), "--fake", "--out-dir", str(tmp_path / "out")])

    assert exc.value.code == 2
    assert "row 0" in capsys.readouterr().err


def test_a_second_run_with_the_same_stem_does_not_overwrite_the_first(tmp_path):
    first_csv, first_summary = unique_output_paths(tmp_path, "custom-runner_x_20261002-120000")
    first_csv.write_text("taken")

    second_csv, second_summary = unique_output_paths(tmp_path, "custom-runner_x_20261002-120000")

    assert first_csv.name == "custom-runner_x_20261002-120000.csv"
    assert second_csv.name == "custom-runner_x_20261002-120000-2.csv"
    assert second_summary.name == "custom-runner_x_20261002-120000-2.summary.json"


@pytest.mark.parametrize("error, reason", [
    (OSError("device disconnected"), "OSError: device disconnected"),
    (KeyboardInterrupt(), "KeyboardInterrupt"),
])
def test_an_interrupted_run_still_saves_what_it_measured(tmp_path, monkeypatch, error, reason):
    records = load_fixture(EXAMPLE).records

    class Unplugged(FakeTransport):
        def write(self, data):
            if len(self.sent) == 2:
                raise error
            super().write(data)

    monkeypatch.setattr(replay, "SerialTransport", lambda *a, **k: Unplugged(fake_replies(records, {})))

    code = main([str(EXAMPLE), "--port", "board", "--out-dir", str(tmp_path)])

    [csv_path] = tmp_path.glob("*.csv")
    [summary_path] = tmp_path.glob("*.summary.json")
    summary = json.loads(summary_path.read_text())
    assert code == 1
    assert len(list(csv.DictReader(csv_path.open()))) == 2
    assert summary["sent"] == 2
    assert summary["aborted"] == reason


def test_unsolicited_byte_after_the_last_response_is_reported(tmp_path):
    code, rows, summary = run_cli(tmp_path, "--inject", "extra@20")

    assert {r["status"] for r in rows} == {"OK"}
    assert summary["trailing_unsolicited_hex"] != ""
    assert code == 1


def test_port_that_cannot_be_opened_is_a_usage_error_not_a_traceback(tmp_path, capsys):
    pytest.importorskip("serial")

    with pytest.raises(SystemExit) as exc:
        main([str(EXAMPLE), "--port", str(tmp_path / "no-such-port"), "--out-dir", str(tmp_path / "out")])

    assert exc.value.code == 2
    assert "no-such-port" in capsys.readouterr().err
    assert not (tmp_path / "out").exists()
