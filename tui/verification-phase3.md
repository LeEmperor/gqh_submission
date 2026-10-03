# Phase 3 verification

Scope: decision history and frozen Inspector from Section 7, plus the requested fixed-admission semantics. Phase 4 was not started. Work remained in the tickweave-tui project; no Git commands were run.

## Implemented

- Persistent bounded FIFO ring of 10,000 recorded decisions; only viewport rows become text views inside the installed scroller.
- Stable (run ID, decision ID) selection. j/k, g/G and Ctrl-d/Ctrl-u use the scroller less handler; single g completes its installed gg binding. G returns to an unselected live tail.
- Scrolled, selected and paused history holds its records and position, counts unseen arrivals, and does not move selection. Space toggles pause; its title shows ⏸ PAUSED. Counts during a pause are tracked separately from earlier unseen arrivals.
- Live bottom arrivals highlight for one display frame. Revision tokens prevent an old after-display clear from clearing a newer highlight.
- Actual Bonsai textbox with six filters. Actor routing isolates all global shortcuts, including queued /qjTab and Esc+Tab without an intermediate redraw. Logical text/cursor mirrors the installed editing keys so queued Enter validates every preceding edit.
- Enter stores the complete selected record independently of live state. Inspector shows run/build/config/slot/snapshot, recorded bid/ask, predicate values, candidate, declared bounds, admission/reason and recorded receipt time. Software predicate reconstruction is labelled (reconstructed) in muted italics. MOCK appears in the history/Inspector labels.
- Declared MOCK checks: engine armed, valid book, order quantity in [1, 5] u and candidate price in [1001, 1005] t. Normal rule quantity is 1 u; blocked fixture quantity is 6 u. Matches below 1001 t occasionally block on the price band. Liquidity is not an admission bound.
- Deterministic MOCK decision time begins at 13:37:00 UTC. Some admissions have a separately recorded MOCK receipt 2 ms later; admission does not imply receipt.
- At 100 columns rows use an 8-character time and ✓A / ✓R / ✗B; the Inspector retains full timestamps and reasons. Unicode-aware field padding keeps no-signal and MATCH columns aligned.

## Installed interfaces opened before API use

Library root: /Users/vishalnaveen/.opam/5.2.0+ox/lib

- bonsai_term_components/scroller/bonsai_term_scroller.mli: component, Action constructors, Scroll_position, less_keybindings_handler, inject, stuck_to_bottom.
- bonsai_term_components/textbox/bonsai_term_textbox.mli: component, is_focused, string, handler, set.
- The scroller and textbox .ml implementations were read to confirm gg handling, offsets and editing semantics.
- bonsai/cont.mli: actors, Clock and Edge including After_display. bonsai_term/view.mli, event.mli, geom.mli, attr.mli and effect.mli; border-box and test interfaces were also checked.
- Scroller/textbox Dune libraries were already installed. No package installation or toolchain changes.

## Final build and tests

Exact commands:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test
```

Real final process results:

```text
dune build: exit 0; stdout/stderr empty
dune test:  exit 0; stdout/stderr empty
60 expect tests total (21 new Phase 3 tests).
```

The required cases pass: scrolled arrival keeps rows/selection/offset; selection survives viewport removal and live-ring eviction; pause freezes rows and counts arrivals; textbox swallows q/j/Tab; Inspector stays identical after newer decisions. Additional passing cases cover actual half-page keys, live follow, all six filters, hidden selection, the minimum-size Inspector, queued key ordering, same-sized run replacement, same-sequence receipt update, fixed admission bounds and controlled-frame highlight expiry.

The initial semantics and stale-log regressions failed as expected before fixes. Rendering goldens were reviewed before dune test --auto-promote; no uncaught-exception expectations were accepted.

## Real terminal previews

Each child ran in its own PTY with the dimensions below. Timer began after the first dashboard appeared. Keys: at 2 s, 3/g/Enter; at 4 s open /, at 4.3 s Ctrl-u then blocked, at 4.6 s Enter; at 6 s G; at 7.1 s /, at 7.4 s Ctrl-u then all, at 7.7 s Enter; at 8 s Space; at 12 s q. The filter remained on screen between edits and Enter. A snapshot was saved at about 11.7 s, before quitting.

An initial capture parser omitted ANSI CSI E (next-line cursor movement). It was corrected and both previews repeated; the final snapshots below are backed by raw ANSI captures.

### 120x36

Exact terminal child command:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty rows 36 columns 120 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
```

Real output/result:

```text
seconds before q: 12.002
exit code: 0
raw captured bytes: 1010876
filter seen: true
paused title seen: true
new-arrival pill seen: true
Inspector remains MOCK FROZEN #1: true
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:17:16.997
```

Observed rows from the saved terminal:

```text
│     55 ██████▉     1002│ 1005 ████████▉       65 │ │ matched 26  admitted 23  blocked 3                              │
│ spread 1 t   mid 1003.5 t                        │ │ MOCK FROZEN #1 · 13:37:00.250                                   │
│ ask                            ⠐⠾⢶⠳⣶⣴⠒⠄ last 60s │ │ cfg v12 · slot 0 · snapshot #1                                  │
│ #20   13:37:05.000 ·     no signal               │ │ receipt ✓ received 13:37:00.252                                 │
│ #29   13:37:07.250 MATCH BUY 1 @1000 ✗BLK price  │ ╰─────────────────────────────────────────────────────────────────╯
│ ↓ 15 new (15 while paused)                       │ │                                                                 │
```

### 100x30

Exact terminal child command:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty rows 30 columns 100 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
```

Real output/result:

```text
seconds before q: 12.006
exit code: 0
raw captured bytes: 719761
filter seen: true
paused title seen: true
new-arrival pill seen: true
Inspector remains MOCK FROZEN #1: true
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0
```

Observed rows from the saved terminal:

```text
│     55 ████▏   1002│ 1005 ████▉      65 │ │ matched 26  admitted 23  blocked 3                   │
│ imbalance -0.51 ▼                       │ │ MOCK FROZEN #1 · 13:37:00.250                        │
│ MOCK #46  updates/s 4.0                 │ │ cfg v12 · slot 0 · snapshot #1                       │
│ #24   13:37:06 MATCH BUY 1 @1004 ✓A     │ │ receipt ✓ received 13:37:00.252                      │
│ #29   13:37:07 MATCH BUY 1 @1000 ✗B px  │ ╰──────────────────────────────────────────────────────╯
│ ↓ 15 new (15 while paused)              │ │                                                      │
```

## Review

Code review approved after fixes for same-sized log/receipt refresh and one-frame arrival highlights. Regressions cover both findings; final review reported no remaining issues.

## Files changed or created

- /Users/vishalnaveen/Downloads/tickweave-tui/README.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/contracts.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/admission.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/decision_buffer.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/decision_row.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/filter_editor.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/history_state.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/history_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/inspector.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/app.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/footer.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/help_overlay.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/shell_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase2_fix_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3_regression_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/history_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/inspector_filter_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/history_revision_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3-terminal-120x36.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3-terminal-120x36.ansi
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3-terminal-100x30.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3-terminal-100x30.ansi
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase3-terminal-results.json
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/verification-phase3.md

Raw .ansi captures preserve the real terminal stream, including colors and control sequences; .txt snapshots contain the decoded terminal screen. Earlier phase reports/captures remain historical.

Stopped after Phase 3.
