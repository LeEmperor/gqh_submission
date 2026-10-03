# Hardware track pivot and architecture handoff

Date: 2026-10-02

## Purpose

This document hands off a revised hackathon objective to another Astra instance for deeper architecture work. It records the user's decisions, the relevant competition requirements, and candidate optimizations. It is an architecture brief, not a completed design or evidence of passing tests.

**User decision: use Hardcaml because the user likes it. Treat Hardcaml as a firm implementation choice, not an option to debate against handwritten RTL.** Board wrappers or vendor primitives may still require small RTL components where appropriate; the intended design language is Hardcaml.

## Why the plan changed

The original project, tickweave, proposed an OCaml/Hardcaml trading-rule toolchain with an Arty Ethernet data path, order-book state, generated trading rules, a terminal console, configuration management, and optional AI assistance.

The user reports that the Jane Street judges are no longer coming. The actual graded assignment is the GQH Hardware Track described in `gqh_hw_guide.pdf`. The user also asked the organizers directly and reports that **latency and LUT count are the primary differentiators, and extra features receive no cool-factor credit**.

Consequently, optimize a fixed-function implementation of the required algorithm. Correctness is a prerequisite; measured latency and LUT usage are the optimization objectives. Do not retain the original product scope merely because it appears in an earlier proposal.

The original proposal's Ethernet path, Arty target, order book, arbitrary rule representation, operator console, AI/voice features, runtime configuration workflow, and order-submission protocol are outside this revised competition scope. Development tooling is worthwhile only insofar as it improves correctness, measurement, optimization, or reproducibility.

## Source material and current context

Working directory to inspect:

`/home/wayne/devel/jane/testing`

Observed Git state at the start of this discussion:

- Worktree of `/home/wayne/devel/jane/tickweave`.
- Branch `bpurtell/base_testing`, tracking `origin/bpurtell/base_testing`.
- Both worktrees were listed at commit `7d89ef9`.
- The PDFs, proposal Markdown, and `viv25_proj/` were untracked. Recheck current state before editing.

Relevant files:

- `/home/wayne/devel/jane/testing/gqh_hw_guide.pdf`: actual competition guide; read this directly before finalizing architecture.
- `/home/wayne/devel/jane/testing/tickweave_source_of_truth.md`: historical proposal, superseded for the competition direction by the user's decisions recorded here.
- `/home/wayne/devel/jane/testing/tickweave_proposal.pdf` and `.docx`: historical proposal editions.
- `/home/wayne/devel/jane/testing/viv25_proj/test_proj1/`: contains a Gowin project, `src/blinky.v`, constraints, and generated implementation artifacts including an `.fs` file. These files were listed, not audited or tested; their presence does not establish board bring-up or a working UART implementation.

No code was changed, no FPGA was programmed, and no correctness, resource, or latency results were produced during this planning discussion. The official UART scripts and competition constraint file have not yet been inspected. Do not assume they are present just because the guide names them.

## Goals and interpretation of scoring

1. Implement the exact required behavior in Hardcaml, entirely on the FPGA.
2. Achieve reliable correctness across official tests, adversarial cases, and repeated sessions.
3. Minimize synthesized total LUT count.
4. Minimize the round-trip latency measured by the official host test, preserving reliability.
5. Deliver a reproducible Tang Nano 20K build and matching submission artifacts.

The written guide specifies:

| Criterion | Points | Formula or threshold |
| --- | --- | --- |
| Packet correctness | 50 | `50 * correct_packets / 84` |
| Action correctness | 20 | `20 * correct_actions / 168` |
| Latency | 15 | 15 points at no more than 1.25 times reference average; 8 points at no more than twice reference; otherwise zero |
| LUT usage | 15 | `15 * min(1, reference_LUTs / design_LUTs)` |

Both latency and LUT points are zero below 95% packet correctness. Reference values in the guide are **16.626 ms** average latency and **542 LUTs**. Full latency credit therefore starts at no more than **20.7825 ms**, and the partial-credit boundary is **33.252 ms**.

**Unresolved scoring distinction:** the printed formulas cap rewards, while the user's direct organizer clarification emphasizes latency and LUTs as the prime factors. Do not invent an uncapped score or tie-break rule. Architect for low values in both dimensions, retain the written scoring thresholds as known facts, and identify whether further clarification would affect optimization choices.

## Required board and external interface

From the supplied guide:

