"""Custom replay-and-measure runner for the GQH hardware track.

Replays a fixture's requests one at a time (stop-and-wait), compares every
response byte with the fixture's expected answer, times each round trip, and
saves raw bytes + timings to CSV with a JSON summary.

These are CUSTOM-RUNNER measurements. Scoring-style validation is the job of
the organizers' 21_quick_uart_test.py and 22_robust_uart_test.py.

    python3 test/runner/replay.py FIXTURE --port /dev/cu.usbserial-XXXX
    python3 test/runner/replay.py FIXTURE --fake --inject wrong_action@16 --inject timeout@20
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import statistics
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from fixture import Fixture, FixtureError, FixtureRecord, load_fixture
from transport import FAULTS, FakeTransport, SerialTransport, Transport, fake_replies

RUNNER_LABEL = "custom-runner"
RESPONSE_LEN = 8
FIRST_SCORED_INDEX = 16
TRAILING_WAIT_S = 0.05  # after the last row, wait this long for stray bytes before the final flush
STATUSES = ("OK", "MISMATCH", "SHORT", "TIMEOUT")
RESPONSE_FIELDS = ("index_hi", "index_lo", "item1", "action1",
                   "item2", "action2", "reserved_hi", "reserved_lo")
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = REPO_ROOT / "results" / RUNNER_LABEL

Clock = Callable[[], int]


@dataclass(frozen=True)
class Result:
    row: int
    session: int
    index: int
    request: bytes
    expected: bytes
    response: bytes
    status: str
    detail: str
    elapsed_ns: int
    stale: bytes  # unsolicited bytes flushed just before this request was sent

    @property
    def scored(self) -> bool:
        return self.index >= FIRST_SCORED_INDEX

    @property
    def complete(self) -> bool:
        return len(self.response) == RESPONSE_LEN


# ---------------------------------------------------------------- one round trip

def exchange(transport: Transport, request: bytes, timeout_s: float,
             clock: Clock = time.perf_counter_ns) -> tuple[bytes, int]:
    """Send one request; collect up to 8 response bytes before the deadline.

    Timing starts immediately before the write and ends once the 8th byte is
    in (or the deadline passes), matching the official scripts.
    """
    received = b""
    t0 = clock()
    transport.write(request)
    deadline = t0 + int(timeout_s * 1e9)
    while len(received) < RESPONSE_LEN:
        remaining_ns = deadline - clock()
        if remaining_ns <= 0:
            break
        chunk = transport.read(RESPONSE_LEN - len(received), remaining_ns / 1e9)
        if not chunk:
            break
        received += chunk
    return received, clock() - t0


def classify(expected: bytes, response: bytes, timeout_s: float) -> tuple[str, str]:
    if not response:
        return "TIMEOUT", f"no bytes within {timeout_s:g} s"
    if len(response) < RESPONSE_LEN:
        return "SHORT", f"got {len(response)}/{RESPONSE_LEN} bytes"
    wrong = [f"{RESPONSE_FIELDS[i]} got {got:02x} want {want:02x}"
             for i, (got, want) in enumerate(zip(response, expected)) if got != want]
    return ("MISMATCH", "; ".join(wrong)) if wrong else ("OK", "")


# ---------------------------------------------------------------- whole fixture

def run(records: Sequence[FixtureRecord], transport: Transport, timeout_s: float = 1.0,
        stop_on_timeout: bool = False, clock: Clock = time.perf_counter_ns,
        on_result: Callable[[Result], None] | None = None) -> list[Result]:
    results = []
    for row, record in enumerate(records):
        stale = transport.drain()
        response, elapsed_ns = exchange(transport, record.request, timeout_s, clock)
        status, detail = classify(record.expected, response, timeout_s)
        result = Result(row=row, session=record.session, index=record.index,
                        request=record.request, expected=record.expected, response=response,
                        status=status, detail=detail, elapsed_ns=elapsed_ns, stale=stale)
        results.append(result)
        if on_result:
            on_result(result)
        if stop_on_timeout and not result.complete:
            break
    return results


# ---------------------------------------------------------------- stats

def percentile(values: Sequence[float], pct: float) -> float:
    """Nearest-rank percentile: the smallest value with at least pct% of values at or below it."""
    ordered = sorted(values)
    rank = max(1, math.ceil(pct / 100 * len(ordered)))
    return ordered[rank - 1]


def latency_stats(results: Sequence[Result]) -> dict[str, Any]:
    """Mean/median/p95 round trip over complete (8-byte) responses, right or wrong."""
    ns = [r.elapsed_ns for r in results if r.complete]
    if not ns:
        return {"count": 0, "mean_ms": None, "median_ms": None, "p95_ms": None}
    return {
        "count": len(ns),
        "mean_ms": statistics.fmean(ns) / 1e6,
        "median_ms": statistics.median(ns) / 1e6,
        "p95_ms": percentile(ns, 95) / 1e6,
    }


def count_statuses(results: Sequence[Result]) -> dict[str, int]:
    return {s: sum(1 for r in results if r.status == s) for s in STATUSES}


# ---------------------------------------------------------------- output files

CSV_FIELDS = ("runner", "row", "session", "index", "scored", "status", "detail",
              "request_hex", "expected_hex", "response_hex", "bytes_received",
              "stale_before_send_hex", "rtt_us")


def write_csv(results: Sequence[Result], path: Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for r in results:
            writer.writerow({
                "runner": RUNNER_LABEL, "row": r.row, "session": r.session, "index": r.index,
                "scored": "yes" if r.scored else "no", "status": r.status, "detail": r.detail,
                "request_hex": r.request.hex(" "), "expected_hex": r.expected.hex(" "),
                "response_hex": r.response.hex(" "), "bytes_received": len(r.response),
                "stale_before_send_hex": r.stale.hex(" "), "rtt_us": f"{r.elapsed_ns / 1000:.2f}",
            })


def build_summary(fixture: Fixture, results: Sequence[Result], transport_info: dict[str, Any],
                  timeout_s: float, label: str | None, started_at: str,
                  aborted: str | None = None, trailing: bytes = b"") -> dict[str, Any]:
    return {
        "runner": RUNNER_LABEL,
        "note": "custom-runner measurement; use the official scripts for scoring-style validation",
        "label": label,
        "started_at": started_at,
        "fixture": {"path": str(fixture.path), "metadata": fixture.metadata},
        "transport": transport_info,
        "timeout_s": timeout_s,
        "planned": len(fixture.records),
        "sent": len(results),
        "counts": count_statuses(results),
        "scored_counts": count_statuses([r for r in results if r.scored]),
        "aborted": aborted,
        "unsolicited_byte_events": sum(1 for r in results if r.stale),
        "trailing_unsolicited_hex": trailing.hex(" "),
        "latency": latency_stats(results),
    }


def output_stem(fixture: Fixture, label: str | None, stamp: str) -> str:
    parts = [RUNNER_LABEL, fixture.path.stem]
    if label:
        parts.append(re.sub(r"[^A-Za-z0-9.-]+", "-", label).strip("-"))
    parts.append(stamp)
    return "_".join(parts)


def unique_output_paths(out_dir: Path, stem: str) -> tuple[Path, Path]:
    """CSV + summary paths that do not overwrite an earlier run's files."""
    candidate, n = stem, 1
    while (out_dir / f"{candidate}.csv").exists() or (out_dir / f"{candidate}.summary.json").exists():
        n += 1
        candidate = f"{stem}-{n}"
    return out_dir / f"{candidate}.csv", out_dir / f"{candidate}.summary.json"


