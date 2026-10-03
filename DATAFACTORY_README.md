# Tickweave data streamer

An OCaml host tool for the data streaming workstream in section 3A of `GQH_Team_Execution_Plan.md`. It reads Databento trades, creates eight-byte GQH price requests, sends one request at a time, checks responses, and preserves transaction evidence in CSV. This branch implements the streaming system only.

## Build and test

Linux/WSL is the supported serial runtime. Use an OCaml 5.2+ switch with Dune, Yojson, and Core_unix:

```sh
opam install dune yojson core_unix
opam exec -- dune build
opam exec -- dune runtest
opam exec -- dune exec tickweave-stream -- --help
```

The tested local switch uses OCaml 5.2.0+ox, Dune 3.24.2, Yojson 2.2.2+ox, and Core_unix v0.18 preview. `core_unix` supplies a monotonic clock for deadlines and round-trip measurements. Historical HTTPS uses the system `curl` executable; the application, parsers, live authentication, codecs, test data, and verification logic are written in OCaml.

## Run without credentials or hardware

Create the results directory and run two complete sessions against a local mock FPGA on one connection:

```sh
cd /home/srijan/tickweave
mkdir -p results
opam exec -- dune exec tickweave-stream -- \
  --source synthetic --seed 42 --packets 100 --sessions 2 \
  --transport mock --output "results/mock-$(date +%s%N).csv" --build-id mock
```

The mock receives real binary requests over a socket pair and returns fragmented responses. Expect `received=100`, `scored packets=84/84`, `scored actions=168/168`, zero timeouts and zero failures for each session. The first 16 packets are warm-up. It is testing infrastructure and does not demonstrate FPGA correctness.

To replay your saved Databento capture against the mock, with no API call:

```sh
cd /home/srijan/tickweave
opam exec -- dune exec tickweave-stream -- \
  --source replay --input results/historical-trades.csv \
  --symbol-a AAPL --symbol-b MSFT --packets 10 \
  --transport mock --output "results/replay-mock-$(date +%s%N).csv"
```

That capture supplies 10 packets. Expect `received=10`, zero timeouts/failures, and `scored packets=0/0` because all 10 are warm-up. For another capture, set `--packets` to a count it can supply. The same source/pairing/encoder/request-response/checker/logging path runs in mock mode; physical UART configuration is exercised by serial mode.

To prove the runner detects errors:

```sh
cd /home/srijan/tickweave
opam exec -- dune exec tickweave-stream -- \
  --source synthetic --transport mock --mock-fault partial \
  --output "results/partial-$(date +%s%N).csv"
```

Faults are injected at index 16: `timeout`, `partial` (seven bytes), `wrong-index`, `wrong-item`, `reserved`, `action`, `mismatch`, or `extra`. Each failure stops the session and produces a nonzero exit status. Choose a new output filename for every run; existing logs are preserved.

## Databento live source

In the WSL terminal where you will run the streamer, enter the key into its environment:

```sh
cd /home/srijan/tickweave
read -rsp "Databento API key: " DATABENTO_API_KEY
export DATABENTO_API_KEY
printf '\n'
```

The prompt hides your input and keeps it out of shell history. This lasts for the current terminal session. The streamer reads `DATABENTO_API_KEY` directly; `.env` files are not loaded automatically. The key is never a CLI argument or a log field. Select a dataset you can access and two distinct raw symbols:

```sh
opam exec -- dune exec tickweave-stream -- \
  --source live --dataset XNAS.ITCH --symbol-a AAPL --symbol-b MSFT \
  --transport serial --port /dev/ttyUSB0 \
  --packets 100 --sessions 2 --swap-slots \
  --capture results/live-trades.csv --output results/live-uart.csv \
  --build-id YOUR_FPGA_BUILD_ID
```

The live adapter uses Databento's native TCP protocol with SHA-256 challenge authentication and JSON records. It consumes trade and symbol-mapping messages and reports source errors. `--transport dry-run` builds and logs requests without UART; `--transport mock` runs the same feed through the local test endpoint.

The FPGA protocol carries two unsigned 16-bit prices. Item A (`17`/`0x11`) maps to `--symbol-a`; Item B (`34`/`0x22`) maps to `--symbol-b`. Databento prices are integer nanodollars. The explicit conversion is:

```text
UART price = floor(Databento price / price_quantum_nanos)
```

The default quantum is `10000000`, or one cent. Prices above $655.35 therefore require a larger quantum. Negative, undefined, or out-of-range prices fail; the tool never clamps or wraps them. Changing the quantum changes the experiment's units. Every market transaction logs the original prices, quantum, symbols, and timestamps.

Each request requires a fresh trade from both symbols since the previous request. If one symbol trades several times before the other, its most recent price is selected. Capture records retain all consumed source ticks so this sampling is reproducible. This is a paired trade-price test stream, not an order-book feed or a reconstruction of every trade on the FPGA. Alternating packet slots is available with `--swap-slots`.

UART stop-and-wait is slower than many live feeds. The live socket applies backpressure and may lag; there is no unlimited application queue. Prefer historical capture and offline replay for reproducible tests. A missing second symbol can time out with `--pair-timeout` (default 60 seconds); an outstanding source read has its own network timeout.

## Historical API and offline replay

Fetch a bounded interval once and save the consumed trades for subsequent offline runs. Historical requests can incur Databento usage charges, so the streamer only contacts the API when you explicitly choose an API source.

```sh
opam exec -- dune exec tickweave-stream -- \
  --source historical --dataset XNAS.ITCH \
  --symbol-a AAPL --symbol-b MSFT \
  --start 2026-10-01T14:00:00Z --end 2026-10-01T14:05:00Z \
  --record-limit 100000 --packets 100 \
  --transport mock --capture results/historical-trades.csv \
  --output results/historical-uart.csv
```

