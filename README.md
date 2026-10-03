# GQH Hardware Track

Build a compact **Hardcaml implementation of the required two-item, 16-sample
moving-average crossing algorithm** on the Tang Nano 20K. Establish complete
correctness, then optimize measured LUT count and UART round-trip latency.

## Start here

- **[PLAN.md](PLAN.md)** — the active implementation plan, exact protocol and
  algorithm, priorities, work assignments, and delivery gates. Update this when
  decisions change.
- **[Competition guide](gqh_hw_guide.pdf)** — organizer requirements, scoring,
  board setup, and submission rules.
- **[Organizer resource checkout](../GQH-Hardware-Track-Submission/)** — official
  constraints, quick/robust UART tests, and submission templates, downloaded to
  `~/devel/jane/GQH-Hardware-Track-Submission/`. Exact paths and test coverage are
  recorded in [PLAN.md](PLAN.md#organizer-repository-available-locally).
- **[Existing Gowin bring-up project](viv25_proj/test_proj1/)** — LED blinky
  source and saved build artifacts for the correct device.
- **[Archive](archive/README.md)** — superseded Tickweave proposals and the
  architecture discussion that led to the current plan.

## Current status

The Hardcaml foundation and minimal board bring-up are implemented and locally
verified. **Gate 0 remains incomplete** until the user runs Gowin synthesis/P&R,
inspects actual memory mapping and timing, and tests startup/reset on the board.
UART, packet handling, the competition engine, and official correctness/performance
results are still pending. The old blinky project and archive are preserved.

## Build and generate

Use the existing `5.2.0+ox` switch; no package installation, upgrade, or global
pinning is needed for this initialization. From `testing/`:

```sh
opam exec --switch=5.2.0+ox -- dune build
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- bringup
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- history-probe
opam exec --switch=5.2.0+ox -- dune runtest
```

Immediate workflow: edit `src/`, run `dune exec bin/generate.exe` inside the
configured switch (no subcommand defaults to bringup), then manually import
`rtl/gqh_top.v` and the constraints into Gowin. The generated file is self-contained,
with `gqh_top`, `gqh_reset_release`, and `gqh_heartbeat` definitions. It has no
sibling-source dependencies. `history-probe` emits a separate `history_probe` top.

Use `-- bringup -help` or `-- history-probe -help` for target help. Override output:

```sh
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- bringup -output rtl/experiment.v
```

Generation uses a fresh non-flattening Scope and emits the complete hierarchy.
Defaults and relative overrides resolve under `DUNE_SOURCEROOT` supplied by
`dune exec`; directories are created as needed. Running `_build/default/bin/generate.exe`
directly requires the project root as the working directory or an explicit
`DUNE_SOURCEROOT` pointing to it. Absolute output overrides are honored. Each run
prints the path and top module and overwrites that HDL file deterministically.

Verified local versions: OCaml **5.2.0+ox**, Dune **3.22.2**; Hardcaml, Core,
Core_unix, ppx_hardcaml, ppx_jane and jane_rope all
**v0.18~preview.130.106+341**. `dune-project` records exact OCaml/Jane package
constraints; Dune generates `hardcaml_gqh.opam`. The Dune language minimum is
3.17; 3.22.2 is the tested version. Edit the project file, not generated opam.
Local HDL checks used Icarus Verilog **12.0** and Yosys **0.33**
(`2584903a060`). Python 3 runs the HDL/checksum checks; pyserial is only needed
for future official board tests. No networking library is a runtime dependency.
The old Gowin report records **V1.9.11.03 Education**, not a new validated build.

## Directory responsibilities

| Path | Responsibility |
| --- | --- |
| `src/` | One wrapped `hardcaml_gqh` library; qualified subdirectories. |
| `src/board/` | 27 MHz configuration, reset release, heartbeat, six-port board top. |
| `src/history_probe.ml` | Separate 32 x 16 synchronous read-first memory experiment. |
| `bin/generate.ml` | Command.group generator, bringup default, output override. |
| `rtl/` | Generated self-contained Verilog deliverables; include in submission. |
| `constraints/` | Unchanged official CST and 27 MHz board SDC. |
| `test/` | Focused Cyclesim, Icarus, Yosys, determinism and checksum regressions. |
| `tools/official/` | Pristine pinned scripts and source/checksum provenance. |
| `gowin/README.md` | Manual IDE input, part/top, reset and memory-mapping instructions. |
| `results/` | Local verification record and instructions for saving new tool/board evidence. |

## Bring-up behavior and manual IDE inputs

Select **GW2AR-LV18QN88C8/I7**, top **gqh_top**, and add:

- `rtl/gqh_top.v`
- `constraints/19_tang_nano_20k.cst`
- `constraints/tang_nano_20k.sdc`

Follow [gowin/README.md](gowin/README.md) for manual synthesis, P&R, and board
checks. Regeneration updates the same RTL path before resynthesis. IDE import,
synthesis/P&R and programming are the user's steps.

The six scalar ports match the official CST. LED0 is active low and toggles every
13,500,000 clocks (0.5 seconds at 27 MHz); LED1 stays high/off. TX stays high/idle,
and RX is preserved but unused. All logic uses `sys_clk`; no fabric-generated
clock is used. Simulation supplies a reduced heartbeat divider through the
creation parameter. No UART responses or fake competition actions are implemented.

The official pull-down on `reset_btn` motivates an **active-high pressed-button
assumption** that must be verified on hardware. Reset asserts asynchronously into
two stages and releases after two clocks; heartbeat clear is synchronous.
The emitted registers have deliberate initial values (reset stages 1; heartbeat
counter/state 0). Icarus validates the emitted initialization semantics, but
Gowin's preservation of these startup values and actual power-up behavior remain
unverified. See the handoff for the precise startup/button checks and possible
future Gowin startup mechanism. The SDC defines only the 37.037 ns primary clock;
UART/reset evolution needs justified CDC/I/O timing review, not blanket false paths.

## Verified behavior and pending work

`dune runtest` checks reduced-divider heartbeat/reset, TX/LED1 high, all 32 memory
addresses, one-edge read latency, disabled writes, and read-first collisions.
Cyclesim exercises synchronous heartbeat clear; Icarus exercises the actual emitted
top's initialization and asynchronous reset/release. Yosys `hierarchy -check`,
`proc` and `check -assert` plus Icarus elaboration confirm complete emitted hierarchy
and exact port directions/widths. Repeated generation is byte-identical and matches
the present RTL deliverables. The pristine official inputs match pinned SHA-256s.
These tests do not establish Gowin mapping, timing closure, or board operation.

The probe has no RAM-cell reset or initialization; unwritten data is unspecified.
Its intended read latency and collision behavior are described in the handoff.
Synthesize it separately without board pin constraints and inspect actual storage
mapping before relying on block RAM. A vendor wrapper is a possible next step
only if reports justify it.

Next add UART RX/TX under `src/uart/`, then complete eight-byte packet capture and
paced responses under `src/packet/`, a shared sequential update engine under
`src/engine/`, and item-indexed history/state under `src/history/` as useful modules
become implemented. Preserve the architecture:
**UART RX → packet capture → shared sequential engine ↔ item-indexed history/state
→ paced UART TX**. Add an independent oracle and directed fixtures alongside UART
verification. Full official quick/robust passes require the complete engine;
the copied scripts have not been run against a serial device during initialization.

**Submission and board return:** Sunday, October 4, 2026, **11:00 am EDT**.
The guide requires a public repository containing the matching source, build
files, constraints, and final `.fs`; put the full final commit SHA in Devpost.

This is the working README. Gate 5 in the plan lists the build, test, team,
attribution, and measured-results details needed for the submission README.
