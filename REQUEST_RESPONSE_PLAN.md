# FPGA Request–Response Architecture and Implementation Plan

Status: packages A–E implemented and locally verified; custom transport board
checks pass. Algorithm packages F–G and synthesis/timing evidence remain pending.
PLL package P is planned, not
implemented or validated. Updated: October 3, 2026.

## 1. Purpose and authority

Build the complete request–response path for the Tang Nano 20K in Hardcaml:

```text
UART RX → request decoder → transaction controller → shared update engine
                                                        ↕
                                                history + item state
                                                        ↓
UART TX ← response sequencer ← echoed fields + computed actions
```

The board top supplies clock/reset and connects the physical pins. These are
logical responsibilities; they do not require a separate FSM for every box.

[PLAN.md](PLAN.md) remains the active competition plan and algorithm contract.
The organizer guide remains the primary specification. This document expands
the implementation boundaries and work assignments; it does not replace the
scoring, submission, or optimization requirements in PLAN.md.

First deliver a reliable byte-oriented transport, then integrate the complete
algorithm, then measure possible cut-through improvements. The user imports
generated Verilog into Gowin and handles synthesis/P&R and programming manually.

## 2. Existing foundation and working rules

The project already contains the wrapped `hardcaml_gqh` library, qualified
subdirectories under `src/`, board reset/heartbeat/top, a history-memory probe,
`bin/generate.ml`, official constraints/scripts, and local verification.

- Read applicable AGENTS.md instructions and inspect Git status before editing.
  This is an existing worktree, not a new repository. Preserve unrelated changes,
  including current board-top and Gowin-project edits.
- Read the actual source before assuming this plan's initial status is current.
- Use the installed `5.2.0+ox` switch. Installed Hardcaml interfaces under
  `~/.opam/5.2.0+ox/lib/` take precedence over upstream master API assumptions.
- Use `../hardcaml_networking/` as a read-only structural reference. Do not make
  the project depend on that sibling checkout or edit it as part of these tasks.
- Preserve the six board ports, official CST, bring-up target, and memory probe.
- Keep organizer test scripts pristine; put custom checks in separate files.
- Do not claim Gowin mapping, timing closure, or board success from simulation.
- **No mutative Git operations.** Implementation agents may edit task-scoped
  files and generate RTL, but must not change Git's index, refs, configuration,
  repository topology or stored history. Do not run `git add`, `commit`, `push`,
  `reset`, `restore`, `checkout`, `switch`, `clean`, `stash`, `merge`, `rebase`,
  `cherry-pick`, `fetch`, `pull`, branch/tag mutation, worktree mutation or
  `git config` writes. Read-only inspection (`status`, `diff`, `log`, `show`,
  `rev-parse`, etc.) is allowed; use `GIT_OPTIONAL_LOCKS=0` where appropriate.
  Preserve pre-existing staged and unstaged changes. Do not stage your own work.
  Any exception requires explicit user authorization for that operation.
- The user performs manual Gowin synthesis/P&R, bitstream generation, programming
  and board-test runs. Prepare the complete local deliverable and exact handoff
  first. Do not operate the IDE, programmer or serial device unless separately
  requested. Generated RTL and local reversible implementation work are in scope.

### Phase completion policy — required for every implementation agent

User clarification, October 3: **do not mark a phase COMPLETE until all required
manual checks have actually been performed by the user and their passing
results have been reported or supplied as artifacts.** Giving the user commands
does not count as running them. Local tests do not substitute for board checks.

Use distinct statuses:

- **In progress:** implementation or required local verification remains.
- **Locally verified — awaiting manual checks:** implementation, relevant local
  tests and RTL generation are finished; enumerate the remaining user actions.
- **Complete:** all required local and manual checks pass for the delivered
  version, and the evidence and its scope are recorded.

Before the handoff, list the phase's concrete required manual checks, using its
acceptance criteria and the applicable Gowin/board handoff. Hardware-affecting
phases require synthesis/P&R and timing review, bitstream generation, programming,
and the relevant board tests. Pure type/documentation work may have no hardware
checks; record that explicitly instead of inventing unrelated tests.

Record the delivered source state (including any dirty diff), generated RTL hash,
programmed bitstream identity/hash, tool/configuration details, manual commands
and reported results when collecting new hardware evidence. No Git commit is
needed to identify a candidate. Existing reports remain historical evidence;
reuse them only when their build identity and test coverage establish that they
apply to the delivered version. A new TX/clock/reset change requires renewed
affected hardware checks. Do not silently erase earlier results or reopen
unrelated completed phases.

Never add a `COMPLETE` heading, tick an overall completion box, or describe a
phase as finished while manual checks remain. A checked **locally verified**
box records only that narrower status. Complete all authorized local work before
handing off; it is appropriate to end the turn with the manual checks pending.
Ask for the actual results when ready, not for permission to perform ordinary
implementation. User silence or elapsed time is not a passing result.

## 3. Frozen external behavior

- Device: Tang Nano 20K, `GW2AR-LV18QN88C8/I7`; reference input: 27 MHz.
  The October 3 user-reported clarification permits internal PLL clocks; see
  PLAN.md for source, clocking policy and measurement requirements.
