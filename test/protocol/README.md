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
