# tickweave-tui

Private workspace for the tickweave operator console. Phases 1–4
implemented.

The dashboard has a complete status header, five focusable panels, help, resize
handling, and a deterministic Async MOCK market stream. Market shows a depth
ladder with up to ten levels per side and eighth-block quantity bars, right-
aligned tick/unit columns, spread, midpoint, best-level imbalance, a braille ask
trace over the last 60 seconds, measured updates/s, and a 300ms best-price
flash. Invalid books are muted with a BOOK INVALID — candidates suppressed
overlay. Rules show selected slot, readable predicate, parameters/units,
match/admission/block counters and ON/OFF/UNKNOWN. Selection follows rule IDs
across incoming updates. Numbers never silently lose digits: bars shrink first;
values beyond capacity show VALUE TOO WIDE.

Layout supports 120×36 and the 100×30 minimum. The header always uses one row:
clock is omitted first, then labels/IDs compact as needed. Extreme values
receive explicit width markers instead of losing digits. Every panel has one
column of horizontal padding. Values use t (ticks) and u (quantity units).
Smaller terminals show a resize message. Tab/Shift-Tab and 1–5 focus panels; j/k
or arrows select a Rules slot; g/G choose first/last; ? opens help; Esc
dismisses it; q/Ctrl-C quits. Press c to open configuration review. A pending apply asks
for quit confirmation.

## Build and run