- Ports: `sys_clk`, `reset_btn`, `uart_rx_i`, `uart_tx_o`, `led0_n`, `led1_n`.
- UART: 115200 baud, eight data bits, no parity, one stop bit; bits LSB first.
- Multi-byte protocol fields are big-endian.
- One eight-byte request produces one eight-byte response.
- No response starts before all eight request bytes have been received.
- The host uses stop-and-wait: it waits for the response before the next request.

| Byte | Request | Response |
| --- | --- | --- |
| 0 | Index high | Index high |
| 1 | Index low | Index low |
| 2 | Slot 1 ID | Slot 1 ID |
| 3 | Slot 1 price high | Slot 1 action |
| 4 | Slot 1 price low | Slot 2 ID |
| 5 | Slot 2 ID | Slot 2 action |
| 6 | Slot 2 price high | Zero |
| 7 | Slot 2 price low | Zero |

IDs: A=`0x11`, B=`0x22`. Actions: NONE=`0x00`, SELL=`0x01`, BUY=`0x02`.
State belongs to item IDs; response order belongs to request slots.

## 4. Component ownership and proposed layout

| Component | Proposed source | Responsibility |
| --- | --- | --- |
| Board integration | `src/board/transport_top.ml`, later `competition_top.ml` | Pins, existing reset release, RX synchronization, status LEDs |
| UART RX | `src/uart/rx.ml` | Start detection, bit sampling, stop validation, byte events |
| UART TX | `src/uart/tx.ml` | Byte acceptance, serialization, full bit periods, TX spacing |
| Shared contracts | `src/protocol/types.ml` | Request/response records, widths, protocol constants |
| Request decoder | `src/protocol/request_decoder.ml` | Byte position, field assembly, complete-request handshake |
| Transaction controller | `src/protocol/transaction_controller.ml` | Session reset, slot dispatch, response assembly, lifecycle |
| Response sequencer | `src/protocol/response_sequencer.ml` | Response bytes and TX handshakes |
| Shared engine | `src/engine/update.ml` | One item's arithmetic, comparisons, and state update |
| History/state | Within `src/engine/`, split only where useful | 32 × 16 history and two items' scalar state |
| Verification | `test/uart/`, `test/protocol/`, `test/engine/`, `test/integration/` | Owned, independently runnable suites |

Use typed Hardcaml I/O and `create`/`hierarchical` boundaries. The contracts task
finalizes OCaml names before dependent tasks start. Avoid empty implementation
modules; create files when implementing their responsibility.

## 5. Shared interface contracts

All functional logic runs on one selected `core_clk`: directly connected to
`sys_clk` in the existing 27 MHz baseline, or supplied by a validated Gowin PLL
in an optional build. Timers generate enables, not fabric clocks. Clock selection
is at build time; do not introduce a runtime logic mux or split UART/engine
domains in the initial PLL experiment. The external `sys_clk` remains 27 MHz.
Internal reset is active high. The PLL variant needs lock-aware assertion and
synchronous release in `core_clk`, extending the existing reset scheme; see
package P. The board synchronizes RX through two registers in the selected
domain. `Uart.Rx` receives that synchronized signal. Initialize/reset the
synchronizer to UART idle high.

For every valid/ready interface, a transfer occurs on a rising clock edge with
both asserted. Producers hold valid and payload stable until acceptance.
Do not confuse these handshakes with one-cycle event pulses.

### UART RX → request decoder

| Signal | Width | Meaning |
| --- | --- | --- |
| `byte_data` | 8 | Complete received byte |
| `byte_valid` | 1 | One-cycle pulse after a valid stop sample |
| `framing_error` | 1 | One-cycle pulse for an invalid stop sample |

Data is already complete during the valid cycle. Valid and error are mutually
exclusive. There is no RX ready signal: the external UART has no flow control.
The decoder must consume each valid byte while receiving a request.

### Request decoder → transaction controller

Payload: `index[15:0]`, `slot1_id[7:0]`, `slot1_price[15:0]`,
`slot2_id[7:0]`, `slot2_price[15:0]`; handshake: `request_valid/request_ready`.

Assemble fields directly as bytes arrive; a second 64-bit raw packet buffer is
unnecessary. Publish only after byte 7, including that newly arrived low byte.
Retain the payload until accepted. Index classification can be combinational
from the retained index; it does not independently reset algorithm state.

### Transaction controller ↔ update engine

Use a single outstanding update command:

- Command payload: `item_select` (A=0, B=1), `price[15:0]`,
  `window_position[3:0]`, `warmup`.
- Command handshake: `update_valid/update_ready`.
- Result payload: `action[1:0]`; handshake: `result_valid/result_ready`.
- Separate `session_clear` pulse, accepted only while the engine is idle with
  no pending result. It clears both items' scalar state, not RAM contents.

The controller owns the shared window position and advances it once after both
item updates complete. On index 0 it resets that position and issues
`session_clear` before dispatching slot 1. Indices 0–15 select warm-up behavior.
Slot IDs are mapped to item selections at dispatch. Unknown/duplicate IDs and
nonsequential indices are outside the official contract; do not build a general
packet processor to support them.

