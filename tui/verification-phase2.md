# Phase 2 verification

Scope: Market and Rules panels plus requested status-header formatting. Application
code remains under tui/. No Git commands were run. The other tickweave folder was
not accessed. No packages were installed or switch settings changed.

## Final checks

Exact commands:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test
```

Real output for each: stdout/stderr empty; exit code 0. All 29 expect tests passed
(16 shell/interaction tests and 13 Market/Rules tests). These include independent
empty, one-sided and invalid-book renders; Rules ON/OFF/UNKNOWN, parameters and
counters; stable rule-ID selection across reordered updates/removal/help; eighth
blocks; time-axis sparkline/gaps/expiry; bounded 60-second history; rate counting;
quantity-only versus price-change flash and expiry at 300ms; exact large/negative
ticks; large quantity/parameter/counter rendering; minimum-size layout and live
Async stream behavior inherited from Phase 1.

Initial four panel tests failed before implementation. Compiler errors encountered
while wiring the modules were corrected. The intentional header/layout changes
and new golden renders were inspected before accepting with:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune promote
```

Actual promotion output:

```text
Promoting _build/default/tui/test/market_rules_tests.ml.corrected to
  tui/test/market_rules_tests.ml.
Promoting _build/default/tui/test/shell_tests.ml.corrected to
  tui/test/shell_tests.ml.
```

A later promotion accepted only the new large-number regression snapshots.

## Real terminal launches

All three ran in a real PTY, emitted truecolor terminal output, rendered their
panels, accepted q, restored the terminal, and exited 0:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 120 rows 36 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 100 rows 30 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 100 rows 30 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario book_invalid
```

The executable path avoids the user's earlier secondary-Dune/public-name lookup
failure. NO_COLOR was unset for each child only. Dune printed build-progress
updates before the alternate screen; the running application emitted ANSI cursor
and color sequences rather than plain logs. The following are actual captured
rows with escape sequences stripped (not reconstructed terminal screens):

120x36:
```text
│    40 ███████████  1000│ 1001 ███▌             12│ │maximum_price 1005 ticks  quantity 1 units                       │
╰───────────[0;38;2;245;166;3…108669 tokens truncated…8;2;11;14;20m  996 ███▌             12│ │maximum_price 1005 ticks  quantity 1 units                       │
│MOCK #52  updates/s 4.0                           │ │                                                                 │
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 14:48:13.657      
│    40 ███████████   995│  996 ███▌             12│ │maximum_price 1005 ticks  quantity 1 units                       │
```

100x30:
```text
14:48:55.780                                                                                        
│qty(u) BID     px(t)│px(t) ASK     qty(u)│ │ask_px ≤ maximum_price → BUY qty @ ask_px             │
│MOCK #26  updates/s 4.0                  │ ╭ Inspector ───────────────────────────────────────────╮
```

Invalid book at 100x30:
```text
│  BOOK INVALID — candidates suppressed   │ │                                                      │
```

The captured 120x36 ANSI stream includes ask flash background RGB 72,37,41 (25%),
bid RGB 19,48,40 (17%), and RGB 15,30,29 (8%), followed by ordinary backgrounds.
The controlled-time regression separately establishes expiration at 300ms.
Mock counters advance only on valid armed matches; the blocked fixture increments
blocked instead of admitted. The invalid fixture counters remain zero.

Header is one row at 120 columns and wraps between whole fields at 100 columns.
Panels/footer remain visible at 100x30. Rules selection/help routing were verified
by deterministic interaction tests; PTY Tab keystrokes were sent but their focus
transition was not established from the truncated capture, so no extra live-key
claim is made.

## Interfaces and review

Before use, inspected installed .mli declarations under
/Users/vishalnaveen/.opam/5.2.0+ox/lib: bonsai_term view/attr/event/effect/geom,
border_box, bonsai_term_test, and Bonsai cont state-machine/Clock/Edge APIs.
View.zcat's first argument is the top layer. Used no unconfirmed Time_source API.
Also confirmed stdlib int64 arithmetic for exact tick display. Read the full TUI
prompt and source-of-truth sections 5,8,9,14.

Read-only code review found numeric cropping and floating-point tick precision
issues; both were fixed and covered by regressions. Re-review approved with no
material remaining findings. Integer display intermediates do not define wire
widths. Rules values come from backend rule records; lifecycle status continues
to distinguish acknowledged, pending, failed and unknown. All evidence is MOCK.

Phase3–5 remain for later: decision history/inspector, apply controls/lifecycle,
command palette/block action and remaining polish. No hardware control was added.
All OCaml files are below 400 lines. Original Phase 1 verification log is retained.

## Files changed

New: market_motion.ml, sparkline.ml, market_rules_tests.ml, verification-phase2.md.
All other files below were updated; dune-project and dependency stanzas unchanged.

- /Users/vishalnaveen/Downloads/tickweave-tui/README.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/app.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/bin/main.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/footer.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/help_overlay.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/keymap.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/market_motion.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/market_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/contracts.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/rules_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/sparkline.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/status_bar.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/market_rules_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/shell_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/theme.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/verification-phase2.md
