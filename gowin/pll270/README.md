# PLL experiment based on the 270-logic candidate

**81 MHz core, 272 logic / 88 registers / 3 BSRAM / 1 rPLL.**
`pll270` identifies the parent design, not a 270 MHz clock or a 270-logic result.
The measured direct-clock 270-logic candidate remains the resource-first winner.
This is a separate experiment; board validation and host-latency measurements
are pending for this image.

## Add these four files to Gowin

1. `gqh_competition_pll_top.v` — generated Hardcaml design and complete hierarchy.
2. `gowin_rpll_81.v` — real Gowin rPLL wrapper, with LOCK exported.
3. `19_tang_nano_20k.cst` — unchanged organizer pin constraints.
4. `pll81.sdc` — 27 MHz reference plus explicit 3x generated-clock constraint.

Top module: **gqh_competition_pll_top**.
Device: **GW2AR-18C**, part **GW2AR-LV18QN88C8/I7**.
Tool: **Gowin V1.9.11.03 Education**, GowinSynthesis, Verilog 2001.

The included `gqh_pll270.gprj` opens these four inputs. Its companion
`impl/gqh_pll270_process_config.json` supplies the reference settings; confirm
the top and settings in the IDE. For a fresh project, consult
`process-config-reference.json`. `build.tcl` and `options.tcl` reproduce all
measured options with `gw_sh build.tcl` from this folder.

Synthesize, then Place & Route. The rebuilt image is
`impl/pnr/gqh_pll270.fs`. The independently measured image is also included as
`bitstream/gqh_pll270.fs`, identified in `manifest.json`.

The reference-only files in `ip-source/` preserve the user's original IP source
and generator settings. They are not project inputs. No IP wizard, proprietary
simulation library, or test-only PLL model needs to be added to the Gowin project.

## Clock and reset integration

The supplied IP was configured for **27 -> 81 MHz** (`IDIV_SEL=0`,
`FBDIV_SEL=2`, `ODIV_SEL=8`; VCO 648 MHz). Those primitive parameters are
preserved. The copied wrapper is renamed `Gowin_rPLL_81` and exposes `LOCK` as
`locked`; the original wrapper discarded that output.

`Board.Competition_pll_top` uses Hardcaml `Instantiation.create` for this external
module. All protocol, engine, UART and synchronization registers use the single
81 MHz core clock. The button or loss of PLL lock asynchronously asserts the
existing two-stage reset-release circuit, including when the core clock stops.
Reset releases after two core edges following lock. The PLL itself is never
held in reset by its own unlocked state. TX is held idle-high during reset.
Both LEDs remain off; protocol fault lockout is retained.

UART divisor is **702**, so `702 / 81 MHz = 234 / 27 MHz`: the physical UART bit
duration is exactly the same as the board-tested parent (approximately 115385
baud, compatible with the nominal 115200 baud 8N1 host). Extra inter-byte idle
remains zero. The PLL does not change the USB bridge's behavior or buffering.

The SDC constrains `pll/rpll_inst/CLKOUT` to the correct 3x relationship. The
fresh timing report identifies `core_clk` at **81.000 MHz**, period **12.346 ns**.
The unused auxiliary PLL outputs appear as automatically derived clocks with
no timing paths; all functional paths use `core_clk`.

## Measured resource/timing comparison

| Metric | Direct-clock parent | PLL experiment |
| --- | ---: | ---: |
| Core clock | 27 MHz | 81 MHz |
| Total logic | 270 | **272** |
| P&R LUT / ALU | 210 / 60 | **212 / 60** |
| Registers | 84 | **88** |
| BSRAM | 3 | **3** |
| rPLL | 0 | **1** |
| Worst reported setup slack | +25.160 ns | **+0.484 ns** |
| Setup / hold violated endpoints | 0 / 0 | **0 / 0** |

The larger UART countdown registers account for four extra registers. Resource
totals are measured whole-design counts, not summed hierarchy estimates. Fresh
Gowin reports and the resolved options are in `evidence/`. The existing PR1014
warning applies to the 27 MHz input reference route. The PLL output is on a
primary clock network; its routed timing was analyzed at 81 MHz.

## Latency expectation

The parent takes 16 core cycles from final request-byte acceptance to first TX
byte acceptance, or 18 cycles for index zero. At 81 MHz the same schedule takes
about **0.198 / 0.222 microseconds**, compared with **0.593 / 0.667 microseconds**
at 27 MHz: about **0.395 / 0.444 microseconds** saved at that internal endpoint.
UART wire time is unchanged. USB/driver/host overhead dominates the measured
16.8 ms round trip, so a meaningful millisecond reduction is not expected.
Actual end-to-end latency must be measured on the board; changes at this scale
can be obscured or quantized by USB scheduling.

Because total logic is ranked before registers and latency, **272 is currently
a worse ranking result than 270**, even if a host run happens to be faster.

## Regenerate and verify

From the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition-pll
python3 test/pll/run_checks.py _build/default/bin/generate.exe \
  --vendor-lib "$HOME/tools/gowin/1.9.11.03-edu/IDE/simlib/gw2a/prim_sim.v" \
  --output /tmp/opencode/pll270-verification-new
```

The output directory must be new. Verification requires Icarus and Verilator.
It checks exact IP parameters, deterministic generation, unchanged engine/
packet-controller/reset modules, delayed lock, stopped-clock unlock during TX,
relock/button recovery, and the actual wrapper's 81 MHz clock using the installed
Gowin rPLL functional model. Full serial oracle replay uses an explicitly ideal
PLL model; it is not an analog PLL or post-route simulation. Current results are
recorded in `manifest.json` and `evidence/`.

All local checks passed: **1,394 production-divisor serial oracle packets across
13 sessions**, full stop bits, framing/busy faults, RX/engine/TX resets and LEDs
off; plus delayed lock, asynchronous reset with a stopped core clock, relock,
and the actual vendor wrapper's 81 MHz output. Regeneration is byte-identical.
The 16/18-cycle internal latency was confirmed by the serial simulation.

On this machine, a vendor CLI rebuild can be run with:

```sh
GOWIN_HOME="$HOME/tools/gowin/1.9.11.03-edu" QT_QPA_PLATFORM=minimal gw_sh build.tcl
```

## Board test

Program this candidate in SRAM mode, close serial applications, then run the
existing wrapper from the other checkout. Confirm fresh startup before pressing
reset, and follow its subsequent prompts:

```sh
cd /home/wayne/devel/jane/gqh_submission
python3 tools/validate_board.py \
  --port /dev/ttyUSB1 --label pll270-81MHz \
  --no-heartbeat --no-fault-led \
  --fs /home/wayne/devel/jane/even_smaller/gowin/pll270/bitstream/gqh_pll270.fs \
  --results-root /home/wayne/devel/jane/even_smaller/results
```

If you rebuild in your own Gowin project, use that freshly programmed `.fs` path
instead. `--fs` records the path and does not program the board. The suite checks
normal/full-range sessions, custom vectors, startup and button/fault recovery;
physical PLL loss-of-reference behavior is covered only by local models so far.
