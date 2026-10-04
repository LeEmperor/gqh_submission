# Phase H — Resource optimization plan

Updated: October 3, 2026. **Status: H0 complete (evidence preparation); H1 accepted/complete (user-authorized closure); H2 accepted/complete; H3a, H3b, combined H3a+H3b and H3c rejected (resource regressions); H4 implemented with a user-recorded two-logic reduction; H5 heartbeat removal measured at 318 total logic, with routed timing and user-reported board quick-test PASS. Full H5 board acceptance and latency have not been recorded.**

This is the working plan for choosing, implementing and measuring Phase H
experiments. Start with history mapping and compact engine state, then evaluate
arithmetic sharing, packet storage and remaining control costs. Promote candidates
by measured whole-design results, retaining a verified fallback throughout.

## 1. Authority and inherited context

This document expands Phase H; the existing algorithm, protocol and competition
requirements remain authoritative:

- [PLAN.md §1](PLAN.md#1-objective-and-priorities): qualification and placement.
- [PLAN.md §3](PLAN.md#3-frozen-external-behavior): wire protocol, exact algorithm,
  full-range prices and session reset.
- [PLAN.md §6](PLAN.md#6-resource-first-optimization-and-measurement-discipline):
  resource-first selection and required measurements.
- [REQUEST_RESPONSE_PLAN.md §2](REQUEST_RESPONSE_PLAN.md#2-existing-foundation-and-working-rules):
  working rules, manual handoffs and evidence-based completion.
- [Request/response contracts](REQUEST_RESPONSE_PLAN.md#5-shared-interface-contracts):
  ownership, handshakes, memory timing and receive lifecycle.
- [Phase H](REQUEST_RESPONSE_PLAN.md#phase-h--resource-first-optimization-after-a-qualification-baseline)
  and [optional Phase P](REQUEST_RESPONSE_PLAN.md#phase-p--optional-board-clock-configuration-and-pll-validation):
  optimization scope and prerequisites for PLL experiments.
- [Organizer placement supplement](docs/placement-supplement-20261003.md): the
  preserved announcement, ranking order and full-range practice requirements.
- [PLAN.md §8](PLAN.md#8-freeze-deadline-and-remaining-decisions): submission
  packaging, October 4 deadline and the planned 9:00 am EDT freeze.

**F, G1, G2 and overall G are complete under the October 3 user-authorized
closure**, recorded in REQUEST_RESPONSE_PLAN.md. The user accepted the functional
results and waived outstanding build-association bookkeeping and separate physical
TX-idle measurement as F/G closure preconditions. Final image packaging remains
deferred until pre-submission freeze. H must preserve that decision: the archived
reports are useful measurements, but are not automatically the reports for the
latest programmed image. H and final packaging remain separate work.

## 2. Objective and observed starting point

Qualification requires perfect scored correctness, synthesis LUTs **≤542** and
official average latency **≤20.7825 ms** under the published references, followed
by perfect full-range correctness with zero timeouts. Judges determine actual
qualification. Among qualifiers, select lexicographically:

1. Lowest Resource Usage Summary **total logic**.
2. At equal logic, lowest **total registers**.
3. At equal resources, lowest **five-run median latency**, within 5% tied.

BSRAM is excluded from placement logic. Moving arithmetic from LUTs to ALUs alone
does not improve that metric. More registers or extra processing cycles can be
acceptable when total logic falls and qualification remains reliable.

### Archived measurements — attribution baseline, not a new validation claim

Source: [observed Gowin build review](results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/REVIEW.md),
[raw P&R report](results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/pnr/test_proj1.rpt.txt)
and [synthesis hierarchy](results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/gwsynthesis/test_proj1_syn_rsc.xml).
These local results may be absent from another checkout; missing evidence must
not be reconstructed as if an experiment had been performed.

| Whole-design metric | Observed value |
| --- | ---: |
| Gowin version | V1.9.11.03 Education |
| P&R total logic | 475 |
| Total registers | 379 |
| Synthesis LUTs | 351 |
| P&R ALUs | 76 |
| History mapping | 8 distributed SSRAM units; no BSRAM |
| Core clock / UART divisor / extra TX gap | 27 MHz / 234 / 0 |
| Normal robust mean host round trip | About 16.8 ms |

The latency comes from saved board runs described in REQUEST_RESPONSE_PLAN.md,
not the resource report. Their association with the latest image remains subject
to the documented deferral. The synthesis hierarchy reports 69 ALUs; do not mix
synthesis attribution with P&R totals.

| Block | Synthesis LUTs | Synthesis ALUs | Registers |
| --- | ---: | ---: | ---: |
| Engine | 130 | 69 | 118 |
| Controller | 60 | 0 | 76 |
| Heartbeat | 45 | 0 | 25 |
| Response sequencer | 38 | 0 | 42 |
| UART RX + TX | 59 | 0 | 45 |
| Request decoder | 18 | 0 | 69 |

These rows identify likely costs; whole-top Gowin results decide whether an
experiment helps. Savings estimated for separate changes are not additive.

## 3. Staged experiment order

| Stage | Experiment | Primary decision |
| --- | --- | --- |
| H0 | Baseline and candidate tracking | Establish the comparison inputs and fallback |
| H1 | History in BSRAM | Does changing memory mapping reduce total logic? |
| H2 | Previous-price comparison-state compression | Can equivalent state remove registers and comparators? |
| H3 | Shared arithmetic, then digit-serial arithmetic | Do operator savings exceed mux, storage and control costs? |
| H4 | Consolidate packet storage | Can explicit field lifetimes eliminate redundant captures? |
| H5 | Re-profile and optimize remaining control | Which remaining measured cost is worth another experiment? |

This is the default evaluation order, not a requirement that every experiment
succeed. A rejected stage does not block the next. Each candidate names its
parent; build on accepted improvements, and compare a rejected alternative against
the same parent when needed. Split each stage into attributable sub-candidates.
Finish with the selection/freeze procedure in §5 rather than an open-ended redesign.

### H0 — Establish the comparison baseline

**Status: COMPLETE — evidence/measurement preparation, no hardware change.**
The [H0 baseline record](results/phase-h-h0-20261003T224056Z-9bb0c55f-final/BASELINE.md),
[candidate ledger](results/phase-h-h0-20261003T224056Z-9bb0c55f-final/candidates.csv),
[artifact inventory](results/phase-h-h0-20261003T224056Z-9bb0c55f-final/inventory.csv),
[preserved fallback](results/phase-h-h0-20261003T224056Z-9bb0c55f-final/FALLBACK.md)
and [H1 handoff](results/phase-h-h0-20261003T224056Z-9bb0c55f-final/HANDOFF.md)
establish the explicit parent, historical comparison and available fallback.
Archived 475/379/351 counts were verified from raw reports. Archived measured
build, user-accepted F/G and current source/IDE observations remain distinct;
final source/report/programmed-image association is deferred to freeze. H0's
record/fallback/ledger exit is satisfied; matched-build qualification is not
claimed. F/G closure is unchanged; no H1 experiment was performed.

**Scope:** consume F/G evidence, identify the fallback and create the candidate
ledger. No hardware change is required.

- Record the source state, generated RTL, project settings, tool version, clock,
  UART configuration, resource reports and applicable board outputs.
- Label the 475-logic report as the archived baseline until matching identity is
  established. Record unresolved associations explicitly, respecting the user's
  deferred final-packaging work; this does not reopen F/G acceptance.
- Preserve the available baseline source/RTL/settings and known-good image without
  replacing previous artifacts. Record which evidence applies to which build.
- Use the hierarchy above to choose experiments; use whole-design P&R for final
  comparisons and separate synthesis LUTs for qualification.

**Exit:** an explicit baseline/parent record, preserved fallback and a ledger that
distinguishes observed measurements from verified candidate evidence. Planning
and local candidate work can proceed while deferred associations remain open;
do not describe unassociated measurements as a fully matched H baseline.

### H1 — Move history into BSRAM

**Status: accepted/complete — user-authorized closure, October 3.**
Candidate `H1-history-block-inference-20261003T225802Z`, parent
`H0-current-source`, resource reference `G2-archived-140459`. A memory-only
Gowin inference attribute preserves the engine schedule and behavioral RTL.
The observed `test_proj2` Gowin build matches the delivered RTL and reports
1 BSRAM / 0 SSRAM, 412 total logic, 363 registers and 337 synthesis-summary LUTs:
63 fewer logic counts than the archived reference. Routed 27 MHz timing has
zero setup/hold violations; PR1014 remains. See the
[measured review and preserved reports](results/phase-h-h1-gowin-20261004T001746Z/REVIEW.md)
and [updated observation ledger](results/phase-h-h1-gowin-20261004T001746Z/candidates.csv).
**Measured gains:** 475 → 412 total logic (**−63, 13.3%**), 379 → 363
registers (**−16, 4.2%**), 351 → 337 synthesis-summary LUTs (**−14, 4.0%**),
8 → 0 SSRAM units and 0 → 1 BSRAM. Synthesis ALUs 69 → 68; P&R ALUs 76 → 75.
Fresh saved board results now pass quick, normal robust and full-range (each
84/84 scored packets, 168/168 actions, zero timeouts), plus custom 1,394/1,394
with no mismatch/SHORT/TIMEOUT or unsolicited/trailing bytes. Normal mean RTT
is 16.807 ms; full-range 16.804 ms. See the
[board progress record](results/phase-h-h1-board-20261004T003448Z/REVIEW.md)
and [progress ledger](results/phase-h-h1-board-20261004T003448Z/candidates.csv).
Saved fault/button-reset checks pass, and custom after populated-history reset
passes 1,394/1,394 with no errors or unsolicited/trailing bytes. The user confirms
all requested runs and explicitly authorizes H1 completion. Fresh startup is
accepted as user-reported; no startup JSON was found. Earlier detailed settings/
encoded-netlist audit limitations remain recorded, without claiming those audits
were performed. See the [H1 closure](results/phase-h-h1-complete-20261004T004023Z/CLOSURE.md),
[user acceptance](results/phase-h-h1-complete-20261004T004023Z/USER_ACCEPTANCE.md)
and [accepted ledger](results/phase-h-h1-complete-20261004T004023Z/candidates.csv).
See the [H1 handoff](results/phase-h-h1-20261003T225802Z-block-inference/HANDOFF.md),
[candidate ledger](results/phase-h-h1-20261003T225802Z-block-inference/candidates.csv),
[local commands/evidence](results/phase-h-h1-20261003T225802Z-block-inference/COMMANDS.md)
and [RTL identity comparison](results/phase-h-h1-20261003T225802Z-block-inference/rtl-comparison.json).
Independent engine/oracle, poison/stale RAM, reset/stall/exact-once, emitted
candidate RTL and serial integration checks pass. Earlier pending H1 statuses
in immutable bundles are superseded by this closure. Acceptance applies to the
archived history-only H1 RTL/image; subsequent engine/test edits in the current
working tree are preserved and do not inherit H1 acceptance.
H0's checksummed bundle and F/G closure remain unchanged;
final baseline-image association remains deferred to freeze.

**Primary files:** [src/engine/update.ml](src/engine/update.ml), a narrowly scoped
memory wrapper if required, and engine/memory verification. Coordinate any vendor
source-manifest or generator changes with the integration owner.

**Hypothesis:** the existing 32 × 16 history consumes counted distributed memory;
BSRAM can remove that cost while preserving the engine interface and schedule.

The archived P&R report lists 427 LUT/ALU logic versus 475 total, a 48-count
difference associated with its SSRAM accounting. This is an opportunity estimate,
not a promised 48-count saving: surrounding logic and output registers may change.

1. Try supported block-memory inference controls; if unsuitable, use a narrow
   exact-device Gowin primitive wrapper with explicit simulation behavior.
2. Keep history-only mapping as the first candidate. Preserve synchronous read
   latency, reset write suppression and exact-once commit.
3. Keep RAM unreset; warm-up must overwrite old history before subtraction uses it.
4. Inspect actual mapped primitives and whole-design resources in Gowin.

**Acceptance:** independent engine/oracle and emitted-RTL checks pass, stale/poison
RAM and repeated-session behavior remain correct, actual BSRAM mapping is proven,
and whole-design logic improves with acceptable timing. A promising candidate then
undergoes the board promotion checks in §5.

Moving scalar state into BSRAM is a separate follow-up candidate, preferably after
H2 establishes what state remains necessary. Count address/decode/control overhead.

### H2 — Replace previous prices with comparison state

**Status: accepted/complete — measured resource improvement and fresh full board validation.**
Candidate `H2-comparison-state-20261004T003607Z`, parent
`H1-history-block-inference-20261003T225802Z`. Engine, protocol, emitted RTL,
production serial and full regressions pass. All nine relation transitions at
index 16 are checked; comparison flags commit during warm-up and remain item-owned.
H1 history inference/read schedule, exact arithmetic, 27 MHz and UART are retained.
The new `test_proj2` Gowin V1.9.11.03 build matches the delivered H2 RTL/CST/SDC.
Measured H2: **362 total logic / 335 registers / 285 synthesis-summary LUTs /
1 BSRAM / 0 SSRAM**. Versus H1: **50 fewer logic (12.1%), 28 fewer registers
(7.7%), 52 fewer synthesis LUTs**. Routed 27 MHz setup/hold checks pass with
+25.197 ns / +0.208 ns slack and zero violations; PR1014 remains.
Fresh H2 programming/startup, quick, normal → full-range with no intervening
reset/programming, custom and populated-history reset replay, and sticky-fault/
button-reset recovery all pass. Normal/full-range each returned 100 responses,
84/84 scored packets, 168/168 actions and zero timeouts. Normal mean is 16.813 ms;
full-range mean is 16.920 ms. Both custom runs pass 1,598/1,598 with no
mismatch/SHORT/TIMEOUT, abort or unsolicited/trailing bytes.
See the [full board summary](results/board-H2-20261003-181927-sdxjntxh/summary.json)
and its per-stage logs/CSVs. The user confirmed fresh programming and physical
LED/reset observations during the wrapper run. Acceptance applies to this combined
H1+H2 candidate, not subsequent changes. Source snapshot/hash packaging was omitted
at the user's request. F/G closure and deferred final-image packaging remain intact.
See [H2 files and manual next steps](results/phase-h-h2-20261004T003607Z-comparison-state/HANDOFF.md).
The concurrent H1 closure is preserved separately; it does not accept H2.

**Primary files:** `src/engine/update.ml` and `test/engine/`; integration tests
consume the unchanged engine command/result interface.

**Hypothesis:** the previous 16-bit price is needed only for its relation to the
old average. That relation was already computed against the new average on the
preceding update of the same item and can be retained directly.

Store two flags per item, `previous_below` and `previous_above`; both false means
equal. For the current update:

```text
new_sum       = exact existing warm-up or rolling-sum update
new_average   = new_sum >> 4
current_below = current_price < new_average
current_above = current_price > new_average

buy  = not previous_above and current_above
sell = not previous_below and current_below

action = NONE during warm-up
         otherwise BUY if buy, SELL if sell, else held_action

on commit for the selected item:
    previous_below = current_below
    previous_above = current_above
```

The retained flags describe the last committed price versus the last committed
average. Since each item's sum changes only on its own update, those become the
next update's previous price and old average. This preserves both inclusive old
comparisons and strict current comparisons, including equality and truncation.

- Compute/store the flags on **every** commit, including warm-up; index 15 must
  prepare index 16 correctly.
- Clear both flags on board/session reset, representing price zero versus sum zero.
- Keep flags item-owned across slot swaps; stalls must not cause repeated commits.
- Preserve full 16-bit prices and exact 20-bit sums throughout computation.

Potential source-state reduction: **32 previous-price bits → 4 flags**, plus removal
of old-price comparisons and associated selection logic. Actual mapping savings
must be measured.

**Acceptance:** the unchanged independent direct-window oracle agrees on actions;
flag-state assertions derive expected relations from that oracle's windows.
Exercise warm-up completion, equality, floor truncation, extremes, held actions,
slot swaps, stalls and repeated sessions. Replace tests that directly inspect
`previous_a`/`previous_b` with equivalent invariant checks; retain sum/history and
exact-once verification. Require whole-design improvement and board promotion.

### H3 — Share arithmetic, then evaluate narrower arithmetic


**H3a status: rejected — measured resource regression.** Candidate
`H3a-shared-full-width-20261004T012455Z`, parent accepted
`H2-comparison-state-20261004T003607Z`. The matching user-built Gowin
V1.9.11.03 candidate reports **364 total logic / 356 registers / 306
synthesis-summary LUTs / 1 BSRAM / 0 SSRAM**: **+2 logic, +21 registers,
+21 synthesis LUTs** versus H2's 362 / 335 / 285. Synthesis hierarchy/utilization
LUTs are 309 including three INV; do not substitute that for the separate
306-LUT synthesis-summary row. Routed 27 MHz setup/hold timing passes with
+29.379 / +0.346 ns slack and zero violations; PR1014 remains. One selected
arithmetic expression/cell removes the separate subtract/increment path, but
the measured whole-design cost does not improve the primary ranking metric.
Focused engine and real-controller checks pass. Production serial Cyclesim
passes; the remaining production RTL/full-regression simulations were stopped
after the measured rejection, with no aggregate PASS claimed. Logs and scope
are retained in the candidate bundle.
No H3a board acceptance or RTT is claimed. The failed resource screen rejects
promotion without requiring board tests. H2 remains the accepted fallback.
The subsequently user-authorized H3b and combined experiments are recorded below.
See [measured review](results/phase-h-h3a-20261004T012455Z/MEASURED_REVIEW.md),
[ledger](results/phase-h-h3a-20261004T012455Z/candidates.csv),
[cycle schedule](results/phase-h-h3a-20261004T012455Z/SCHEDULE.md) and
[handoff](results/phase-h-h3a-20261004T012455Z/HANDOFF.md).

**H3b and combined H3a+H3b status: rejected — user-confirmed resource-screen
decisions, October 3.** H3b candidate
`h3b-shared-relations-8853aea` builds directly on accepted H2 at commit
`8853aea`; its unchanged parent generation matched the accepted H2 competition
RTL byte-for-byte. It replaces the separate unsigned below/above comparisons
with one 16-bit unsigned less-than comparison plus equality, deriving above as
`!(below || equal)`. H2's relation flags, exact 20-bit sums and schedule remain.

Combined candidate `h3ab-shared-arithmetic-relations-3f4e842` adds the same
comparator change to H3a's shared full-width arithmetic. Its implementation
parent at commit `3f4e842` generated RTL identical to archived measured H3a
before the comparator edit. Neither experiment accepts H3a or replaces H2.

| Candidate | Total logic | Registers | Synthesis-summary LUTs | Logic/register/LUT change vs H2 | Decision |
| --- | ---: | ---: | ---: | --- | --- |
| Accepted H2 | 362 | 335 | 285 | reference | Retain accepted fallback |
| H3a alone | 364 | 356 | 306 | +2 / +21 / +21 | Rejected |
| H3b alone | 368 | 335 | 289 | +6 / 0 / +4 | Rejected |
| H3a+H3b combined | 381 | 356 | 321 | +19 / +21 / +36 | Rejected |
| H3c digit-serial | 378 | 376 | 335 | +16 / +41 / +50 | Rejected |

All three user-built candidates use Gowin V1.9.11.03 Education and retain
1 BSRAM / 0 SSRAM. H3b P&R reports 292 LUT + 76 ALU; combined P&R reports
325 LUT + 56 ALU. These P&R LUT counts are distinct from the synthesis-summary
LUT column. Routed 27 MHz timing passes with zero setup/hold violations:
H3b worst setup/hold slack +23.820 / +0.227 ns; combined +30.515 / +0.321 ns.
Clock/UART settings and competition constraints are unchanged.

Read-only reviews of the live `test_proj2/test_proj2/impl/` reports created
October 3 at 18:54:49 (H3b) and 19:02:03 (combined) confirmed each project
RTL/CST/SDC matched its delivered candidate byte-for-byte at review time.
The combined run replaced the live H3b reports; no standalone H3b raw-report
archive was made. H3a's archived raw reports remain preserved in its bundle.
The counts above record the observed measurements, not an estimated additive
result: comparator reuse added 17 logic counts to H3a, so the combination
also fails the primary resource screen.

H3b build, focused existing engine Cyclesim/Icarus checks (464 packets /
9,918 edges), complete-top elaboration and Yosys process/hierarchy checks pass.
Combined checks likewise pass (518 packets / 12,223 edges), including all nine
first-scored relation transitions, extremes/truncation, stalls, session reuse,
reset at each applicable H3a stage and exact-once commit/RAM checks. Structural
checks confirm the intended shared operators and retained block-memory inference
attribute. Full regression and serial suites were not run for these candidates;
no H3b/combined board validation or RTT is claimed. Failed resource screens
reject promotion without board tests.

Delivered RTL and constraints remain in
[H3b folder](results/h3b-shared-relations-8853aea/) and
[combined folder](results/h3ab-shared-arithmetic-relations-3f4e842/).
Accepted H2 remains 362 / 335 / 285 and is the reference for subsequent experiments;
use its [competition RTL and constraints](results/phase-h-h2-20261004T003607Z-comparison-state/gowin/src/).

**H3c status: rejected — measured resource regression, October 3.** Candidate
`h3c-digit-serial-h2`, parent accepted
`H2-comparison-state-20261004T003607Z`. The existing H3a command/commit shell
was reused while replacing its full-width arithmetic with one shared four-bit
add/subtract datapath. Five LSB-first chunks propagate carry/no-borrow for each
operation; rolling updates subtract oldest then add current, while warm-up only
adds current. Fixed shifts assemble the exact 20-bit result before the single
commit. H2's separate below/above comparisons and warm-up relation flags,
H1's synchronous history/read schedule and block-memory inference, direct
27 MHz clock and UART settings are retained. Temporary arithmetic state is
40 bits (20-bit sum scratch, 16-bit operand, carry and 3-bit chunk counter).
Engine result publication is 8 cycles warm-up / 14 cycles rolling after command
acceptance; earliest result transfer is 9 / 15 cycles.

The matching user-built Gowin V1.9.11.03 Education candidate reports
**378 total logic / 376 registers / 335 synthesis-summary LUTs /
1 BSRAM / 0 SSRAM**. Versus accepted H2, this is **+16 logic (4.4%),
+41 registers (12.2%) and +50 synthesis LUTs (17.5%)**. P&R reports
338 LUT + 40 ALU = 378 logic. Synthesis hierarchy/utilization reports
338 LUT (including three INV) and 34 ALU; keep these distinct from the
335-LUT synthesis-summary row. Routed 27 MHz timing passes with worst
setup/hold slack **+30.124 / +0.323 ns**, zero setup/hold violations and
zero total negative slack. PR1014 remains.

Read-only review confirmed the live project RTL/CST/SDC matched the delivered
candidate byte-for-byte. Reports were created October 3 at 19:11:53:
[P&R resources](test_proj2/test_proj2/impl/pnr/test_proj2.rpt.txt),
[synthesis summary](test_proj2/test_proj2/impl/gwsynthesis/test_proj2_syn.rpt.html)
and [routed timing](test_proj2/test_proj2/impl/pnr/test_proj2_tr_content.html).
These are live project reports and may be replaced by a later build; no separate
raw-report archive was created. Delivered inputs remain in the
[H3c folder](results/h3c-digit-serial-h2/).

Build, focused engine Cyclesim/Icarus checks (742 packets / 26,161 edges),
controller variable-latency mocks and 72-packet real-controller sanity replay,
complete-top elaboration and Yosys hierarchy/process checks pass. Coverage
includes independent integer window sums, carry/borrow propagation, zero/max
values, top-nibble handling, all nine first-scored relation transitions,
reset at every processing edge, stale history, exact-once commits and stalled
result stability. Structural checks confirm four-bit arithmetic operands with
carry-out (one six-bit guarded addition), no full-width sum add/subtract and
retained block-memory inference. Full regression, long serial simulations and
the broader controller reset sweep were not run. No H3c board validation or
RTT is claimed. The failed resource screen rejects promotion; H2 remains the
accepted fallback and implementation parent for H4.

At the H3c review, engine source and live `test_proj2` inputs contained rejected
H3c. They have since been superseded by H4 and H5, recorded below; H2's archived
fallback remains available.

**Primary files:** `src/engine/update.ml`, engine tests and schedule-sensitive
integration checks. Preserve latency-independent command/result handshakes.

The baseline selects one item but still expresses subtract and add as separate
operators in one update path. Evaluate separately:

1. **H3a:** one time-multiplexed 20-bit add/subtract datapath.
2. **H3b:** comparator reuse, using the H2 representation if accepted.
3. **H3c:** a narrower digit-serial datapath, only if earlier measurements justify
   its implementation and verification effort.

Keep 20-bit exact sums, unsigned extension, truncated averages and old-state
comparison semantics. Count intermediate storage, muxes, carries/borrows and FSM
cost. Sequential source statements alone do not prove operator sharing.

At 27 MHz, 100 cycles take approximately 3.7 µs, versus about 16,800 µs observed
host round trips. This supports spending cycles for area, but does not replace
end-to-end latency measurement. Begin at 27 MHz; use Phase P only for a measured
resource-saving schedule or qualification need.

**Acceptance:** independent arithmetic checks, command/result stalls, reset at
every new stage and exact-once commit pass. Update schedule-specific scoreboards
without weakening behavioral checks. Record warm-up/steady/session-start cycles;
require a better whole-design ranking tuple and successful board promotion.

### H4 — Consolidate packet storage

**H4 findings, recorded October 3:** candidate
`h4-borrow-decoder-request-h2` retains the decoder's request fields through
final response drain and lets the controller borrow them, removing its redundant
request capture. Commit `fefc7d0` records the user's result, "h4 gave us -2".
Relative to H2's 362 total logic, this implies **360 total logic**. This is an
inference from that recorded reduction; H4's original raw resource reports,
register count, synthesis LUT count and timing were not archived here and are
not reconstructed from H5. Delivered inputs remain in the
[H4 folder](results/h4-borrow-decoder-request-h2/).

H4 is H5's implementation parent. Before the H5 edit, regenerating the clean
`fefc7d0` source produced competition RTL byte-identical to saved H4.

**Primary files:** `src/protocol/request_decoder.ml`,
`src/protocol/transaction_controller.ml`, `src/protocol/response_sequencer.ml`,
their tests and coordinated production composition changes.

The pre-H4 source captured a 64-bit request in the decoder, another 64-bit
request in the controller, and a 36-bit response in the sequencer. These are
source-level payload sizes, not guaranteed independent mapped register counts.

**Hypothesis:** stop-and-wait permits one authoritative retained copy of fields
whose lifetimes overlap. Remove one redundant capture boundary per candidate.

Before editing, write a field-lifetime table: writer, consumers, first valid edge,
last required edge, and overwrite/release event. Ordinary valid/ready guarantees
stability only until acceptance; borrowed storage needs an explicit stronger
ownership contract through the final consumer. Preserve exact index/ID echo,
slot/action association and full-frame completion before receive rearm.

**Acceptance:** changed boundaries pass payload stability, backpressure, reset,
fault/acceptance collisions, legal host pauses, no early TX, final drain and
same-connection session checks. Verify actual logic savings; fewer registers alone
does not justify increased total logic. Run full serial integration and board
promotion before accepting a new storage contract.

### H5 — Re-profile remaining control overhead

**H5 findings, recorded October 3:** candidate `h5-no-heartbeat`, parent H4
at `fefc7d0`. The user explicitly authorized removing the competition top's
heartbeat instance and driving `led0_n` high. LED0 now stays off. Every other
module is byte-identical to H4; the remaining top wiring is unchanged apart
from generated internal net renumbering. The SDC and CST are byte-identical to
H4. The optional heartbeat timing argument remains accepted for call
compatibility and is ignored by the competition top. Diagnostic tops retain
their heartbeat behavior.

The matching user-built Gowin V1.9.11.03 Education reports, created October 3
at 19:30:36 for GW2AR-LV18QN88C8/I7, show:

| Metric | H5 |
| --- | ---: |
| P&R total logic | **318** |
| P&R LUT / ALU | 244 / 74 |
| Total registers | **246** (245 logic FF, 1 I/O FF) |
| Synthesis-summary LUTs | **242** |
| Synthesis ALUs | 67 |
| BSRAM / SSRAM | 1 / 0 |
| Worst routed setup / hold slack | **+24.405 / +0.425 ns** |
| Setup / hold violated endpoints | 0 / 0 |
| Reported Fmax | 79.164 MHz |

At the unchanged 27 MHz clock, routed setup/hold timing passes with zero total
negative slack. P&R's 244 LUT count and synthesis-summary's 242 LUT count are
separate measurements. Compared with measured H2, H5 saves **44 total logic
(12.2%), 89 registers (26.6%) and 43 synthesis-summary LUTs (15.1%)**. Using
H4's inferred 360-logic baseline, heartbeat removal saves a further **42 total
logic (11.7%)**. Compared with archived G2's 475 total logic, H5 saves **157
(33.1%)**. These are whole-design comparisons, not isolated heartbeat cell counts.

Build, Icarus elaboration and Yosys hierarchy/process checks pass with zero
problems. The user reported that the board quick test passes. No H5 normal
robust, full-range, custom replay or latency results were supplied; this records
a successful resource screen and quick board check, without claiming full
board acceptance. The P&R log still reports PR1014: generic routing resources
are used for `sys_clk_d` under the specified constraint, with a warning about
possible delay or skew. The unchanged SDC defines the onboard clock only.

At review time, live project RTL/CST/SDC hashes matched delivered H5 inputs.
The reports, synthesis netlist and project settings are now preserved under
[H5 measured reports](results/h5-no-heartbeat/gowin/) so later IDE builds will
not replace this evidence. See the
[P&R resource report](results/h5-no-heartbeat/gowin/impl/pnr/test_proj2.rpt.txt),
[synthesis summary](results/h5-no-heartbeat/gowin/impl/gwsynthesis/test_proj2_syn.rpt.html),
[routed timing](results/h5-no-heartbeat/gowin/impl/pnr/test_proj2_tr_content.html)
and [measurement record](results/h5-no-heartbeat/measurement.json).
The generated `.fs` hash is recorded for build identity; which image was
programmed was not independently verified. Final submission packaging remains
separate work.

**Primary files:** whichever measured block is selected; keep experiments narrow.

The original candidate list was to re-read the hierarchy after H1–H4 and rank
remaining costs. It included:

- Heartbeat counter/terminal-count implementation. H5 instead removes the
  competition heartbeat under the user's explicit instruction, as recorded above.
- FSM encoding and register enables, one block at a time.
- TX shift-register versus indexed-byte serialization, preserving byte capture,
  exact bit durations, stop bits and ready/busy semantics.
- UART timer/control sharing only with an explicit lifecycle proof. RX still
  observes unexpected traffic while TX is active for the sticky-fault policy;
  stop-and-wait alone does not prove the timers can be shared safely.

The baseline already has zero extra TX gap. Frequency escalation and cut-through
need a measured benefit under the resource-first ordering. Any PLL candidate must
satisfy Phase P before full-system promotion.

**Acceptance:** focused waveform/control tests, relevant serial regressions,
whole-design resource/timing comparison and affected board checks pass. Keep
changes only when they improve the selection order while preserving qualification.

## 4. Candidate records and implementation handoffs

Use fresh `results/phase-h-<stage>-<candidate>/` directories. Give every candidate
an explicit parent and exactly one stated hypothesis. Record rejected candidates
as well as winners; rejected experiments need not proceed to board testing.

Minimum ledger columns:

| Candidate / parent | Change | Total logic | Registers | Synth LUTs | BSRAM | Timing | Correctness / timeouts | Official mean | Status / decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Archived G2 observation / — | Original 27 MHz design | 475 | 379 | 351 | 0 | See archived review | See F/G closure; identity caveat above | ~16.8 ms | Historical reference |
| H1 / G2 | History in BSRAM | 412 | 363 | 337 | 1 | Pass | Quick, normal/full-range and custom pass | 16.807 ms | Accepted/complete |
| H2 / H1 | Comparison-state compression | 362 | 335 | 285 | 1 | Pass | See H2 acceptance | See H2 record | Accepted/complete |
| H3a / H2 | Shared full-width arithmetic | 364 | 356 | 306 | 1 | Pass | Focused checks pass; no board run | Not measured | Rejected |
| H3b / H2 | Shared comparisons | 368 | 335 | 289 | 1 | Pass | Focused checks pass; no board run | Not measured | Rejected |
| H3a+H3b / H3a | Combined sharing | 381 | 356 | 321 | 1 | Pass | Focused checks pass; no board run | Not measured | Rejected |
| H3c / H2 | Digit-serial arithmetic | 378 | 376 | 335 | 1 | Pass | Focused checks pass; no board run | Not measured | Rejected |
| H4 / H2 | Borrow decoder request fields | 360 (inferred) | Not archived | Not archived | Not archived | Not archived | Not recorded here | Not recorded | User-recorded −2 logic; H5 parent |
| H5 / H4 | Remove competition heartbeat; LED0 high | **318** | **246** | **242** | **1** | **Pass** | **User-reported quick PASS**; broader checks not recorded | Not measured | Resource screen and quick check pass |

Each candidate folder should retain source revision plus dirty diff/new files,
generated RTL identity, complete project settings and vendor sources, raw Gowin
reports, bitstream identity when produced, clock/UART settings, measured engine
cycles, commands, test outputs and host setup. Preserve five raw run outputs when
using latency as a tie-break; the supplement leaves some statistical details
unspecified, so retain samples and per-run summaries rather than inventing them.

Implementation assignments must name the stage, parent, owned files, interface
changes, local checks, manual handoff and decision metric. One integration owner
coordinates board/generator/shared configuration edits. Follow the existing
prohibition on mutative Git operations; preserve unrelated work. The user performs
Gowin synthesis/P&R, programming and board runs unless separately requested.

Useful existing verification entry points, from the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune build
opam exec --switch=5.2.0+ox -- dune build @test/engine/runtest
opam exec --switch=5.2.0+ox -- dune build @test/protocol/runtest
opam exec --switch=5.2.0+ox -- dune build @test/transport/runtest
opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest
opam exec --switch=5.2.0+ox -- dune runtest
```

Use the relevant focused checks during development, then complete integration and
regression checks for the delivered candidate. See [engine verification](test/engine/README.md),
[serial integration](test/integration/README.md), and [Gowin handoff](gowin/README.md)
for coverage and generation instructions. Existing tests pin some internal names,
latencies and hierarchy details; adapt those deliberately when the architecture
changes while preserving independent expected results and external contracts.

## 5. Promotion and final selection

1. **Local verification:** pass relevant independent-oracle, protocol, reset,
   emitted-RTL and serial checks; generate reproducible complete candidate RTL.
2. **Resource screening:** user runs whole-design Gowin V1.9.11.03 synthesis/P&R.
   Record placement logic/registers, separate synthesis LUTs, memory mapping and
   timing. Reject regressions before spending board-test time unless there is an
   explicit reason to investigate further.
3. **Board promotion:** program the identified candidate; require official quick
   PASS, then normal robust followed by full-range practice without intervening
   reset/reprogramming. Each robust run needs 100 responses, 84/84 scored packets,
   168/168 actions and zero timeouts. Require custom all-byte warm-up, boundary,
   slot-swap and same-connection repeated-session checks, plus applicable
   startup/reset/status and changed waveform behavior checks.
4. **Selection:** confirm qualification latency/LUT margin, then compare total
   logic, registers and finally five-run median latency. Promote the winner and
   preserve its parent fallback. Re-test a combined candidate; separate experiment
   results do not establish correctness or additive savings for the combination.
5. **Freeze:** stop new experiments in time for PLAN.md's submission schedule.
   Package the selected source, generated RTL, exact project settings/reports and
   matching `.fs`; run final acceptance on that image and record the evidence.

Use **planned**, **in progress**, **locally verified — awaiting manual checks**,
**rejected**, and **accepted/complete** distinctly. Local simulation or a lower
resource count does not establish board acceptance. Record actual user-supplied
results before promoting a hardware candidate; any further waiver must be explicit
and scoped. This planning-only document itself requires no hardware checks.
