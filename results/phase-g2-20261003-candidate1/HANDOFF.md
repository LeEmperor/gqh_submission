# Phase G2 competition candidate — October 3, 2026

Status: **Locally verified — awaiting manual checks** (see verification logs).
F and G1 retain that status. G2, overall G and the measured baseline remain open.
No Gowin IDE, programmer or serial device was operated. No Git mutations or
package changes were performed. No board/timing/resource/PLL result is claimed.

## Candidate identity and architecture

Repository: `/home/wayne/devel/jane/gqh_submission`.
Base HEAD: `a192ce4b36a5dfd86461115f20059b87805c7271`.
Initial Git status: only `?? test_proj1/`; that existing user work was preserved.
The source remains dirty/uncommitted; use `source-sha256.txt`, `source-state.txt`,
`tracked.diff` and the saved source snapshot to identify this candidate, rather
than treating HEAD alone as its identity. `results/` is ignored by Git; retain
this directory separately. Historical F/G1 handoff directories were absent;
existing source/interfaces/tests and plan records were used as evidence.

Production RTL SHA-256:
`6c7f220cf209f87d796ec11836d0299913f37faa322f44ccc6b70c5792c32164`.
The copy here and `rtl/gqh_competition_top.v` must match before the manual build.

Changed/new implementation files:

- `src/board/competition_top.ml` / `.mli`: six-port production composition.
- `bin/generate.ml`: competition target; default bringup and existing target/output behavior retained.
- `gqh_competition.gprj`: separate whole-design Gowin project.
- `rtl/gqh_competition_top.v`: deterministic self-contained production hierarchy.
- `test/integration/dune`, `serial_verify.ml`, `run_checks.py`, `competition_tb.v`, `README.md`: full serial verification.
- `README.md`, `gowin/README.md`, `PLAN.md`, `REQUEST_RESPONSE_PLAN.md`, `test/engine/README.md`: current status/handoff and directly stale summaries reconciled.

No defect in F/G1/UART/decoder/sequencer required a component change. The official
scripts, constraints, bringup, history probe, diagnostic transport and PLL project
are unchanged.

UART RX → decoder → G1 controller ↔ F engine → sequencer → UART TX. Board reset
release is shared by every component. RX uses two idle-high synchronizer flops.
Controller request_ready/receive_enable feed the decoder. Controller update,
update_valid, result_ready and session_clear feed the exclusively owned engine;
engine update_ready/result_valid/action feed the controller. Controller response
and response_valid feed the sequencer; sequencer response_ready/response_done
feed the controller. Sequencer tx_data/tx_valid and UART ready/busy complete the
TX handshake. No composition scheduling, pointer, fixed engine latency or session
state duplicates controller responsibilities. LED0 is heartbeat; LED1 active-low
sticky decoder fault. Index zero clears scalar session state, not RAM; complete
warm-up overwrites both items' history before scoring.

Clock: direct 27,000,000 Hz `sys_clk` (no PLL).
UART: 8N1, requested 115200; 234 clocks/bit; actual 115384.6153846 baud
(+0.1602564%); mandatory full stop bit; **zero** extra idle clocks.
Heartbeat: 13,500,000-clock half-period, 0.5 seconds.

## Local verification and latency

Exact commands and outcomes are in `COMMANDS.md` and saved logs. The focused
suite uses both Cyclesim actual production composition (divisor 16 supplement)
and the emitted production RTL (divisor 234) with independent nominal 115200-baud
serial stimulus/decoding at 27 MHz. Both check all 1,394 oracle packets: 800 saved,
336 directed and 258 seeded full-range random; 13 sessions, 208 warm-up packets,
1,186 scored packets, 82 wraps, 92 warm-up swaps and 536 scored swaps.
Equality/truncation, full unsigned 16-bit prices, distinct item histories,
BUY/SELL and held actions are counted in `coverage.json`. Expected actions use
the existing pinned direct-window oracle, never the DUT's rolling-sum algorithm.

