# databento_audit handoff report

Branch `codex/databento-fixtures`, worktree `/home/srijan/tickweave-external`,
based on `7d89ef9`. The full commit SHA is given in the handoff message, since
a commit cannot contain its own hash.

All results below are from synthetic local CSV data run through this offline
tool. Nothing here is a hardware, FPGA, UART or Databento API result. No
network access, credentials or environment API keys were used.

## Files added (all under `external/databento_audit/`)

| File | Purpose |
|---|---|
| `dune-project`, `dune`, `.gitignore` | standalone Dune project (library `databento_audit_lib`, executable `databento_audit`) |
| `csv_stream.ml` | incremental RFC 4180 reader with a per-record byte limit |
| `trade_contract.ml` | exact int64 price/quantum/ts_event parsing, wire conversion, request rows |
| `validator.ml` | streaming validator: header checks, row checks, pairing, counters |
| `report.ml` | JSON report (units, scope disclaimer, counts, pending ticks, first error) |
| `safe_output.ml` | no-clobber file writes (`link(2)` commit), same-file detection |
| `generator.ml` | deterministic fixture specs (SplitMix64 PRNG, hand-written edge cases) |
| `fixture_check.ml` | replays every manifest through the validator |
| `databento_audit.ml` | CLI: `generate`, `validate`, `verify` |
| `test/dune`, `test/test_audit.ml` | test suite (run by `dune runtest`) |
| `fixtures/**` | output of `generate --output-dir fixtures --seed 42 --pairs 100` (74 files) |
| `README.md`, `REPORT.md` | usage, implemented contract, this report |

Nothing outside `external/databento_audit/` was modified. No files in
`/home/srijan/tickweave` were touched.

## Toolchain

- OCaml 5.2.0+ox (OxCaml), opam 2.5.0, Dune 3.24.2, Yojson 2.2.2
- Linux 6.18.33.2-microsoft-standard-WSL2

## Commands run

```sh
cd /home/srijan/tickweave-external
git branch --show-current            # codex/databento-fixtures
git status --short
cd external/databento_audit
opam exec -- dune build              # exit 0, no warnings
opam exec -- dune exec ./databento_audit.exe -- generate --output-dir fixtures --seed 42 --pairs 100
opam exec -- dune exec ./databento_audit.exe -- generate --output-dir fixtures      # exit 3, nothing written
opam exec -- dune exec ./databento_audit.exe -- generate --output-dir fixtures --overwrite
opam exec -- dune exec ./databento_audit.exe -- verify --fixtures-dir fixtures     # 31 fixtures, 0 failed
opam exec -- dune runtest --force    # 2232 checks passed, 0 failed (~3 s)
./_build/default/databento_audit.exe validate --input fixtures/valid/05_late_second_symbol_trailing/trades.csv \
    --symbol-a AAPL --symbol-b MSFT --quantum-nanos 10000000                       # exit 0
./_build/default/databento_audit.exe validate --input fixtures/expected_failure/int64_overflow/trades.csv \
    --symbol-a AAPL --symbol-b MSFT                                                # exit 1
```

During development, the first `verify` run flagged one fixture,
`07_quoted_crlf_long_timestamps`: I had written 7 expected records by hand
where the file has 6. The parser was right; the manifest was corrected and the
fixtures were regenerated.

## Test results

All passed. Coverage by area:

- **Exact arithmetic**: price parsing for 0, leading zeros, 2^53+1,
  INT64_MAX-1, UNDEF (INT64_MAX), INT64_MAX+1, 2^64 and longer, negative
  values including `-0`, and malformed forms (`+1`, `1.5`, `1e9`, spaces, hex,
  non-ASCII digits). Wire conversion at 0, at remainders just below a quantum,
  at 65535/65536, at quantum 1 and 3, and at quantum 2^48 above 2^53. A float
  control check confirms float division gives 32768 where exact int64 gives
  32767. Quantum parsing rejects 0, negative, empty, `1.0` and INT64_MAX+1.
- **ts_event**: uint64 bound, leading zeros, empty and non-digit values.
- **CSV**: quoted commas, `""` escapes, CRLF, LF and CR-LF inside quotes, no
  trailing newline, blank lines, an unterminated quote, a quote inside an
  unquoted field, text after a closing quote, a bare CR, and the exact
  record-size limit.
- **Hand-derived pairing**: coalescing, unrelated rows, a trailing pending
  tick with its exact line/record/price/wire, reversed arrival order, no
  forward fill, quoted symbol match versus case/whitespace mismatches, and
  quantum 3.
- **Validator errors**: every category, with its line and field.
- **Committed fixtures**: all 31 pass `verify`. The malformed corpus covers
  every required error class, and every expected failure is labelled.
