# databento_audit

Standalone OCaml fixture builder and offline capture validator for the
Databento-normalized trade CSV contract used by the Tickweave streamer. It has
no dependency on the main `Tickweave` library, never contacts Databento, and
never reads API keys. Dependencies: OCaml stdlib, `unix`, `yojson`.

```sh
cd external/databento_audit
opam exec -- dune build
opam exec -- dune runtest
```

If this directory ends up inside a larger Dune workspace, add `--root .` to
keep the build standalone.

The executable is `_build/default/databento_audit.exe`; it can also be run
with `opam exec -- dune exec ./databento_audit.exe -- <command> ...`.

## Commands

```text
databento_audit generate --output-dir DIR [--seed N] [--pairs N] [--overwrite]
databento_audit validate --input FILE|- --symbol-a SYM --symbol-b SYM
                         [--quantum-nanos N] [--max-line-bytes N]
                         [--report FILE] [--requests-out FILE] [--overwrite]
databento_audit verify --fixtures-dir DIR
```

Exit codes: `0` ok, `1` invalid data or fixture mismatch, `2` usage/config
error (bad flags, non-positive quantum, identical symbols, output equal to
input), `3` output exists without `--overwrite`, or another I/O error.

### generate

Writes the fixture set under `DIR`. `--seed` (default 42) drives the seeded
sessions; `--pairs` (default 100, range 1..65536) sets the request count of
`01_alternating`. Output is byte-identical for the same seed and pairs.

It checks every target before writing anything. If any target exists and
`--overwrite` is not given, it exits 3 and writes nothing. Files are written
to a temporary sibling and moved into place; without `--overwrite` the move
uses `link(2)`, which fails rather than replacing a file created concurrently.
The checked-in `fixtures/` directory is the output of
`generate --output-dir fixtures --seed 42 --pairs 100`, and a test asserts it
is current.

### validate

Streams one capture and writes a JSON report (stdout by default). With
`--requests-out` it also writes the derived request CSV, but only if the
capture is valid. Rows go to a temporary file that is discarded on failure.
`--report`/`--requests-out` never replace existing files without
`--overwrite`, and are refused outright if they name the input file.
`--input -` reads stdin.

Memory is bounded. Only the current CSV record (at most `--max-line-bytes`,
default 65536, counting quoted newlines), the latest pending tick for each
configured symbol and fixed counters are kept. Distinct unrelated symbols are
counted in total, not individually, so memory stays bounded.

### verify

Re-runs every fixture listed in `DIR/index.json` through the validator and
compares validity, error category/line/field/value, accepted record count,
request count, incomplete symbols, and byte equality with
`expected_requests.csv`.

## Contract as implemented

- Header: exactly one column named `symbol`, `ts_event` and `price` (exact,
  case-sensitive, after CSV unquoting). Extra columns are allowed and ignored.
  Every row must have the header's field count. A UTF-8 BOM is not stripped.
- CSV: RFC 4180 quoting (`""` escapes), LF or CRLF line endings, newlines
  inside quotes. A lone CR, a quote inside an unquoted field, text after a
  closing quote, or end of input inside quotes is an error. A blank line is a
  one-field record, so it is reported as a field-count error.
- `symbol`: non-empty, compared byte-exactly with `--symbol-a`/`--symbol-b`
  (case and whitespace are significant).
- `ts_event`: ASCII digits only, value at most 2^64-1. It is kept as text and
  never sorted or synthesized. Decreasing values are counted in
  `ts_event_regressions` for information only.
- `price`: ASCII digits only, int64 nanodollars (1 USD = 1000000000), checked
  for overflow on every digit. Empty prices are rejected as `missing_price`.
  A leading `-` is `negative_price`, `9223372036854775807` is
  `undefined_price`, and values beyond int64 are `int64_overflow`. Anything
  else is `invalid_number`. No floats are used anywhere.
- Unrelated symbols: fully parsed and validated (a negative unrelated price
  still fails), counted in `unrelated_trades`, and ignored for pairing.
