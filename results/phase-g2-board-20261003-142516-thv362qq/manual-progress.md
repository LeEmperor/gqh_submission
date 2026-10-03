# G2 manual progress — October 3, 2026

Status: **Locally verified — awaiting manual checks**; partial board evidence received.

User reports the competition bitstream was generated/programmed, LED0 heartbeat
works, and LED1 starts off and remains off throughout quick testing. Official
quick output supplied in chat shows all 21 responses, 16 warm-up and 5 scored
updates OK, reserved zeros, swapped slots and final PASS. The current saved
quick/console.log also shows 21 responses and final PASS, independently checked
and copied to quick-pass-observed.log. Its individual timing values differ from
the pasted output, so those are distinct observations; do not merge their timing
samples or assume this latest log is the exact pasted invocation.

The earlier index-zero timeout is retained in the previous fresh results folder;
its cause has not been established. No RTL change was made to resolve it.

Official robust PASS is now verified against saved console, summary and CSV:
100 responses, 84/84 scored packets, 168/168 individual actions, zero timeouts.
The supplied terminal output matches the saved summary: average successful
host round trip 16808.59 us (16.809 ms), including warm-up and host/USB overhead.
All 100 CSV rows were checked: 16 ignored warm-up rows and 84 CORRECT rows with
both actions/packet marked YES. Original artifacts are preserved with hashes in
robust-pass-observed/. The ignored warm-up rows do not establish full all-byte
warm-up correctness; the custom fixture is still required.

A run-custom.sh launcher prepares a new output folder each invocation and runs
the archived 1,394-row fixture on one serial connection (13 index-zero sessions).
It uses --stop-on-timeout and preserves console/CSV/JSON outputs. Launcher syntax
was checked only; the agent did not run this hardware test.

Remaining: custom full-range/warm-up/swaps/repeated-session checks;
startup/reset/fault/TX idle follow-ups; whole-design resource/memory/clock/timing
review and archival; exact programmed-bitstream identity. Quick/robust PASS alone
does not close F/G1/G2/G or the required fully identified measured baseline.
The initial timeout's cause remains unestablished. No RTL change was made.
The agent did not open serial or operate Gowin/programming tools.

## Custom board replay — verified PASS

Saved JSON and all CSV rows verified: 1,394/1,394 OK, including 208 warm-up
and 1,186 scored rows, 13 sessions on one runner connection. No mismatches,
SHORT/TIMEOUT, abortion, unsolicited-byte events or trailing unsolicited bytes.
Mean 16.927633 ms, median 16.939633 ms, p95 17.138110 ms (custom runner latency).
The fixture covers full unsigned prices, equality/truncation, swaps, wraps and
repeated index-zero sessions. Evidence/hashes are in custom-Me94C2ml/.
This closes the required custom response correctness replay, not all G2 checks.

The organizer placement supplement now additionally requires normal robust →
full-range practice without intervening reset/reprogramming. A prepared
run-qualification-practice.sh launcher runs PORT-only copies, preserves original
LF/CRLF line endings and creates fresh output directories each invocation.
Copy integrity, Python compilation and shell syntax were checked; hardware
execution remains manual. Both scripts open separate serial connections; the
custom replay above supplies the separate one-connection repeated-session check.

Remaining: the new qualification practice pair; startup/reset/fault/TX-idle
follow-ups; clock-routing review/whole-design report archival and exact programmed
bitstream identity. F/G1/G2/G/H are not marked complete.

## Supplemental consecutive practice pair — verified PASS

qualification-qb8kuABs/ contains normal robust followed by full-range practice
from the same launcher, with no reset/reprogramming step in the launcher.
Both CSVs checked: 100 responses, 16 ignored warm-up rows, 84 CORRECT scored
rows with both actions correct, no timeouts. Normal average 16.811 ms
(16811.46 us); full-range average 16.914 ms (16913.94 us), seed 0x1F00D16B.
Evidence hashes are preserved in that folder. Human intervention between tests
cannot be inferred from logs; the launcher explicitly requested no reset.
This is practice coverage, not the unpublished official judge qualification.

All prepared response correctness tests now pass. Remaining acceptance is
programmed .fs identity, remaining physical startup/reset/fault/idle checks,
and clock-routing/timing review acknowledgement. No phase completion inferred.

## Physical busy-fault/reset check — verified PASS

status-fz9wj7qq/summary.json confirms heartbeat observed, LED1 initially off after
button reset, correct accepted response 0000110022000000, no response to the
request sent after busy fault, LED1 latched on, LED1 cleared after S2/KEY2 reset,
and fresh correct response 0000110022000000 after reset. The script also checked
that no extra byte followed reset recovery. User terminal reports PASS. Summary
integrity hash saved in the status directory. No agent serial operation occurred.

Remaining acceptance now: exact programmed .fs path/mode; fresh configuration/
power-up startup and physical idle-high TX confirmation; acknowledgement of the
archived whole-design timing/clock-routing review, including PR1014. Reset,
heartbeat and busy-fault indication/recovery checks no longer remain pending.
F/G1/G2/G/H are not marked complete until remaining required evidence is supplied.

## Fresh startup — PASS; final identity work deferred by user

startup-2ld34y_z/summary.json verifies fresh programming without button reset,
heartbeat working, LED1 off, exact response 0000110022000000 and no unsolicited/
surplus bytes. User confirms SRAM programming of test_proj1.fs, current SHA-256
fac34993701c469f322eba8b77ef9c4f012a7fa2ea086aea8d3662d2bbd773d4.
This differs from the previously archived .fs. Review of the archived PR1014
caveat was acknowledged; that acknowledgement does not identify current reports.
Physical TX idle was explicitly unmeasured, so it remains unconfirmed.

User explicitly defers .fs wrapping, final build identity and matching-report
work until tomorrow before submission. Do not pursue or request this work now.
Keep all earlier passing test evidence historical; final freeze must tie source,
RTL, reports, programmed .fs and final acceptance runs to the selected image.
No new report/bitstream archive or source comparison was performed in this update.
G2 remains locally verified — awaiting the deferred final manual checks.

### F–G closure — user-authorized, October 3, 2026

**F, G1, G2 and overall G: COMPLETE.** The user explicitly requested closure
based on fresh synthesis/programming and the passing local and board tests.
Official quick PASS; normal robust and full-range practice each pass 84/84 scored
packets, 168/168 actions and zero timeouts; custom replay passes 1,394/1,394 rows
across 13 sessions with no unsolicited/trailing bytes. Physical busy-fault/reset
recovery and fresh SRAM startup without button reset also pass. Evidence is in
`results/phase-g2-board-20261003-142516-thv362qq/`.

The user waives remaining SHA/source/report/bitstream association bookkeeping
and a separate physical TX-idle measurement as F/G closure preconditions, accepting
the functional results. Physical TX idle remains unmeasured; exact association
of the latest .fs with the earlier report archive remains unresolved. These
items are not falsely recorded as performed. PR1014 remains the documented
routing caveat acknowledged by the user. No additional published grader run is
required to close F/G; unpublished judge qualification remains an event result,
not an agent-run acceptance step.

This explicit user decision supersedes earlier pending F/G statuses and their
closure requirements for the accepted direct 27 MHz implementation. Historical
logs/status entries remain intact. Final submission-image packaging remains
scheduled for tomorrow at the user's direction; H's optimization/baseline work,
optional P and submission freeze are not marked complete by this closure.
