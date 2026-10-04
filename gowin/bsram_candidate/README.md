# 302-logic / 109-register competition handoff

This project selects `rtl/gqh_competition_bsram_top.v`, with top module
`gqh_competition_top`, part **GW2AR-LV18QN88C8/I7**, direct 27 MHz clock and UART
divisor 234. It includes the original heartbeat and complete stop bits.

Gowin V1.9.11.03 Education reports **302 Logic (242 LUT + 60 ALU), 109 Registers,
3 BSRAM**, zero setup/hold violations and 24.321 ns worst setup slack.
[The matching bitstream](../../bitstream/gqh_competition_bsram.fs) is identified
by [manifest.json](manifest.json). Board acceptance is pending.

## Rebuild

1. Keep the repository layout intact. Run
   `opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition-bsram`.
2. Open [gqh_competition.gprj](gqh_competition.gprj) in Gowin IDE.
3. Confirm the device above and top `gqh_competition_top`. Select GowinSynthesis,
   Verilog 2001, and preserve the 27 MHz SDC. The measured settings are in
   [process-config-reference.json](process-config-reference.json); this reference
   is not automatically imported. Keep hold correction enabled.
4. Run Synthesize, then Place & Route. Preserve the generated configuration,
   reports, logs and bitstream. Compare resource counts and both timing checks.

## Verify and qualify

With Icarus/Yosys available as described in [the toolchain guide](../../tools/HOPT_TOOLCHAIN.md):

```sh
opam exec --switch=5.2.0+ox -- dune runtest
opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest-bsram
```

The ordinary `competition` generator and root `gqh_competition.gprj` preserve
the exact 363-logic / 235-register fallback. Historical accepted images remain
separate from both new candidates; no new board acceptance is claimed.

For board promotion, first check the manifest's bitstream identity. Run quick
PASS, normal robust immediately followed by full-range without reset, custom
packet checks, and startup/reset checks. Record five latency runs only if needed
for the resource tie-break. Programming remains user-operated.

See [implementation and qualification notes](../../docs/bsram-register-optimization.md)
and the reports under [evidence](evidence). Open-source counts use a separate
scale; its hold-failing route does not replace the successful Gowin measurement.