The engine commits each accepted command exactly once before presenting its
result. A stalled result handshake must not repeat the update. There is no
tentative execution in the baseline: commands originate only from a complete
accepted request.

### Transaction controller → response sequencer

Payload: retained `index`, `slot1_id`, `slot2_id`, and two 2-bit actions;
handshake: `response_valid/response_ready`. The sequencer zero-extends actions
to bytes and generates the two reserved zero bytes.

The sequencer accepts one response, holds its fields internally, emits exactly
eight bytes, and pulses `response_done` after the final frame finishes. The
controller rearms request reception only after that completion.

### Response sequencer → UART TX

Signals: `tx_data[7:0]`, `tx_valid`, `tx_ready`, plus TX's `tx_busy` output.
TX latches the payload on acceptance. The caller may change it afterward.

Define busy as high throughout the frame and configured extra idle gap. Ready
is high only when another byte can be accepted. Following acceptance of byte 7,
the sequencer waits for TX to become idle before pulsing `response_done`.

### Reception lifecycle and error policy

Expose a receive-enable input to the decoder, driven by the transaction
controller. It stays enabled while collecting a request and is disabled once
that request is accepted, until response completion. A decoder holding a valid
request must not overwrite it even before the controller accepts it.

For the initial diagnostic implementation, a framing error while receiving a
request aborts that partial request and latches a protocol fault. An unexpected
byte while a request is held or the transaction is busy also latches a fault.
The fault inhibits acceptance of new requests until board reset. An already
accepted transaction may finish; partial data must never become another request.

This deliberately simple fault policy is outside normal valid stop-and-wait
traffic. There is no guaranteed automatic packet realignment: the protocol has
no sync marker, length field, or checksum. Do not claim that clearing the byte
counter or observing index 0 alone repairs a dropped-byte stream. Do not invent
an inter-byte timeout that rejects legitimate host pauses. More elaborate
recovery needs an explicit later decision and tests.

## 6. UART timing design

At 27 MHz and 115200 baud, a bit is 234.375 system clocks. Start with a build-time
integer divisor of 234 clocks (approximately +0.16% baud error), configurable
for simulation. This remains the baseline. Package P derives the divisor from
the actual selected core frequency and 115200 baud, reports the resulting baud
error, and scales heartbeat/idle-gap counts to preserve physical durations.
Never reuse 234 at a higher clock. Use independent RX/TX counters and test timing
mismatch. The engine/controller interfaces must tolerate changed cycle latency.

RX sequence:

1. Observe idle high, then a falling edge on synchronized RX.
2. Check the candidate start bit near its center, half the configured bit period
   later (approximately 117 clocks in the baseline).
   Reject a false start without publishing a byte.
3. Sample d0 through d7 at full-bit intervals; assemble the byte LSB first.
4. Sample the stop position high, then publish the complete byte; otherwise
   report framing error. Re-arm safely for back-to-back frames and avoid treating
   a continuously low break condition as repeated new starts.

TX sequence: accept/latch byte → full start bit → eight full data bits → full
stop bit → configurable extra idle gap → ready. Rephase its timer on acceptance.
Specify whether terminal counts are inclusive and test durations to catch
off-by-one errors. Reset immediately returns TX to idle and cancels an in-flight
frame. Extra gap never replaces or shortens the mandatory stop bit.

The networking reference must be adapted: its RX valid spans STOP, it does not
check the stop bit, and its externally phased tick is not a sufficient receive
sampling contract. Its TX reads the caller's byte throughout transmission and
does not expose ready/busy. Do not inherit those behaviors accidentally.

## 7. Processing-engine baseline

Implement the exact algorithm in PLAN.md, with one shared sequential engine:

- History: 32 × 16 circular store addressed by `{item_select, window_position}`.
  Respect explicit synchronous read latency. Confirm Gowin mapping separately;
  the existing probe does not prove inferred block RAM on the board.
- Per item: 20-bit sum, 16-bit previous price, 2-bit held action.
- Index 0: logically clear both items, then insert the request's first samples.
- Warm-up indices 0–15: accumulate, overwrite history, update previous price,
  return NONE, and never subtract stale/unwritten history.
- Thereafter: retain old average/comparison, subtract oldest price, add current
  price, compare with the new truncated average, and update exactly once.
- Zero-extend prices for arithmetic. Averages are sum bits `[19:4]`.
- Preserve held action when no crossing occurs. Maximum sum is 1,048,560.
- Do not clear RAM cells on board/session reset. Warm-up overwrites the complete
  logical window before its old contents can contribute.

Use an independent software oracle that recomputes sums from stored windows,
rather than reproducing the hardware's rolling-sum implementation.

## 8. Agent work packages and dependencies

Each assignment should tell an agent to read this document and PLAN.md, implement
only its package, run its focused checks, and report remaining limitations.
Do not treat a package handoff as permission to implement all later packages.

### Phase A — Freeze contracts and test layout — COMPLETE

