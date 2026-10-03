# Phase 4 verification

Phase 4 configuration review is complete. No Phase 5 work was started. All application edits stayed in this workspace; no git commands or new raw ANSI captures were used. Existing root dune-project was retained. All changed OCaml modules are below 400 lines.

## Implemented behavior

The frozen Config_contract module defines proposals, validation, Apply_proposal/Reconcile commands and backend progress events. It compiled before workers began; workers did not edit it. Three workers owned separate backend/modal/stepper files and used _build_a/_build_b/_build_c. Lead integrated app routing, dimmed dashboard, command serialization and regression coverage, then reviewed every changed module against the supplied spec. Worker directories have been deleted; normal _build remains.

c opens a centered, opaque zcat review modal. Target/connected build and base/active ACK version are compared. The diff highlights changed values and flags invalid ranges; deployment badges and all four validation checks are present. Parameter-name selection and the actual textbox validate live. Input owns dashboard keys, Esc discards the draft, and A followed by exactly apply + Enter sends one command.

The mock backend alone owns all six ACK stages. Parameters and header ACK stay v12 until activation ACK v13. Failure stops at its named step, keeps the engine DISARMED, never activates or automatically retries. Lost activation stays UNKNOWN with last ack v12 and offers only a backend reconciliation read. Reconciliation confirms the mock last-ACK v12/DISARMED state; it does not invent a successful activation. Fresh externally supplied plans are supported after known terminal states; old proposal IDs remain blocked. New decisions carry cfg v13 after ACK; older history and frozen Inspector evidence remain cfg v12.

The completed modal now says APPLIED rather than awaiting acknowledgment. UNKNOWN from the engine or configuration overrides retained old failure progress. An asynchronous poll started before Apply cannot roll back the accepted command.

## Final commands and real output

The final integrated command was:
```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build && dune test && _build/default/tui/test/.tickweave_tui_tests.inline-tests/inline-test-runner.exe inline-test-runner tickweave_tui_tests -source-tree-root tui/test -show-counts -strict
```

Exit 0. dune build and dune test emitted no output. The uncached direct full expect runner reported:
```text
96 tests ran, 0 test_modules ran
```

This includes the 60 prior tests and 36 Phase 4 regressions. Required stale/range/input/failure/unknown/header/version tests pass. Additional regressions cover backend timing, duplicate commands, fresh plans, unknown precedence, post-ACK action text and late polling.

Workers also ran these exact isolated build/test commands with the same required prefix:
```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build --build-dir _build_a
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test --build-dir _build_a
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build --build-dir _build_b
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test --build-dir _build_b
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build --build-dir _build_c
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test --build-dir _build_c
```

Focused worker results before final integration: backend initially 10 tests, then 11 after the consecutive-plan review fix; modal 9 tests; stepper/version 8 tests. Each focused runner exited 0. Their earlier full runs exposed integration regressions; those results were not treated as the final passing suite.

Terminal harness command:
```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && python3 tui/test/phase4_terminal_check.py
```

The harness launched real 120×36 terminals, pressed c/A/apply/Enter, retained decoded text only, inspected a post-ACK decision in update_ok, and quit both processes cleanly. The final exact child commands and real output are below.

### update_ok

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty rows 36 columns 120 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor ./_build/default/tui/bin/main.exe console --mode mock --scenario update_ok
```

```text
Duration: 12.56 seconds; exit code: 0
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v13 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 17:04:50.149
```

Observed pending header:
```text
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 ◐ APPLYING 4/6 │ ○ DISARMED │ book ✓VALID │ trace loss 0
```

Observed modal rows:
```text
│ #9    13:3│ ✓ ACK v13                                                                                    │           │
│ #10   13:3│ ✓ APPLIED — ACK v13 · Esc close                                                              │           │
```

### lost_at_activate

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && stty rows 36 columns 120 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor ./_build/default/tui/bin/main.exe console --mode mock --scenario lost_at_activate
```

```text
Duration: 12.53 seconds; exit code: 0
tickweave ▸ MOCK LOST │ build m01 │ run demo-03 │ cfg ?UNKNOWN last v12 │ ? UNKNOWN │ book ✓VALID │ trace loss 0
```

Observed pending header:
```text
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 ◐ APPLYING 4/6 │ ○ DISARMED │ book ✓VALID │ trace loss 0
```

Observed modal rows:
```text
│ imbalance │ ? STATE UNKNOWN — last ack v12                                                               │           │
│ #2    13:3│ ? activate · indeterminate: MOCK activation acknowledgment missing                           │           │
│ #3    13:3│ ? STATE UNKNOWN — last ack v12                                                               │           │
│ #4    13:3│ r reconcile                                                                                  │           │
│ #5    13:3│ r reconcile · Esc close                                                                      │           │
```

update_ok: final Inspector capture contains MOCK FROZEN and cfg v13. lost_at_activate: both the result and final UNKNOWN captures retain v12 and contain neither v13 nor disabled. Header assertions specifically check the first line so matching panel text cannot mask an incorrect header.

Earlier Dune-exec previews also passed both scenarios for 12.52 seconds. A later Dune launcher rerun stalled and hit macOS process-group signal restrictions, so final evidence uses the already-built executable directly; it passed both runs above. One earlier stalled dune build was interrupted and rerun. Final build/test results are the clean run above, not those interrupted attempts.

## Interface and review checks

Installed View, Attr, Event, Effect, test, border-box, textbox, scroller, spinner and Bonsai actor/Clock/Edge interfaces were opened before use under /Users/vishalnaveen/.opam/5.2.0+ox/lib. No packages were installed and no toolchain settings changed. Textbox input handling was checked against the installed implementation as well.

Lead reviewed the worker changes against the full prompt and source-of-truth requirements. Independent OCaml review found the completed-plan acceptance and retained-progress UNKNOWN issues; both were fixed, tested and re-reviewed with no remaining material findings. Python review approved header-specific/final-UNKNOWN assertions, direct binary launch and bounded cleanup. This remains logical MOCK verification; SIM/HW still print not yet connected.

## Files changed

- /Users/vishalnaveen/Downloads/tickweave-tui/README.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/config_contract.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/model/contracts.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/backend_intf.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/dune
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_backend.mli
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/mock_apply.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/config_review.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/config_review_state.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/config_stepper.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/config_version.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/status_bar.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/app.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/theme.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/history_panel.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/footer.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/help_overlay.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/bin/main.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/backend_lifecycle_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/config_contract_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/config_review_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/config_stepper_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/config_version_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/config_integration_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/shell_tests.ml
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4_terminal_check.py
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-results.json
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/verification-phase4.md
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-lost_at_activate-applying.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-lost_at_activate-result.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-lost_at_activate-unknown.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-update_ok-applying.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-update_ok-inspector.txt
- /Users/vishalnaveen/Downloads/tickweave-tui/tui/test/phase4-terminal-update_ok-result.txt

All Phase 4 text/JSON capture files contain MOCK evidence. No new .ansi files were produced.