- Tang Nano 20K, Gowin GW2AR-LV18QN88C8/I7.
- Onboard clock: 27 MHz.
- Guide's tool setup: Gowin EDA V1.9.11.03 Education; record the actual tool version used.
- Judges program the submitted `.fs` into SRAM.
- Use the organizer-supplied `19_tang_nano_20k.cst`.
- Top-level names: `sys_clk`, `reset_btn`, `uart_rx_i`, `uart_tx_o`, `led0_n`, `led1_n`.
- Keep optional ports in the top-level interface; drive unused active-low LEDs high.
- UART: 115200 baud, 8 data bits, no parity, one stop bit; bits transmitted LSB first.
- Multi-byte protocol fields are big-endian.
- No team-supplied host program runs during official judging. UART parsing, state, computation, and response generation must all occur on the FPGA.

### Request: exactly eight bytes

| Byte offsets | Contents |
| --- | --- |
| 0–1 | 16-bit index |
| 2 | Item ID in slot 1 |
| 3–4 | Unsigned 16-bit price in slot 1 |
| 5 | Item ID in slot 2 |
| 6–7 | Unsigned 16-bit price in slot 2 |

### Response: exactly eight bytes

| Byte offsets | Contents |
| --- | --- |
| 0–1 | Echo request index |
| 2 | Echo slot 1 item ID |
| 3 | Slot 1 item's action |
| 4 | Echo slot 2 item ID |
| 5 | Slot 2 item's action |
| 6–7 | Zero |

Item A is `0x11`; item B is `0x22`. Actions are NONE `0x00`, SELL `0x01`, BUY `0x02`.

There is exactly one response per request, no unsolicited bytes, and no response may begin before all eight request bytes arrive. Either item can appear in either slot. State belongs to the item ID; response order follows request-slot order.

The guide describes requests carrying both items. Check the actual test contract before assuming behavior for duplicate IDs, unknown IDs, malformed traffic, or nonsequential indices. Do not spend LUTs supporting invented requirements.

## Exact algorithm and session semantics

Each item maintains independent state:

- Its last 16 unsigned 16-bit prices.
- Their sum, requiring 20 bits.
- Its previous price.
- Its last generated action, initially NONE.

Index 0 begins a fresh session without requiring board reset or reprogramming. Clear the previous session's logical state, then process index 0's two prices as the first samples of the new windows.

Indices 0 through 15 are warm-up. Insert the prices, accumulate sums, and update previous prices. Return NONE for both items. Do not evaluate crossings during warm-up.

For index 16 onward, independently for each item:

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

replace oldest history entry with current_price
store new_sum, current_price as previous_price, and action
```

Both averages use floor division. The previous-price comparison uses the old average; the current-price comparison uses the updated average, including the incoming price. No crossing means hold the last action, not return NONE.

## Judging behavior relevant to architecture

- One official run contains 100 requests, indices 0–99.
- Indices 0–15 warm up the state, leaving 84 scored packets and 168 scored actions.
- Requests are stop-and-wait: the host waits for the complete response before sending another request.
- The price seed is unpublished and shared among teams. General correctness is required.
- Failure to receive all eight response bytes within one second is a timeout, counts as incorrect, and ends the run; unreceived packets score zero.
- The guide warns that the onboard BL616 USB-serial bridge can drop or corrupt bytes when responses are transmitted back-to-back without sufficient idle time. Determine reliable response spacing experimentally.
- Measured latency includes the request transmission, FPGA work, response transmission, added byte gaps, and host USB/serial overhead.
- Sixteen UART bytes at 115200 baud and 8N1 take approximately 1.39 ms on the wire. The guide attributes most of its roughly 16.6 ms reference measurement to bridge/USB/host overhead.

These facts favor examining area-saving sequential computation rather than assuming parallelism improves the actual score. For scale, 20 cycles at 27 MHz are about 0.74 microseconds. This observation is an architecture hypothesis, not a measured comparison of implementations.

## Candidate architecture to evaluate

The current preferred starting hypothesis is a compact shared sequential datapath:

```text
UART RX -> request capture/decode -> shared update engine
                                      <-> A/B history and state
                                  -> response assembly -> paced UART TX
