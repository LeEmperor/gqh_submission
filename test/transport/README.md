# Transport verification

Run the focused package A–E suite from the project root:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/transport/runtest
```

`transport_tests.ml` owns the block and reduced-divider serial integration
checks; its Dune executable has an explicit module owner (`transport_tests`).
The existing foundation executable stays in `test/`. No networking checkout
is needed to build or test.

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
