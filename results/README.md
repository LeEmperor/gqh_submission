# Evidence to retain

Gate 0 is locally prepared, not complete. There is no new Gowin or board evidence.
The existing old blinky reports and bitstream are not evidence for `gqh_top`.

For each manual candidate create a directory here, e.g. `bringup-YYYYMMDD-run1/`
or `history-probe-YYYYMMDD-run1/`. Save:

- Source revision and dirty diff, generated HDL and SHA-256, configuration
  (clock/divider/reset assumptions), device, actual Gowin version and options.
- Synthesis report: total LUTs (competition scoring metric), registers, RAM/BSRAM,
  warnings, and mapped memory primitive/netlist evidence for the probe.
- P&R report: resource usage, clock/constraints applied, worst setup/hold slack,
  unconstrained paths and exceptions, and any recovery/removal review.
- Board observations: programming method, fresh power-up/configuration with reset
  released, reset button polarity and press/release results, measured LED period,
  UART idle level, and whether initialization behaves as intended.

Later save official quick-test output, robust CSV/summary, timeout/mismatch counts,
repeated-session tests, host/Python/pyserial/USB details, TX pacing configuration,
and the matching `.fs` identity/hash. Keep a selected final bitstream in
`bitstream/`; it is not ignored. Local checks establish no LUT score, device
mapping, timing closure, board behavior, or official UART pass.

`local-verification.txt` records the initialization checks and their limits.
