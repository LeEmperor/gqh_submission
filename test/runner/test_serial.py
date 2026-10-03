"""SerialTransport through pyserial's built-in loop:// port (echoes whatever is written).

No board needed: this exercises the real pyserial calls the board run will make.
"""
import csv
import json
import time
from pathlib import Path

import pytest

pytest.importorskip("serial")

from replay import main  # noqa: E402
from transport import SerialTransport  # noqa: E402

EXAMPLE = Path(__file__).resolve().parent / "examples" / "quick_test_vectors.json"
REQ = bytes.fromhex("001022003c110050")


@pytest.fixture
def loop():
    t = SerialTransport("loop://", 115200, timeout_s=1.0, settle_s=0)
    yield t
    t.close()


def test_bytes_written_come_back_through_read(loop):
    loop.write(REQ)

    assert loop.read(8, 1.0) == REQ


def test_read_gives_up_with_nothing_after_its_timeout(loop):
    t0 = time.monotonic()

    assert loop.read(8, 0.05) == b""
    assert 0.04 <= time.monotonic() - t0 < 0.5


def test_drain_returns_buffered_bytes_without_waiting(loop):
    loop.write(b"\xaa\xbb")
    time.sleep(0.01)

    assert loop.drain() == b"\xaa\xbb"
    assert loop.drain() == b""


def test_full_cli_run_over_pyserial(tmp_path):
    # loop:// echoes the request, which can never equal a valid response -> all MISMATCH.
    code = main([str(EXAMPLE), "--port", "loop://", "--out-dir", str(tmp_path)])

    [csv_path] = tmp_path.glob("*.csv")
    [summary_path] = tmp_path.glob("*.summary.json")
    rows = list(csv.DictReader(csv_path.open()))
    summary = json.loads(summary_path.read_text())
    assert code == 1
    assert {r["status"] for r in rows} == {"MISMATCH"}
    assert rows[0]["response_hex"] == rows[0]["request_hex"]
    assert summary["transport"] == {"kind": "serial", "port": "loop://", "baud": 115200}
    assert summary["latency"]["count"] == 21


# The next two look at the pyserial object's configured timeout directly: that setting
# is the behavior under test and has no other observable effect without a board.

def test_tiny_read_budget_is_clamped_to_one_millisecond(loop):
    # On Windows pyserial turns a sub-ms timeout into 0 ms = "no timeout", and ReadFile blocks forever.
    loop.read(8, 0.0001)

    assert loop._serial.timeout >= 0.001


def test_drain_restores_the_full_timeout_before_the_next_timed_send(loop):
    loop.read(8, 0.05)

    loop.drain()

    assert loop._serial.timeout == 1.0
