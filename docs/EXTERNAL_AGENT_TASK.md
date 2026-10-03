# External agent assignment: independent Databento fixtures and capture validation

Work on the data streaming system only. Your deliverable is a standalone OCaml fixture builder and capture validator. It can be built and tested immediately, without waiting for the team's Databento adapter, UART implementation, API credentials, or FPGA.

## Exact directory and branch

An isolated Git worktree has already been created for you:

```text
Working directory: /home/srijan/tickweave-external
Your branch:       codex/databento-fixtures
Starting commit:   7d89ef9
Main team folder:  /home/srijan/tickweave
Main team branch:  codex/databento-streamer
```

Start with:

```sh
cd /home/srijan/tickweave-external
git branch --show-current
git status --short
```

The branch must be `codex/databento-fixtures`. Keep all work in this worktree. Do not switch branches, modify files, run cleanup commands, or commit anything in the main team's directory. If your agent's sandbox does not allow this directory, request normal access to this explicitly assigned directory; do not bypass sandbox controls.

Your copy begins from the repository's original commit, so it intentionally does not contain the team's uncommitted implementation. You do not need that implementation. The frozen file contracts below are your integration boundary. If applicable AGENTS.md instructions exist in your checkout or its parents, read them before editing.

## Owned files and independent build

Own only:

```text
external/databento_audit/dune-project
external/databento_audit/dune
external/databento_audit/*.ml
external/databento_audit/test/*
external/databento_audit/README.md
external/databento_audit/fixtures/*
external/databento_audit/REPORT.md
```

Create a standalone Dune project under `external/databento_audit/`. Use OCaml standard library and Unix; Yojson is allowed if needed for reports. Keep the tool deterministic and all implementation/tests in OCaml. Do not depend on the main project's `Tickweave` library or modify its Dune files. Build/run from your own project directory:

```sh
cd /home/srijan/tickweave-external/external/databento_audit
opam exec -- dune build
opam exec -- dune runtest
```

Choose executable names that do not collide with `tickweave-stream`. Keep generated build files, secrets, and large data out of commits. Add a project-local `.gitignore` if needed. This standalone project remains a separate tool when merged.

## Frozen integration contracts

Databento-normalized trade CSV:

```csv
symbol,ts_event,price
AAPL,1790982000000000000,200000000000
MSFT,1790982000000000001,400000000000
```

`symbol` is the configured raw input symbol, `ts_event` is an unsigned decimal event timestamp preserved exactly as text, and `price` is an integer nanodollar price parsed as OCaml `int64`. One dollar is `1000000000` nanodollars. No float conversion is allowed. CSV quoting and CRLF are supported. Reject negative, undefined (`9223372036854775807`), overflowing, malformed, or missing prices. Require one unambiguous header for each required column and exactly the declared number of fields per row. Preserve record order; do not sort or invent timestamps.

The streamer's two symbols are configured explicitly. A request is emitted after at least one new trade from BOTH configured symbols since the previous request. Repeated trades from a faster symbol are coalesced to its latest price before the slower symbol updates. These are paired test samples, not all market events. Unknown symbols do not supply either price. No forward fill is used to create the first pair.

Convert selected prices explicitly:

```text
wire_price = floor(nanodollar_price / quantum_nanos)
```

Default `quantum_nanos=10000000` is one cent. Require a positive quantum and wire prices in `0..65535`. Reject instead of clamping or wrapping. Item A is decimal `17` (`0x11`), Item B is decimal `34` (`0x22`). Index zero starts each session. The original execution plan's request replay contract is:

```csv
index,item1,price1,item2,price2
0,17,20000,34,40000
1,34,39900,17,20100
```

Indices must be consecutive from zero, count at most 65536, both item IDs distinct and present in each row, and unsigned 16-bit prices. Alternating slot order is an explicit fixture choice. Generate expected request rows for known fixture cases; do not implement moving-average actions, UART transport, FPGA logic, or a Databento connection.

## Deliverable 1: deterministic fixture builder

Provide an independently runnable CLI, for example:

