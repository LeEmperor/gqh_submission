# Bit-serial BSRAM candidate

**Selected: `gqh_serial_top.v` — 195 Gowin Logic, 98 registers, 4 BSRAM.**

## Manual import into a fresh Gowin project

Add **exactly these three files** from this directory:

1. `gqh_serial_top.v` — self-contained engine + whole-frame/LFSR UART TX.
2. `19_tang_nano_20k.cst` — unchanged official board pin constraints.
3. `tang_nano_20k.sdc` — unchanged 27 MHz clock constraint.

Top module: **`gqh_competition_top`**.
Device: **GW2AR-18C**, part **GW2AR-LV18QN88C8/I7**.
Tool: **Gowin V1.9.11.03 Education / GowinSynthesis / Verilog 2001**.
No IP generation, external HDL, OCaml or Hardcaml installation is needed for
manual import. Run synthesis and place-and-route.

`gowin_import.zip` packages these inputs, both variants, reports and bitstreams
for transfer to another machine. Extract it before adding files in the IDE.

For the engine-only alternative, replace `gqh_serial_top.v` with
`gqh_serial_engine_only_top.v`. Both files define the same top and helper
modules: **include only one**. `serial_engine_test.v`, `engine_tb.v` and
`tx_tb.v` are simulation inputs, not board-project inputs.

The full measured process settings are in `options.tcl`. Adding HDL and
constraints to a new project does not import those settings. In particular:
RAM read/write checking **off**, timing-driven routing and hold correction
**on**, input/output/I/O register packing **on**, resource replication **off**,
placement/routing options **0**, route max fanout **23**. Use the same settings
when comparing against the existing 270-logic candidate.

## Hardware changes

The new engine uses three inferred block RAMs:

| Memory | Organization | Address |
| --- | --- | --- |
| History | 512 × 1 | item, circular slot, price bit |
| Rolling sums | 64 × 1 (20 used bits/item) | item, sum bit |
| Previous comparison and held action | 2 × 4 | item |

The existing 8×8 packet RAM makes **four intended BSRAMs total**. Each memory
has `syn_ramstyle="block_ram"`; actual mapping must be checked in the vendor
report.

For each sample the engine primes synchronous RAM reads, then performs twenty
LSB-first update steps. A single-bit full adder and a single-bit subtractor
compute `sum + price - oldest` using carry/borrow registers. The newest sum
bit is written back while the next old bit is read. During warm-up the outgoing
price is masked to zero. Two per-item validity bits mask stale sums/metadata
after reset/session clear; no RAM is cleared or initialized.

A four-clock price-bit delay aligns price bits with sum bits 4–19, comparing
against the **truncated** average. A more-significant unequal bit supersedes
the current relation. Previous below/above flags are retained, including during
warm-up, so no previous-price RAM or second serial comparator is needed.
Prices remain unsigned 16-bit and sums remain exact 20-bit.

The controller borrows the command through the entire update. Acceptance is
E0, RAM priming E1, bit updates E2–E21, result publication E21 and earliest
result transfer E22. Result stalls do not write memory. A reset may interrupt
a bitwise write; reset invalidates scalar state and a new index-zero session
must overwrite the full history during warm-up before evaluation.

`gqh_serial_top.v` additionally replaces TX with a ten-bit `{stop,data,start}`
shifter and LFSR baud/frame counters. Every start/data/stop bit lasts exactly
234 clocks. No extra inter-byte gap is inserted. RX, packet handling, sticky
framing/busy-input fault lockout, button reset and the 27 MHz clock use the
existing implementation. Both LEDs remain off.

