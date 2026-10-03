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

| Edge | Pre-edge state | Effect |
| --- | --- | --- |
| E0 | IDLE | Accept when valid && ready; capture all four command fields |
| E1 | READ | Enabled synchronous history read at the captured address |
| E2 | COMMIT | Consume registered old word; write history and scalar state once; publish action/result |
| E3 or later | RESULT | Accept result when ready; return IDLE |
| E4 earliest | IDLE | Accept next command |

Warm-up and steady-state have the same measured latency: **2 elapsed cycles
from acceptance to result publication**, or three rising edges including E0.
Earliest result transfer is 3 cycles after acceptance; with no stalls, earliest
next-command acceptance is 4 cycles after E0. At 27 MHz, publication latency is
approximately 74.074 ns; these are engine-only times, not UART measurements.
Result stalls add cycles without any writes and hold action/result_valid stable.
There is no same-edge command acceptance on a result-consumption edge.

RAM is 32 x 16 addressed by `{item_select, window_position}`, explicit one-edge
read latency, read-before-write mode, no reset or initialization. Read enable is
READ only; write enable is COMMIT only and is suppressed by reset. Ports never
collide in this schedule. Warm-up ignores the read data, accumulates price,
overwrites history and previous price and returns NONE. Steady-state selects
old scalar state, zero-extends prices to 20 bits, subtracts the oldest price then
adds the new one, and compares old/new averages extracted as bits [19:4]. Scalar
state is two 20-bit sums, two 16-bit previous prices and two 2-bit held actions.
Combinational arithmetic is shared between selected items in source; this is
not evidence of one synthesized arithmetic operator or Gowin BRAM mapping.

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
stalls and 64-edge stalls. Reset tests cover IDLE, READ, COMMIT before write and
RESULT, for each item, with nonzero actions/full histories and held reset/valid.
Clear/valid collisions, repeated sessions, poison initial RAM and retained stale
RAM across reset/session clear are checked on the same engine instance.

Both simulators check pre-edge handshakes, post-edge outputs, all six scalar
registers and all 32 RAM words on every edge. Sums are independently recomputed
from chronological windows. The RAM image scoreboard only records committed
writes, preserving poison/stale values across clear/reset. This checks write
addresses, exact-once commit, reset suppression and memory retention separately
from action comparisons. RTL testbench poisoning is test-only; hardware RTL
contains no initial block. Cyclesim default zero RAM is never relied upon.

Saved candidate logs, coverage, hashes and Phase G/manual instructions are in
`results/phase-f-20261003-candidate1/`. Local simulation and generic Yosys checks
establish behavior/elaboration, not Gowin mapping, routed timing or board success.
