# Hardware track: main plan of attack

Updated: October 3, 2026. **This is the active team plan.**

## 1. Objective and priorities

Implement the organizer's fixed algorithm entirely on the **Tang Nano 20K**, in
**Hardcaml**. First qualify with **100/100 on the official run and a perfect
full-range hidden run**, then minimize resources in this strict ranking order:
**total logic count → total registers → median latency over five runs**.
Latency within 5% counts as tied. Preserve reliable qualification throughout.

**Clocking decision (October 3): PLL use is permitted.** We can multiply the
board's 27 MHz reference to run the internal logic faster. Use a higher core
frequency only when it enables a measured resource reduction or is needed for
qualification; frequency alone earns no placement credit. Select the final
frequency using timing closure and board measurements. The external UART
remains at 115200 baud, with its divisors and idle-gap counters adjusted to the
selected core clock. See [the clocking plan](#clocking-decision-configurable-frequency-one-processing-domain).

The critical path is:

> Official fixtures + working build → reliable UART → correct complete engine
> → measured baseline → targeted optimization → frozen submission.

Hardcaml is a settled implementation choice. Small RTL wrappers or vendor memory
primitives are acceptable where needed. Development tooling earns its place by
helping verification, measurement, or reproducibility.

### Authority and scoring

- [The supplied guide](gqh_hw_guide.pdf), especially Part 2 §§7–11 and Part 3,
  defines the written contract. Record any subsequent organizer clarification
  here, including its source.
- **Placement supplement, October 3:** the organizer announcement supplied by
  the user establishes qualification and a strict resource-first ranking. The
  [preserved announcement and attachment review](docs/placement-supplement-20261003.md)
  supplement the guide without changing its rubric or algorithm. Extra features
  have no specified placement credit.
- **Clocking clarification, October 3:** the user reports that the competition
  permits the FPGA PLL and faster internal clocks. Treat 27 MHz as the board's
  input reference, not a mandated processing frequency. Source: user report in
  the planning conversation; no written organizer clarification has been added
  to the repository. This does not change the specified 115200-baud UART.
- The rubric below determines qualification; the separate placement metrics
  below determine ranking among qualifiers.

| Criterion | Written scoring rule |
| --- | --- |
| Packet correctness | `50 * correct_packets / 84` |
| Action correctness | `20 * correct_actions / 168` |
| Latency | 15 points at ≤1.25× reference average; 8 at ≤2×; otherwise 0 |
| LUTs | `15 * min(1, reference_LUTs / design_LUTs)` |

Latency and LUT points are both zero below 95% packet correctness. Aim for
**100%**, not that cutoff. Published references are **542 LUTs** and **16.626 ms**;
the full-credit latency boundary is **20.7825 ms**, and the partial-credit
boundary is **33.252 ms**. The judging PC determines the official measurements.

### Qualification and placement — organizer supplement

1. **Official run: 100/100.** Under the published references this requires
   perfect packet/action correctness, synthesis LUTs **≤542**, and official
   average round-trip latency **≤20.7825 ms**. Judges may rerun once if the
   latency tier is missed; design for margin rather than relying on a rerun.
2. **Immediately following hidden full-range run:** every packet and action
   correct, zero timeouts, prices `0..65535`, without reprogramming. Latency and
   LUTs are not re-scored in this run. Preserve 16-bit prices, 20-bit sums and
   index-zero session reset. Rehearse normal → full-range without board reset.
3. **Qualified-team order:** lowest **total logic count**, then lowest **total
   register count**, then lower **median latency over five runs**, with latency
   differences within 5% tied. This is lexicographic, not a weighted tradeoff.
   Nonqualifiers rank below every qualifier, ordered by rubric score.

Judges re-synthesize committed source with **Gowin V1.9.11.03** and the committed
project settings. Placement uses **Resource Usage Summary total logic** (LUTs,
ALUs and other logic types combined) and **total registers** from that same
summary. **BSRAM is allowed and excluded from logic count.** Moving arithmetic
from LUTs into ALUs is not itself a reduction. Keep the guide's synthesis-LUT
qualification metric separate from this placement total.

Judges use their rebuilt counts, not self-reported figures, and check that the
rebuilt source behaves like the submitted `.fs`. Preserve complete reproducible
project settings and matching source/RTL/bitstream. First establish qualification
with margin, then select measured candidates by the ranking order above.

## 2. What exists and what is missing

| Material | Reviewed status / use |
| --- | --- |
| `gqh_hw_guide.pdf` | Read directly; primary competition specification. |
| `viv25_proj/test_proj1/src/blinky.v` | A six-LED counter in Verilog; starting point for device/tool bring-up. |
| `viv25_proj/test_proj1/test_proj1.gprj` | Gowin project for `GW2AR-LV18QN88C8/I7`. |
| Blinky `.cst`, `.sdc`, and `impl/` | Saved synthesis/P&R reports and `.fs` exist; report names Gowin V1.9.11.03 Education. These establish saved build evidence, not verified board operation. |
| Competition implementation | Hardcaml UART/protocol foundation, F engine, G1 controller and G2 competition board system exist. REQUEST_RESPONSE_PLAN.md records A–E evidence and F/G1/G2 local verification. F/G board correctness acceptance is complete under the user-authorized closure in REQUEST_RESPONSE_PLAN.md. H and final submission packaging remain open; PLL validation is separate. |
| Organizer inputs | All three files are available in the sibling `../GQH-Hardware-Track-Submission/` checkout; exact paths and reviewed behavior below. Copy pinned inputs into the team project during integration. |
| Results | Official quick, normal robust, full-range practice, 1,394-packet custom replay, fault/reset and fresh-startup checks pass; evidence is under `results/phase-g2-board-20261003-142516-thv362qq/`. An earlier build’s whole-design reports are archived. Matching final source/report/bitstream identity is deferred by the user until pre-submission freeze; physical TX-idle measurement remains unconfirmed. |

The directory is a Git worktree on `bpurtell/base_testing`; at review time only
the old README was tracked, and the supplied plans, PDFs, and Gowin project were
untracked. Include intended inputs explicitly when committing the project.

### Organizer repository: available locally

- Local checkout: `~/devel/jane/GQH-Hardware-Track-Submission/`
  ([open from this worktree](../GQH-Hardware-Track-Submission/)).
- Upstream: [ShayanNazir/GQH-Hardware-Track-Submission](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission).
- Reviewed revision: `80467b5d0e481373daf126de9a0f57e67f19906b` (clean checkout
  when inspected). Record the revision again if updated before copying assets.
- Its participant-guide PDF is byte-identical to this project's
  `gqh_hw_guide.pdf`. The organizer repository explicitly gives the guide
  precedence over its other documentation.

Paths below are relative to that organizer checkout:

| Resource | Path / use |
| --- | --- |
| Official physical constraints | [`participant-resources/19_tang_nano_20k.cst`](../GQH-Hardware-Track-Submission/participant-resources/19_tang_nano_20k.cst) → include in our `constraints/` and Gowin project. |
| Quick UART test | [`participant-resources/testing/21_quick_uart_test.py`](../GQH-Hardware-Track-Submission/participant-resources/testing/21_quick_uart_test.py) → run first on the board. |
| Robust UART test | [`participant-resources/testing/22_robust_uart_test.py`](../GQH-Hardware-Track-Submission/participant-resources/testing/22_robust_uart_test.py) → scoring-style correctness and latency baseline. |
| Test explanations | `participant-resources/testing/21_quick_uart_test_REFERENCE.md` and `22_robust_uart_test_REFERENCE.md` in the same directory → starting references for replay/test owners. |
| Judging rules | [`JUDGING_AND_TESTING.md`](../GQH-Hardware-Track-Submission/JUDGING_AND_TESTING.md) → readable protocol, algorithm, and scoring reference. |
| Submission preparation | `TEAM_README_TEMPLATE.md`, `REPOSITORY_STRUCTURE.md`, and `SUBMISSION_CHECKLIST.md` → use at Gate 5. |

Copy the scripts into `tools/official/` when integrating, retaining upstream
provenance and changing only `PORT`. Both require Python 3 and `pyserial`.
Our submitted build must include its own required inputs rather than depend on
this sibling checkout. The organizer repository is shared reference material;
the team's source and final `.fs` belong in the team's own submission repository.

### What the supplied tests actually cover

- **Quick:** 21 requests, with 16 warm-up packets and five scored updates.
  Includes crossings, held actions, and post-warm-up slot swaps. A complete
  `PASS` requires working algorithm logic, not just an echo/placeholder engine.
- **Robust:** 100 requests using practice seed `0x57214720`, prices in `0..100`,
  and seeded slot swaps after warm-up. Both scripts send each item exactly once
  per request and use sequential indices beginning at zero. The unpublished
  judging seed differs; retain full unsigned 16-bit price support.
- **Full-range supplement:** user-downloaded
  `tools/22_robust_uart_test_fullrange.py`, seed `0x1F00D16B`, 100 requests,
  prices `0..65535`, with post-warm-up swaps. Change only PORT in run copies;
  preserve attachment provenance separately from the pinned older checkout.
  Outputs: `trade_results_100_fullrange.csv` and `trade_summary_100_fullrange.txt`.
  Run after normal robust without resetting/reprogramming. Require 100 complete
  responses, 84/84 scored packets, 168/168 actions and zero timeouts in each.
- **Coverage gaps (including the attachment):** warm-up responses must arrive but their fields/actions are
  not checked for correctness. Each script runs one session. Custom tests must
  check warm-up bytes, full-range prices, and repeated index-0 sessions, including
  swaps during warm-up.
- **Outputs:** robust writes `trade_results_100.csv` and
  `trade_summary_100.txt` in its working directory. Run each measurement in a
  fresh results directory to preserve earlier outputs. Its points estimate is
  correctness-only, out of 70.
- **Measurement:** robust's average includes every complete response, including
  warm-up and incorrect responses, but excludes timeouts. Timing covers the
  write/read transaction. Report correctness and timeout counts alongside latency.
- **Automation:** do not equate exit status zero with passing. Quick prints
  mismatches without a failing exit code; robust writes its counts/summary even
  after a timeout. Require 84/84 correct packets, 168/168 correct actions, and
  zero timeouts for a complete robust pass.

For the beginner replay tasks, use these scripts as the compatibility baseline:
the fixture/oracle owner adds independent boundary and repeated-session vectors;
the runner/results owner preserves official outputs and builds separately
labelled custom replay/analysis tooling. The scripts have been read, not run
against a board during this review.

## 3. Frozen external behavior

### Board and wire protocol

- Tang Nano 20K, `GW2AR-LV18QN88C8/I7`, onboard **27 MHz input reference** at
  `sys_clk`. Internal processing may use a PLL-derived clock; retain the direct
  27 MHz configuration as the initial baseline and fallback.
- Use the organizer-supplied `.cst`. Required port names are `sys_clk`,
  `reset_btn`, `uart_rx_i`, `uart_tx_o`, `led0_n`, and `led1_n`.
  Keep optional ports; unused active-low LEDs are driven high.
- UART: **115200 baud, 8N1, LSB-first bits**. Multi-byte fields are big-endian.
- All parsing, state, computation, and response generation run on the FPGA.

| Byte | Request | Response |
| --- | --- | --- |
| 0–1 | 16-bit index | Echo index |
| 2 | Slot 1 item ID | Echo slot 1 ID |
| 3 | Slot 1 price, high byte | Slot 1 action |
| 4 | Slot 1 price, low byte | Echo slot 2 ID |
| 5 | Slot 2 item ID | Slot 2 action |
| 6–7 | Slot 2 unsigned 16-bit price | `0x0000` |

IDs: A = `0x11`, B = `0x22`. Actions: NONE = `0x00`, SELL = `0x01`, BUY = `0x02`.

Exactly one eight-byte response per request. **Do not start a response before
all eight request bytes arrive.** Echo item order, but route state by item ID.
The official run is 100 requests, indices 0–99, stop-and-wait. A one-second
response timeout ends the run; remaining packets score zero.

### Algorithm and session reset

For each item, keep its own 16-price window, 20-bit sum, 16-bit previous price,
and last action (initially NONE).

**Index 0:** logically clear both items' previous-session state, then insert
this request's prices as the first samples. This must work without board reset
or reprogramming.

**Indices 0–15:** insert prices, accumulate sums, update previous prices, and
return NONE for both slots. Do not evaluate crossings.

**Index 16 onward**, independently for each item:

```text
old_average = old_sum >> 4
new_sum = old_sum - oldest_price + current_price
new_average = new_sum >> 4

if previous_price <= old_average and current_price > new_average:
    action = BUY
else if previous_price >= old_average and current_price < new_average:
    action = SELL
else:
    action = last_action

replace oldest window entry with current_price
store new_sum, current_price as previous_price, and action
```

Both averages truncate downward. The first comparison uses **old** state; the
second uses the window **including the incoming price**. No crossing holds the
last action. Slot swaps must never swap the items' histories.

The guide and inspected participant scripts use both items exactly once per
request and sequential indices. A shared window position is valid under that
contract. Duplicate/unknown IDs and nonsequential indices are unspecified
extensions, not reasons to build a general packet processor now.

## 4. Starting architecture

**Start with one shared sequential update engine.** This is the chosen starting
design, not a claim that sharing will synthesize smaller.

```text
UART RX → eight-byte capture → item/slot selection → shared update engine
                                                      ↕
                                           A/B state + history RAM
                                                      ↓
UART TX ← paced response sequencer ← echoed fields + slot actions
```

| Boundary | Responsibility |
| --- | --- |
| Board top | Fixed ports, 27 MHz reference input, selectable direct/PLL internal clock, lock-aware startup/reset, RX synchronization into the selected domain. |
| UART RX/TX | Byte-level receive-valid and transmit-ready/busy interfaces; correct framing and tunable TX idle gap. |
| Packet controller | Capture one complete request, dispatch the two slots, emit exactly one ordered response. |
| Update engine | Consume item ID/price and session/warm-up context; return the action after updating that item's state. |
| History/state | Item-indexed storage; explicit memory read latency and write semantics. |

### Clocking decision: configurable frequency, one processing domain

The permission adds an optional optimization axis; it does not require replacing
the shared sequential engine with a deeply pipelined design. Keep the correctness
path moving at 27 MHz. Under the placement supplement, prioritize resource
sharing at 27 MHz; prepare a PLL option only for a measured resource-saving or
qualification hypothesis.

```text
sys_clk (27 MHz reference)
    → build-time choice: direct connection OR Gowin PLL
    → core_clk → RX synchronizer, UART, protocol, engine, memory, status logic
```

Use one selected internal clock for the first PLL experiment. Selection is at
build time, not a combinational runtime clock mux. UART baud remains 115200 by
changing its timer divisors. Do not introduce a slow-UART/fast-engine split
unless measurements justify the extra crossings, handshakes and reset complexity.
If that split is later chosen, it needs explicit related-clock timing or CDC
design; a two-flop synchronizer on each payload bit is not a coherent bus transfer.

[Sipeed's board documentation](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
confirms the FPGA has two PLLs and a 27 MHz board clock. Use the **internal FPGA
PLL**; changing the separate board clock-generator/BL616 configuration is not
part of this plan. Select the exact-device PLL IP using the installed Gowin
tools and verify legal input, VCO, divider, output and speed-grade limits.
PLL output capability alone does not establish the design's achievable frequency.

Implement the following before enabling a PLL build:

1. Separate `reference_clock_hz` from the selected `core_clock_hz`. One build
   configuration must determine the PLL parameters, actual output frequency,
   timing constraints and all time-based counters. Record requested and actual
   frequency if they differ. Preserve the current direct-clock target.
2. Derive UART bit/half-bit counts, heartbeat and extra TX idle counts from the
   **actual** core clock. Specify TX gaps in physical time and document rounding;
   holding the same cycle count at a higher clock silently shortens the gap.
   Audit counter widths and reject inconsistent configuration. Current UART
   defaults are fixed at 234 clocks/bit and need this integration work.
3. Encapsulate the vendor PLL in a small board-clock wrapper. Include every
   required generated IP source/configuration in the reproducible manual Gowin
   handoff. A simulation-only PLL model must never substitute for hardware RTL.
4. Hold functional logic reset while the PLL is unlocked; assert reset on lock
   loss and release synchronously in `core_clk` after qualified lock. Keep the
   PLL's own reset independent of the functional reset so waiting for lock does
   not keep the PLL itself in reset. TX must stay idle high during startup or
   loss of lock, even if core clock edges stop; synchronous-only clearing is
   insufficient for that case. Reinitialize control/scalar state on recovery.
5. Keep the physical 27 MHz input constraint and constrain/verify the derived
   clock relationship using the installed Gowin flow. Check whether PLL clocks
   are derived automatically before adding explicit generated-clock constraints;
   avoid duplicate clocks. Review setup/hold, recovery/removal, clock routing,
   memory timing and unconstrained paths. Do not hide failures with blanket
   false paths or change the input constraint to pretend the oscillator is faster.
6. Test direct and PLL configurations, startup, reset, delayed lock and lock
   loss. Functional simulation with an ideal core clock validates logic, not
   analog PLL lock/jitter or routed timing. Require Gowin and board evidence
   before making a PLL build the selected competition build.

### Pipeline depth, sharing, and frequency: minimize resources within qualification

For a fixed implementation, processing latency is approximately `L / f`, where
`L` is the measured cycles from complete-request acceptance to response-ready
and `f` is the implemented core frequency. Include memory, dispatch and handshake
cycles; count warm-up, steady-state and session-start paths separately.
End-to-end latency also includes UART reception/transmission, intentional gaps
and host/USB overhead. Only part of that latency scales with `f`.

Pipelining can increase achievable frequency and throughput while **increasing
cycle latency**. A change improves core latency only if `L_new / f_new` is lower.
The official stop-and-wait stream gives little reason to pursue one new request
per clock. Feedback through each item's window/sum also imposes dependencies.
Keep valid/ready boundaries insensitive to engine latency; do not add fixed-cycle
assumptions to the controller or tests. Existing engine result handshakes support
different internal schedules without changing the wire protocol.

Illustrative arithmetic only, **not measured designs or validated PLL settings**:

| Request processing cycles | Core frequency | Processing time |
| --- | --- | --- |
| 20 | 27 MHz | 0.741 µs |
| 20 | 54 MHz | 0.370 µs |
| 20 | 108 MHz | 0.185 µs |
| 40 | 108 MHz | 0.370 µs |
| 100 | 108 MHz | 0.926 µs |

Even the illustrative 20-cycle 27→108 MHz change saves only about 0.556 µs,
around 0.04% of the nominal 1.39 ms UART wire time. Do not predict a fourfold
improvement in the judged round trip from a fourfold clock increase.

More cycles can provide budget for **more resource sharing**, first at 27 MHz:
less arithmetic hardware may retain qualification latency with fewer total logic
elements. Consider higher frequency only if needed for that resource-saving
schedule. Compare shared add/subtract, a shorter combinational schedule, and
register cuts at measured critical paths. Explicitly selecting one shared
operator may be necessary; sequential source statements do not prove sharing.
Pipeline registers consume FFs and can add enables/muxes, routing and LUT cost;
faster UART timers may also need wider counters. Measure the whole top.

### Datapath and storage decisions

1. **History:** begin with a circular `32 × 16` history store addressed by
   `{item_select, window_position}` and target Gowin block RAM. Prove the mapping
   in a small synthesis experiment before depending on it. If inference is
   unsuitable, use a narrow vendor wrapper or compare a register implementation.
2. **State:** two sums, two previous prices, two held actions. A shared 4-bit
   window pointer is sufficient under the verified one-update-per-item packet
   contract. Preserve full request index and IDs for echoing.
3. **Arithmetic:** unsigned prices/averages are 16 bits; sums and subtract/add
   work registers are 20 bits. The maximum sum is `16 * 65535 = 1048560`.
   Subtract the oldest price before adding the new one. Explicitly zero-extend
   operands and retain the old-average comparison before overwriting the sum.
   Average extraction is the sum's bits `[19:4]`, not a divider.
4. **Reset:** use logical window invalidation rather than resetting RAM cells.
   Clear scalar state on index 0; during warm-up skip history subtraction and
   overwrite every entry before it can be read as valid. Verify equivalence to
   a cleared window for complete repeated sessions. Startup must also initialize
   UART/parser/control so the first index-0 packet can actually be received.
5. **Buffering:** one captured request and two slot-action registers are enough
   for stop-and-wait. Build response bytes from retained fields and constants;
   add storage only if synthesis or integration justifies it.

### Initial execution schedule

Accept the complete request → apply any session reset → select slot 1's item →
read its oldest sample/state → retain old comparison predicates → subtract old
sample → add new sample → compare and commit state/action → repeat for slot 2 →
launch response. During warm-up, bypass history reads/subtraction and crossing
evaluation, accumulating the price and returning NONE instead. Account explicitly
for the selected RAM's read latency; commit each item's update exactly once.
Advance the window position once after both updates.

Keep this simple sequential schedule for the first correct implementation.
Twenty clocks at 27 MHz take about **0.74 µs**; the 16 UART bytes alone take
about **1.39 ms**, and the guide reports much larger USB/host overhead. Optimize
internal parallelism only when reports show a worthwhile improvement.

### Transport reliability

Synchronize asynchronous RX and validate receive sampling/framing. Make TX byte
spacing a **build-time parameter**, initially conservative and then tuned on the
board. The guide specifically warns that BL616 can corrupt/drop back-to-back
response bytes. Every added gap is part of judged latency. Preserve the normal
stop bit in all experiments; verify repeated runs rather than choosing the
fastest setting that passed once.

## 5. Implementation gates

Each gate needs saved evidence before it is called complete. These are the
ordered milestones; independent software and transport work can overlap.

**Implementation-agent rules (user clarification, October 3):** no mutative Git
operations, including staging, committing, pushing, switching/resetting/restoring,
stashing, merging/rebasing, fetching/pulling, or modifying branches/worktrees/Git
configuration. Read-only Git inspection and task-scoped source/RTL edits are
allowed; preserve existing staged and unstaged work. Do not mark a phase or gate
complete until its required manual synthesis/P&R, bitstream generation,
programming and applicable board tests have actually been performed by the user
and passing results supplied for the delivered candidate. Finish local work and
give exact manual instructions first; record **locally verified — awaiting manual
checks** while those checks are pending. Historical evidence only covers the
build and behavior it actually tested. See REQUEST_RESPONSE_PLAN.md §2 and the
individual phase's manual-acceptance checklist for the detailed policy.

**Phase C (October 3): COMPLETE.**
The TX audit retained the existing implementation and production direct 27 MHz
configuration. Added an independent all-byte, 15-configuration timing/boundary
suite; build, focused tests, full regressions and generated-Verilog checks pass.
Transport RTL is byte-identical to the pre-task file. See
[`results/phase-c-20261003-candidate1/HANDOFF.md`](results/phase-c-20261003-candidate1/HANDOFF.md)
for the original source/RTL identity and manual checklist. Synthesis/P&R,
timing review, bitstream generation/programming, startup/reset/TX-idle checks
and both 100-request transport checks now have passing evidence or user
confirmation. See REQUEST_RESPONSE_PLAN.md §11 for the closing record.

October 3 follow-up: after the user reported programming a fresh bitstream,
both custom 100-request transport checks were run on the identified Sipeed
serial interface and passed (zero mismatches/timeouts/surplus bytes; exit 0).
New outputs are in
`results/phase-c-20261003-candidate1/board-tests-20261003T174429.688210Z/`.
The user confirmed the programmed bitstream was built from the delivered artifacts.

October 3 clarification: the user waived bitstream hashes and report archival
for this early Phase C delivery. Current Gowin P&R/timing outputs were reviewed
in place: the delivered RTL is the project input, 27 MHz setup/hold timing has
zero violations (worst slacks +31.839 ns / +0.425 ns), and P&R/bitstream generation
completed. PR1014 is recorded as a clock-routing caveat; the report still lists
PRIMARY clock distribution. The user subsequently confirmed startup/reset/TX-idle
checks and explicitly requested Phase C closure. Final acceptance is checked;
no Phase C work remains. This validates diagnostic transport, not algorithm PASS.

| Gate | Work | Exit evidence |
| --- | --- | --- |
| **0 — Inputs and build** | Integrate the available organizer scripts/constraints from the pinned sibling checkout; pin OCaml/Hardcaml and Gowin versions. Generate a minimal Hardcaml top and exercise intended history-memory mapping. | Reproducible generation + synthesis + P&R for the target part; inspect actual mapped memory and timing constraints. |
| **1 — Oracle and UART** | Write the independent software model and hand-checked vectors. Bring up the exact packet receiver/response sequencer on the board with placeholder actions. | Reference fixtures reviewed; repeated packet traffic has correct echoes/length/order, no early TX, and no timeouts. Full quick-test PASS requires Gate 2's algorithm; use separate transport checks here. |
| **2 — Complete correctness** | Implement and integrate the rolling windows/crossings/session reset. Compare simulation with the oracle, then run official tests. | Quick PASS; normal robust followed by full-range practice passes without reset/reprogramming; exact custom warm-up/repeated-session/slot-swap checks pass; retain CSVs and known-good `.fs`. |
| **3 — Qualification baseline** | Save whole-design Gowin V1.9.11.03 synthesis/implementation and official-style outputs for a fixed build. | Local evidence supports 100/100 plus full-range pass; record synthesis LUTs separately from Resource Usage Summary total logic/registers, BSRAM, timing, latency, source/settings/bitstream identity, host setup and TX gap. Official qualification is determined by judges. |
| **4 — Resource-first optimization** | Change one measured cost at a time; preserve qualification and compare total logic, then registers, then five-run median latency. | Improvement in ranking order without qualification regression; keep a known-good fallback and record rejected candidates. |
| **5 — Freeze and submit** | Rebuild/program the selected design, rerun both scripts, complete README, publish matching source/build/bitstream, submit and return board. | Public repository; final `.fs` matches source; final commit SHA in Devpost; submission and return completed before the deadline. |

**Immediate assignments:** one owner integrates the available organizer assets and proves
the Hardcaml/Gowin path; one builds UART/packet handling; one writes the oracle
and vectors; one prepares the repeatable test/results workflow. Agree byte and
engine interfaces first so these tasks can progress independently.

**Phase G split (October 3):** the request/response plan now assigns **G1** to
the production transaction controller and its integration tests with F's engine,
and **G2** to the competition board top, generator, serial end-to-end verification
and manual full-system acceptance. Progress **F → G1 → G2 → measured H**; G2 can
start after G1's local acceptance, with G1 hardware checks collected in G2's
matching build. Overall G still requires both parts. See
[REQUEST_RESPONSE_PLAN.md](REQUEST_RESPONSE_PLAN.md#phase-g--full-transaction-controller-and-competition-integration)
for ownership and acceptance criteria. This is a planning split, not a new
completion claim.

**G1 local evidence (October 3): Locally verified — awaiting manual checks.**
The controller and mock/real-engine/byte-composition tests pass, including all
800 fixtures, 3,414 additional oracle vectors and 455 reset-recovery packets.
All required local builds/regressions and emitted-RTL elaboration checks pass.
The [G1 handoff](results/phase-g1-20261003-candidate1/HANDOFF.md) records exact
interfaces, cycle measurements, source identity and G2 wiring instructions.
G2 may begin; G1 hardware acceptance still comes from G2's matching full-system
build. G2 and overall G remain open for manual acceptance; G2 local delivery
is recorded below.

**G2 local evidence (October 3): Locally verified — awaiting manual checks.**
The direct 27 MHz `gqh_competition_top` now connects UART, decoder, G1 controller,
F engine and sequencer. Production RTL and separate root Gowin project are
available. Serial oracle verification, production-divisor emitted-Verilog checks
and earlier regressions pass; see [integration coverage](test/integration/README.md)
and [candidate handoff](results/phase-g2-20261003-candidate1/HANDOFF.md).
Matching whole-design synthesis/P&R, memory/resource/timing/clock inspection,
exact bitstream identity, remaining startup/reset/status checks, robust/full-range
84/84 and 168/168 with zero timeouts, and custom same-connection sessions remain
pending. Subsequent partial board evidence records user-reported programming,
heartbeat/no-fault LED behavior and official quick PASS; see
`results/phase-g2-board-20261003-142516-thv362qq/manual-progress.md`.
F/G1 retain local status, and G2, overall G and H's measured baseline remain open.
Missing historical F/G1 result directories were not recreated as evidence.


**F–G closure (October 3): COMPLETE, explicitly authorized by the user.**
Fresh synthesis/programming, official quick/normal robust/full-range tests,
1,394-packet custom replay, fault/reset recovery and fresh startup pass. The user
accepts these results and waives remaining identity bookkeeping/separate TX-idle
measurement as F/G closure requirements; neither is falsely reported as performed.
See REQUEST_RESPONSE_PLAN.md's F–G closure. Earlier pending statuses above are
historical. H optimization, optional P and final submission freeze remain open.

### Gate 0 initialization evidence (October 2, 2026)

The project foundation is implemented: wrapped `hardcaml_gqh` library, manual
Gowin generator/handoff, six-port heartbeat top, separate synchronous-read
32 x 16 history probe, and pristine official inputs copied from the clean pinned
revision. See README and tools/official/README.md for commands, actual versions,
and checksums. Existing blinky/archive/guide inputs are preserved.

Local build, generation, Cyclesim behavioral checks, Icarus emitted-RTL simulation,
Yosys hierarchy/port/elaboration checks, repeated-generation equality and official
input checksums pass. No official serial tests were run and bring-up has no packet
or algorithm functionality. The active-high reset assumption derives from the
CST pull-down; emitted initialization must be confirmed in Gowin and on hardware.

**Gate 0 remains open:** user-run Gowin synthesis/P&R, actual history-memory
mapping/collision behavior, clock/timing review, startup initialization, reset
polarity and board operation all need new saved evidence under results/.
No block-RAM mapping or new Gowin/tool version is claimed from the old reports.

### Clocking follow-up (October 3, 2026)

Add the optional clocking work package **P** described in
[REQUEST_RESPONSE_PLAN.md](REQUEST_RESPONSE_PLAN.md). Parameter/configuration
work and a separate PLL transport experiment may proceed alongside engine work,
with one owner for shared board/generator files. They must not block F/G's
27 MHz correctness baseline. Preserve the already recorded A–E local evidence;
new clock settings require new timing/transport evidence.

Every PLL candidate repeats the relevant Gate 0 startup/clock/timing checks,
Gate 1 UART checks and Gate 2 full correctness checks. Gate 3 records its actual
frequency, pipeline/schedule and cycle latency. Gate 4 compares that candidate
against the baseline under the same host setup. No gate is satisfied by a higher
reported frequency alone.

### Verification required at Gate 2

- Exact byte order, echoed index/IDs, reserved zeros, response count, and no
  transmission before request completion.
- Warm-up, first scored update at index 16, and circular-buffer wraparound.
- Repeated index-0 sessions with different histories, without reprogramming.
- Normal official robust followed immediately by full-range practice without
  reset/reprogramming; require perfect scored results and zero timeouts in both.
- Arbitrary A/B slot swaps with deliberately different item histories.
- Equality boundaries, truncated averages, zero/max prices, and large jumps.
- Holding BUY and SELL across multiple non-crossing updates.
- Sum equals the current window's sum; stale RAM never contributes after reset.
- UART-level simulation, startup/reset behavior, and real-board transport tests.

Use an independent reference model that recomputes the sum from its window,
rather than copying the hardware's rolling-sum implementation. Keep custom
tests separate from the organizer scripts; the guide permits changing only
their `PORT` setting. Retain each local robust-test CSV.

## 6. Resource-first optimization and measurement discipline

**Qualification is a constraint; placement is lexicographic.** Among reliably
qualifying candidates, fewer total logic elements wins even with more registers
or slower latency. Compare registers only at equal total logic; compare five-run
median latency only when both resource counts tie, applying the 5% tie rule.
Keep enough latency/timing margin to qualify repeatedly on the judging host.

1. **Measure the complete baseline first:** use Gowin V1.9.11.03 and preserve
   Resource Usage Summary total logic/registers, synthesis LUTs, BSRAM mapping,
   timing and project settings. Quick, robust/full-range and custom practice tests
   now pass; final matching-build identity remains deferred. Archived report
   counts describe that earlier image, not automatically the newly flashed one.
   Attribute costs before choosing experiments.
2. **History and state storage:** prove the 32 × 16 history maps to BSRAM;
   BSRAM is excluded from placement logic. If inference fails, compare a vendor
   primitive wrapper. Experiment with additional item state in BSRAM where the
   saved logic/registers exceed address, mux and control overhead. Preserve
   logical invalidation and read latency; do not reset all memory cells.
3. **Shared arithmetic/comparisons:** the current shared item engine still
   expresses subtract and add as separate operations in one update path. Measure
   one time-multiplexed add/subtract unit, comparator reuse, and narrower
   digit-serial arithmetic over more cycles. Keep exact 16-bit values and 20-bit
   sums; serializing arithmetic is allowed, truncating prices is not. Include
   intermediate storage, muxes and FSM cost in the whole-design comparison.
4. **Packet/control/UART overhead:** inspect duplicate payload registers across
   decoder/controller/engine/sequencer, retained fields, enables and state
   encoding. Reuse storage only when lifetimes and valid/ready stability permit.
   Evaluate timer sharing only with a proven receive/transmit lifecycle and
   retained fault/reset behavior. Measure total logic first, registers second.
5. **Clock/schedule:** use extra 27 MHz cycles before adding a PLL or pipeline.
   Higher frequency is justified by a measured resource-saving schedule or a
   qualification need, accounting for wider timers and lock/reset logic. Package
   P remains required for any PLL candidate; no speculative Fmax escalation.
6. **Latency margin and final tie-break:** tune TX spacing when needed for
   reliable qualification. For equal logic/register counts, preserve five-run
   latency results and their median; within 5% is a placement tie. Cut-through
   or extra parallelism must justify its resource cost under this ordering.

Make one attributable change per candidate, rerun relevant local/board checks,
and retain the best qualifying fallback. A logic-saving serialization may be
worth many additional core cycles given sub-microsecond current processing and
millisecond host round trips, but measure the resulting complete transaction.
With the October 4 freeze approaching, prefer verified resource reductions over
unfinished redesigns.

For every candidate record source revision (and dirty diff), **Gowin version and
all project settings**, generated RTL and bitstream identity, actual frequency,
schedule, processing cycles/time, **Resource Usage Summary total logic and total
registers**, separate **synthesis LUTs for rubric qualification**, BSRAM/PLL use,
routed timing, UART divisor/baud, physical TX gap, host setup, normal/full-range
and custom correctness/timeouts, official average latency and five-run median
when comparing the latency tie-break. Preserve raw reports and CSVs.

Do not substitute a LUT-only count or generic-tool estimate for the placement
total. Verify the judge-specified Resource Usage Summary in the actual Gowin
flow, including LUTs, ALUs and other logic types. Local numbers predict the
judge rebuild; self-reported counts are not authoritative. All resource-saving
changes must preserve the original ≤542 synthesis-LUT qualification condition.
Distinguish core processing time from host round-trip latency; archive all five
run results rather than selecting a fastest run. The supplement does not spell
out the per-run latency statistic or denominator for the 5% comparison; preserve
raw samples and per-run summaries rather than inventing those judge details.

## 7. Team work split and repository shape

If the four-person structure from the original proposal still applies, use this
replacement split; assign names before work starts:

| Role | First deliverable | Continuing responsibility |
| --- | --- | --- |
| Lead / hardware | Hardcaml build + engine interface | Datapath, memory mapping, integration, area optimization. |
| Experienced teammate | UART + exact packet round-trip | Board transport, timing/reset review, pacing experiments. |
| Teammate A | Hand-checked protocol/session fixtures | Boundary tests, slot swaps, repeated-session regressions. |
| Teammate B | Independent reference model + comparison runner | CSV analysis, reproducible runs, results and submission README. |

Lead reviews the algorithm oracle; transport and hardware owners review their
shared interfaces. Every handoff includes an actual command, inputs, expected
outputs, and result. Fixture/testing tasks can run before a board is available.

Create directories as implementation needs them:

```text
src/             Hardcaml implementation and required RTL wrappers
rtl/             generated HDL used for the submitted build
constraints/     organizer .cst and clock/timing constraints
gowin/           competition project and reproducible build configuration
test/            independent model, fixtures, simulations, custom runners
tools/official/  organizer test scripts (only PORT changed for local use)
bitstream/       selected final .fs
results/         synthesis/timing reports, test CSVs, candidate measurements
```

The existing `viv25_proj/` is bring-up material. Create the competition project
with its correct ports/constraints rather than treating the blinky project as a
ready competition build.

## 8. Freeze, deadline, and remaining decisions

**Hard deadline:** Sunday, October 4, 2026, **11:00 am EDT**, for submission and
board/accessory return at Reitz Room 2345. Recheck organizer announcements.
Aim to freeze the selected build by **9:00 am EDT Sunday** (team planning target)
to leave time for final testing, upload, and return. Stop experiments earlier if
they threaten a verified submission.

The submitted repository must contain Hardcaml sources, the generated HDL used,
required dependencies/configuration, official constraints, Gowin project/build
files, test sources/data, and the matching final `.fs`. Judges program that
file into SRAM and run their own host software.

Complete the README with team/project name and members, implemented FPGA
functionality, local host tooling, board/part, languages, actual tool versions,
top module, build/program commands, input/output and reproduction steps,
verification and measured qualification LUTs, placement logic/register counts
and latency results, external-resource attribution,
and known limitations. Publish the repo and verify logged-out access. Put the
full final commit SHA in **Devpost**, not a self-referential README. The guide's
submission link is [gqhacks.devpost.com](https://gqhacks.devpost.com).

| Open item | Resolve when / why |
| --- | --- |
| Integrate official `.cst` and scripts | Copied unchanged with pinned provenance/checksums; local checks pass. Gowin/board Gate 0 evidence remains pending. |
| Custom-test coverage beyond supplied scripts | Gate 2; warm-up field checks, full-range prices, and repeated sessions. |
| Ranking beyond capped written scores | Resolved by October 3 supplement: qualification, then total logic → registers → five-run median latency (5% tie). |
| Hardcaml memory mapping and startup initialization | Gate 0 experiments, then Gate 2 board verification. |
| PLL configuration and useful frequency/schedule | Optional: pursue only for measured resource savings or qualification need. Package P validates the hardware option; 115200 baud remains fixed. |
| Reliable minimum TX gap | Gate 4 on the actual board/host, with repeated runs. |
| Named owners and public submission repository | Assign now; confirm the final project identity before freeze. |

## 9. Planning history

This plan consolidates the hardware pivot handoff and the verified competition
guide. The useful inherited practices are independent reference verification,
small reviewable interfaces, clear ownership, and reproducible measured results.
The original Tickweave proposal and prior handoff are preserved in
[archive/](archive/README.md). Their earlier task lists and authority statements
are historical; **update this file for current implementation decisions**.
