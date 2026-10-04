# GQH Hardware Track

Build a compact **Hardcaml implementation of the required two-item, 16-sample
moving-average crossing algorithm** on the Tang Nano 20K. Qualify with **100/100
plus a perfect full-range run**, then minimize **total logic → registers →
five-run median latency** (within 5% tied), in that order.

## Start here

- **[Submission checklist and agent handoff](SUBMISSION_CHECKLIST.md)** — the
  ordered final-packaging, verification, Devpost and board-return workflow. Final
  candidate selection remains pending until the user is ready.
- **[PLAN.md](PLAN.md)** — the active implementation plan, exact protocol and
  algorithm, priorities, work assignments, and delivery gates. Update this when
  decisions change.
- **[October 3 placement supplement](docs/placement-supplement-20261003.md)** —
  qualification, resource-first ranking, judge rebuild rules and full-range script.
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
- **[Data streamer documentation](DATAFACTORY_README.md)** — build, test, and
  operation instructions for the imported datafactory workstream.
- **[Replay runner](test/runner/README.md)** — Python replay-and-measure runner
  imported from the runner feature branch.
- **[270 MHz PLL project](Hackathon/)** — Gowin project and generated PLL
  artifacts imported from the Nano20k PLL branch.
- **[Root-level Gowin projects](gowin/README.md#root-level-project-files)** —
  separate competition, engine, UART diagnostic, and PLL test projects with canonical paths.

## Current status

**F, G1, G2 and overall G are COMPLETE**, explicitly accepted by the user after
fresh synthesis/programming and passing local/board tests. Official quick,
normal robust and full-range practice pass; custom replay passes all 1,394 rows
across 13 sessions; fault/reset recovery and fresh startup also pass. Evidence
and the precise user-authorized closure are in REQUEST_RESPONSE_PLAN.md.
The user waives remaining build-identity bookkeeping and a separate physical
TX-idle measurement as F/G closure requirements; those were not performed.
Resource-first optimization (H), optional PLL work (P), and final submission
packaging remain open. The old blinky and diagnostic/PLL projects are preserved.

The new placement rule uses **Resource Usage Summary
total logic** (including ALUs), then total registers; BSRAM is excluded from
logic. Judges rebuild with **Gowin V1.9.11.03** and committed project settings.
The guide's synthesis-LUT and average-latency limits still govern qualification.

The downloaded practice attachment is `tools/22_robust_uart_test_fullrange.py`.
Run a PORT-only copy immediately after normal robust without resetting or
reprogramming. Each needs 100 responses, 84/84 scored packets, 168/168 actions
and zero timeouts; custom tests additionally verify warm-up contents and session
recovery. Preserve separate output directories and the matching build identity.

## Build and generate

Use the existing `5.2.0+ox` switch; no package installation, upgrade, or global
pinning is needed for this initialization. From the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune build
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- bringup
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- history-probe
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- transport
opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition
opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest
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

UART RX/TX live under `src/uart/`, packet decoding, the transaction controller
and paced responses under `src/protocol/`, and the shared update engine with
item-indexed 32 x 16 history RAM under `src/engine/`. Expected actions in tests
come from an independent direct-window oracle, not the DUT's rolling sum.

## Diagnostic UART transport

`generate.exe transport` emits self-contained `rtl/gqh_transport_top.v`, top
`gqh_transport_top`, with the official six ports. The default target remains
bringup. Transport echoes the index and slot IDs, returns NONE actions and two
reserved zero bytes, and starts only after the complete eight-byte request.
It has no algorithm state. See [REQUEST_RESPONSE_PLAN.md](REQUEST_RESPONSE_PLAN.md)
for the interface contracts and acceptance status.

UART uses independent RX/TX timers at 234 clocks/bit (27 MHz / 234 ≈ 115385 baud,
about +0.16% vs 115200), with zero extra idle clocks by default. TX always holds
the mandatory full stop bit. `create`/`hierarchical` accept `cycles_per_bit` and
`extra_idle_cycles` for simulation or a later spacing experiment. RX validates
the start center and stop sample, publishes one-cycle byte/error events, and
does not repeatedly restart on a continuously low line. Two idle-high registers
synchronize RX at the board boundary. LED0 remains heartbeat; LED1 lights on a
sticky protocol fault. Reset cancels partial requests and transmission and clears
that fault. Arbitrary host pauses between bytes are legal.

Use [gowin/README.md](gowin/README.md#diagnostic-transport-handoff) for manual board
steps. Run only the custom checker against this target:

```sh
python3 tools/check_transport.py /dev/ttyUSB0 --count 100
python3 tools/check_transport.py /dev/ttyUSB0 --count 100 --byte-pause 0.005
```

Requires Python 3 and pyserial on the host. It fails on mismatches, timeouts or
surplus output and never resets the board automatically. Reset the board before
retrying a failed stream: there is no protocol marker for automatic realignment.
These transport checks cannot establish official algorithm correctness.

Focused local checks:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/transport/runtest
```

Full regressions: `dune runtest` in the same switch.
See [test/transport/README.md](test/transport/README.md) for exact coverage and
tested baud mismatch. Emitted RTL passes Icarus and Yosys checks; Gowin mapping,
timing closure and board behavior remain unverified.


## Competition candidate

`generate.exe competition` emits [rtl/gqh_competition_top.v](rtl/gqh_competition_top.v),
top **gqh_competition_top**, with the same six scalar board ports. Open the separate
[gqh_competition.gprj](gqh_competition.gprj) for **GW2AR-LV18QN88C8/I7**; its only
inputs are that self-contained RTL and the pristine board CST/27 MHz SDC.

The wiring is UART RX → decoder → G1 controller ↔ F engine → sequencer → UART TX.
The controller owns slot-to-item routing, session clear, warm-up, pointer and
response ordering. Both items clear logically on index zero, including repeated
sessions on one connection; warm-up overwrites retained RAM. Receive rearm waits
for the sequencer's final-frame completion. There is no stream timeout or automatic
resynchronization: framing/busy-input faults latch LED1 until button reset.
UART remains 234 clocks/bit, 115384.615 baud (+0.1603% against 115200), 8N1 and zero
extra gap; every stop bit is full length. All logic runs directly on `sys_clk`.

See [test/integration/README.md](test/integration/README.md) for serial verification
and [G2 candidate handoff](results/phase-g2-20261003-candidate1/HANDOFF.md) for
source/RTL identity, measured core latency, commands and manual acceptance.
F–G status is **COMPLETE under the user-authorized closure**. The candidate
handoff retains its historical local-only status; subsequent board evidence and
closure are recorded in REQUEST_RESPONSE_PLAN.md.
Official scripts must run against this competition image, with their actual PASS
outputs/counts preserved; diagnostic NONE responses cannot satisfy acceptance.

**Submission and board return:** Sunday, October 4, 2026, **11:00 am EDT**.
The guide requires a public repository containing the matching source, build
files, constraints, and final `.fs`; put the full final commit SHA in Devpost.

This is the working README. Gate 5 in the plan lists the build, test, team,
attribution, and measured-results details needed for the submission README.
