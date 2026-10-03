# Phase 2 corrections verification

All five requested corrections are complete. Phase 3 frontend work has not begun.
Only tickweave-tui was changed; no Git commands ran. Dependencies/switch unchanged.

## Behavior

- Header always occupies one row. Drop clock first, abbreviate trace loss to loss,
  compact build/run labels, then omit lower-priority IDs. UNKNOWN and safety states
  remain explicit. Extreme values use width markers rather than truncated digits.
- Seeded mock bid walk mean-reverts toward 1003 t. Each side supplies ten levels;
  every per-level quantity changes on each update, and spread varies from 1–3 t.
- Latest MOCK evaluation records frozen snapshot/configuration inputs, candidate,
  decision/run/snapshot IDs and no-signal/admitted/blocked outcome. No signal when
  ask > 1005 t; rule quantity stays 1 u. A fixed mock-only admission bound requires
  displayed best-ask quantity >= 10 u. Failure gives an explicit quantity reason;
  rule counters distinguish matches, admissions and blocks. The blocked fixture
  can force an admission block. No hardware limit is inferred.
- Invalid ladder/header/bars/separator/border are muted, flash is suppressed, and
  View.zcat places an opaque centered three-row stamp box across the live panel.
- Market fills available depth rows, capped at ten per side: six rows at 100x30,
  nine at 120x36. Panel frames include one column of left/right interior padding.
  Parameters/values use t/u consistently.

## Build and tests

Exact final commands:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test
```

Real output: stdout/stderr empty; exit code 0 for each. All 39 expect tests pass:
16 shell/interaction, 13 Market/Rules, 10 new correction regressions.

Initial regressions reproduced wrapping, fixed quantities/depth/spread/imbalance,
missing mixed outcomes/blocks and missing padding. Golden changes were reviewed
before dune promote. A test quantity-only fixture was corrected to retain its
original best price after the mock starting point changed. Narrow UNKNOWN headers
with invalid books and nonzero/max-int trace loss are separately covered.

Read-only review found a numeric header fallback that could turn loss 10 into loss 1
at 80 columns. A failing regression reproduced it; additional compaction/explicit
width markers fixed it. Re-review found no material remaining issues.

Hand-checked rendered output from the seeded 40-update regression:

```text
40 updates: bid 999..1006 t, ask 1000..1009 t, threshold crossings 11
matched 22 admitted 21 blocked 1 no-signal 18
ask qty 1 u < min 10 u
```

## Real terminal launches

Python orchestrated real PTYs and invoked these exact shell commands. Runtime was
measured after the first application header appeared, excluding build/startup.
After at least 12 seconds, q was sent and the terminal was restored.

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 120 rows 36 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled --seed 42 --rate 4
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 100 rows 30 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled --seed 42 --rate 4
```

Actual PTY observations (ANSI removed):

120x36: 12.01 seconds in app, exit0, last snapshot#47.

```text
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 15:13:25.547
matched 27  admitted 24  blocked 3
last block: ask qty 3 u < min 10 u
```

39 distinct displayed imbalance values captured.

100x30: 12.01 seconds in app, exit0, last snapshot#47.

```text
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0
matched 27  admitted 24  blocked 3
last block: ask qty 3 u < min 10 u
```

39 distinct displayed imbalance values captured.

The 100-column header above is a single actual terminal row. The clock is absent;
no second header row exists. The 47 committed updates yielded 27 matches and 20
no-signal evaluations. Both runs show nonzero blocked counters and a reason.
Complete initial frames and commands are in test/terminal-120x36.txt and
terminal-100x30.txt; test/terminal-results.json contains the timed result metadata.
These are actual captures, not reconstructed screenshots.

## Interface and scope checks

Before changed API use, opened installed bonsai_term view.mli/attr.mli and
bonsai_term_components border-box .mli, plus bonsai_term_test.mli under
/Users/vishalnaveen/.opam/5.2.0+ox/lib. Confirmed hcat/zcat/center/rectangle/text,
pad/crop/dimensions, attributes and opaque border-box padding. No unconfirmed API.
All OCaml files remain below 400 lines. Mock generator state is copied before
advancement, preserving existing same-seed/branch determinism tests.

Decision history/scrolling/inspector remain Phase 3. The latest evaluation record
is backend fixture data only. Receipts, deployment and hardware transport remain
future work. Acknowledged/unknown lifecycle semantics are unchanged.

## Files changed

- /Users/vishalnaveen/Downloads/tickweave-tui/README.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/status_bar.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/contracts.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/market_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/rules_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/shell_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/market_rules_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase2_fix_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/terminal-120x36.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/terminal-100x30.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/terminal-results.json
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/verification-phase2-fixes.md