# ---------------------------------------------------------------- console

def print_result(r: Result) -> None:
    rtt = f"{r.elapsed_ns / 1e6:8.3f} ms"
    stale = f"  [flushed {len(r.stale)} unsolicited byte(s): {r.stale.hex(' ')}]" if r.stale else ""
    detail = f"  {r.detail}" if r.detail else ""
    print(f"[row {r.row:3d}] s{r.session} idx {r.index:3d}  {r.status:8s} {rtt}{detail}{stale}")


def _fmt_counts(counts: dict[str, int]) -> str:
    return " | ".join(f"{s} {n}" for s, n in counts.items())


def _fmt_ms(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.3f} ms"


def print_summary(summary: dict[str, Any], csv_path: Path, summary_path: Path) -> None:
    lat = summary["latency"]
    lines = [
        "",
        "=" * 64,
        "CUSTOM-RUNNER MEASUREMENT (not the official scoring script)",
        "=" * 64,
        f"fixture   {summary['fixture']['path']}",
        f"transport {json.dumps(summary['transport'])}   timeout {summary['timeout_s']:g} s",
        f"sent      {summary['sent']}/{summary['planned']}",
        f"all rows  {_fmt_counts(summary['counts'])}",
        f"scored    {_fmt_counts(summary['scored_counts'])}   (index >= {FIRST_SCORED_INDEX})",
        *([f"ABORTED   {summary['aborted']} (rows up to here are saved)"] if summary["aborted"] else []),
        f"unsolicited-byte events  {summary['unsolicited_byte_events']}",
        *([f"unsolicited bytes after the last response: {summary['trailing_unsolicited_hex']}"]
          if summary["trailing_unsolicited_hex"] else []),
        f"latency over {lat['count']} complete responses:  mean {_fmt_ms(lat['mean_ms'])}"
        f" | median {_fmt_ms(lat['median_ms'])} | p95 {_fmt_ms(lat['p95_ms'])}",
        *(["(fake transport: timings are Python overhead, not board latency)"]
          if summary["transport"]["kind"] == "fake" else []),
        f"csv       {csv_path}",
        f"summary   {summary_path}",
    ]
    print("\n".join(lines))