Icarus additionally checks true startup without a button reset, the full stop
bit, decoder acceptance before TX, receive rearming only after final TX drain,
legal byte pauses, sticky framing/busy-input lockout, reset during all eight RX
byte data fields, all three engine phases on both slots, and all eight TX frame
data fields. Each reset is followed by 17 fresh oracle packets on the same DUT
(index zero through the first scored update), with physical RAM retained.
The real default heartbeat is checked after reset. All nine modules, exact six
scalar port widths/directions, generation determinism, Yosys hierarchy/process/
check and Icarus elaboration are checked. These are generic elaboration/functional
checks, not Gowin mapping or timing evidence.

`latency.csv` records controller complete-request handshake at rising edge E0
(`request_valid && request_ready`, pre-edge values), to the first rising edge
observing computed `response_valid` offered and accepted by the ready sequencer.
This includes both item updates, controller dispatch/result capture, and index-zero
idle observation/session clear. These are pre-edge observations, so registered
publication follows the preceding edge. See the measured summary in `COMMANDS.md`.
This excludes UART RX sync/capture before E0, sequencer/TX launch, wire frames,
intentional host pauses, USB and host overhead. It is not official round-trip
latency; no physical latency baseline has been measured here.

## Exact manual Gowin input

Open root **`gqh_competition.gprj`**.
Top **`gqh_competition_top`**, device **`GW2AR-LV18QN88C8/I7`**
(family `GW2AR-18C`, identifier `gw2ar18c-000`). Only inputs:

- `rtl/gqh_competition_top.v` (all nine modules; no sibling/source RTL dependencies)
- `constraints/19_tang_nano_20k.cst` (pristine official pins)
- `constraints/tang_nano_20k.sdc` (27 MHz, 37.037 ns primary clock)

Confirm selected top/part manually. Do not add transport, standalone-engine,
bringup or PLL RTL. Record Gowin version/options and hashes before synthesis.
Regenerate only if intentionally building a new source state; compare the hash
with this candidate before using its local evidence.

## Required manual acceptance (all remain pending)

1. Synthesize/P&R the matching competition candidate.
2. Inspect/preserve **whole-design** LUTs, registers, actual memory primitive/
   count/read behavior, clock routing, applied constraints, unconstrained paths,
   initialization/CDC warnings and setup/hold/recovery/removal timing. A generic
   Yosys memory cell is not proof of Gowin BSRAM mapping. Do not hide paths with
   blanket exceptions or infer timing closure from simulation.
3. Generate/identify the matching `.fs`, save SHA-256 and build identity, program
   it manually, and record precisely which file was programmed.
4. Check fresh power-up/configuration, active-high button reset, heartbeat,
   idle-high TX and sticky fault indication/reset. Reset during active traffic,
   then start a fresh index-zero session/full warm-up.
5. Official quick test must print **PASS**.
6. Official robust test must show **84/84 scored packets, 168/168 actions,
   zero timeouts**. Script exit zero alone does not prove either official PASS.
7. Custom checks must match every byte including warm-up/reserved fields,
   full-range/boundary cases, warm-up/steady slot swaps, and repeated index-zero
   sessions **without closing the connection or board reset**.
8. Preserve reports, complete console output, CSV/summary files, official latency
   measurements and build identity. Supply results before closing F/G1/G2/G/H.

## Concrete board-test commands (user performs)

Run from the repository root in Bash. Set the actual host port and use a fresh
directory for each attempt; do not overwrite previous results. Commands below
are prepared, **not run against hardware** here.

```sh
G2_ROOT="$PWD"
G2_PORT=/dev/ttyUSB0   # replace with the verified UART port, e.g. COM6
G2_RUN="$G2_ROOT/results/phase-g2-board-$(date +%Y%m%d-%H%M%S)-$$"
mkdir "$G2_RUN"
sha256sum rtl/gqh_competition_top.v gqh_competition.gprj \
  constraints/19_tang_nano_20k.cst constraints/tang_nano_20k.sdc > "$G2_RUN/inputs.sha256"
# After manually building and programming, archive the exact .fs and reports here.
# Record SHA-256 of the actual .fs and the programmer/build identity.
```

Reset the board before each official run. The scripts have a hard-coded PORT;
keep repository copies pristine and change **only PORT** in archived run copies:

