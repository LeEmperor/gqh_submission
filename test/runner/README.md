# Custom replay-and-measure runner

Replays a fixture's requests to the board one at a time (stop-and-wait), checks
every response byte against the fixture's expected answer, times each round trip,
and saves raw bytes + timings to CSV with a JSON summary.

**These are custom-runner measurements.** Every output file, CSV row and console
summary is labeled `custom-runner`. For scoring-style validation, use the
organizers' `21_quick_uart_test.py` and `22_robust_uart_test.py`.

## One-command optimization validation

After programming the candidate in Gowin, leave it running without a button
reset, close other serial terminals, and run from the repository root:

```sh
python3 tools/validate_board.py --port /dev/ttyUSB1
```

The default candidate label is H2 and image path is
`test_proj2/test_proj2/impl/pnr/test_proj2.fs`. For later stages use `--label H3`
and optionally `--fs /path/to/programmed.fs`. The script does not program the board.
It creates a unique `results/board-H2-.../` directory, patches PORT in private
copies of the pristine official scripts, and prints the result path at the start
and end. No shell variables, directory preparation, separate launchers or log
redirection are needed. Requires Python 3 and pyserial.

The full sequence is startup (before button reset), official quick, normal robust
then full-range with no intervening reset/programming, a 1,598-packet independent
custom replay across 25 sessions, the same replay after populated-history button
reset, and sticky busy-fault/button-reset recovery. The custom fixture includes
all nine H2 relations at the first scored update, warm-up slot swaps, equality,
truncated averages, zero/max/full-range prices and repeated sessions. Prompts
cover the physical reset presses and LED observations; other steps run themselves.

Official quick must print PASS; robust CSVs and summaries must show all 100
responses, 84/84 packets, 168/168 actions and zero timeouts. Normal mean must be
at most 20.7825 ms. Custom runs require every byte correct, no abort, timeout,
short response or unsolicited/trailing bytes. The wrapper stops on failure and
exits nonzero; `summary.json` and per-stage console/CSV/summary files retain the
results. A full PASS is board-test evidence, with resource/timing screening kept
separate. It does not update phase acceptance automatically.

For a fast screening pass between builds:

```sh
python3 tools/validate_board.py --port /dev/ttyUSB1 --smoke
```

This runs quick only after a reset prompt. Its result is explicitly smoke-only;
use the default suite for candidate board validation. `--prepare-only` creates
all fixtures/scripts without opening serial. Wrapper logic can be tested without
a board using `python3 -m unittest discover -s test/runner -p test_board_validation.py`.

## Quick start

Requires Python 3.9+. `pyserial` is needed only for board runs (`pip install pyserial`),
`pytest` only for the tests.

```bash
# 1. Fake transport that answers with the fixture's expected bytes -> all OK, exit 0
python3 test/runner/replay.py test/runner/examples/quick_test_vectors.json --fake

# 2. Same, with injected faults -> each one is caught, exit 1
python3 test/runner/replay.py test/runner/examples/quick_test_vectors.json --fake \
    --inject wrong_action@16 --inject short@18 --inject timeout@20

# 3. The real board (same runner, same fixture)
python3 test/runner/replay.py path/to/fixture.json --port /dev/cu.usbserial-XXXX --label "build 1a2b3c, tx gap 4"
```

Board checklist:
- Program the board (SRAM) with a `.fs` that speaks the 8-byte protocol.
- Close Gowin Programmer and any serial terminals, because only one program can hold the port.
- Find the port. On macOS run `ls /dev/cu.usbserial*`; if two appear, the UART is usually the
  second, and the wrong one shows TIMEOUT on every row. On Windows look in Device Manager →
  Ports (COM6 etc.). On Linux it is `/dev/ttyUSB*`.
- Use `--label` to record the build hash, TX gap and so on. It goes into the file names and summary.

`examples/quick_test_vectors.json` is a placeholder: the 21 packets from the organizers'
quick test, with expected answers from their reference model. Use Beginner 1's fixtures
for real runs.

## Fixture format

One record per request, as agreed with the fixture author:

```json
{"session": 0, "index": 0, "request_hex": "00001100642200c8", "expected_response_hex": "0000110022000000"}
```

- `*.jsonl`: one record per line.
- `*.json`: a list of records, or `{"records": [...], "seed": ..., "settings": {...}}`.
  Every key except `records` is kept as metadata and copied into the run's summary.