# ---------------------------------------------------------------- CLI

def parse_fault(text: str) -> tuple[int, str]:
    kind, sep, row = text.partition("@")
    if not sep or kind not in FAULTS or not row.isdigit():
        raise argparse.ArgumentTypeError(f"expected KIND@ROW with KIND in {', '.join(FAULTS)}")
    return int(row), kind


def positive_float(text: str) -> float:
    value = float(text)
    if not value > 0:
        raise argparse.ArgumentTypeError("must be > 0")
    return value


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("fixture", type=Path, help=".json or .jsonl fixture")
    where = p.add_mutually_exclusive_group(required=True)
    where.add_argument("--port", help="board serial port, e.g. /dev/cu.usbserial-XXXX or COM6")
    where.add_argument("--fake", action="store_true",
                       help="replay against a fake that answers from the fixture")
    p.add_argument("--inject", type=parse_fault, action="append", default=[], metavar="KIND@ROW",
                   help=f"(--fake only) break fixture row ROW; KIND is one of {', '.join(FAULTS)}")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=positive_float, default=1.0,
                   help="per-packet timeout in seconds (judge: 1.0)")
    p.add_argument("--stop-on-timeout", action="store_true",
                   help="end the run at the first SHORT/TIMEOUT, as the judge does")
    p.add_argument("--label", help="free text recorded with the results, e.g. build hash or TX gap")
    p.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return p


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.inject and not args.fake:
        parser.error("--inject only works with --fake")
    try:
        fixture = load_fixture(args.fixture)
    except FixtureError as exc:
        parser.error(f"bad fixture: {exc}")
    faults = dict(args.inject)
    past_end = [row for row in faults if row >= len(fixture.records)]
    if past_end:
        parser.error(f"--inject row(s) {past_end} past the fixture's {len(fixture.records)} rows")

    transport, transport_info = open_transport(args, parser, fixture, faults)

    started = datetime.now()
    print(f"{RUNNER_LABEL}: replaying {len(fixture.records)} rows from {fixture.path}")
    results, aborted, trailing = replay_protected(fixture, transport, args)

    summary = build_summary(fixture, results, transport_info, args.timeout, args.label,
                            started.isoformat(timespec="seconds"), aborted, trailing)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    stem = output_stem(fixture, args.label, started.strftime("%Y%m%d-%H%M%S"))
    csv_path, summary_path = unique_output_paths(args.out_dir, stem)
    write_csv(results, csv_path)
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print_summary(summary, csv_path, summary_path)

    all_ok = len(results) == len(fixture.records) and all(r.status == "OK" for r in results)
    clean = not aborted and not trailing and not summary["unsolicited_byte_events"]
    return 0 if all_ok and clean else 1


def open_transport(args: argparse.Namespace, parser: argparse.ArgumentParser, fixture: Fixture,
                   faults: dict[int, str]) -> tuple[Transport, dict[str, Any]]:
    if args.fake:
        info = {"kind": "fake", "faults": {str(row): kind for row, kind in sorted(faults.items())}}
        return FakeTransport(fake_replies(fixture.records, faults)), info
    try:
        transport = SerialTransport(args.port, args.baud, args.timeout)
    except ImportError:
        parser.error("pyserial is not installed: pip install pyserial")
    except OSError as exc:  # serial.SerialException is an OSError
        parser.error(f"could not open port {args.port}: {exc}")
    return transport, {"kind": "serial", "port": args.port, "baud": args.baud}


def replay_protected(fixture: Fixture, transport: Transport,
                     args: argparse.Namespace) -> tuple[list[Result], str | None, bytes]:
    """Run the fixture, keeping every finished row even if the port dies or Ctrl-C is pressed."""
    results: list[Result] = []

    def keep(result: Result) -> None:
        results.append(result)
        print_result(result)

    aborted, trailing = None, b""
    try:
        run(fixture.records, transport, args.timeout, args.stop_on_timeout, on_result=keep)
        if not args.fake:
            time.sleep(TRAILING_WAIT_S)  # give a late or extra byte time to arrive
        trailing = transport.drain()
    except (OSError, KeyboardInterrupt) as exc:
        aborted = type(exc).__name__ + (f": {exc}" if str(exc) else "")
    finally:
        try:
            transport.close()
        except OSError as exc:
            print(f"warning: closing the port failed: {exc}", file=sys.stderr)
    return results, aborted, trailing


if __name__ == "__main__":
    sys.exit(main())