**Status: complete.** Typed payloads and protocol constants are implemented in
`src/protocol/types.ml`; handshake names and fault/receive-enable ownership are
established. Test layout and explicit module ownership are in place. Build and
existing regressions pass; see the evidence in §11.

**Depends on:** existing scaffold. **Owns:** `src/protocol/types.ml`, shared test
helpers/layout, minimal shared Dune changes, contract clarifications here.

Deliver compiling request/response types and constants, finalized handshake
names, and test ownership conventions. Record fault/receive-enable ownership.
Keep mocks in tests. Preserve existing tests; when adding test executables,
explicitly assign modules so Dune does not claim the same module twice.

**Acceptance:** existing build/tests pass; later agents can implement against
the types without guessing payload widths or handshake semantics.

### Phase B — UART receiver — COMPLETE

**Status: complete.** `src/uart/rx.ml` implements start-edge timing, start/stop
validation and one-cycle byte/error events. Independent local checks cover all
256 bytes, back-to-back frames, tested baud mismatch, false starts, framing
errors, long low input and reset. The board transport also passed both
100-request checks on October 3; see §11 for coverage and results.

**Depends on:** A. **Owns:** `src/uart/rx.ml`, `test/uart/rx/`.

Implement the RX timing/state machine and byte/error events. Test with an
independent serial waveform source, not only the project's TX.

**Acceptance:** representative/all byte values, back-to-back frames, varied
start phase, nominal and modest positive/negative baud mismatch, false starts,
invalid stop, long low input, reset mid-frame, and exactly one valid pulse per
good byte. State the tested mismatch range; do not claim universal tolerance.

### Phase C — UART transmitter — COMPLETE

**Status: complete (October 3, 2026).** The user confirmed startup/reset/TX-idle
checks and explicitly requested closure. Local tests, matching-artifact Gowin
synthesis/P&R and timing review, programming and both 100-request transport
checks passed. The user waived bitstream-hash and report-archival requirements
for this early delivery. See the closing evidence in §11.

October 3 focused audit
found no TX implementation defect; retained the existing hardware and added an
independent boundary suite. Current candidate and local evidence are recorded
in §11 and `results/phase-c-20261003-candidate1/HANDOFF.md`.
Final acceptance is supported by this candidate's checks and user confirmation;
the earlier transport board runs remain historical evidence.

**Depends on:** A. **Owns:** `src/uart/tx.ml` and its tests. Existing TX tests live
in `test/transport/transport_tests.ml`; extend that suite or add an explicitly
owned `test/uart/tx/` suite without duplicate Dune module ownership.

Implement latched input, ready/busy, full bit periods, and build-time idle gap.
Test with an independent serial decoder/timing checker.

**Acceptance:** exact LSB-first framing and durations, data changing after
acceptance, valid held through stalls, consecutive transfers, zero/nonzero gap,
idle high, and reset during transmission. No shortened first start bit.

**Required manual acceptance:** after local verification, hand off the generated
transport RTL and exact Gowin inputs. The user must synthesize/P&R for the stated
part, review relevant clock/timing reports, generate and identify the `.fs`,
program that build, and check startup/reset plus TX returning to idle. Then run
both custom transport checks against the programmed candidate:

```sh
python3 tools/check_transport.py PORT --count 100
python3 tools/check_transport.py PORT --count 100 --byte-pause 0.005
```

Require 100/100 matching responses and no timeouts or surplus bytes in each run.
Use the actual selected serial port; the earlier `/dev/ttyUSB1` is historical,
not a guaranteed current device. Save outputs and build/report identity in a
fresh results directory. Document and perform any additional board checks needed
for timing/gap/reset behavior changed by this delivery. Exact bit-duration and
handshake coverage also comes from the independent local checker; a host round
trip alone does not prove every waveform property.

The diagnostic target returns NONE actions. Official algorithm quick/robust
PASS is not required to close this TX-only phase and must not be claimed from
its custom tests. Leave the phase **locally verified — awaiting manual checks**
until the user supplies the required matching-build results. See §2 for the
completion rule and the prohibition on mutative Git operations.

### Phase D — Request decoder and response sequencer — COMPLETE

**Depends on:** A; can use byte-level mocks before B/C finish.
**Owns:** decoder/sequencer modules and `test/protocol/` suites for those blocks.
Original Phase D checks remain active in `test/transport/transport_tests.ml`;
the dedicated suite adds boundary scenarios without duplicating Dune ownership.

