import csv

import pytest

from fixture import FixtureRecord
from replay import exchange, latency_stats, percentile, run, write_csv
from transport import FakeTransport, fake_replies

REQ = bytes.fromhex("001022003c110050")      # index 16, B=60 in slot 1, A=80 in slot 2
GOOD = bytes.fromhex("0010220111020000")     # B SELL, A BUY, reserved 0x0000


def rec(row_index, req=REQ, rsp=GOOD, session=0):
    return FixtureRecord(session=session, index=row_index, request=req, expected=rsp)


class FakeClock:
    def __init__(self):
        self.now = 1_000_000

    def __call__(self):
        return self.now


class ClockedFake(FakeTransport):
    """Every write costs 100 ns and every read 1000 ns of fake time."""

    def __init__(self, replies, clock):
        super().__init__(replies)
        self.clock = clock
        self.timeouts = []

    def write(self, data):
        self.clock.now += 100
        super().write(data)

    def read(self, size, timeout_s):
        self.timeouts.append(timeout_s)
        self.clock.now += 1_000
        return super().read(size, timeout_s)


# ---------------------------------------------------------------- exchange

def test_exchange_sends_request_and_returns_full_response():
    fake = FakeTransport([[GOOD]])

    response, _ = exchange(fake, REQ, timeout_s=1.0)

    assert fake.sent == [REQ]
    assert response == GOOD


def test_exchange_reassembles_a_response_that_arrives_in_pieces():
    fake = FakeTransport([[GOOD[:1], GOOD[1:3], GOOD[3:]]])

    response, _ = exchange(fake, REQ, timeout_s=1.0)

    assert response == GOOD


def test_exchange_returns_partial_bytes_when_the_rest_never_arrives():
    fake = FakeTransport([[GOOD[:5]]])

    response, _ = exchange(fake, REQ, timeout_s=1.0)

    assert response == GOOD[:5]


def test_exchange_never_reads_past_the_eighth_byte():
    fake = FakeTransport([[GOOD[:3], GOOD[3:] + b"\xEE"]])

    response, _ = exchange(fake, REQ, timeout_s=1.0)

    assert response == GOOD
    assert fake.drain() == b"\xEE"


def test_timing_starts_before_the_write_and_stops_after_the_last_byte():
    clock = FakeClock()
    fake = ClockedFake([[GOOD[:3], GOOD[3:]]], clock)

    _, elapsed_ns = exchange(fake, REQ, timeout_s=1.0, clock=clock)

    # write (100) + two reads (2 x 1000). Starting after the write gives 2000;
    # stopping after the first chunk gives 1100.
    assert elapsed_ns == 2_100


def test_exchange_stops_reading_once_the_deadline_has_passed():
    clock = FakeClock()
    fake = ClockedFake([[GOOD[:1]] * 8], clock)

    response, _ = exchange(fake, REQ, timeout_s=1.05e-6, clock=clock)

    # 1.05 us budget: write (0.1 us) + one read (1 us) uses it up; a second read never starts.
    assert response == GOOD[:1]


def test_each_read_is_given_only_the_time_left():
    clock = FakeClock()
    fake = ClockedFake([[GOOD[:3], GOOD[3:]]], clock)

    exchange(fake, REQ, timeout_s=1.0, clock=clock)

    assert fake.timeouts == [pytest.approx(1.0 - 100e-9, abs=1e-12),
                             pytest.approx(1.0 - 1_100e-9, abs=1e-12)]


# ---------------------------------------------------------------- run / classify

def test_correct_response_is_ok():
    [result] = run([rec(16)], FakeTransport([[GOOD]]))

    assert result.status == "OK"
    assert result.response == GOOD


def test_wrong_action_is_a_mismatch_that_names_the_field():
    wrong = bytes.fromhex("0010220211020000")    # slot 1 action BUY instead of SELL

    [result] = run([rec(16)], FakeTransport([[wrong]]))

    assert result.status == "MISMATCH"
    assert result.detail == "action1 got 02 want 01"


def test_every_wrong_byte_is_listed():
    wrong = bytes.fromhex("0011110111020001")    # index_lo, item1, reserved_lo wrong

    [result] = run([rec(16)], FakeTransport([[wrong]]))

    assert result.detail == "index_lo got 11 want 10; item1 got 11 want 22; reserved_lo got 01 want 00"


def test_short_response_is_short_not_timeout():
    [result] = run([rec(16)], FakeTransport([[GOOD[:7]]]))

    assert result.status == "SHORT"
    assert result.response == GOOD[:7]
    assert result.detail == "got 7/8 bytes"


def test_no_response_is_a_timeout():
    [result] = run([rec(16)], FakeTransport([[]]))

    assert result.status == "TIMEOUT"
    assert result.response == b""


def test_run_continues_after_a_timeout_by_default():
    results = run([rec(16), rec(17), rec(18)], FakeTransport([[GOOD], [], [GOOD]]))

    assert [r.status for r in results] == ["OK", "TIMEOUT", "OK"]