```text
fixture-tool generate --output-dir fixtures/generated --seed 42 --pairs 100
```

Finalize actual syntax in your README. Generate small normalized trade CSVs and independently derived expected integer request CSVs. A seed must yield identical contents across repeated runs; timestamps must be deterministic too. Include at least these fixtures:

1. Exactly alternating AAPL/MSFT updates, producing a 100-packet session.
2. Faster AAPL: several A updates before B; expected A price uses the last update.
3. Faster MSFT and a reversed first-symbol arrival order.
4. An unrelated-symbol record between relevant updates.
5. No initial second symbol and an unmatched trailing trade, producing fewer pairs with a reported incomplete pair.
6. Precision: nanodollars above `2^53`, fractional quantum remainders, zero, the maximum accepted uint16 boundary, and its first rejected value. Supply a suitable larger quantum for large-price successful cases.
7. Quoted symbols, embedded CSV quotes, CRLF, and exact long decimal timestamps.
8. Malformed corpus: missing/duplicate header, wrong field count, truncated quote, invalid number, negative/undefined price, int64 overflow, and out-of-range wire conversion.

A malformed corpus should be clearly labelled as expected failure; it is not a valid trading session. Each fixture needs a manifest with its quantum, configured symbols, seed where applicable, expected input count, expected pair/request count, and expected validity or error category. JSON or plain documented text is acceptable. Keep fixtures small enough to review.

## Deliverable 2: capture validation

Provide an offline CLI, for example:

```text
fixture-tool validate --input capture.csv --symbol-a AAPL --symbol-b MSFT \
  --quantum-nanos 10000000 --report report.json
```

It reads an existing normalized capture, validates the contract, and reports record counts, per-symbol counts, resulting pair count, unmatched trailing symbols, and the first exact row/field/value causing failure. Return zero for valid captures and nonzero for malformed or unrepresentable subscribed-symbol data. Do not silently skip corruption. State whether unrelated valid symbols are counted/ignored for pairing. Handle an empty input or header-only file explicitly.

Bound memory: validate incrementally, retaining only the latest pending ticks for the two symbols and counters. Add a reasonable configurable maximum line length. Do not load an arbitrarily large capture into memory. Use exact int64 arithmetic and overflow checks. Reports must identify units and must not claim FPGA acceptance or API completeness.

Creating requested output files is allowed, but preserve existing reports/fixtures by default or require an explicit overwrite flag. Never contact Databento; all inputs are local dummy data. Avoid reading any environment API key.

## Verification

Your automated tests must run independently in the worktree's standalone Dune project. Cover all valid/invalid fixtures, reproducibility, exact arithmetic, conversion boundaries, quoted parsing, incomplete pairs, output preservation, CLI exit codes, and large-input streaming behavior. Derive expected rows by hand for small cases rather than copying the main team's pairing or parser implementation.

The main team will later run its replay adapter against your valid trade fixtures and compare logged request fields with your expected request CSV. That later integration is the lead's responsibility and is not a prerequisite for your build/test acceptance. Do not invent adapter stubs or wait for the main code.

Useful primary references for units and fields:

- https://databento.com/docs/api-reference-historical?historical=http
- https://databento.com/docs/standards-and-conventions/common-fields-enums-types

The assignment follows section 3A of `/mnt/c/Users/srija/Downloads/GQH_Team_Execution_Plan.md`, adapted to the user's explicit OCaml/Databento request. The unrelated broader Tickweave proposal does not expand this task.

## Handoff

Write `external/databento_audit/REPORT.md` including files changed, exact commands run, toolchain versions, passed/failed/untested cases, fixture manifest locations, and proposed contract questions. Report real evidence; do not label fixtures or mock results as hardware results.

Commit only your owned files on `codex/databento-fixtures` and return the full commit SHA, branch, directory, and report path to the user. Do not push, publish, open a PR, program hardware, contact paid services, or merge into the main branch. The lead will inspect and integrate your isolated commit. You can work immediately and in parallel; no production interface edits are required.
