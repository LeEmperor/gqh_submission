# Transport verification

Phase E is complete as of October 3, 2026. The Phase E closure in
`../../REQUEST_RESPONSE_PLAN.md` records local acceptance and reuse of the
unchanged transport candidate's matching-build hardware evidence. This is
diagnostic NONE-action transport acceptance; algorithm verification remains
with phases F/G. No new synthesis or flashing is required for this closure.

Run the focused package A–E suite from the project root:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/transport/runtest
```

Phase D's additional focused handshake/reset/collision suite lives in
`test/protocol/`; run `dune build @test/protocol/runtest` in the same switch.
See [its verification notes](../protocol/README.md) for coverage and sampling.
The original decoder/sequencer checks here remain active.

`transport_tests.ml` owns the original block and reduced-divider serial integration
checks; its Dune executable has an explicit module owner (`transport_tests`).
The existing foundation executable stays in `test/`. No networking checkout
is needed to build or test.

Phase C also has a focused executable, `tx_boundary_tests.ml`, explicitly owned
by `(modules tx_boundary_tests)` in the same Dune file. Run it alone with
`opam exec --switch=5.2.0+ox -- dune exec test/transport/tx_boundary_tests.exe`.
It checks all 256 bytes at each of these `(clocks_per_bit, extra_idle_cycles)`
settings: `(1,0)`, `(1,1)`, `(1,2)`, `(2,0)`, `(2,1)`, `(3,3)`, `(7,0)`,
`(7,13)`, `(8,7)`, `(8,8)`, `(8,9)`, `(9,0)`, `(9,16)`, `(234,0)`, `(234,256)`.
The independent clock-by-clock oracle checks all ten bit durations and the
exact gap, latched data under continuously changing inputs, held/pulsed valid
under backpressure, first-ready-edge acceptance, no deferred busy-time offers,
extended idle, reset at both ends of every bit/gap, valid asserted during held
reset, and immediate post-reset acceptance. Invalid zero/negative bit periods
and negative gaps must fail elaboration. The production board remains at
234 clocks/bit with zero extra gap; these parameter variants are local tests.

- RX uses an independent waveform source: all 256 bytes back-to-back at 100
  clocks/bit; start phases with 98–102 clocks/bit (about ±2% period mismatch);
  short false start, invalid stop, long break, and reset mid-frame. Valid is a
  single cycle and never coincides with framing error. This is a tested range,
  not a universal tolerance claim.
- TX uses an independent bit/duration checker at 7 clocks/bit: zero and 13-clock
  extra gaps; exact full start/data/stop periods; changed input after acceptance;
  valid held while busy; consecutive transfers; reset mid-frame.
- Byte-level decoder checks all fields/endian order, the eighth byte, long
  pauses, stable stalled payload, acceptance, and sticky framing/busy/held faults.
- Sequencer checks latched fields, action extension, reserved zeros, arbitrary
  ready stalls, eight accepted bytes, and final busy drain before done.
- Reduced-divider board integration checks multiple stop-and-wait transactions,
  swapped slots, no early TX, partial-request reset, and zero/21-clock TX gaps.
  Cyclesim's explicit reset API is used for this test because button assertion
  is asynchronous; actual pin reset is covered in emitted RTL instead.
- `check_transport_rtl.py` checks deterministic/stale deliverables, exact six
  ports, Yosys hierarchy/process/check passes, and Icarus simulation of the
  emitted complete hierarchy at the production 234-clock divisor.
  `transport_tb.v` checks serial responses, legal host pauses, asynchronous
  button reset, partial abort, framing-fault lockout, and busy-input fault with
  completion of the already accepted response.

Internal producers retain payload/valid until acceptance. RX events are pulses
without ready. Decoder owns the sticky protocol fault; harness owns receive
lifecycle. The harness accepts only complete requests and blocks reception
through final-frame completion. Framing errors or unexpected bytes latch the
fault until board reset. There is no timeout or automatic stream realignment.