The adapter requests `schema=trades`, CSV, unformatted integer prices/timestamps, and symbol mapping. Replay consumes the normalized capture format:

```csv
symbol,ts_event,price
AAPL,1790982000000000000,200000000000
MSFT,1790982000000000001,400000000000
```

```sh
opam exec -- dune exec tickweave-stream -- \
  --source replay --input examples/trades.csv \
  --symbol-a AAPL --symbol-b MSFT --packets 3 --sessions 2 \
  --transport mock --output results/replay.csv
```

Replay reopens the same input for each session. Live/historical sessions consume successive data from one source connection. Index zero starts each session; requests never wrap their index silently. If a source ends before the requested packet count, the run fails and the log records `INCOMPLETE_SOURCE`. Capture is bounded by the run and contains consumed records, not necessarily the entire queried historical range.

The execution plan's integer request CSV is also supported, with no market-price conversion:

```csv
index,item1,price1,item2,price2
0,17,20000,34,40000
1,34,39900,17,20100
```

Use `--source requests --input FILE --packets ROW_COUNT`. A session must have consecutive indices starting at zero, both distinct item IDs in each row, and prices in `0..65535`. The input is validated before transmission. Synthetic sessions use a local seeded generator and alternate item slots.

## UART behavior and evidence

The serial port is configured as raw 115200 baud, eight data bits, no parity, one stop bit, with software flow control disabled. Hardware RTS/CTS must also be disabled in the device configuration (`stty -F /dev/ttyUSB0 -crtscts` on Linux). Multi-byte fields are big-endian:

```text
request:  index(2) item1(1) price1(2) item2(1) price2(2)
response: index(2) item1(1) action1(1) item2(1) action2(1) reserved(2)=0
```

The absolute transaction deadline starts before writing and defaults to one second. Writes and partial reads share that deadline. The next request follows only a complete valid response. A timeout or invalid response stops without resending a state-changing request or flushing away surplus bytes. Recovery is an explicit new run beginning with index zero. The same transport connection is retained for `--sessions 2`.

The independent host checker implements the guide's 16-price windows, old/new floor averages, strict crossings, held actions, item routing, and session reset. It is used solely to verify the streamer's responses. The plan’s illustrative sixteen-100s-then-99 SELL example conflicts with its floor-average formula: the new average is 99, so that case returns NONE; 98 produces SELL. The checker follows the exact formulas. Warm-up indices `0..15` are checked and logged; the terminal summary reports scored packets/actions separately. Remaining packets after a failure count in the denominator. Logs include session/source/seed/build identity, request/response hex, prices, expected/actual actions, monotonic elapsed time, status, and error text. Output and capture files are created with owner-only permissions.

`--interval-ms` adds pacing between completed transactions; it is excluded from round-trip latency. `--timeout` allows transport diagnostics. Native Windows COM ports are not supported by this Unix implementation; under WSL, expose the board as a Linux serial device first. Keep other serial owners closed. Board attachment and hardware testing require the actual device.

Official judging runs the organizer's unchanged `21_quick_uart_test.py` and `22_robust_uart_test.py` directly against the FPGA. This host tool is for development and does not replace those acceptance tests. No FPGA programming, synthesis, order execution, or UI implementation is part of this branch.

## Implementation references

- [Databento historical HTTP API](https://databento.com/docs/api-reference-historical?historical=http)
- [Databento live raw protocol](https://databento.com/docs/api-reference-live?live=raw)
- [Live symbol mapping](https://databento.com/docs/examples/symbology/live-symbol-mapping)
- [Databento record types and conventions](https://databento.com/docs/standards-and-conventions/common-fields-enums-types)

Protocol and acceptance requirements come from the GQH hardware guide and execution-plan section 3A. OCaml replaces the plan's proposed Python host files, and Databento extends its synthetic/replay sources, as requested.

## Independent offline audit tool

The external agent's completed tool is integrated under `external/databento_audit/`. It generates deterministic fixtures and validates local trade captures without credentials. To run its checks independently:

```sh
cd /home/srijan/tickweave/external/databento_audit
opam exec -- dune runtest --root .
opam exec -- dune exec --root . ./databento_audit.exe -- verify --fixtures-dir fixtures
```

The main streamer's integration test compares all 11 valid fixtures with their independently derived request CSVs and rejects the 20 malformed fixtures. Replay supports quoted fields spanning physical lines, retains CRLF inside quotes, and bounds each whole record. Extra columns and arbitrary header order are accepted, required headers are unique, symbols match exactly, and all prices/timestamps are validated even on unrelated rows. Wire conversion is checked on every configured-symbol trade, including trades later superseded by coalescing. The audit's zero-request/header-only captures are valid data; a streamer run still fails if it cannot supply the requested packet count.

The operator's first real historical capture passed an independent encoding audit of all 10 packets: see [encoding verification](docs/ENCODING_VERIFICATION.md) for the exact byte breakdown, evidence, and repeatable OCaml check.

## Python test-data factory (Beginner 1)

The new plan's Python fixture factory is in [`tools/test_data_factory/`](tools/test_data_factory/README.md). It supplies an independent direct-window oracle, seven deterministic scenarios, eight sessions, and 800 exact request/expected-response records. CSV exports can be replayed with the existing OCaml streamer. Run all offline checks with:

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/run_checks.py
```

Use `--python-only` to skip the OCaml mock comparison. See the factory README for generation commands, hand-checked answers, and the replay-runner handoff.
