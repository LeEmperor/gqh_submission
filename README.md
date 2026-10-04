# GQH Hardware Track — Bit-Serial Trading Signals

A compact Hardcaml trading-signal engine for the **Tang Nano 20K**. The FPGA
receives two instruments' prices over UART, maintains independent 16-sample
moving averages, and returns buy/sell crossing signals. Parsing, history,
arithmetic, state and response generation all run on the FPGA; no team-supplied
host computation is required during judging.

## Selected submission

**Serial engine + LFSR UART TX (`serial_lfsr`): 195 total logic, 98 registers,
4 BSRAM.** The user confirms the full board suite passed. Saved official tests
and custom replay results are included; see [board evidence](submission/BOARD_VALIDATION.md)
and [the finalization checklist](SUBMISSION_CHECKLIST.md).

| Item | Selected value |
| --- | --- |
| Repository author | [LeEmperor](https://github.com/LeEmperor); participant details on Devpost |
| Board | Tang Nano 20K |
| Device | GW2AR-18C / **GW2AR-LV18QN88C8/I7** |
| Tool | **Gowin V1.9.11.03 Education**, GowinSynthesis, Verilog 2001 |
| Top module | **`gqh_competition_top`** |
| Final HDL | [`serial_adder_approach/gqh_serial_top.v`](serial_adder_approach/gqh_serial_top.v) |
| Reproducible build | [`submission/gowin/build.tcl`](submission/gowin/build.tcl) |
| Synthesis/P&R settings | [`serial_adder_approach/options.tcl`](serial_adder_approach/options.tcl) |
| Programming image | **[`bitstream/gqh_serial.fs`](bitstream/gqh_serial.fs)** |
| Input/image identity | [`submission/manifest.json`](submission/manifest.json) |
| Repository | <https://github.com/LeEmperor/gqh_submission> |
| Submission portal | <https://gqhacks.devpost.com> |

The selected `.fs` SHA-256 is
`a26f7ec1900b6cde817a8df396610a7a3e58f9b262331652e326bf5f1e892fa0`.
The selected RTL SHA-256 is
`b9a530d94a2dc9c7da8ff650e2f38ec9788e0d395e2bd03d229e305573f4664e`.
Other candidate projects/images in the repository are development history.

## Architecture

- A bit-serial engine updates each exact 20-bit rolling sum with a one-bit adder
  and subtractor over twenty cycles. Prices retain the full unsigned 16-bit range.
- Four inferred BSRAMs hold price history, sums, comparison/action metadata and
  packet bytes. Logical validity and warm-up handle stale memory after session reset.
- Comparisons use floor averages (`sum >> 4`); previous comparison flags replace
  storage of full previous prices. Non-crossings repeat the last action.
- A ten-bit UART frame shifter and LFSR counters reduce transmitter logic.
  All logic runs at **27 MHz**, without a PLL. UART uses **234 clocks per bit**
  (approximately 115385 baud, +0.16% from nominal 115200), with a full stop bit
  and no additional inter-byte gap. Both LEDs are held off.

See [the serial design notes](serial_adder_approach/README.md) for the datapath,
memory organizations, timing and implementation history.

## Build from the submitted source

The final Verilog is self-contained. **Rebuilding the FPGA image requires only
Gowin V1.9.11.03 Education**; OCaml/Hardcaml and IP generation are unnecessary
unless regenerating HDL. Clone the submitted repository and check out the full
commit SHA recorded on Devpost, then run from its root:

```sh
gw_sh submission/gowin/build.tcl
```

Put Gowin's `IDE/bin` directory on `PATH` (or invoke `gw_sh`/`gw_sh.exe` by full
path). On headless Linux, `QT_QPA_PLATFORM=minimal` may be needed. Use the vendor
runtime environment for the installed Gowin version.

The script selects the device/top, loads every saved option, adds exactly the
selected RTL, official CST and 27 MHz SDC, and runs synthesis and place-and-route.
Outputs are isolated in `submission/gowin/impl/`:

- Rebuilt image: `submission/gowin/impl/pnr/gqh_serial.fs`
- Resource report: `submission/gowin/impl/pnr/gqh_serial.rpt.txt`
- Synthesis report: `submission/gowin/impl/gwsynthesis/gqh_serial_syn.rpt.html`
- Resolved settings: `submission/gowin/resolved-settings.tcl`

