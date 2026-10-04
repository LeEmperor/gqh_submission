# Phase F engine verification

Status: **COMPLETE under the user-authorized F–G closure (October 3)**; see
REQUEST_RESPONSE_PLAN.md for passing board tests and the waived closure items. This package implements
`Hardcaml_gqh.Engine.Update`, independently of UART and the diagnostic transport.
This standalone F package does not own the competition top or controller;
those are now delivered by G1/G2 (see ../integration/README.md).

From the `testing/` root:

```sh
opam exec --switch=5.2.0+ox -- dune build
opam exec --switch=5.2.0+ox -- dune build @test/engine/runtest
opam exec --switch=5.2.0+ox -- dune runtest
```

The focused alias explicitly owns `engine_verify.ml`, the local Python runner,
Verilog testbench and copied oracle tree. No shared build-file edits were needed.
It runs Python checks, real-engine Cyclesim, deterministic Verilog generation,
Yosys hierarchy/process/check and Icarus simulation. Python uses only the standard
library; installed `iverilog`, `vvp` and `yosys` are required. No sibling checkout,
streamer, Databento, serial device or dependency installation is involved.

Standalone engine RTL generation, without a production target:

```sh
opam exec --switch=5.2.0+ox -- dune exec test/engine/engine_verify.exe -- emit /tmp/gqh_update_engine.v
```

Reproduce checks and save RTL/coverage in a fresh directory:

```sh
opam exec --switch=5.2.0+ox -- dune build test/engine/engine_verify.exe
PYTHONDONTWRITEBYTECODE=1 python3 test/engine/run_checks.py _build/default/test/engine/engine_verify.exe /tmp/phase-f-results
```

`run_checks.py` prints coverage and the deterministic trace/RTL SHA-256; the
optional directory receives `gqh_update_engine.v`, `coverage.json` and
`trace.sha256`. Intermediate trace, Yosys JSON and simulation executable are
created in temporary storage. Rebuild before the direct Python command.

## Interface and schedule

Typed input `Engine.Update.I`: `clock`, active-high synchronous `reset`,
`session_clear`, nested `update : Protocol.Types.Update.t`, `update_valid`,
`result_ready`. The existing payload is item_select(1), price(16),
window_position(4), warmup(1). Output `Engine.Update.O`: update_ready(1),
result_valid(1), action(2). NONE=0, SELL=1, BUY=2. `create` and `hierarchical`
follow the existing Hardcaml pattern; hierarchy name is `gqh_update_engine`.
Emitted nested payload port names contain `$`: `update$item_select`,
`update$price`, `update$window_position`, `update$warmup`.

H3a's schedule (the H2 fallback retains its earlier two-cycle schedule):

| Edge | Warm-up | Rolling update |
| --- | --- | --- |
| E0 | Capture command → READ | Capture command → READ |
| E1 | Synchronous read → ADD | Synchronous read → SUBTRACT |
| E2 | Add old sum + price to intermediate → COMMIT | Subtract oldest from old sum to intermediate → ADD |
| E3 | Commit history/scalars/result → RESULT | Add price to intermediate → COMMIT |
| E4 | Earliest result transfer | Commit history/scalars/result → RESULT |
| E5 | Earliest next command | Earliest result transfer |

Publication is **3 cycles warm-up / 4 cycles steady** after acceptance. Earliest
result transfer is 4 / 5 cycles, next command acceptance 5 / 6 cycles. Arithmetic
states change only the 20-bit intermediate, never committed item state. Result
stalls add cycles without writes and hold action/result_valid stable. There is
no same-edge command acceptance on a result-consumption edge.

RAM is 32 x 16 addressed by `{item_select, window_position}`, explicit one-edge
read latency, read-before-write mode, no reset or initialization. Read enable is
READ only; write enable is COMMIT only and is suppressed by reset. Ports never
collide in this schedule. Warm-up ignores the read data, accumulates price,
overwrites history and comparison flags and returns NONE. Steady-state selects
old scalar state, zero-extends prices to 20 bits, subtracts the oldest price then
adds the new one, and compares the current price with the new average extracted as bits [19:4].
Scalar state is two 20-bit sums, two pairs of 1-bit previous_below/previous_above
flags and two 2-bit held actions. Each pair records the last committed price
versus its committed truncated average; both false means equality. BUY uses
not previous_above and current_above; SELL uses not previous_below and
current_below. Flags commit during warm-up too, preparing index 16, and clear
to false on reset/session clear.
H3a selects operands around a single add/subtract datapath. Both encoded
21-bit operands append the subtraction control as a guard bit; one addition
and bits [20:1] implement the 20-bit sum with carry-in and no extra increment.
Emitted-RTL process checks assert one $add, no $sub and equal guard inputs.
Actual Gowin arithmetic/memory mapping and total logic still need measurement.