```sh
mkdir "$G2_RUN/quick" "$G2_RUN/robust"
python3 - "$G2_PORT" "$G2_RUN" <<'PY'
from pathlib import Path
import re, sys
port, destination = sys.argv[1], Path(sys.argv[2])
for folder, name in [('quick','21_quick_uart_test.py'),('robust','22_robust_uart_test.py')]:
    source = (Path('tools/official') / name).read_text()
    edited, count = re.subn(r'^PORT\s*=.*$', 'PORT = ' + repr(port), source, flags=re.M)
    assert count == 1
    (destination / folder / name).write_text(edited)
PY
# After button reset:
(cd "$G2_RUN/quick" && python3 21_quick_uart_test.py 2>&1 | tee console.log)
# Inspect actual PASS/mismatches. Button reset before robust:
(cd "$G2_RUN/robust" && python3 22_robust_uart_test.py 2>&1 | tee console.log)
# Inspect trade_summary_100.txt, trade_results_100.csv and console counts/timeouts.
```

For the explicit sticky-fault/status check, reset first, then send a ninth byte
while the first response is transmitting. Observe LED1 lit and retained, record
the output, then button-reset and confirm LED1 clears before official testing:

```sh
python3 - "$G2_PORT" <<'PYFAULT' | tee "$G2_RUN/busy-fault-check.log"
import serial, sys, time
with serial.Serial(sys.argv[1], 115200, timeout=1) as port:
    time.sleep(0.2)
    port.reset_input_buffer()
    port.write(bytes.fromhex('00001100642200c8') + b'\x99')
    response = port.read(8)
    print('accepted response:', response.hex())
    assert response == bytes.fromhex('0000110022000000')
    port.write(bytes.fromhex('00001100642200c8'))
    blocked = port.read(8)
    print('after sticky fault:', blocked.hex())
    assert blocked == b''
print('Observe LED1 latched; button reset is required before further replay.')
PYFAULT
```

The PORT-only copies and outputs remain with each run. On hosts where `sha256sum`
is unavailable use an equivalent SHA-256 tool and preserve its output. Preserve
command exit status as supplementary information; a successful pipeline does
not establish algorithm PASS.

After reset, run the combined G2 fixture, which includes all 13 sessions, on one
connection. It includes warm-up/full-range/equality/crossing and slot-swap cases:

```sh
python3 test/runner/replay.py \
  results/phase-g2-20261003-candidate1/board-fixture.jsonl \
  --port "$G2_PORT" --baud 115200 --timeout 1 --stop-on-timeout \
  --label "G2-6c7f220cf209-direct27MHz-div234-gap0" --out-dir "$G2_RUN/custom"
# After reset, a shorter explicit two-session check (one process/one connection):
python3 test/runner/replay.py \
  tools/test_data_factory/fixtures/repeated_sessions/fixture.jsonl \
  --port "$G2_PORT" --baud 115200 --timeout 1 --stop-on-timeout \
  --label "G2-6c7f220cf209-repeated-one-connection" --out-dir "$G2_RUN/repeated"
```

Runner review: `open_transport` is called once per fixture; `run` iterates every
row and only `replay_protected` closes it at the end. Thus the two-session fixture
retains one real connection. Its default continues after SHORT/TIMEOUT; use
`--stop-on-timeout` for acceptance. It drains/records/discards unsolicited bytes
before sends, drains after the final 50 ms wait, and returns failure for any such
bytes or incomplete/mismatching rows. Require all planned rows OK, no abortion,
no SHORT/TIMEOUT/MISMATCH, zero unsolicited events and empty trailing bytes.
It does not stop on mismatch or unsolicited bytes, provide automatic FPGA reset,
prove packet realignment, or offer controlled inter-byte pauses; after any fault,
reset and run a fresh fixture. Opening also settles 0.2 s and clears the host RX
buffer, so this runner alone cannot prove absence of unsolicited startup traffic.
Its custom timings/outputs and checks are distinct from pristine official tests;
retain the official results for acceptance/measurement. Do not run the diagnostic
NONE checker as a substitute for competition oracle acceptance.