The script leaves the supplied programming image in `bitstream/` intact. The
committed build script/options are the authoritative project definition; a new
GUI project with default options will not reproduce the recorded configuration.
For manual import, use the three inputs below and apply the saved options/top/part.
Do not add the engine-only alternative, simulation testbenches or other board tops.

### Constraints and ports

The unchanged organizer-supplied
[`19_tang_nano_20k.cst`](serial_adder_approach/19_tang_nano_20k.cst) and
[`tang_nano_20k.sdc`](serial_adder_approach/tang_nano_20k.sdc) are used with the
selected RTL. No manual pin reassignment is required.

| Port | Pin | Direction / function |
| --- | ---: | --- |
| `sys_clk` | 4 | Input, 27 MHz oscillator |
| `reset_btn` | 87 | Input, active-high reset button, pull-down |
| `uart_rx_i` | 70 | Input, BL616 to FPGA |
| `uart_tx_o` | 69 | Output, FPGA to BL616 |
| `led0_n` | 15 | Output, held high/off |
| `led1_n` | 16 | Output, held high/off |

## Program and reproduce the demo

1. Connect the Tang Nano 20K with a data-capable USB-C cable.
2. In Gowin Programmer, Scan Device and select **GW2AR-18C**.
3. Select **SRAM Mode → SRAM Program** and load **`bitstream/gqh_serial.fs`**.
4. Program/Configure successfully. Both LEDs remain off; this is intentional.
5. Close Programmer and other serial terminals. Run the board checks with Python 3
   and pyserial, replacing `PORT` with the actual UART port:

   ```sh
   python3 serial_adder_approach/validate_board.py PORT --fs bitstream/gqh_serial.fs
   ```

The helper prompts for programming/startup and physical reset steps. It changes
only `PORT` in private copies of the official tests. It runs quick, five normal/
full-range pairs **without reset or reprogramming between the paired tests**, custom
replays, legal byte pauses, and reset/fault recovery. Results are saved in a fresh
`serial_adder_approach/board_results/board-serial195-*` directory. It never programs
the board itself; the recorded programming identity is operator-confirmed.

Expected results: quick `PASS`; each robust run completes 100 responses with
84/84 scored packets, 168/168 actions, zero timeouts and correct warm-up bytes;
custom responses match the independent oracle. Official practice summaries report
correctness out of 70, not an official qualification score out of 100.

### Fixed wire interface

```text
PC -> FPGA: [index16][item1_8][price1_16][item2_8][price2_16]
FPGA -> PC: [index16][item1_8][action1_8][item2_8][action2_8][reserved16]
ITEM_A = 0x11; ITEM_B = 0x22
NONE = 0x00; SELL = 0x01; BUY = 0x02; reserved = 0x0000
UART: 115200 baud, 8N1, LSB first; multi-byte fields big-endian
```

One complete 8-byte request produces exactly one 8-byte response. State is routed
by item ID and responses preserve request slot order. Index 0 starts a fresh
session; indices 0–15 fill the windows and return NONE. No host-side algorithm or
unsolicited FPGA output is used.

## Verification and measured results

Selected-build reports are in
[`serial_adder_approach/evidence/serial_lfsr/`](serial_adder_approach/evidence/serial_lfsr/).
Resource measurements are local Gowin results; judges independently rebuild and
measure the submitted source/settings.

| Metric | Selected build |
| --- | ---: |
| Synthesis total LUTs (qualification metric) | **193** |
| P&R total Logic | **195** |
| P&R ALUs / SSRAM / latches | **0 / 0 / 0** |
| Total registers | **98** (97 logic FF + 1 I/O FF) |
| BSRAM | **4** |
| Reported setup / hold violated endpoints | **0 / 0** |
| Worst setup slack at 27 MHz | **+29.221 ns** |
| Normal five-run median of mean UART RTT | **16.814655 ms** |
| Full-range five-run median of mean UART RTT | **16.8111103 ms** |

