# Reused independent oracle

Source: `datafactory`, revision `73f42c2d3ecb8a5d178903a7c254a3f9c81d06a8`,
`tools/test_data_factory/`. Read-only Git inspection found a clean source checkout.
No runtime reference to that checkout is used by these tests.

`SOURCE.json` records every upstream filename and SHA-256, its local destination,
and whether copied unchanged. The focused test verifies the unchanged copies.

Copied byte-for-byte:

- `model.py`: independent direct-window algorithm, recomputes both averages with
  `sum()`. **No oracle changes.**
- `factory.py`: deterministic fixture generation and saved-fixture validation.
- All 22 fixture files: seven scenarios, eight sessions, 800 records; original
  metadata, request CSVs, JSONL records and hashes are preserved.
- `README.md` as `UPSTREAM_README.md`: historical upstream instructions; use the
  testing-local README and commands for this package.

Deliberately adapted:

- `test_factory.py`: only `check_ocaml` import/references changed to `log_check`.
  All 22 checks remain, including the hand-checked examples and a second
  complete-history implementation that independently validates model answers.
- `log_check.py`: verbatim pure validator section of upstream `check_ocaml.py`
  (`CheckFailure` through `check_log`), with a local docstring/import preamble.
  Excludes its subprocess runner and CLI for the unrelated OCaml streamer.
  Four upstream negative/positive log checks still run. The source hash of the
  complete upstream `check_ocaml.py` is retained in `SOURCE.json`.
- `run_checks.py`: upstream Python unit/verification/regeneration checks retained;
  removed the `--python-only` option and OCaml-streamer invocation so Python
  checks are always independent. No streamer source or dependency is imported.

Local Phase F `../run_checks.py` adds the real-engine packet adapter and shared
edge trace consumed by Hardcaml Cyclesim and Icarus. Expected actions come from
unchanged `ReferenceModel`; scalar sums use complete stored windows. The adapter
owns the index classification, item routing and shared pointer only in tests.
