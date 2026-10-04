# Phase H — Resource optimization plan

Updated: October 3, 2026. **Status: H0 complete (evidence preparation); H1 accepted/complete (user-authorized closure); H2 accepted/complete; H3a rejected (resource regression); H3b–H5 experiments have not been run.**

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
promotion without requiring board tests. H2 remains the accepted fallback;
H3b/H3c and later experiments are not authorized by this H3a assignment.
See [measured review](results/phase-h-h3a-20261004T012455Z/MEASURED_REVIEW.md),
[ledger](results/phase-h-h3a-20261004T012455Z/candidates.csv),
[cycle schedule](results/phase-h-h3a-20261004T012455Z/SCHEDULE.md) and
[handoff](results/phase-h-h3a-20261004T012455Z/HANDOFF.md).

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

**Primary files:** `src/protocol/request_decoder.ml`,
`src/protocol/transaction_controller.ml`, `src/protocol/response_sequencer.ml`,
their tests and coordinated production composition changes.

The source currently captures a 64-bit request in the decoder, another 64-bit
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

**Primary files:** whichever measured block is selected; keep experiments narrow.

Re-read the hierarchy after H1–H4 and rank remaining costs. Candidates include:

- Heartbeat counter/terminal-count implementation, preserving its current cadence
  and startup/reset behavior. Its archived 45 LUTs justify an early inexpensive
  comparison if this is more economical than the next large redesign.
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