**Status: complete.** Local verification and applicable matching-build hardware
evidence are recorded in the October 3 Phase D closure below. Focused command:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/protocol/runtest
```

Also run `dune build @test/transport/runtest` in the same switch for the original
block tests and serial/emitted-RTL integration. See
[test/protocol/README.md](test/protocol/README.md) for ownership, reference testing
conventions, and precise pre-edge/post-edge sampling semantics.

Implement complete-request assembly, held payloads, response ordering, TX
backpressure handling, completion events, and the stated decoder fault policy.

**Acceptance:** all eight byte positions, distinct high/low bytes, arbitrary
inter-byte pauses, byte 7 included correctly, no request after seven bytes,
stable stalled requests/responses, exactly eight accepted TX bytes, reserved
zeros, final-frame completion, partial-frame abort, and busy-input fault.
Additional focused coverage: a second response held valid through Send/Drain;
exact acceptance/byte/completion counts under deterministic generated stalls;
reset at every partial/held request position, every sending byte and final drain;
fresh successful transfers after reset; and fault/acceptance collisions.

Collision policy: a framing error suppresses a held request before acceptance
and wins over final-byte publication. An unexpected byte on a held request's
acceptance edge does not overwrite its payload: the published request transfers,
then fault lockout blocks future reception. With ready low, no transfer occurs.
Tests exercise both ready values, sticky lockout and reset recovery. These
verification additions preserve the existing RTL behavior.

### Phase E — Transport integration and manual board handoff

**Depends on:** B, C, D. **Owns:** transport board top, a clearly named transport
harness, generator integration, custom host transport check, integration tests,
and transport documentation.

Implement a complete round trip with placeholder NONE actions and no engine.
Keep this harness separate from the production transaction controller. Add
`generate.exe transport` emitting `rtl/gqh_transport_top.v`, top
`gqh_transport_top`, with the official six ports and complete hierarchy.
Retain `bringup` and `history-probe` behavior and outputs.

**Acceptance:** serial-in to serial-out simulation checks exact response bytes,
no early TX, multiple stop-and-wait transactions, reset, and parameterized TX
spacing. Run emitted-Verilog elaboration. Provide manual Gowin instructions and
a custom host check that fails on mismatches/timeouts. Do not call placeholder
responses an official quick/robust algorithm PASS. Board testing is pending the
user's run, not a reason to leave local integration unfinished.

### Phase F — Independent oracle and engine

**Depends on:** A and finalized engine command contract. May proceed independently
of transport. **Owns:** `src/engine/`, `test/engine/`, custom algorithm fixtures.

Implement history/scalar state and the shared update engine. Build independent
window-based oracle checks and hand-checked boundary fixtures.

**Acceptance:** warm-up, index-16 first scored update, wraparound, held BUY/SELL,
equality and truncation boundaries, zero/max prices, distinct item histories,
slot swaps, repeated index-0 sessions including warm-up swaps, exact-once
updates under result stalls, and reset/session clear. Account for memory latency.

### Phase G — Full transaction controller and competition integration

**Depends on:** D, E, F. **Owns:** production transaction controller, competition
board top, generator integration, end-to-end tests, and final usage documentation.

Implement complete request acceptance → optional session clear → slot 1 update
→ slot 2 update → pointer advance → response handoff → response completion.
Add `generate.exe competition` emitting `rtl/gqh_competition_top.v`, top
`gqh_competition_top`. Do not silently change the default bring-up target.

**Acceptance:** compare full serial transactions against the oracle, including
swapped slots, full-range prices, repeated sessions, warm-up responses, no early
TX, correct response count, and reset. Locally elaborate emitted RTL and preserve
transport regressions. Then hand off official board-test commands to the user.

### Phase H — Measured optimization, only after a correct baseline

**Depends on:** G and saved correctness/resource/latency evidence.

Evaluate one change at a time: memory mapping, arithmetic/control area,
clock/schedule tradeoffs after P, TX gap, then early prefetch/field-level
computation if useful. P is required only for PLL experiments, not other H work.
First compare the unchanged engine at a modest legal PLL frequency with the
27 MHz baseline, holding physical UART timing constant. Then compare sharing
or pipeline changes at fixed frequency. Optimize measured cycles/frequency and
whole-top LUTs, not Fmax or initiation interval alone. Preserve a known-good
baseline and report actual synthesis LUTs plus complete measured latency results.
Bit/nibble-level UART outputs are not part of packages A–G.

### Phase P — Optional board clock configuration and PLL validation

**Depends on:** A–E transport foundation (locally complete). May proceed alongside
F without changing its functional contract. **Owns:** agreed clock configuration,
board clock/reset wrapper and PLL IP assets, dedicated clock tests, plus shared
generator/constraints/handoff changes coordinated with the integration owner.

This is a new package, not a reason to reopen completed A–E functionality or
delay the complete 27 MHz F/G baseline. Implement in two reviewable steps:

1. **Phase P1: configuration seam.** Separate reference/core frequency; derive UART,
   heartbeat and gap settings from actual core frequency, with rounding and
   width checks. Keep gap configuration in physical time at the build boundary.
   Preserve direct-clock target behavior and tests. One configuration must drive
   both RTL timing and the associated clock constraints; reject inconsistent
   PLL-frequency/divisor combinations. No PLL implementation required for P1.
2. **Phase P2: optional PLL target.** Generate/select exact-device Gowin PLL IP and
   preserve its sources/configuration in the repo. Add a separate PLL transport
   target with an explicit source manifest, leaving existing targets intact.
   Keep all functional logic in one core domain. Implement reset during unlock,
   qualified synchronous release after lock, lock-loss recovery and idle-high TX
   even when clock edges stop. Do not hold the PLL itself in reset through its
   own not-locked condition. Document generated-clock constraints and verify
   the routed clock reports. An initial 54 MHz candidate is provisional until
   legal IP settings, timing and board behavior are established.

**Local acceptance:** all direct-clock regressions pass; configured UART timing
and physical gap/heartbeat durations are checked at representative frequencies;
independent serial stimulus remains at nominal 115200 baud rather than copying
the DUT's divisor. Simulate delayed lock, reset and stopped-clock lock loss with
an explicit model. Core tests may bypass analog PLL behavior but must identify
that limitation. Emitted hardware must include the real PLL instance and required
wrapper definitions; use vendor simulation models or explicitly declared vendor
primitive boundaries for local elaboration. Do not mistake generic Yosys/Icarus
blackbox acceptance for validated PLL hardware.

**Gowin/board acceptance:** user runs synthesis/P&R for the actual part; save IP
settings, actual frequency, derived-clock/setup/hold reports, resource counts,
startup/relock checks and repeated custom transport results. Only then enable
the PLL option for the full competition design and rerun full correctness.
No new board verification is implied by adding this plan.

**Handoff:** exact generator command, actual clock/baud/gap values, complete
Gowin input list, test outcomes and remaining hardware evidence. Claim P1/local
P2/board P2 separately so another agent can continue without guessing status.

### Scheduling and shared-file rules

```text
A → B ─┐
  → C ─┼→ E ─┐
  → D ─┘     ├→ G → H
  → F ───────┘

