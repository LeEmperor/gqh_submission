# FPGA Request–Response Architecture and Implementation Plan

Status: packages A–E implemented and locally verified; transport board checks
and algorithm packages F–G remain pending. Updated: October 2, 2026.

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
- Do not commit, push, program hardware, or automate the IDE unless separately
  requested. Generated RTL and local reversible implementation work are in scope.

## 3. Frozen external behavior

- Device: Tang Nano 20K, `GW2AR-LV18QN88C8/I7`; clock: 27 MHz.
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

All internal logic runs on `sys_clk`. Timers generate enables, not new clocks.
Internal reset is active high, using the existing board reset-release circuit.
The board synchronizes RX through two registers; `Uart.Rx` receives that
synchronized signal. Initialize/reset the synchronizer to UART idle high.

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
for simulation. Use independent RX/TX counters and test timing mismatch.

RX sequence:

1. Observe idle high, then a falling edge on synchronized RX.
2. Check the candidate start bit near its center, approximately 117 clocks later.
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

### A — Freeze contracts and test layout

**Depends on:** existing scaffold. **Owns:** `src/protocol/types.ml`, shared test
helpers/layout, minimal shared Dune changes, contract clarifications here.

Deliver compiling request/response types and constants, finalized handshake
names, and test ownership conventions. Record fault/receive-enable ownership.
Keep mocks in tests. Preserve existing tests; when adding test executables,
explicitly assign modules so Dune does not claim the same module twice.

**Acceptance:** existing build/tests pass; later agents can implement against
the types without guessing payload widths or handshake semantics.

### B — UART receiver

**Depends on:** A. **Owns:** `src/uart/rx.ml`, `test/uart/rx/`.

Implement the RX timing/state machine and byte/error events. Test with an
independent serial waveform source, not only the project's TX.

**Acceptance:** representative/all byte values, back-to-back frames, varied
start phase, nominal and modest positive/negative baud mismatch, false starts,
invalid stop, long low input, reset mid-frame, and exactly one valid pulse per
good byte. State the tested mismatch range; do not claim universal tolerance.

### C — UART transmitter

**Depends on:** A. **Owns:** `src/uart/tx.ml`, `test/uart/tx/`.

Implement latched input, ready/busy, full bit periods, and build-time idle gap.
Test with an independent serial decoder/timing checker.

**Acceptance:** exact LSB-first framing and durations, data changing after
acceptance, valid held through stalls, consecutive transfers, zero/nonzero gap,
idle high, and reset during transmission. No shortened first start bit.

### D — Request decoder and response sequencer

**Depends on:** A; can use byte-level mocks before B/C finish.
**Owns:** decoder/sequencer modules and `test/protocol/` suites for those blocks.

Implement complete-request assembly, held payloads, response ordering, TX
backpressure handling, completion events, and the stated decoder fault policy.

**Acceptance:** all eight byte positions, distinct high/low bytes, arbitrary
inter-byte pauses, byte 7 included correctly, no request after seven bytes,
stable stalled requests/responses, exactly eight accepted TX bytes, reserved
zeros, final-frame completion, partial-frame abort, and busy-input fault.

### E — Transport integration and manual board handoff

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

### F — Independent oracle and engine

**Depends on:** A and finalized engine command contract. May proceed independently
of transport. **Owns:** `src/engine/`, `test/engine/`, custom algorithm fixtures.

Implement history/scalar state and the shared update engine. Build independent
window-based oracle checks and hand-checked boundary fixtures.

**Acceptance:** warm-up, index-16 first scored update, wraparound, held BUY/SELL,
equality and truncation boundaries, zero/max prices, distinct item histories,
slot swaps, repeated index-0 sessions including warm-up swaps, exact-once
updates under result stalls, and reset/session clear. Account for memory latency.

### G — Full transaction controller and competition integration

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

### H — Measured optimization, only after a correct baseline

**Depends on:** G and saved correctness/resource/latency evidence.

Evaluate one change at a time: memory mapping, arithmetic/control area, TX gap,
then early prefetch/field-level computation if useful. Preserve a known-good
baseline and report actual synthesis LUTs plus complete measured latency results.
Bit/nibble-level UART outputs are not part of packages A–G.

### Scheduling and shared-file rules

```text
A → B ─┐
  → C ─┼→ E ─┐
  → D ─┘     ├→ G → H
  → F ───────┘
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
- [x] D: decoder/sequencer locally verified.
- [x] E: transport integrated and emitted RTL locally checked.
- [ ] E board follow-up: repeated custom transport checks pass on hardware.
- [ ] F: engine and independent oracle locally verified.
- [ ] G: complete serial system locally verified and RTL generated.
- [ ] G board follow-up: official tests and custom session/boundary tests pass.
- [ ] Baseline synthesis/timing/latency evidence saved.
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
`test/transport/README.md` for full scope. Custom host fixture/CLI checks pass;
`tools/check_transport.py` has not been run against hardware. Official scripts
and constraints remain pristine. No synthesis/P&R/board claims are made.

Next eligible package: **F**, then **G** once the engine is independently
verified. The NONE-action transport is diagnostic only. Manual transport board
follow-up can proceed independently using `gowin/README.md` and the custom host
checker; it does not establish an official algorithm PASS.
