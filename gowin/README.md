# Manual Gowin handoff

Create a new project in the Gowin IDE. The old `viv25_proj/test_proj1` is only
a part/tool reference; its build results do not verify this generated design.
Its saved P&R report names **V1.9.11.03 Education**. Record the version you
actually use for this new design.

1. Select **Tang Nano 20K**, device **GW2AR-LV18QN88C8/I7** (old project device
   family name `GW2AR-18C`, device identifier `gw2ar18c-000`).
2. Add exactly these bring-up inputs, relative to this project root:
   - `rtl/gqh_top.v` — contains top and both child definitions.
   - `constraints/19_tang_nano_20k.cst` — unchanged organizer pins.
   - `constraints/tang_nano_20k.sdc` — 27 MHz `sys_clk`, period 37.037 ns.
3. Select **gqh_top** as the top module. Do not add the old blinky or the
   history probe to this project.
4. Run synthesis and P&R manually. Check warnings, six scalar port names,
   applied pin/clock constraints, unconstrained paths, resource usage, and
   timing. Save evidence as described in `../results/README.md`.
5. Program manually using your board workflow. Expect LED0 to alternate on/off
   every 0.5 seconds; LED1 stays off (high); TX remains idle high. RX is unused.
   There are no packet responses and this design cannot pass official UART tests.

After editing Hardcaml, rerun `dune exec bin/generate.exe` (in the configured
switch) or the explicit bringup command from the README. It overwrites the same
`rtl/gqh_top.v`. Reload the updated file and rerun synthesis/P&R in the IDE.
No IDE or programmer automation is supplied.

## Reset and startup checks

Official CST: reset button S2/KEY2 on pin 87, pull-down. Organizer text does not
explicitly establish the pressed level. This design **assumes pressed = high**;
confirm on the board. Assertion asynchronously sets both reset synchronizer
stages; release takes two rising edges. The heartbeat consumes the synchronized
reset as a synchronous clear. Thus the LED clears on the next clock after reset
assertion; button bouncing can prolong/reassert reset, which is acceptable here.

The generated RTL explicitly initializes both reset stages to 1, the counter
to 0, and the heartbeat state to 0 using Verilog register declaration initial
values. Local HDL simulation confirms those emitted values, but is not proof
that Gowin maps/preserves them at FPGA power-up. Inspect synthesis initialization
warnings and mapped register startup values. Test fresh power-up and configuration
with the button released, then press/release the button and confirm heartbeat
restart. If initialization is not implemented reliably, add an evidence-driven
Gowin startup mechanism before relying on unattended startup. No Xilinx primitive
is present. An explicit button reset is the current recovery procedure.

The SDC supplies only the primary clock. Review recovery/removal and routing of
the asynchronous button to its two-stage release circuit. Do not add blanket
false paths. As UART evolves, constrain its asynchronous input deliberately,
review synchronizer placement/attributes and CDC timing exceptions, and add
appropriate I/O timing requirements with justification.

## Separate history-memory experiment

Create a separate synthesis project with **rtl/history_probe.v**, top
**history_probe**, same device. Do **not** add the board CST or board SDC: these
are internal memory ports, not the six board ports. For synthesis/timing experiments,
use a separate clock constraint on `clock` (37.037 ns), and document the remaining
unconstrained internal-interface I/O timing. Physical pin placement or programming
of this probe is not required.

Storage is 32 words x 16 bits, a single write port and one read port on the same
clock. Present address/data/enable before a rising edge; after that edge,
`read_data` contains the old word at the sampled read address. This is **one-edge
synchronous read latency**. A same-address read/write returns old data on that
edge and new data on a later read. No cells or output register are reset or
initialized; reads of unwritten words are unspecified. Future engine warm-up
must overwrite entries before using them as valid history.

Inspect the synthesized netlist and resource report: did the memory become BSRAM,
registers, or other logic? Record the primitive type/count, read register placement,
and collision mode. Read-first inference is an experiment, not a block-RAM guarantee.
If mapping/collision behavior is unsuitable, compare a narrow Gowin wrapper or
register implementation based on the saved evidence. No mapping result exists yet.