The synthesis LUT total comes from Resource Usage Summary in
[`gqh_serial_syn.rpt.html`](serial_adder_approach/evidence/serial_lfsr/gqh_serial_syn.rpt.html);
P&R metrics come from
[`place-route.rpt.txt`](serial_adder_approach/evidence/serial_lfsr/place-route.rpt.txt).
The synthesis usage table lists 193 LUTs and 2 INV cells; the mapped logic total
is 195. These are distinct report fields, not interchangeable qualification metrics.
The saved engine test log passes **8,956 samples** and the TX test passes all
**256 byte values** with exact 234-clock bit lengths. The selected LFSR variant
passes **1,394 production-divisor serial oracle packets**, startup, legal pauses,
full stop bits, sticky faults and RX/engine/TX reset recovery. The verification
script also runs the unselected engine-only variant; its combined summary is
written when both finish. See [verification.log](serial_adder_approach/evidence/verification.log).

Five normal/full-range board pairs each completed perfectly, including warm-up
bytes, and both custom replays passed **2,834/2,834 packets across 26 sessions**.
The user confirms completion of the full board suite. The evidence record clearly
distinguishes saved machine results from operator confirmation. A clean-location
rebuild reproduces identical programming data (only its creation-time comment
differs): [rebuild verification](submission/REBUILD.md).

Optional HDL regeneration/local verification uses OCaml **5.2.0+ox**, Dune ≥3.17,
and the exact Jane Street/Hardcaml versions in [dune-project](dune-project), plus
Icarus Verilog and Yosys for HDL checks:

```sh
opam exec --switch=5.2.0+ox -- dune exec serial_adder_approach/generate.exe
python3 serial_adder_approach/verify.py
```

Regeneration consumes `serial_adder_approach/*.ml` and the shared `src/` library.
The verifier checks generated HDL identity, oracle-based engine state, complete
UART behavior, restart/reset/fault cases and both serial variants. Do not rerun it
over an in-progress verification job's evidence directory.

## External resources and local tooling

- **Jane Street Hardcaml, Core, ppx_hardcaml and related dependencies:** hardware
  construction/Verilog generation and OCaml tooling; versions are in `dune-project`.
- **GQH organizers:** participant guide, unchanged board CST, quick/robust tests,
  and the full-range practice attachment. Provenance is in
  [tools/official/README.md](tools/official/README.md) and the
  [placement supplement](docs/placement-supplement-20261003.md).
- **[BlackList GQH](https://github.com/jaydennargen/blacklist-gqh), inspected commit
  `8ed4a39`:** architectural inspiration from `src/ma_engine.sv` and `src/uart_tx.sv`
  for bit-serial processing and compact TX. This implementation is Hardcaml and
  retains this project's comparison-state and packet-controller architecture.
- **Gowin:** synthesis/P&R/programming tools and inferred FPGA memory resources.
  The selected design does not use the repository's PLL experiment.
- **Icarus Verilog, Yosys, Python/pyserial:** simulation, structural checks and local
  board testing. The independent oracle and replay runner are under `test/`.
  Imported datafactory/streaming tools and other experiments are development/demo
  resources; they are not dependencies of the selected judge FPGA build.

## Known limitations and status

- Local board results and operator confirmation are recorded in
  [submission/BOARD_VALIDATION.md](submission/BOARD_VALIDATION.md); official
  qualification and placement remain the judges' measurements.
- The design follows stop-and-wait. Framing errors or unexpected input while busy
  cause sticky protocol lockout until button reset; both diagnostic LEDs are disabled.
- No additional TX inter-byte idle delay is configured. The guide's BL616 transport
  warning makes final on-board no-timeout testing important.
- Vendor logs retain warning **PR1014** about clock routing. The saved timing report
  shows zero setup/hold violations for the applied constraints.

## Submission information

Submit the public repository URL and **full final commit SHA on Devpost**, then
return the board/accessories to Reitz Room 2345 by **October 4, 2026, 11:00 am EDT**.
Keep the repository public through judging. The SHA belongs in Devpost, not this
README. [SUBMISSION_CHECKLIST.md](SUBMISSION_CHECKLIST.md) tracks remaining work;
[README_DEVELOPMENT.md](README_DEVELOPMENT.md) preserves earlier candidates and notes.
