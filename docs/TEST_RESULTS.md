# Streaming verification

Checked October 2, 2026, on branch `codex/databento-streamer` in `/home/srijan/tickweave`.

## Checks run

`opam exec -- dune build @install @runtest` passed. The four suites cover:

| Suite | Evidence |
| --- | --- |
| Core | Guide packet bytes, uint16 rejection, reserved/action validation, warm-up/reset/slot order, held actions, full-window independent oracle across 1,800 random updates, seed reproducibility, exact price conversion and fresh-symbol pairing |
| Transport | Fragmented 1/2/5-byte reads, one absolute deadline despite dripped bytes, bounded writes with a saturated socket, refusal to reuse failed connections, unsolicited/surplus byte evidence |
| Databento | Three SHA-256 known vectors, exact prices above 2^53, uint64 timestamps, quoted CSV/CRLF, malformed headers/rows, mocked historical request parameters and secret handling, rejection of HTTP 206/401/500, child-process error/cleanup, local TCP live handshake, symbol mappings, fragmented JSON, server/auth errors, and bounded control-record filtering |
| CLI | Two 100-packet mock sessions on one connection, all eight deliberate failure modes, source/request replay, source error and incomplete-input logs, capture output, preserved existing logs, malformed inputs, and 26-column CSV consistency |

A separate smoke run sent 200 packets to the local mock endpoint: each session received 100 responses, matched 84/84 scored packets and 168/168 scored actions, and recorded zero timeouts/failures. Its log is `results/mock-smoke-200.csv` (ignored by Git). Mean mock round-trip times were approximately 2.504 ms and 2.599 ms; these measure local socket/process overhead and say nothing about FPGA/USB latency.

`git diff --check` passed. The tested switch is OCaml 5.2.0+ox, Dune 3.24.2, Yojson 2.2.2+ox, and Core_unix v0.18~preview.130.106+341. OxCaml emits informational `unsafe_multidomain` alerts for signal handling and test environment mutation; these paths run in a single domain. Stock OCaml/Core_unix combinations have not been separately tested.

## Acceptance still requiring the operator

No real Databento API key was read, no paid API query was made, and no physical FPGA exchange was attempted. Verify account dataset access and run the streamer against the board's exposed Linux serial device. Hardware RTS/CTS must be disabled; see README. The official organizer quick/robust scripts remain the FPGA acceptance gate.

The external fixture/validation deliverable is now integrated under `external/databento_audit/`, from the staged handoff in `/home/srijan/tickweave-external` on `codex/databento-fixtures`. Its standalone suite passed 2,232 checks, including a two-million-row memory test. A fifth main-project integration suite matched all 11 valid fixture request files and rejected all 20 malformed fixtures (31 total). Multiline quoted CSV support was added to the main replay reader for compatibility, with the whole record bounded and internal CRLF retained. No external worktree files were changed during integration.

The external report's open contract questions are resolved by the current behavior: accept extra/reordered columns; validate wire range before coalescing; reject corrupt unrelated rows; preserve digit timestamps including leading zeros and the uint64 maximum; compare symbols exactly; allow header-only data while requiring enough packets in a requested run; never wrap an index silently. Historical formatting flags are explicitly present in the adapter. The audit's configurable record limit is used by fixture integration tests; production replay defaults to 1 MiB.

## Specification clarification

The plan's hand-worked “sixteen 100s then 99 produces SELL” example conflicts with its exact floor-average formula. The new sum is 1599 and new average is 99, so current price 99 is not strictly below the average. The checker returns NONE for that case, and SELL for 98, in accordance with the guide's exact procedure. Both boundaries are covered by tests.

## Operator capture and offline mock recheck

The operator's successful historical Databento capture contained 605 trades and produced 10 requests. All 10 saved request packets passed the independent byte, price, timestamp, and fresh-pairing audit in `docs/ENCODING_VERIFICATION.md`. Replaying this capture against the local mock received 10 valid responses with zero timeouts/failures; all packets were warm-up.

A fresh two-session synthetic mock run received 100 responses per session, matched 84/84 scored packets and 168/168 scored actions per session, and had zero timeouts/failures. Evidence is in `results/offline-historical-mock-encoding-check.csv` and `results/offline-synthetic-mock-encoding-check.csv`. These runs used no API credentials, network requests, or physical FPGA. A deliberately partial seven-byte mock response was also rejected with a nonzero exit code.

## Python fixture factory — Beginner 1

Completed the new plan's Python data-factory work in `tools/test_data_factory/` on `codex/databento-streamer`. The model keeps the last 16 prices per item and recomputes old/new sums directly. Seven scenarios supply eight sessions and 800 JSONL request/expected-response records, including constants, ramps, crossings/held actions, swapped slots, zero/max values, seeded randomness, and consecutive index-zero sessions. Metadata records settings and SHA-256 hashes; per-session integer CSVs work with the OCaml request source.

`python3 tools/test_data_factory/run_checks.py` passed: 22 Python tests, byte-identical regeneration of saved fixtures, and all eight request/response bytes matching the OCaml mock for all 800 packets. Tests include a separate complete-history oracle over 2,000 random requests, hand-calculated boundaries, reset after nonzero actions, invalid inputs/output preservation, and rejection of wrong actions, short responses, and timeout logs. The constant and swapped first-assignment fixtures were independently reviewed before generating the advanced scenarios.

The OCaml comparison starts a fresh mock connection for each session; continuous different-history resets are checked by the Python model tests and supplied in the two-session JSONL fixture for the future replay runner. No physical UART, API query, or official scoring measurements are part of this fixture check. Generation and test commands are in the factory README.
