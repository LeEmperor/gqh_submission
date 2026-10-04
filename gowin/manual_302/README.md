# Reviewed 302-logic Gowin handoff

## Files to import into your project

Add these three files from this folder:

- `gqh_competition_bsram_top.v` — complete, self-contained generated Verilog.
- `19_tang_nano_20k.cst` — official Tang Nano 20K pin constraints.
- `tang_nano_20k.sdc` — 27 MHz clock constraint (37.037 ns).

Select **GW2AR-LV18QN88C8/I7**, device **GW2AR-18C**, and top module
**gqh_competition_top** (the top name does not include `bsram`). Use
**Gowin V1.9.11.03 Education**, **GowinSynthesis**, **Verilog 2001**.
Run **Synthesize**, then **Place & Route**. Read **Logic** in the P&R
**Resource Usage Summary**.

Expected result, independently reproduced on October 4, 2026:

| Metric | Result |
| --- | ---: |
| Total logic | **302** |
| P&R LUT / ALU | 242 / 60 |
| Registers | **109** |
| BSRAM / SSRAM | 3 / 0 |
| Setup / hold violated endpoints | 0 / 0 |
| Worst reported setup slack | +24.321 ns |

The HDL contains all seven modules, including the original heartbeat and fault
LED. No IP generation, PLL, memory initialization file, OCaml installation or
additional Verilog source is required. UART is 115200 baud, 8N1, using divisor
234 at 27 MHz. LED0 toggles every half second; LED1 indicates a sticky fault.

## Reproducing the measured settings

`process-config-reference.json` contains the original measured GUI settings.
In particular, keep RAM read/write checking off, timing-driven routing and
hold correction on, input/output/I/O register packing on, resource replication
off, placement/routing options at 0, and routing max fanout at 23. The complete
settings are also in `options.tcl`.

For a ready-made standalone project, open `gqh_competition.gprj`; its companion
`impl/gqh_competition_process_config.json` supplies those settings. Confirm the
top/device/settings in the IDE. For a new project with a different name, use
the reference settings in its configuration dialog; simply adding the three
design files does not import settings.

Optional CLI build from this folder: `gw_sh build.tcl`. On this Linux machine:

```sh
GOWIN_HOME=/home/wayne/tools/gowin/1.9.11.03-edu QT_QPA_PLATFORM=minimal gw_sh build.tcl
```

## Review

This is the exact `competition-bsram` candidate from branch `newop`, commit
`9c2c22c`, packaged without HDL changes. `SHA256SUMS` identifies the package.
The RTL SHA-256 is
`ce77edb9c8221e34c78818d572178617844e7087f8388f92d5e216b967a3ca87`.

The reduction is legitimate: packet storage (8x8) and per-item scalar records
(2x24) use two additional BSRAMs alongside the 32x16 history. Prices remain
unsigned 16-bit and sums remain exact 20-bit. A signed 17-bit price delta is
sign-extended into the sum; comparison subtraction covers the full price range.
Resettable record-valid bits mask stale scalar memory, and warm-up masks stale
history. The packet controller retains engine command fields through commit
and retains response bytes through the final UART stop bit.

Compared with the user's 304-logic reference, this is two fewer logic counts
while including heartbeat and fault indication. It is a divergent implementation,
not a two-cell patch to main. The branch's ordinary `competition` target and
root project select its older 363-logic fallback; use the files in this folder
for the 302 result.

`evidence/` contains the fresh Linux Gowin build's resource/timing reports,
synthesis hierarchy, build log and parsed summary. The clock-route warning
PR1014 is present in both the original and reproduced builds; the reported
setup/hold endpoint violation counts are zero. The SDC constrains the core clock.

Fresh regeneration matched the delivered RTL byte-for-byte. The selected engine
configuration passed both Cyclesim and Icarus: **4,978 packets / 104,927 edges**,
checking exact window sums, actions, poisoned/stale RAM, reset at every engine
stage, command lifetime and stalled results against the independent oracle.
The engine log and coverage are included under `evidence/selected-engine*`.
The full regression run and selected production-divisor serial regression also
passed: **1,394 serial oracle packets**, startup, complete stop bits, framing/
busy-input fault lockout, RX/engine/TX reset recovery and heartbeat. See
`evidence/full-regressions.log`. This run identifies the original 302-logic RTL
hash above; the LED-free 270-logic candidate has its own separate verification.

Hardware qualification remains pending for this image. After building and
programming, run the normal robust and full-range tests consecutively without
reset, plus the existing startup/reset checks. Simulation and P&R establish
readiness for that board test, not its result.
