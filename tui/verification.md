# Phase 1 verification

Scope: shell, theme, complete status header, five empty bordered panels, focus,
footer, help overlay, resize handling, and deterministic Async mock market stream.
All application code is under tui/. No Git commands were run in this workspace.

## Final build and tests

Exact commands:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test
```

Real result for each: exit code 0; stdout/stderr empty. The suite contains 15
expect tests. Its successful run includes the controlled-time live Async stream
regression and the uppercase Ctrl-C regression. No unrun tests are claimed.

Initial focus regression failed (Market repeated instead of cycling). Later
regressions exposed queued-key state capture and physical Ctrl-C encoding; those
were fixed in production and retested. Two deliberately empty render expectations
were populated only after examining the actual header/minimum-layout output:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune promote
```

Real output:

```text
Promoting _build/default/tui/test/shell_tests.ml.corrected to
  tui/test/shell_tests.ml.
```

## Real terminal launches

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 120 rows 36 && dune exec -- tickweave console --mode mock
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 120 rows 36 && TERM=xterm-256color COLORTERM=truecolor dune exec -- tickweave console --mode mock
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 100 rows 30 && TERM=xterm-256color COLORTERM=truecolor dune exec -- tickweave console --mode mock
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty cols 100 rows 30 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- tickweave console --mode mock
```

Observed five bordered panels and complete status/footer at both sizes. The MOCK
snapshot counter advanced, Tab moved focus, help appeared, and q exited with code
0, including from Help. The final 100×30 launch accepted raw physical Ctrl-C
(byte 0x03), exited 0, and restored the terminal. The inherited environment has
NO_COLOR=1; the final command unset it only for the child and produced truecolor
SGR sequences. The global preference was preserved.

Actual earlier terminal rows (escape codes omitted):

```text
tickweave MOCK link:UP build:m01 run:demo-03 cfg:✓ACKv12 ○DISARMED book:✓VALID loss:0 14:07:16.193
Tab/⇧Tab focus  1–5 panel  ? help  q quit  · MOCK stream                               focus: Market
```

## CLI stubs and rejection

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune exec -- tickweave console --mode simulation
```

Exit 0, actual output:

```text
SIM: not yet connected
```

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune exec -- tickweave console --mode hardware
```

Exit 0, actual output:

```text
HW: not yet connected
```

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune exec -- tickweave console --mode mock --rate 1e-300
```

Expected rejection, exit 1, actual output:

```text
--rate must be finite and in [0.1, 60] Hz
```

## Interface checks and boundaries

Read the full supplied TUI prompt and source-of-truth sections 5, 8, 9, 14.
Inspected installed interfaces before using Bonsai Term APIs: bonsai_term.mli,
view.mli, attr.mli, event.mli, effect.mli, geom.mli, border-box interface,
bonsai_term_test.mli, Bonsai cont.mli (state/clock/reducer), and test handle APIs.
Also read the installed hello_world, responsive_dimensions, clock and events
examples. Installed Dimensions lives in geom.mli, not a separate dimensions.mli.
No dependencies were added; no switch was changed.

Read-only code review approved the final code after timer bounds, help quit,
queued-key routing and Ctrl-C fixes. There are no unresolved important findings.
All OCaml implementation files are under 400 lines.

Phase 2–5 functionality is intentionally deferred: market ladder/rules content,
decision generation/history/inspection, apply lifecycle/controls, command palette,
and hardware/simulation connections. Scenario names for admitted/blocked/received
are shell/status fixtures only in this phase. MOCK remains explicit; the fake
ACK is mock application state, never hardware evidence. C0 types remain provisional.

## Files created or changed

README.md was updated. All other files listed below were created; _build artifacts
are omitted. The existing .gitignore was not changed.

- /Users/vishalnaveen/Downloads/tickweave-tui/AGENTS.md
- /Users/vishalnaveen/Downloads/tickweave-tui/README.md
- /Users/vishalnaveen/Downloads/tickweave-tui/dune-project
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/AGENTS.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/app.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/backend_intf.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/bin/AGENTS.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/bin/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/bin/main.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/config_review.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/footer.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/help_overlay.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/history_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/inspector.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/keymap.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/market_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.mli
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/AGENTS.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/contracts.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model_adapter.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/rules_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/status_bar.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/AGENTS.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/shell_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/theme.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/verification.md
