# 270-logic competition candidate: diagnostic LEDs removed

Import these three files into Gowin:

- `gqh_competition_bsram_lean_top.v`
- `19_tang_nano_20k.cst`
- `tang_nano_20k.sdc`

Top: **gqh_competition_top**. Device: **GW2AR-18C**,
part **GW2AR-LV18QN88C8/I7**. Use **Gowin V1.9.11.03 Education**,
**GowinSynthesis**, **Verilog 2001**. Synthesize and run Place & Route.
The Verilog is self-contained; no IP generator or other HDL files are needed.

Alternatively open the included `gqh_competition.gprj`, with its companion
`impl/gqh_competition_process_config.json`. The reference settings are also
provided as `process-config-reference.json` and `options.tcl`. For a newly
created project, set those options in the IDE; adding HDL/constraints does not
import process settings. Keep RAM read/write checking off, timing-driven routing
and hold correction on, I/O register packing on, resource replication off,
placement/routing options 0, and routing max fanout 23.

## Measured result

Fresh Linux Gowin V1.9.11.03 Education build on October 4, 2026, using the same
options and constraints as the independently reproduced 302-logic parent:

| Metric | Parent | This candidate |
| --- | ---: | ---: |
| P&R total logic | 302 | **270** |
| P&R LUT / ALU | 242 / 60 | **210 / 60** |
| Registers | 109 | **84** |
| BSRAM / SSRAM | 3 / 0 | **3 / 0** |
| Setup / hold violated endpoints | 0 / 0 | **0 / 0** |
| Worst reported setup slack | +24.321 ns | **+25.160 ns** |

The measured saving is **32 total logic / 25 registers**. Synthesis can optimize
across module boundaries, so the original heartbeat's hierarchy attribution is
not an exact prediction of the whole-design saving.

## Change and behavior

The heartbeat module and fault-indicator inverter are omitted. Both active-low
LED pins are driven high/off; the official six-port interface and constraints
are retained. This removes all diagnostic-only logic from the selected top.

The UART, engine, packet controller and reset-release modules are byte-identical
to the 302-logic parent's generated modules. In particular, the sticky protocol
fault state still gates reception after framing/busy-input faults and clears
on reset. It is functional receive-lockout state, not an LED-only register.
There is no fault LED or heartbeat to observe during board tests.

Clock remains 27 MHz, UART divisor 234, 115200 baud 8N1. The complete stop bit,
full 16-bit prices, exact 20-bit sums and three inferred block memories remain.

## Regeneration and verification

From the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition-bsram-lean
opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest-bsram-lean
```

The corresponding general generator flags are:

```sh
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition \
  -packet-ram -records-in-bram -borrow-command -delta-arithmetic \
  -difference-relation -no-diagnostics -output rtl/gqh_competition_bsram_lean_top.v
```

For a command-line Gowin rebuild use `gw_sh build.tcl` in this folder. On this
Linux machine the tested invocation is:

```sh
GOWIN_HOME=/home/wayne/tools/gowin/1.9.11.03-edu QT_QPA_PLATFORM=minimal gw_sh build.tcl
```

Fresh resource/timing evidence is in `evidence/`. PR1014 remains the same
clock-routing warning as the parent; reported setup/hold violation counts are
zero.

Fresh Cyclesim and production-divisor Icarus serial regressions pass:
**1,394 oracle packets across 13 sessions**, startup, legal byte pauses, full
stop bits, sticky framing/busy fault lockout, RX/engine/TX reset recovery and
both LEDs staying off. Regeneration is deterministic and matches the delivered
RTL. Generated functional modules match the parent byte-for-byte, and
regenerating the original `competition-bsram` target still matches its committed
RTL. See `evidence/selected-serial.log`, `evidence/selected-serial-coverage.json`
and `review.json`.

## Board validation: passed

The user confirmed programming the 270-logic candidate and completed the full
interactive board suite on October 4, 2026. The saved summary has
`pass_all: true`; a copy is included as `evidence/board-summary.json`.

| Check | Result |
| --- | --- |
| Fresh startup | Exact response, no extra bytes |
| Official quick | 21/21 responses |
| Normal robust | 100 responses, 84/84 scored packets, 168/168 actions, zero timeouts |
| Full-range immediately after normal, without reset | 100 responses, 84/84 scored packets, 168/168 actions, zero timeouts |
| Custom replay | 1,598/1,598, zero mismatches/short responses/timeouts |
| Custom replay after populated-history reset | 1,598/1,598, zero mismatches/short responses/timeouts |
| Fault/reset | Busy-input lockout and fresh response after button reset passed |
| LEDs | Both off, confirmed at the interactive prompts |

Normal mean host round trip: **16.813 ms**, below the **20.7825 ms** qualification
threshold. Full-range mean: **16.902 ms**. These are single-run means, not the
five-run median tie-break measurement.

Full logs and CSVs remain at:
`../../result/board-bsram-270-20261004-070249-_874a3je/`.
The wrapper records the supplied image path and the user's programming
confirmation; it does not hash or read back the programmed bitstream.