- **Reproducibility**: the same seed gives identical bytes, both in-process
  and across two CLI runs. Committed fixtures equal regenerated ones. A
  different seed changes the seeded fixtures but not the hand-written ones.
- **Cross-check**: for seeds 0 to 40 with varying `--pairs`, the validator
  reproduces the generator's plan-derived rows exactly for every valid
  fixture.
- **CLI**: exit codes for every fixture (valid gives 0, failure gives 1),
  usage errors give 2, a missing input gives 3, stdin input works, and JSON
  report contents are checked.
- **Output preservation**: an existing report or requests file is kept (exit
  3) unless `--overwrite` is given. The input is refused as an output even
  with `--overwrite`. No request file or partial file is left after an invalid
  capture. `generate` writes nothing if any target exists. `verify` detects a
  tampered expected file.
- **Streaming**: 2,000,000 rows (about 76 MB) were piped from a child process
  and never written to disk. The validator kept 0 words of major-heap growth,
  under a 4 MiB limit, and a control check confirms the probe does detect
  10 MB of retained data. A 64 MiB single line with a 4096-byte limit was
  rejected as `line_too_long`, also with bounded heap.
- **Request limit**: 65536 pairs are accepted, with last index 65535. The
  65537th pair is a `request_limit` error, reported at its exact line.

Not tested: real Databento captures, and the main team's replay adapter
comparison (that integration belongs to the lead). Hardware and UART are out
of scope.

## Fixture manifest locations

- Index: `external/databento_audit/fixtures/index.json`
- Valid sessions: `external/databento_audit/fixtures/valid/<name>/{trades.csv,expected_requests.csv,manifest.json}`
  - `01_alternating` (100 requests), `02_faster_symbol_a`, `03_faster_symbol_b_reversed_first`,
    `04_unrelated_symbol_interleaved`, `05_late_second_symbol_trailing`, `05b_single_symbol_only`,
    `06a_precision_cent_boundaries`, `06b_precision_above_2_53`, `07_quoted_crlf_long_timestamps`,
    `08_header_only`, `09_extra_columns_reordered`
- Expected failures (not trading sessions): `external/databento_audit/fixtures/expected_failure/<name>/{trades.csv,manifest.json}`
  - `empty_file`, `missing_header`, `missing_price_column`, `duplicate_header`, `field_count_extra`,
    `field_count_short`, `blank_line`, `truncated_quote`, `malformed_quote`, `bare_carriage_return`,
    `line_too_long` (manifest sets `max_line_bytes` 128), `invalid_number`, `missing_price`,
    `negative_price`, `negative_price_unrelated_symbol`, `undefined_price`, `int64_overflow`,
    `wire_out_of_range`, `invalid_timestamp`, `empty_symbol`

For integration, the lead's replay adapter should be configured from each
valid manifest (`symbol_a`, `symbol_b`, `quantum_nanos`). Its logged requests
should then be compared with `expected_requests.csv`, using the header
`index,item1,price1,item2,price2` and LF line endings.

## Proposed contract questions

1. **Extra columns.** Real Databento CSV output has many columns (`ts_recv`,
   `rtype`, `size`, ...). I accept extra columns and any column order
   (fixture `09_extra_columns_reordered`). Should the adapter require exactly
   `symbol,ts_event,price`?
2. **Wire range on superseded trades.** I reject an out-of-range price for a
   configured symbol even if a later trade coalesces it away. The alternative
   is to check only emitted prices.
3. **Corrupt unrelated rows.** A negative, overflowing or malformed price on
   an unrelated symbol fails the capture
   (`negative_price_unrelated_symbol`). Wire range is not checked for
   unrelated symbols. Is that the intended strictness?
4. **ts_event edge values.** Leading zeros and `18446744073709551615`
   (Databento's undefined timestamp) are currently accepted. Monotonicity is
   not required, only counted. Should undefined timestamps be rejected?
5. **Symbol matching.** Matching is byte-exact after CSV unquoting, with no
   trimming or case folding, and an empty symbol is an error. Confirm that the
   adapter does not trim.
6. **Empty inputs.** Header-only is valid with zero requests, and a zero-byte
   file is invalid. Blank lines anywhere, including a trailing extra blank
   line, are field-count errors. A UTF-8 BOM is not stripped.
7. **More than 65536 pairs.** I treat the 65537th pair as an error. Should
   the streamer instead end the session and restart at index 0?
8. **Capture parameters.** My understanding of Databento's historical API,
   not re-checked against the linked docs in this session, is that integer
   nanodollar prices, integer `ts_event` and a `symbol` column require CSV
   requests with `pretty_px=false`, `pretty_ts=false` and `map_symbols=true`.
   The lead should confirm this when capturing real data.