Architecture inspiration: `../../blacklist-gqh/src/ma_engine.sv` and
`../../blacklist-gqh/src/uart_tx.sv` in the workspace (repository
https://github.com/jaydennargen/blacklist-gqh, inspected commit `8ed4a39`).
The new implementation is Hardcaml source in this directory; it retains this
project's comparison-flag state and packet controller.

## Reproduction

From the `even_smaller` root:

```sh
opam exec --switch=5.2.0+ox -- dune exec serial_adder_approach/generate.exe
python3 serial_adder_approach/prepare.py
python3 serial_adder_approach/verify.py
python3 serial_adder_approach/build.py
python3 serial_adder_approach/summarize.py
python3 serial_adder_approach/package.py
```

The build command is optional for manual IDE use. It invokes installed `gw_sh`
on both variants sequentially, using `builds/` for work files, and saves reports,
settings, bitstreams and input SHA-256s under `evidence/`. `GOWIN_HOME` may
override the local tool location. Generation uses the existing RX/controller/
reset Hardcaml modules, plus `serial_engine.ml` and `serial_tx.ml` here.
The summary command checks saved input/bitstream hashes and setup/hold endpoints,
and writes `evidence/resources.json` from the vendor report rows.
The package command verifies matching successful simulation/build RTL hashes
before creating `gowin_import.zip`.

Verification reuses the independent direct-window oracle and production UART
testbench from the project. It checks full-range arithmetic and stored state,
poisoned RAM, item isolation, stalled results, all 256 TX bytes with exact bit
lengths, emitted hierarchy, startup, session restarts, slot swaps, legal byte
pauses, complete stop bits, sticky faults, reset during every serial engine
digit in both slots, and RX/TX reset recovery.

See `evidence/verification.json` and `evidence/verification.log` for completed
local results. No FPGA is programmed by these scripts.

The focused engine test passes **8,956 samples**, checking the actual stored
20-bit sum, history and comparison/action metadata against direct-window
expectations, with poisoned initial RAM and stalled results. The focused TX
test passes **all 256 byte values**, checking each of the 234 clocks of every
start, data and stop bit, including back-to-back frame acceptance.

## Vendor measurements — October 4, 2026

Fresh Gowin V1.9.11.03 Education builds with the existing 270-LC build's options:

| Variant | Post-route Logic | LUT / ALU | Registers | BSRAM | Setup / hold violations | Worst setup slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Existing lean baseline | 270 | 210 / 60 | 84 | 3 | 0 / 0 | +25.160 ns |
| Serial engine + original TX | **203** | 203 / 0 | 97 | 4 | 0 / 0 | +28.218 ns |
| **Serial engine + LFSR TX** | **195** | 195 / 0 | 98 | 4 | 0 / 0 | +29.221 ns |

The selected candidate saves **75 LC (27.8%)** against the saved 270-LC build,
and measures **19 LC below** BlackList's reported 214. The engine-only change
saves 67 LC; the complete LFSR TX variant saves a further 8 at whole-design level.
Both variants have zero SSRAM and zero inferred latches. Vendor-reported Fmax
is 127.936 MHz for the selected candidate and 113.390 MHz for engine-only;
both actually operate at **27 MHz**. The existing PR1014 clock-routing warning
is retained in the logs.

Raw reports, resolved settings, matching `.fs` images and SHA-256 manifests:

- `evidence/serial_lfsr/` — selected **195-LC** build.
- `evidence/serial_engine_only/` — **203-LC** comparison build.

The selected RTL SHA-256 is
`b9a530d94a2dc9c7da8ff650e2f38ec9788e0d395e2bd03d229e305573f4664e`.
Its matching bitstream is `evidence/serial_lfsr/gqh_serial.fs`, SHA-256
`a26f7ec1900b6cde817a8df396610a7a3e58f9b262331652e326bf5f1e892fa0`.

**Board validation: user-confirmed full-suite PASS, October 4.** Five saved
normal/full-range pairs and both 2,834-packet custom replays pass. Normal/full-range
median-of-run-means RTT is 16.814655 / 16.8111103 ms. See
[the submission evidence record](../submission/BOARD_VALIDATION.md) for saved
machine results and operator-confirmed completion, and [the root README](../README.md)
for the selected programming image and portable judge build.

## Run the board-validation script

From the `even_smaller` root, after programming the selected image:

```sh
python3 serial_adder_approach/validate_board.py /dev/ttyUSB1
```

Use `COM6` (or your actual port) on Windows. Requires `pyserial`
(`python3 -m pip install pyserial`). Close serial terminals and the programmer.
If you programmed your fresh project's own image, identify it explicitly:

```sh
python3 serial_adder_approach/validate_board.py /dev/ttyUSB1 --fs /path/to/your/impl/pnr/design.fs
```

The script records that file's SHA-256 and asks you to confirm fresh programming;
it neither programs nor reads back the board. Do not press reset before the
startup check. It then runs:

1. Fresh-startup exact response and no surplus bytes.
2. The official quick script with only its `PORT` setting changed.
3. **Five normal/full-range pairs**, with no reset/reprogramming or other test
   traffic between normal and full-range. It checks every CSV response against
   the independent oracle, including warm-up bytes, and records all five mean
   latencies and their median. Every run needs 100 responses, 84/84 scored
   packets, 168/168 actions and zero timeouts.
4. Custom replay: public fixtures, randomized full-range sessions, all-maximum,
   all-zero, alternating extremes, truncation/equality, swaps, circular wraps
   and new sessions interrupting warm-up.
5. Legal pauses between request bytes, then a **prompted button reset** with
   populated history and a partial request. The full custom replay repeats.
6. Busy-input and UART framing fault lockout, each followed by a **prompted
   button reset** and exact-response recovery. Both LEDs stay off on this build;
   fault detection is checked through UART behavior.

Allow a few minutes and stay nearby for **three button-reset prompts** after
the initial programming confirmation. Do not reset during the official pairs.
The final terminal verdict must be **`BOARD VALIDATION PASS`**, with exit status
0 and `pass_all: true` in the saved summary. Failures/interruptions retain their
logs and never produce that verdict. Official mean latencies must also stay
within 20.7825 ms. This is the practice confidence suite, not a hidden-judge run.

Results go into a new timestamped folder under `serial_adder_approach/board_results/`:
`summary.json`, official PORT-only script copies/logs/CSVs, custom fixtures and
custom-runner per-packet CSVs/summaries. `--rounds 1` gives a faster first pass;
the default five pairs provide repeatability and the latency median.
`--prepare-only` builds the fixture and records inputs without opening a port.