A–E → P1 → P2 → H's PLL experiments
                  (full-design use also requires G and renewed correctness)
```

Packages may run one at a time. If multiple agents are explicitly assigned in
parallel, use these file boundaries and nominate one owner for shared files.
Only the current integration owner edits `bin/generate.ml`, board integration,
README, and common build configuration; other agents request changes or return
a concrete patch suggestion. Use package-local Dune files for owned tests.

Every handoff must include changed files, interfaces implemented, exact commands
run, outcomes, assumptions, pending hardware checks, and the next eligible task.
Update the checklist below only with evidence; distinguish local completion
from board validation. Do not mark another agent's package complete by inference.
Apply the §2 completion policy: explicitly say which manual checks are pending,
provide runnable user instructions, and wait for reported results before changing
the overall phase status to complete. Do not perform mutative Git operations as
part of preparing, recording or delivering a handoff.

## 9. Cut-through policy and expected benefit

The baseline already decodes bytes incrementally; it does not wait to capture
64 bits and then run a separate parsing pass. Algorithm execution begins only
after complete-request acceptance.

A future field-level experiment can prefetch state after an ID and calculate a
proposed slot-1 result after byte 4 while bytes 5–7 arrive. Stage tentative state
and defer commit/session reset until the request is accepted in full. This needs
an explicit extension of the engine contract; do not silently change its
commit-on-command behavior.

At 115200 baud, one 8N1 byte frame takes approximately 86.8 microseconds. The
remaining three frames provide about 260 microseconds of overlap opportunity,
not 260 microseconds of response-latency saving. The saving is the computation
removed from the post-reception critical path. Twenty clocks at 27 MHz are only
about 0.74 microseconds. The eight-byte request and response together require
about 1.39 milliseconds of wire time before extra gaps and host overhead.

Bit/nibble output is possible but tentative until stop validation. It couples
the decoder to partial-byte timing and may add control/state. Introduce it only
for a measured latency/area hypothesis, not as a prerequisite for streaming.

## 10. Verification commands and evidence

Run from this project with the existing switch:

```sh
opam exec --switch=5.2.0+ox -- dune build
opam exec --switch=5.2.0+ox -- dune runtest
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- bringup
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- history-probe
```

The following commands become available only after packages E and G respectively:

```sh
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- transport
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition
```

Each package adds a documented focused test command/alias. Integration checks
should elaborate the generated hierarchy with the existing Icarus/Yosys tools
and exercise actual emitted RTL where relevant. RX/TX loopback alone is
insufficient because shared timing bugs can cancel each other.

For board measurements preserve source/build identity, TX gap, tool versions,
synthesis total LUTs, memory/register usage, timing, correctness, timeouts, and
latency. Run official scripts in fresh results directories. Their exit codes
alone do not establish success; full robust success requires 84/84 packets,
168/168 actions, and zero timeouts. See PLAN.md for complete evidence requirements.

## 11. Progress checklist

- [x] A: contracts and test layout frozen; existing regressions pass.
- [x] B: UART RX locally verified.
- [x] C: UART TX locally verified.
- [x] C final acceptance: matching-build synthesis/timing, bitstream/programming,
  startup/reset and required custom board checks recorded for the Phase C delivery.
- [x] D: decoder/sequencer complete; local boundary coverage and unchanged-build
  transport hardware acceptance recorded in the October 3 closure.
- [x] E: transport integrated and emitted RTL locally checked.
- [x] E board follow-up: repeated custom transport checks pass on hardware.
- [ ] F: engine and independent oracle locally verified.
- [ ] G: complete serial system locally verified and RTL generated.
- [ ] G board follow-up: official tests and custom session/boundary tests pass.
- [ ] Baseline synthesis/timing/latency evidence saved.
- [ ] P1: clock-derived configuration implemented; direct-clock regressions pass.
- [ ] P2 local: optional PLL integration and lock/reset simulations pass.
- [ ] P2 board: legal PLL settings, timing/startup and transport evidence saved.
- [ ] H: each chosen optimization independently measured and regression-tested.

Local A–E handoff (October 2): typed payloads live in `src/protocol/types.ml`;
UART modules implement independent integer timers, pulse RX events and latched
ready/busy TX. Decoder owns sticky fault; the separate transport harness owns
receive-enable and blocks new requests until final-frame completion. Board top
includes idle-high two-stage RX synchronization and fault LED1. Defaults are
234 clocks/bit and zero extra TX gap. `generate.exe transport` emits the complete
six-port `rtl/gqh_transport_top.v` hierarchy. Existing bringup/default and history
probe are preserved, as are existing user edits to board top and Gowin projects.

Evidence: `opam exec --switch=5.2.0+ox -- dune build` and `dune runtest` passed;
`dune exec bin/generate.exe -- transport` generated the deliverable. Focused
checks run with `dune build @test/transport/runtest` in the same switch. RX was
tested independently at 100 clocks/bit against 98–102-clock sources, all 256
nominal bytes, back-to-back frames and error/reset cases. TX independent timing
checks cover zero/nonzero gap and latched data. Byte mocks cover packet fields,
stalls, fault lockout and final drain. Serial integration covers repeated
transactions and swapped slots; production-divisor emitted RTL passes Icarus
serial/reset/fault simulation and Yosys hierarchy/process/check. See
`test/transport/README.md` for full scope. Custom host fixture/CLI checks pass.
Official scripts and constraints remain pristine. Local checks do not establish
Gowin resource mapping or timing closure.

October 3 board follow-up: user programmed a fresh transport bitstream; both
custom checker runs on `/dev/ttyUSB1` exited successfully:

| Command | Responses | Mismatches/timeouts | Mean round trip | Maximum |
| --- | --- | --- | --- | --- |
| `python3 tools/check_transport.py /dev/ttyUSB1 --count 100` | 100/100 | 0 | 16.961 ms | 17.698 ms |
| `python3 tools/check_transport.py /dev/ttyUSB1 --count 100 --byte-pause 0.005` | 100/100 | 0 | 50.957 ms | 51.758 ms |

These runs support the A/B completion checks and establish the basic E board
transport follow-up, including legal inter-byte pauses. They check diagnostic
NONE-action responses only. The paused-run time includes host-inserted pauses.
Exact programmed bitstream identity and Gowin synthesis/P&R reports were not
captured in these runs; baseline resource/timing evidence remains pending.

Next eligible package: **F**, then **G** once the engine is independently
verified. The NONE-action transport is diagnostic only. Further manual board
checks can use `gowin/README.md` and the custom host checker; transport success
does not establish an official algorithm PASS.

October 3 clocking amendment: **P1/P2** may also be assigned to a separate owner
with coordinated shared-file edits. Keep F/G progressing at 27 MHz. Frequencies,
PLL support and pipeline experiments described here are planned options, not
changes already made to the current direct-clock implementation.

Phase C candidate, October 3: **Locally verified — awaiting manual checks.**
Added `test/transport/tx_boundary_tests.ml` with explicit Dune ownership;
preserved the existing TX implementation and all earlier tests. All 256 bytes
pass an independent every-clock waveform/ready/busy oracle at 15 timing settings,
including divisors 1/2/3, 7/8/9 and 234, zero/one-cycle and counter-width-boundary
gaps. Checks cover changing data after acceptance, busy-time offers, held valid
across completion, idle without valid, reset at both ends of each bit/gap,
held reset with valid, immediate post-reset acceptance and invalid parameters.
`dune build`, `dune build @test/transport/runtest`, transport generation and
`dune runtest --force` passed in switch `5.2.0+ox`, including fresh Yosys/Icarus
checks for transport, bringup and history RTL. No unrelated failures found.

Delivered RTL: `rtl/gqh_transport_top.v`, SHA-256
`62cc2f314102c4d13860df1d27f187b5fe6aadfd916459890fae4e228ffd7090`;
byte-identical to the pre-task RTL. Direct 27 MHz, 234 clocks/bit, zero extra gap;
no PLL changes. Source-state snapshots, prior dirty plan patches and local logs
are in `results/phase-c-20261003-candidate1/`. Manual synthesis/P&R and timing
review, identified `.fs` generation/programming, startup/reset/TX idle and both
100-request custom tests remain required for this candidate. Follow its handoff
and return the actual reports and results before closing Phase C. Historical
board results and unrelated completed-phase statuses remain unchanged.

Phase C board-script follow-up, October 3: after the user reported programming
a fresh bitstream and explicitly authorized agent serial access, both custom
checks were run on the identified Sipeed USB Debugger interface
`/dev/serial/by-id/usb-SIPEED_USB_Debugger_2025030317-if01-port0` (`/dev/ttyUSB1`).
Normal: 100/100 responses, zero mismatches/timeouts, mean 16.965 ms, max 17.331 ms.
With `--byte-pause 0.005`: 100/100 responses, zero mismatches/timeouts, mean
50.877 ms, max 51.591 ms. Both exited 0 and detected no surplus bytes.
No reset or input discard was performed by the runner. Commands, stdout/stderr,
exit statuses, Python/pyserial details and current RTL/checker hashes are saved
in `results/phase-c-20261003-candidate1/board-tests-20261003T174429.688210Z/`.
These are diagnostic NONE-action transport passes, not an algorithm PASS.
Status remains **Locally verified — awaiting manual checks**: the exact
programmed `.fs` identity/hash, matching Gowin synthesis/P&R and timing review,
and user startup/reset/TX-idle observations still need to be supplied.

October 3 acceptance clarification: the user explicitly waived `.fs`/SHA
retention and synthesis-report archival for this early Phase C step. Those
record-keeping requirements are no longer blockers for this delivery; existing
evidence is retained. The user confirms the programmed bitstream was built from
the delivered artifacts and synthesis passed, with PR1014 as the sole IDE warning.
Read-only review found the current Gowin V1.9.11.03 Education P&R/timing outputs
in `viv25_proj/test_proj1/impl/pnr/` (October 3, 10:42:28). The project RTL
matches the delivered RTL. P&R and bitstream generation completed; the timing
report applies 27 MHz and shows zero setup/hold violations, worst setup slack
+31.839 ns and worst hold slack +0.425 ns. The P&R report lists `sys_clk_d`
on PRIMARY routing and no dedicated GCLK input pin usage. PR1014 indicates
generic routing in the clock route; it is recorded as a clock-routing caveat,
not a demonstrated failure of this 27 MHz candidate. No routing/PLL changes
were made. Recovery/removal tables have nothing to report; they do not prove
asynchronous board-reset behavior. Manual startup/reset/TX-idle confirmation
remains the final pending Phase C check. No additional serial runs are needed
unless that check fails. Status remains **Locally verified — awaiting manual checks**.

**Phase C closure, October 3, 2026: COMPLETE.** In response to the remaining
startup/reset/TX-idle checklist, the user confirmed those checks and requested
closure. The delivered candidate passed the independent local TX boundary suite,
build/regressions and emitted-RTL checks; matching-artifact Gowin synthesis/P&R,
27 MHz setup/hold timing and bitstream generation were reviewed; the user
programmed the build; both custom board tests passed 100/100 with no mismatches,
timeouts or surplus bytes. PR1014 remains a recorded clock-routing caveat for
future clock work, with no timing failure in this build. Bitstream hashes and
report archival were explicitly waived for this step. Earlier pending-status
entries above describe the verification sequence and are superseded by this
closure. No Phase C work remains. This establishes UART TX/diagnostic transport
acceptance, not an official algorithm PASS, and does not change other phases.


**Phase D closure, October 3, 2026: COMPLETE.** The user authorized closure
against the existing matching-build transport evidence after the focused
verification additions. No decoder, sequencer, UART, clock/reset, board-top or
RTL changes were made in this Phase D follow-up. The current transport RTL
SHA-256 was checked and remains
`62cc2f314102c4d13860df1d27f187b5fe6aadfd916459890fae4e228ffd7090`, matching
the Phase C delivered and programmed candidate. The source changes for this
follow-up are the new `test/protocol/` suite, its documentation, the transport
verification README and this plan; the existing untracked Phase C evidence is
preserved. No Git index, refs or history were changed.

Local acceptance: the original decoder/sequencer tests and the new six
unit/property tests plus two golden tests pass. Coverage includes all packet
fields/byte positions, legal pauses, stable stalled payloads, byte-7 publication,
response order/zeros, second-response backpressure, final-frame drain,
reset at every partial/held request position and sending byte/final drain,
fault/acceptance collisions and reset recovery. The deterministic property runs
100 payload/stall trials. `dune build`, `dune runtest --force` and
`dune build @test/protocol/runtest` passed in switch `5.2.0+ox`; full regressions
include independent UART checks and Icarus/Yosys transport, bringup and history
RTL verification. See `test/protocol/README.md` for exact scope and commands.

Hardware acceptance reuses the unchanged transport candidate's recorded Phase C
closure: matching-artifact Gowin synthesis/P&R and bitstream generation,
27 MHz timing with zero setup/hold violations, user-confirmed programming and
startup/reset/TX-idle checks, and both custom transport runs passing 100/100
with zero mismatches/timeouts or surplus bytes. The byte-paused run establishes
legal inter-byte-pause behavior. Saved custom-run artifacts are in
`results/phase-c-20261003-candidate1/board-tests-20261003T174429.688210Z/`.
This is reuse of that candidate's accepted evidence, not a new board run or a
claim that host checks exercise internal stalls/fault collisions; those boundary
properties are established by local simulation. The accepted candidate retains
its recorded PR1014 clock-routing caveat and the user's existing record-keeping
waiver. No additional synthesis, flashing or manual checks are required for
this verification-only follow-up. No Phase D work remains; this closes protocol
transport acceptance only and does not establish an algorithm PASS or change
other phases. F, followed by G, remains the algorithm implementation path.