- Wire price: `floor(price / quantum_nanos)` in exact int64, and it must be in
  0..65535. It is checked on every trade of a configured symbol, including
  trades later superseded by coalescing.
- Pairing: emit after at least one new trade from both configured symbols
  since the previous request, using each symbol's latest price, then clear
  both. No forward fill.
- Requests: `index` runs consecutively from 0, at most 65536 per session (the
  65537th pair is a `request_limit` error). Item A=17 and B=34. Slots
  alternate: even index is `17,A,34,B` and odd index is `34,B,17,A`.

Error categories: `empty_input`, `missing_column`, `duplicate_column`,
`field_count`, `unterminated_quote`, `malformed_quote`,
`bare_carriage_return`, `line_too_long`, `empty_symbol`, `invalid_timestamp`,
`missing_price`, `negative_price`, `undefined_price`, `int64_overflow`,
`invalid_number`, `wire_out_of_range`, `request_limit`. Reports give the
physical line where the failing record starts, the 1-based data record
number, the field name where it applies, and the raw value (clipped to 256
bytes).

A header-only file is valid with status `valid_header_only`. A zero-byte file
is `empty_input` (exit 1).

## Report fields

`status` (`valid`, `valid_header_only` or `invalid`), `config`, `units`,
`unrelated_symbol_policy`, and `counts`: `data_records`, `symbol_a_trades`,
`symbol_b_trades`, `unrelated_trades`, `coalesced_trades`, `requests` and
`ts_event_regressions`. It also has `incomplete_pair`, `unmatched_trailing`
(pending ticks with line, record, ts_event, `price_nanos` as a decimal string
and wire price) and `error`. On failure, counts cover only records accepted
before the failure. The report scope states that it is not a hardware/FPGA
result and not a Databento API completeness check.

## Fixtures

```text
fixtures/index.json                     list of all fixtures + generator seed/pairs
fixtures/valid/<name>/trades.csv        normalized trade input
fixtures/valid/<name>/expected_requests.csv
fixtures/valid/<name>/manifest.json
fixtures/expected_failure/<name>/trades.csv     deliberately malformed, NOT sessions
fixtures/expected_failure/<name>/manifest.json
```

Each manifest records quantum, configured symbols and item IDs, seed (or null
for hand-written fixtures), max line bytes, expected input records, expected
request count, expected incomplete symbols, expected validity, and the
expected error (category, line, field, value). For expected failures, record
and request counts are those accepted before the failure.

| Fixture | What it covers |
|---|---|
| `01_alternating` | strict A/B alternation, 100 requests (seeded) |
| `02_faster_symbol_a` | 2-5 AAPL trades per MSFT trade; last A price wins (seeded) |
| `03_faster_symbol_b_reversed_first` | MSFT first and faster (seeded) |
| `04_unrelated_symbol_interleaved` | GOOG/TSLA/aapl/MSFT.X/NVDA between relevant updates (seeded) |
| `05_late_second_symbol_trailing` | six A before first B, three trailing A left pending (seeded) |
| `05b_single_symbol_only` | only MSFT, zero requests (seeded) |
| `06a_precision_cent_boundaries` | zero, flooring remainders, max wire 65535 |
| `06b_precision_above_2_53` | prices above 2^53 with quantum 2^48; float would be wrong |
| `07_quoted_crlf_long_timestamps` | quoting, embedded quotes/comma/CRLF, 19-20 digit ts_event |
| `08_header_only` | header with no rows |
| `09_extra_columns_reordered` | wider Databento-style header, columns reordered |
| `expected_failure/*` | 20 malformed cases, one per error class |

Seeded sessions are planned as rounds. A leader symbol updates one or more
times, then the other symbol updates once. Expected requests come from that
plan, and each price is built as `wire * quantum + remainder` with
`remainder < quantum`. So expected rows are not derived from the validator's
parser, division or pairing code. The precision, quoting and wide-header
fixtures are hand-written with hand-computed expected rows.