Every command uses the prescribed switch prefix:

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune build
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && dune test
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
```

Use --scenario book_invalid to see the suppression overlay, or --scenario
connected_disarmed for OFF. Optional --seed N defaults 42; --rate HZ defaults 4,
range [0.1,60]. Rate bounds are mock scheduling policy. Same seeds produce same
market updates; the display clock uses wall time independently. The seeded walk
reverts toward a best bid of 1003 t, varies spread between 1–3 t, and changes
every displayed quantity each update. Ask crosses the 1005 t predicate
regularly. The explicit executable path avoids secondary-Dune public-name
resolution failures.

Fixtures: connected_disarmed, enabled, no_signal, admitted, blocked, received,
update_pending, update_failed, connection_lost, book_invalid. All remain visibly
MOCK. The backend retains a persistent FIFO ring of the last 10,000 evaluations,
including frozen snapshot/run/decision/configuration IDs, build, slot, predicate,
candidate, admission and receipt. Normal quantity is 1 u. The declared MOCK
admission bounds are quantity [1, 5] u and candidate price [1001, 1005] t.
The rule threshold remains 1005 t, so matching prices below 1001 t occasionally
block with an explicit price-band reason. The blocked fixture declares quantity
6 u and fails the same quantity check. Invalid books and disarmed engines
suppress evaluation; those conditions also exist in the fixed admission checker.
Receipts are separate recorded MOCK evidence, deterministically 2 ms after some
admissions; other admissions have no recorded receipt. MOCK decision timestamps
start at 13:37:00 UTC independently of the live status clock. Lost connection
preserves UNKNOWN and the last acknowledgment.

Decisions renders only the visible rows inside the installed Bonsai scroller.
Focus it with 3. j/k or arrows select by (run ID, decision ID); g goes to the top;
G clears selection and returns to the live tail. Ctrl-d/Ctrl-u move half a page.
Enter freezes the selected decision in Inspector; later market updates and
selection changes leave that evidence unchanged until another Enter. Esc clears
selection. A scrolled, selected, or paused view holds its displayed records and
shows a muted ↓ N new pill. Space pauses/resumes; the title shows ⏸ PAUSED and
the pill counts arrivals during the pause separately. A bottom, unselected view
follows new rows, highlighting each arrival for one display frame.

/ opens the installed textbox for all | match | admitted | blocked | received |
errors. Enter applies a valid filter; Esc closes. While editing, all keys belong
to the textbox, including q, j, Tab and global shortcuts. A filter can hide a
selected row without losing its ID or frozen evidence. Narrow rows abbreviate
admission/receipt/block badges to ✓A / ✓R / ✗B and omit timestamp milliseconds;
Inspector retains the full timestamp, inputs and block reason. Admission
rejections use the blocked filter; errors selects malformed/invalid decision
evidence. Software predicate reconstruction is explicitly muted/italic and
labelled (reconstructed). MOCK panels and Inspector remain labelled MOCK.

--mode simulation (alias sim) and --mode hardware print “not yet connected.”
NO_COLOR is honored; truecolor uses COLORTERM=truecolor/24bit; other terminals
use the 16-color palette. Unset NO_COLOR only for the child if previewing
colors.

## Configuration review

Press c to review the backend's structured proposal. The centered modal dims the
dashboard and compares target/connected build and base/last acknowledged version.
It displays parameter diffs, declared t/u ranges, deployment class and validation
checks. Stale, out-of-range, unreachable, REBUILD_REQUIRED and UNSUPPORTED proposals
cannot Apply. j/k selects a parameter by name; Enter opens the actual textbox.
Editing validates live and captures all shortcuts. Esc discards the draft.

Press uppercase A, type exactly apply, then Enter. The UI emits one
Apply_proposal; Mock_apply owns validate → disable → wait idle → write → verify
readback → activate. Each MOCK acknowledgment takes 0.5 seconds of backend time.
The spinner only animates observed in-flight work. The header retains ACK v12
and numeric APPLYING progress until activation acknowledges v13. Active
parameters/rule identities update atomically, and subsequent records carry v13;
old history and frozen Inspector evidence retain v12. Completed configuration
activation restores the previous armed state; an initially disarmed engine stays
DISARMED.

Fixtures selectable by --scenario: update_ok, fail_at_idle, fail_at_verify,
lost_at_activate, stale_base. Select a scenario, then c/A/apply/Enter to exercise
it. Idle/readback failures stop permanently, show the failed step and reason,
confirm DISARMED, and never activate or automatically retry. Lost activation
shows STATE UNKNOWN and last ack v12, offers r reconcile only, and never asserts
DISARMED while uncertain. Reconcile performs a backend status read; this MOCK
scenario then confirms v12/DISARMED and terminal failure. Previously handled
proposal IDs cannot be replayed. An externally supplied fresh, valid plan may
apply after a known failure or acknowledged completion; the modal does not
create new plans or IDs.

```sh
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario update_ok
cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor dune exec -- ./tui/bin/main.exe console --mode mock --scenario lost_at_activate
```

## Boundaries and verification

All application code is under tui/. model/config_contract.ml contains the frozen configuration
contract; model/contracts.ml adds provisional logical C0 types. model_adapter.ml
is the shared-contract boundary. backend_intf.ml supplies an interchangeable
command/event stream; the mock backend is opaque. No wire widths, transport/register encoding or hardware evidence are
implemented. Configuration lifecycle behavior is logical MOCK controller work. Rules consume backend records; the frontend
adds display history.

Environment remains OCaml/OxCaml 5.2.0+ox, Dune 3.22.2, Bonsai/Core/Async family
v0.18~preview.130.106+341. No packages installed; scroller and textbox use already-installed component
libraries. The 96 expect tests cover
panel fixtures, motion, units, precision, stable selection, status, minimum
layout, overlay keys, deterministic stream and live Clock.every/Async behavior.
Installed interfaces were checked before API use. Phase 3 additionally covers
queued-key focus isolation, stable selection through window/ring eviction,
paused arrival counting, filters, frozen Inspector, same-sized log/receipt
updates, and one-frame live highlights.

See tui/verification-phase4.md for the latest exact commands, real output,
review and changed-file list. Phase 4 adds stale/range/class/confirmation guards,
all failure step rendering, UNKNOWN precedence, reconciliation, ACK-only version
propagation, fresh proposal/replay checks, queued modal input and stale asynchronous
poll protection. Real PTY captures contain decoded text only.

tui/verification-phase3.md retains the Phase 3 report. tui/verification-phase2-fixes.md retains the
Phase 2 fix report. tui/verification-phase2.md retains the earlier
run. tui/verification.md retains the historical Phase 1 report.
