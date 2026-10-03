# Phase D protocol verification

Run the focused decoder/sequencer suite from the project root:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/protocol/runtest
```

The original field assembly, endian, pause, stalled payload, response ordering,
and fault checks remain active in `../transport/transport_tests.ml`. Run that
baseline and the serial/emitted-RTL integration checks with:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/transport/runtest
```

This suite follows the read-only `hardcaml_networking` reference's settled
verification structure (`test/test_architecture.md`, UART TX and UDP TX suites):
a testbench owns simulation and typed observations; unit/Quickcheck tests check
scenarios; expect tests record reviewable golden observations. It uses local
Cyclesim fixtures rather than importing the sibling's verification library.
There is no new package dependency or superseded legacy harness.

- `protocol_testbench.ml`: finite scenario drivers and typed observations.
  Before-edge snapshots determine valid/ready transfers and accepted TX bytes;
  after-edge snapshots determine registered publication, faults and completion.
  Simulation steps execute in explicit sequence, including collection loops.
- `protocol_unit_quickcheck_tests.ml`: reset at all decoder positions (0–7
  partial bytes and 8 held bytes), fresh field assembly after reset, reset at
  all eight stalled sending bytes and final drain, reset with offers asserted,
  no stale output/completion, and successful post-reset response transmission.
  A second response stays valid with stable fields while the sequencer sends
  and drains the first; all live response fields change after capture.
  Checks count exactly two input acceptances, sixteen TX transfers, and two
  single-cycle completion events. A deterministic 100-trial Quickcheck property
  varies both payloads, every byte's ready stalls (0–20 cycles), and final drain
  stalls (0–30 cycles). All two-bit action values are tested as serialization
  inputs; value 3 does not acquire an algorithm meaning.
- `protocol_expect_tests.ml`: golden byte/count observations for two responses,
  and before/after observations for request acceptance colliding with faults.

## Fault collision expectations

A framing error suppresses `request_valid` combinationally, so even with ready
asserted a held request does not transfer on that edge. The edge clears held
valid and latches the fault. Framing error also takes priority over an incoming
final byte; no completed request is published.

An unexpected byte while a request is held leaves the old payload and valid
visible before the edge. If ready is asserted, that published request transfers
once; the edge latches the fault, blocking future requests. If ready is low,
there is no transfer and fault lockout suppresses the held request. The incoming
byte never overwrites the held payload. Both cases stay locked through later
bytes and recover only after reset. This implements the plan's allowance for an
already accepted transaction to finish.

These additions change verification and documentation only. They do not change
hardware behavior or establish new manual board acceptance. Phase D is complete
as of October 3, 2026: the user authorized reuse of the unchanged transport
candidate's accepted synthesis/timing, programming, startup/reset and custom
board evidence. The current RTL hash matches that candidate. See the Phase D
closure in `../../REQUEST_RESPONSE_PLAN.md` for build identity, evidence scope
and the inherited clock-routing caveat. No new synthesis or flashing is needed.

Local verification on October 3, 2026: `dune build` and `dune runtest --force`
passed in switch `5.2.0+ox`, including all six new unit/property tests and both
golden tests, original transport checks, TX boundary checks, and Icarus/Yosys
checks for transport, bringup and history-probe RTL. The focused
`dune build @test/protocol/runtest` command also passed.

## Phase G1 transaction controller

Status: **Locally verified — awaiting manual checks** (October 3, 2026).
The production module is `Hardcaml_gqh.Protocol.Transaction_controller`;
`transaction_controller.mli` documents every direction, width and lifecycle rule.
Engine, decoder and sequencer instances remain outside it. The diagnostic
transport and its generator/board top are unchanged.

The focused alias above now also owns `transaction_verify.ml`,
`transaction_harness.ml` and `transaction_checks.py`, with explicit executable
module ownership separate from the existing inline-test library. It uses F's
local pinned oracle, all 800 fixtures, six seeded 513-packet streams and three
112-packet directed streams. No sibling worktree or new dependency is required.
The harnesses only instantiate/wire blocks; the production controller schedules
all clears, updates, results and responses.

Coverage: nine controller reset stages, arbitrary command/response stalls,
variable engine latency including next-edge results, distinct slot actions,
held request offers with changing fields, exact-once updates/results/responses,
shared-pointer wrap and final-completion receive lockout. Real-engine replay
checks 4,214 base packets plus 455 fresh-session packets after 13 interrupted
transactions, on one instance. Byte composition checks 100 oracle packets with
legal inter-byte pauses, realistic ready/busy TX stalls, exact reserved zeros,
final drain, fault/acceptance collisions, partial-byte and drain reset recovery.
All three generated test/controller tops are generated twice and checked by
Yosys hierarchy/proc/check and Icarus elaboration; G1 behavioral checks use
Cyclesim. Existing F and transport emitted-Verilog behavioral regressions remain
active. Full UART waveform/competition-board acceptance belongs to G2.

Save a fresh candidate's logs/coverage/RTL after rebuilding:

```sh
opam exec --switch=5.2.0+ox -- dune build test/protocol/transaction_verify.exe
PYTHONDONTWRITEBYTECODE=1 python3 test/protocol/transaction_checks.py \
  _build/default/test/protocol/transaction_verify.exe /tmp/phase-g1-results
```

Standalone controller RTL, without changing the production generator:

```sh
opam exec --switch=5.2.0+ox -- dune exec test/protocol/transaction_verify.exe -- \
  emit controller /tmp/gqh_transaction_controller.v
```

Replace `controller` with `payload` or `byte` to elaborate a test-only composition.
These are not six-port board designs. Measured complete-request acceptance to
response publication is 10 cycles for index zero and 8 for warm-up/steady paths;
earliest response transfer is one edge later. Callers must use handshakes.

The precise G2 wiring, measurement edges, candidate identity, preservation
manifest, command results and remaining hardware checks are in
[`results/phase-g1-20261003-candidate1/HANDOFF.md`](../../results/phase-g1-20261003-candidate1/HANDOFF.md).
That evidence directory is ignored by Git; retain it and the untracked source
files when transferring this local candidate. G2 may start; G1 hardware
acceptance still depends on G2's matching full-system build/tests.