```

Evaluate rather than blindly adopt these ideas:

1. **Shared arithmetic.** Process the two items sequentially and consider reusing an adder for subtraction and addition. Account for the LUT cost of operand muxes, intermediate registers, and control; sharing is not automatically smaller.
2. **Circular history memory.** Compare inferred block RAM with register-based storage. A combined 32-by-16 history store is a candidate organization. Check actual Gowin inference, access latency, read/write behavior, and resource reports.
3. **Logical reset without clearing memory cells.** Reset sums, actions, pointers, and warm-up validity, then overwrite history during warm-up. Stale entries must never influence calculations before they have been replaced. Prove equivalence to a cleared history for the specified protocol and verify repeated sessions. This could avoid reset structures that prevent memory inference.
4. **Minimal necessary state.** Evaluate whether the guaranteed input index and update schedule safely eliminate redundant counters or state. Keep item identity and slot ordering correct. Make any assumptions explicit.
5. **Tight widths.** Derive widths and intermediate arithmetic semantics explicitly, including subtraction, extension, and comparisons. Avoid accidental signed arithmetic or oversized inferred operations.
6. **Compact UART and control.** Consider timer sharing only where operational overlap permits it. Do not compromise receiver synchronization or sampling reliability for nominal LUT savings.
7. **Prompt response with measured spacing.** Begin transmission as soon as the full request and required response data permit; tune inter-byte idle spacing on hardware. Do not guess that zero gap works or optimize against one lucky run.

Two independent item engines are a useful alternative baseline if they greatly simplify verification or synthesize competitively. Avoid implementing multiple variants without a specific measurement question.

## Verification and measurement priorities

Build an independent software reference model and test the Hardcaml design against it. Obtain and inspect `21_quick_uart_test.py` and `22_robust_uart_test.py`; the guide allows changing only their PORT setting for official-style testing. Additional custom tests should be separate.

Cover at least:

- Correct byte order, echoed index/items, reserved zeros, and exactly eight response bytes.
- No response before the complete request arrives.
- Warm-up and the first scored update at index 16.
- Repeated index-0 sessions without reprogramming, including different price histories.
- Slot swaps with deliberately different item histories.
- Equality boundaries in both halves of the crossing predicate.
- Average truncation cases, all-zero prices, maximum prices, and large transitions.
- Holding the last BUY or SELL through multiple non-crossing updates.
- Circular-buffer wraparound and sum invariants.
- UART-level simulation plus actual-board tests, not only algorithm-level simulation.

Record for each meaningful implementation candidate:

| Measurement | Required context |
| --- | --- |
| Total LUTs | Actual Gowin synthesis report, matching source/build |
| Other resources | Registers and block RAM, to understand mapping changes |
| Timing closure | Actual clock constraints and implementation results |
| Round-trip latency | Official-style test, host setup, byte-gap setting, retained CSV |
| Reliability | Repeated runs, mismatches, timeouts, and tested scenarios |

Retain a known-good bitstream while experimenting. Host variability and the judging PC can change end-to-end results; distinguish measured improvements from noise. Optimize one variable at a time when practical.

## Suggested delivery sequence

1. Inspect existing code, available tooling, organizer scripts, and constraints. Establish what already works.
2. Prove Hardcaml RTL generation through Gowin synthesis and place-and-route for this device, including the intended memory mapping.
3. Bring up exact UART request/response handling on the board.
4. Integrate the complete algorithm and pass reference comparisons and the oggfficial scripts.
5. Use reports and measurements to identify the real area and latency costs.
6. Iterate on shared arithmetic, storage mapping, control, and byte spacing where evidence supports it.
7. Freeze the best verified implementation and produce matching source, constraints, Gowin build files, `.fs`, README, and results.

The guide lists submission and board return as **Sunday, October 4, 2026, 11:00 am EDT**. It requires a public repository and the full final commit SHA in the Devpost submission. Recheck organizer communications for updates.

## Requested work from the architecture instance

Develop a concrete Hardcaml architecture for this revised objective. Begin by inspecting the supplied guide and available project/tooling, and distinguish established facts from assumptions.

The architecture response should address:

1. Proposed module boundaries, interfaces, state, and dataflow.
2. A cycle-level schedule for request completion, each item's update, and response launch.
3. Exact arithmetic widths and old/new state semantics.
4. History-memory organization and a credible Gowin inference or primitive-instantiation strategy.
5. Reset/startup and index-0 session behavior, including whether physical memory clearing can be avoided.
6. UART receive/transmit timing, synchronization, and experimentally tunable response spacing.
7. Expected area tradeoffs, explicitly labeled as estimates until synthesized.
8. Verification structure, measurement experiments, and an ordered implementation plan.
9. Any unresolved protocol or scoring questions that materially affect the design.

Prefer a justified, small design over a generic extensible framework. Hardcaml is settled. The optimization target is the required computation and its actual judged transport path; additional product features are excluded.