- `session` is optional (default 0). Hex may contain spaces. A UTF-8 BOM, which Windows
  editors add, is fine.

Records are replayed in file order. The loader rejects, naming the row:
- a request or expected response that is not exactly 8 bytes
- an `index` that disagrees with request bytes 0–1
- an expected response that does not echo the index and item IDs in slot order, has a nonzero
  reserved field, or uses an action other than NONE/SELL/BUY

## What it records

Per request, before sending, it flushes any bytes already waiting. These are unsolicited:
usually a late byte from the previous packet, or a board that sent more than 8 bytes. They
are recorded in `stale_before_send_hex` on the row being sent, so they cannot shift the next
response. It then sends the request and reads until 8 bytes have arrived or the timeout runs
out. Reads that return only part of a response are joined together. After the last row it waits
50 ms and flushes once more, so a stray byte after the final response is reported too, as
`trailing_unsolicited_hex` in the summary.

If the port fails mid-run (board unplugged) or you press Ctrl-C, every finished row is still
saved. The summary's `aborted` field says why the run stopped.

| Status | Meaning |
|---|---|
| `OK` | all 8 bytes match |
| `MISMATCH` | 8 bytes arrived, at least one wrong; `detail` names each one, e.g. `action1 got 02 want 01` |
| `SHORT` | 1–7 bytes arrived before the timeout (`detail`: `got 7/8 bytes`) |
| `TIMEOUT` | nothing arrived before the timeout |

The official judge logs both SHORT and TIMEOUT as `TIMEOUT` and ends the run there.
This runner keeps going so you get a full CSV; pass `--stop-on-timeout` to stop like the judge.

**Timing** starts immediately before the write and ends once the 8th byte is in, using
`time.perf_counter_ns()`, which is how the official scripts time it. The timeout window (1 s
by default, as the judge uses) starts at the same moment.

**Latency stats** (mean, median, p95) cover every complete 8-byte response, right or wrong,
as the official script's average does. Warm-up packets are included. p95 uses the nearest-rank
method. SHORT/TIMEOUT rows are excluded because their time is just the timeout.

**Exit code**: 0 only if every row was sent and is `OK` and no unsolicited bytes appeared.
Otherwise 1, which includes aborted runs. 2 means the run never started: a bad fixture, bad
arguments, a port that can't be opened, or pyserial isn't installed.

## Output

Written to `results/custom-runner/` (change with `--out-dir`). An existing run is never overwritten.

- `custom-runner_<fixture>[_<label>]_<YYYYmmdd-HHMMSS>.csv`, one row per request:
  `runner, row, session, index, scored, status, detail, request_hex, expected_hex,
  response_hex, bytes_received, stale_before_send_hex, rtt_us`.
  `scored` is `yes` for index ≥ 16.
- `….summary.json` has the fixture path and metadata (seed and settings), transport, timeout,
  label, counts for all rows and for scored rows, `aborted`, unsolicited-byte events,
  trailing unsolicited bytes, and latency stats.

## Options

| Option | Default | |
|---|---|---|
| `--port PORT` / `--fake` | (one required) | board serial port, or the fake transport |
| `--inject KIND@ROW` | | fake only, repeatable; ROW is the 0-based fixture row; KIND is `wrong_action`, `short`, `timeout`, `split` (3+5 bytes, should still pass), or `extra` (one unsolicited byte after the response) |
| `--timeout S` | 1.0 | per-packet timeout |
| `--stop-on-timeout` | off | end at the first SHORT/TIMEOUT |
| `--baud N` | 115200 | |
| `--label TEXT` | | recorded in file names and summary |
| `--out-dir DIR` | `results/custom-runner` | |

## Tests

```bash
python3 -m pytest test/runner -q
```

- `test_fixture.py` covers loading and validation.
- `test_replay.py` covers round trips with partial and late bytes, the deadline, timing, statuses, flushing, stats, and the CSV.
- `test_cli.py` covers end-to-end fake runs with injected faults.
- `test_serial.py` drives the real pyserial code through pyserial's built-in `loop://` echo
  port, so the serial path is exercised without a board.

## Files

| File | Role |
|---|---|
| `replay.py` | round trip, classification, run loop, stats, CSV/summary, CLI |
| `transport.py` | `SerialTransport` (pyserial), `FakeTransport`, fault injection |
| `fixture.py` | fixture loading and validation |
| `examples/quick_test_vectors.json` | placeholder fixture (organizer quick-test packets) |