@pytest.mark.parametrize("failure", [[], [GOOD[:4]]], ids=["timeout", "short"])
def test_stop_on_timeout_ends_the_run_like_the_judge(failure):
    fake = FakeTransport([[GOOD], failure, [GOOD]])

    results = run([rec(16), rec(17), rec(18)], fake, stop_on_timeout=True)

    assert len(results) == 2
    assert len(fake.sent) == 2


def test_unsolicited_bytes_are_flushed_and_recorded_before_the_next_send():
    fake = FakeTransport([[GOOD + b"\xAA"], [GOOD]])

    first, second = run([rec(16), rec(17)], fake)

    assert first.stale == b""
    assert second.stale == b"\xAA"
    assert second.status == "OK"


def test_late_bytes_from_a_short_response_do_not_shift_the_next_response():
    # None = silence until the deadline: the 8th byte of packet 16 shows up late.
    fake = FakeTransport([[GOOD[:7], None, GOOD[7:]], [GOOD]])

    results = run([rec(16), rec(17)], fake)

    assert [r.status for r in results] == ["SHORT", "OK"]
    assert results[1].stale == GOOD[7:]


# ---------------------------------------------------------------- fake fault injection

def test_fake_replies_inject_each_fault_at_its_row():
    records = [rec(16), rec(17), rec(18), rec(19), rec(20), rec(21)]
    faults = {1: "wrong_action", 2: "short", 3: "timeout", 4: "extra", 5: "split"}

    results = run(records, FakeTransport(fake_replies(records, faults)))

    assert [r.status for r in results] == ["OK", "MISMATCH", "SHORT", "TIMEOUT", "OK", "OK"]
    assert results[1].detail.startswith("action1")
    # row 4's extra byte is flushed (and recorded) before row 5 is sent
    assert [len(r.stale) for r in results] == [0, 0, 0, 0, 0, 1]


def test_unknown_fault_is_rejected():
    with pytest.raises(ValueError):
        fake_replies([rec(16)], {0: "explode"})


# ---------------------------------------------------------------- stats

def test_percentile_uses_nearest_rank():
    assert percentile(list(range(1, 21)), 95) == 19
    assert percentile(list(range(1, 101)), 95) == 95
    assert percentile(list(range(1, 31)), 95) == 29   # rank ceil(28.5) = 29, not 28
    assert percentile([7.0], 95) == 7.0


def test_latency_stats_cover_complete_responses_only():
    clock = FakeClock()
    # OK, MISMATCH (both complete: 1100 ns each), SHORT and TIMEOUT excluded.
    fake = ClockedFake([[GOOD], [GOOD[:3] + b"\x00" * 5], [GOOD[:2]], []], clock)
    results = run([rec(16), rec(17), rec(18), rec(19)], fake, clock=clock)

    stats = latency_stats(results)

    assert stats == {"count": 2, "mean_ms": 0.0011, "median_ms": 0.0011, "p95_ms": 0.0011}


def test_latency_stats_with_no_complete_responses():
    results = run([rec(16)], FakeTransport([[]]))

    assert latency_stats(results) == {"count": 0, "mean_ms": None, "median_ms": None, "p95_ms": None}


def test_latency_median_of_even_count_averages_the_middle_pair():
    clock = FakeClock()

    class Steps(FakeTransport):
        delays = iter([1_000_000, 4_000_000, 2_000_000, 3_000_000])

        def read(self, size, timeout_s):
            clock.now += next(self.delays)
            return super().read(size, timeout_s)

    results = run([rec(16)] * 4, Steps([[GOOD]] * 4), clock=clock)

    stats = latency_stats(results)

    assert stats["mean_ms"] == 2.5
    assert stats["median_ms"] == 2.5
    assert stats["p95_ms"] == 4.0


# ---------------------------------------------------------------- csv

def test_csv_keeps_raw_bytes_timing_and_the_custom_runner_label(tmp_path):
    clock = FakeClock()
    fake = ClockedFake([[GOOD], [GOOD[:7]]], clock)
    results = run([rec(16), rec(17, session=2)], fake, clock=clock)
    path = tmp_path / "out.csv"

    write_csv(results, path)

    rows = list(csv.DictReader(path.open()))
    assert rows[0] == {
        "runner": "custom-runner", "row": "0", "session": "0", "index": "16", "scored": "yes",
        "status": "OK", "detail": "",
        "request_hex": "00 10 22 00 3c 11 00 50",
        "expected_hex": "00 10 22 01 11 02 00 00",
        "response_hex": "00 10 22 01 11 02 00 00",
        "bytes_received": "8", "stale_before_send_hex": "", "rtt_us": "1.10",
    }
    assert rows[1]["session"] == "2"
    assert rows[1]["status"] == "SHORT"
    assert rows[1]["response_hex"] == "00 10 22 01 11 02 00"


def test_warmup_rows_are_marked_unscored():
    results = run([rec(15)], FakeTransport([[GOOD]]))

    assert results[0].scored is False