Reset wins over all activity, aborts pending processing/result, clears scalar,
command and FSM registers, masks both handshake outputs and prevents RAM writes.
RAM cells and the RAM read register are not cleared. Synchronous reset requires
a rising edge; this module does not provide board reset synchronization or
power-up initialization. Restart a full warm-up after reset.

`session_clear` is legal only idle with no pending result; it clears both items'
scalar state and output action but does not touch RAM. It wins over simultaneous
update_valid by suppressing update_ready. While high in IDLE it continues to
clear scalars and block acceptance. Deassert it before dispatch. Illegal busy
clear is ignored; production integration must obey the idle-only precondition.
Reset has priority over clear. No window validity counters, index classifier,
slot mapper or shared pointer are implemented in the engine.

## Coverage and independence

The pinned source/provenance and adaptation rationale are in
`oracle/PROVENANCE.md` and `oracle/SOURCE.json`. Original metadata/checksums are
intact, and all 22 upstream tests pass; all 800 saved records verify and regenerate
byte-for-byte. No expected rolling-sum algorithm was added.

The test-only packet adapter clears on index zero, resets pointer to zero, maps
both slots by IDs, dispatches sequentially with warm-up for indices 0–15, and
advances the pointer once after both result transfers. Every packet's two actions
are checked against the oracle. Current schedule is intentionally pinned by the
edge checks; a future engine schedule change must update the timing scoreboard,
while retaining independent oracle arithmetic and controller handshakes.

Additional coverage includes six seeded 513-packet streams (three full-range,
three 0..127), three directed 112-packet streams, and populated-state reset and
restart runs. Checks include equality, floor truncation, held BUY/SELL, full and
zero sums, first scored index 16, multiple wraps, warm-up swaps, changing all
fields after acceptance, busy command offers, early result_ready, random result
stalls and 64-edge stalls. Reset tests cover every reachable stage on both
warm-up and rolling paths, for each item, with populated/stale histories and
held reset/valid. Both simulators also check the exact commit/write-enable
pulse on every edge, including unchanged-price writes.
Clear/valid collisions, repeated sessions, poison initial RAM and retained stale
RAM across reset/session clear are checked on the same engine instance.

Both simulators check pre-edge handshakes, post-edge outputs, all eight scalar
registers and all 32 RAM words on every edge. Sums are independently recomputed
from chronological windows. The RAM image scoreboard only records committed
writes, preserving poison/stale values across clear/reset. This checks write
addresses, exact-once commit, reset suppression and memory retention separately
from action comparisons. RTL testbench poisoning is test-only; hardware RTL
contains no initial block. Cyclesim default zero RAM is never relied upon.

H1 adds the Gowin `syn_ramstyle="block_ram"` inference attribute only to
`engine_history`. The emitted-RTL check requires exactly one attribute, directly
on the 32 × 16 array. All oracle, per-edge RAM/scalar, poison, reset and stall
checks above remain unchanged. Hardcaml's `Ram.create ~attributes` is supported
in the installed 5.2.0+ox switch; no vendor primitive or separate behavioral
replacement is used. The attribute does not alter simulation semantics.
Actual BSRAM mapping, inferred read mode and resources await manual Gowin checks.

Saved candidate logs, coverage, hashes and Phase G/manual instructions are in
`results/phase-f-20261003-candidate1/`. Local simulation and generic Yosys checks
establish behavior/elaboration, not Gowin mapping, routed timing or board success.

H2 replaces previous-price observations with both relation flags for each item
on every edge in both simulators. Expected flags use the independently retained
chronological price windows and `sum(window) // 16`, never a DUT sum. Directed
17-packet sessions cover all nine below/equal/above transitions, all three final
warm-up relations and their first scored update, with alternating slots and
distinct item prices. Existing oracle, sum/history, reset, exact-once and stalled
result checks remain. Equality includes a sum remainder of 15; extremes and
seeded full-range streams continue to exercise 16-bit prices and 20-bit sums.
