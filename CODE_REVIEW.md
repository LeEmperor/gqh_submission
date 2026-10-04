# Code review: `main` @ `7469d98`, re-checked at `9330a63`

Reviewer: Vishal · October 3, 2026 · checked against the Hardware Track guide
(`gqh_hw_guide.pdf`) and the October 3 placement supplement
(`docs/placement-supplement-20261003.md`).

`9330a63` ("H1 has reduced the LC down by 62") landed on `main` during this
review. Everything below has been re-checked against it. C5, H4 and M6 are new
in that commit, and every other finding still applies.

## Summary

**The algorithm is right. The submission isn't safe yet.** Every practice run
is 100%. The risks are (1) a robustness hole that can turn the official run
into a zero, (2) packaging that can get us rejected or rebuilt from the wrong
project, (3) source, RTL and tested hardware that no longer match as of
`9330a63`, and (4) logic we're paying for that scores nothing.

| # | Severity | Finding | Fix |
| --- | --- | --- | --- |
| C1 | **CRITICAL** | One stray byte or RX glitch latches a permanent fault. The board answers nothing until S2 is pressed. Reproduced in simulation on both `7469d98` and `9330a63`. | Make errors non-sticky and add an RX idle timeout that resyncs framing. |
| C5 | **CRITICAL** (new) | Source, committed RTL and board-tested RTL are three different designs. `update.ml` has H1 + H2. `rtl/` (used by the root project) is the old G2. `test_proj2` is H1 only. H2 has no RTL and no board run. | Regenerate `rtl/` from the source we freeze. Board-test that exact RTL. One copy only. |
| C2 | **CRITICAL** | No tested competition `.fs` where a judge would look. `impl/` and `results/` are gitignored. The most visible `.fs` is the PLL toggle test. The passing image was never committed. Phase H evidence folders aren't pushed. | Commit the final image in `bitstream/`, built from the one submitted project, and push all work. |
| C3 | **CRITICAL** | Seven Gowin projects. The top-module setting isn't committed. The root competition project was never built. The README tells judges to select `gqh_top` (the blinky). | Keep one competition project and commit its process config with the top module set. Archive the rest. |
| C4 | **CRITICAL** | The repo is private. Private repos are rejected (guide Part 3 §6). | Owner flips it public at submission and checks it while logged out. |
| H1 | HIGH | README misses most of the guide's required items and reads like an agent log. Its links point to paths that don't exist. | Rewrite the README as the submission README. |
| H2 | HIGH | Pre-event material is in the tree: commit `7d89ef9` (Fri 02:56 EDT) and a tickweave proposal PDF created Fri 02:42 EDT. | Remove `archive/` and the tickweave material from the submission. |
| H3 | HIGH | The heartbeat costs 45 LUTs and 25 registers for an LED that scores nothing. | Delete it and drive `led0_n` high. |
| H4 | HIGH (new) | The stale-RTL test was disarmed. The integration check now compares the generator's output with a copy the same generator just produced. `dune runtest` can no longer see that `rtl/` is stale, and it is. | Restore the comparison against the delivered `rtl/gqh_competition_top.v`. |
| M1 | MEDIUM | The request is stored three times (decoder 64 + controller 64 + sequencer 36 bits), plus a 22-bit engine copy. | Phase H4: one retained copy. |
| M2 | MEDIUM | Per-item state sits in muxed registers. The H2 comparison-flag proposal is mathematically correct. | Do H2, then consider moving item state into the history BSRAM. |
| M3 | MEDIUM | Unrelated code and dependencies ship in the submission (tickweave lib, Databento, agent task doc). | Remove from the submission tree. |
| M4 | MEDIUM | TX gap is 0 despite the guide's BL616 warning. All board tests ran on one Linux host; none on Windows with Gowin Programmer. | Run the judge's flow once on Windows before freeze. |
| M5 | MEDIUM | Phase P (PLL) and the H5 timer-sharing constraint spend effort with no ranking value. | Drop P. Revisit timer sharing after C1. |
| M6 | MEDIUM (new) | `test_proj1.gprj` now also builds `gowin_rpll.v`. Nothing instantiates `Gowin_rPLL`, and the top module isn't pinned, so the project has two candidate tops. | Remove the PLL from competition projects, or pin the top module. |
| L1 | LOW | Phase H bookkeeping is consuming the hours before the 9 AM freeze. The waived build-identity check is what judges now verify. | Freeze on one image and tie the source, reports and `.fs` together. |
| L2 | LOW | The qualification LUT line is cited inconsistently (351 vs 347). | Cite the guide's line. |

### Verified solid

- **Engine matches guide §10.3.** It uses 20-bit sums and floor averages (`sum[19:4]`) with unsigned compares. Previous price updates during warm-up, and index 0 clears both items. Routing is by item ID only. Full range can't underflow, since the old sum always contains the oldest price. See `src/engine/update.ml`.
- **Board practice results** in `results/phase-g2-board-20261003-142516-thv362qq/`:
  - quick test: PASS
  - normal robust: 84/84 packets, 168/168 actions, 0 timeouts, 16.81 ms
  - full-range, run straight after normal robust: 84/84, 168/168, 0 timeouts, 16.91 ms
  - custom replay: 1,394/1,394 rows across 13 sessions
- **`dune runtest` passes at `7469d98`**. Environment: OCaml 5.2.0+ox, Icarus 12, Yosys on PATH. The serial integration test takes over 10 minutes.
- **At `7469d98` only, the RTL matches its source.** `generate.exe competition` reproduces `rtl/gqh_competition_top.v` byte-for-byte (sha256 `6c7f220c…`). At `9330a63` this no longer holds (see C5).
- **H2 math is correct, and the `9330a63` code matches it** (see M2).
- **The practice script copies are clean.** The copies used for the practice runs differ from the organizer originals only in `PORT`.
- **No secrets.** A scan of all branches' history found no API keys, tokens or private keys.

### Recommended order before the 9 AM freeze

1. **One candidate:** current source (H1 + H2) + delete the heartbeat + the C1 decoder fix. Regenerate `rtl/gqh_competition_top.v` from it. Then:
   - the glitch testbench (appendix) must answer indices 0, 1 and 2 in all three runs;
   - `dune runtest` must pass, with the H4 guard restored;
   - board: quick, then normal robust → full-range back-to-back, then the custom replay;
   - one run from a Windows PC with Gowin Programmer.
2. **Packaging (C2, C3, C5, H1, H2, M3, M6).** Build from exactly one project, commit that `.fs` and its reports, rewrite the README and push.
3. **Phase H4 (packet storage)** only if there's time before the freeze.
4. **Owner flips the repo public.** Check it while logged out, and put the full SHA in Devpost.

---

## Details

### C1 — A sticky protocol fault turns any line glitch into a zero

**What.** In `src/protocol/request_decoder.ml`, two events set `fault`:

- a framing error (line 33–34);
- any byte that arrives while the controller isn't receiving (line 49).

`fault` clears only on reset. While it is set, `receiving` is false (line 28) and `request_valid` is gated off (line 53). The board stays silent until someone presses S2.

**Reproduction.** The testbench in the appendix (save it as `glitch_tb.v` in a `main` checkout) drives the committed `rtl/gqh_competition_top.v`. It injects one low pulse on `uart_rx_i` while idle, waits 2 ms, then sends indices 0, 1 and 2 stop-and-wait:

```sh
iverilog -g2012 -o /tmp/glitch glitch_tb.v rtl/gqh_competition_top.v
vvp -n /tmp/glitch +GLITCH=0      # control
vvp -n /tmp/glitch +GLITCH=540    # ~19 us glitch
vvp -n /tmp/glitch +GLITCH=3000   # ~111 us low
```

| Injected before idx 0 | Result on `7469d98` |
| --- | --- |
| nothing | idx 0, 1, 2 all answered correctly |
| 19 µs low pulse | Decoded as a valid stray byte. The board answers early with a misframed response to idx 0, a timeout follows, and it never recovers. |
| 111 µs low pulse | Framing error. Every packet times out from idx 0. |

The RTL generated from `9330a63` gives identical results. The request decoder didn't change in that commit.

**Why it matters.**

- Guide §10.2.2: the board is not reset between runs.
- The supplement runs the hidden full-range test right after the official run, without reprogramming.
- Nobody will press S2. One glitch scores 0, and a rerun (§10.2.8) is only for failures "outside the design", which this isn't.

**Related evidence.**

- Our first quick test timed out at index 0 with 0 of 8 bytes, and the cause was never established (`results/phase-g2-board-20261003-142012-4fbtzcph/initial-timeout-diagnosis.json`, `manual-progress.md`).
- The busy-fault board check (`status-fz9wj7qq`) confirms the board stops answering after a fault until reset.
- Every board run so far was on Linux (`/dev/ttyUSB1`). The judge flow is Windows plus the Gowin Programmer GUI, then the script opening the COM port. That flow is untested.

**Fix.**

- On a framing error or an unexpected byte, set `position <- 0` and keep receiving. No latch.
- Add an RX idle timeout. If no byte arrives for about 1 ms while `position != 0`, reset `position` to 0. Requests arrive as one 8-byte write, and the next request comes about 16 ms later, so 1 ms separates the two cases cleanly. A ~15-bit cycle counter does it, or a few bits counting RX bit-times if the RX timer exposes a tick.
- Deleting the fault register and the LED1 logic offsets most of the added logic.
- The sticky behavior is asserted on purpose by existing tests, so update them:
  - `test/protocol/transaction_verify.ml`
  - `test/integration/competition_tb.v`
  - the transport/integration READMEs
  - the `.mli` contracts in `src/protocol/transaction_controller.mli` and `src/board/competition_top.mli`
- After the fix, the glitch testbench should answer indices 0, 1 and 2 in all three runs.

### C5 — Source, committed RTL and tested RTL disagree (new in `9330a63`)

I regenerated the RTL from `src/` at `9330a63` and compared it with every committed copy:

| Copy | sha256 | Contents | Board-tested? |
| --- | --- | --- | --- |
| Generated from `src/` at `9330a63` | `efb465ea…` | H1 (`syn_ramstyle="block_ram"`) + H2 (`previous_below`/`previous_above` flags) | **No** |
| `rtl/gqh_competition_top.v`: what `gqh_competition.gprj`, the README and `gowin/README.md` point to | `6c7f220c…` | Original G2, distributed RAM, no H1 or H2 | Yes (G2 runs) |
| `test_proj2/test_proj2/src/gqh_competition_top.v` | `897d6d38…` | H1 only, no H2 flags | Yes (H1 runs) |
| `test_proj1/test_proj1/src/gqh_competition_top.v` | `6c7f220c…` | Original G2 | Yes |

- **H2 is in the source but has nothing behind it.** `resource_optimization.md` says "H2–H5 experiments have not been run", and the commit message mentions only H1, yet `src/engine/update.ml` now contains H2. No committed RTL contains it, and nothing has run on the board. In simulation it does pass: at `9330a63`, the engine and integration suites both pass (independent oracle, 1,394 serial packets, exit 0). So the remaining gap is the hardware: no board run and no RTL in the repo.
- **Every rebuild path gives an untested or old design.** Judges rebuild from committed source. Regenerating from Hardcaml gives an untested design. Opening the root project gives the old G2. Only `test_proj2` matches a board-tested image, and it isn't the source.

**Fix.** Pick the freeze source. Regenerate `rtl/gqh_competition_top.v` from it and delete the other copies. Build the `.fs` from the one project that reads `rtl/`, and run the full board acceptance on that image.

### C2 — No tested competition `.fs` is in a reachable place

- **`.gitignore` ignores `impl/` and `results/`** (lines 32–33). Gowin writes the bitstream to `impl/pnr/<project>.fs`. The guide's freeze commands (`git add .`) will silently skip it.
- **There is no `bitstream/` folder.** The guide's recommended layout has one.
- **Only two `.fs` files are committed, and neither is a good image to submit:**
  - `Hackathon/impl/pnr/Hackathon.fs` is the 270 MHz PLL `toggle_test`, not the competition design, and it's the most visible one.
  - `results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/pnr/test_proj1.fs` (sha256 `eb348fab…`) is the build that timed out at index 0.
- **The image that passed every test (sha256 `fac34993…`) was never committed.** `startup-2ld34y_z/summary.json` records `"matches_archived_bitstream": false`.
- **Phase H evidence isn't on GitHub.** `9330a63` pushed the H1 source and `resource_optimization.md`, but none of the `results/phase-h-*` folders it links to. That's the H1 reports, ledgers and board runs (H1: 412 logic / 363 registers, board-tested). They exist on one laptop only.

**Fix.**

- Build the final image from the single submitted project and commit it as `bitstream/gqh_competition.fs`. Either `git add -f` it or un-ignore that path.
- Commit its synthesis and P&R reports next to it.
- Run the final quick/robust/full-range acceptance on that exact file and record its sha256.
- Push Phase H now, even if it isn't promoted.

### C3 — Ambiguous Gowin project and top module

- **There are seven `.gprj` files:**
  - at the root: `gqh_competition`, `gqh_engine`, `gqh_transport`, `gqh_pll_test`;
  - nested: `Hackathon/`, `test_proj1/test_proj1/`, `viv25_proj/test_proj1/`.
- **The judges' rule is ambiguous here.** They re-synthesize "using the project settings in your commit", and it isn't clear which project those are.
- **The root `gqh_competition.gprj` has never been built.** It was hand-written in `36dd19e`. The passing builds came from `test_proj1` (and H1 from `test_proj2`).
- **The top-module setting isn't committed.** Gowin stores it in `impl/<project>_process_config.json`, which is gitignored. The observed build had `"TopModule": ""`, meaning auto-detect.
- **The README sends judges to the blinky.** The first IDE section it gives (`README.md` line 116–118, "Bring-up behavior and manual IDE inputs") says to select top **`gqh_top`** and add `rtl/gqh_top.v`. That's the heartbeat bring-up design, which never answers a packet.

**Fix.**

- Keep exactly one competition project, either at the root or in `gowin/`.
- Commit its process config with `TopModule = gqh_competition_top`.
- Build the submitted `.fs` from it.
- Move the other projects to an archive, or delete them from the submission.

### C4 — The repository is private

The guide (Part 3 §6) says private repositories are not accepted. The repo must open while logged out and stay public through judging. Only the owner (LeEmperor) can change visibility. Do it at submission time, then put the full final SHA in Devpost, not in the README (Part 3 §7).

### H1 — The README doesn't meet the guide's requirements

**Missing items** from guide Part 3 §3:

- team and project name and members;
- the logic/LUT count for the submitted build;
- the Gowin version used for this build (the README says the old report "is not a new validated build");
- disclosure of external resources: Hardcaml and Jane Street libraries, the organizer `.cst` and scripts, AI tools;
- known limitations (today: a reset-button-only recovery after any RX fault).

**Other problems:**

- Status text reads like an agent log ("The user waives remaining build-identity bookkeeping", "user-authorized closure", lines 40–41 and 229). Judges are told to expect you to explain your design.
- Links point to paths that don't exist in the repo (`../GQH-Hardware-Track-Submission/`, `~/devel/jane/…`, lines 17–19).

### H2 — Pre-event material is in the submission

The rule is "Pre-existing work: not allowed. Everything you submit must be built during the event." Hacking began Friday at 7:15 PM.

- Commit `7d89ef9` "fc" is dated Fri Oct 2 02:56 EDT. It's a one-line README, so it's low risk, but it's visible.
- `archive/tickweave/tickweave_proposal.pdf` has a PDF creation date of Fri Oct 2 02:42 EDT. The `archive/` folder and the tickweave proposal have no role in the hardware submission. Remove them from the tree.

### H3 — The heartbeat costs about 10% of our logic

The synthesis hierarchy (`…/gowin-build-observed/impl/gwsynthesis/test_proj1_syn_rsc.xml`) shows `heartbeat` at **45 LUTs and 25 registers**. The design totals 468 logic and 379 registers on `main`. A blinking LED earns no points, and guide §9 says to drive an unused LED high.

The Phase H plan lists the heartbeat under H5 and preserves its "current cadence". It should go first instead: it's the cheapest and lowest-risk cut available. Do it with H1 so both stack on the 412-logic candidate.

### H4 — The stale-RTL test was disarmed (new in `9330a63`)

**Before.** At `7469d98`, `test/integration/run_checks.py` asserted that fresh generator output equals the committed `rtl/gqh_competition_top.v` (`'stale production RTL'`).

**Now.** `9330a63` changes two things:

- `test/integration/dune` adds a rule that runs `generate.exe competition` to produce `competition_candidate.v`.
- The test then compares the generator's fresh output with that file.

Both sides come from the same generator, so the check can never fail. `rtl/gqh_competition_top.v` is no longer a test dependency at all.

This is exactly how C5 got through: `rtl/` is stale and the suite stays green. Confirmed: `dune build @test/engine/runtest @test/integration/runtest` passes at `9330a63` (exit 0) while `rtl/` is stale.

**Fix.** Compare against the delivered `rtl/gqh_competition_top.v` again, and regenerate `rtl/` as part of any candidate that should be built. If H experiments need a fallback, keep the fallback RTL under `results/` instead of pointing the check away from `rtl/`.

### M1 — Redundant packet storage (Phase H4)

Per-module registers on `main`:

| Block | LUT | ALU | Registers | Notes |
| --- | --- | --- | --- | --- |
| engine | 130 | 69 | 118 | 22-bit command copy, 2×(20+16+2) item state, 16-bit RAM output register |
| controller | 60 | 0 | 76 | Second 64-bit copy of the request |
| request_decoder | 18 | 0 | 69 | First 64-bit copy |
| response_sequencer | 38 | 0 | 42 | 36-bit response copy |
| heartbeat | 45 | 0 | 25 | See H3 |
| uart_rx + uart_tx | 59 | 0 | 45 | |

Stop-and-wait only needs one retained copy. Removing the controller and sequencer copies is roughly 100 registers, which is tiebreak #2. The LUT savings are smaller because Gowin flip-flops have free clock enables.

### M2 — Item state and H2

H2 is now in `src/engine/update.ml` at `9330a63`; see C5 for why it isn't board-tested yet. I checked the flag rewrite against the spec, and the committed code implements it:

- `previous <= old_average` is exactly `not previous_above`, and `previous >= old_average` is exactly `not previous_below`. Both flags come from that item's own previous commit, because an item's sum only changes on its own updates.
- Flags computed at index 15 prepare index 16 correctly.

It removes 32 previous-price registers, a 16-bit 2:1 mux and two 16-bit comparators. After H2, the per-item sum and held action could move into the same BSRAM as the history. That removes the remaining 2:1 muxes, about 38 LUT3s on `main`.

### M3 — Unrelated code and dependencies

The submission tree carries a lot that the hardware doesn't use:

- the `tickweave` OCaml library (`lib/`: Databento client, runner, SHA-256);
- `bin/stream.ml`, `tickweave.opam` and `DATAFACTORY_README.md`;
- `external/databento_audit/`;
- `docs/EXTERNAL_AGENT_TASK.md`, a prompt for an external coding agent;
- `archive/`.

The README's first build command (`dune build`) also builds `tickweave`, which needs `yojson` and `core_unix`. A judge reproducing the Hardcaml build has to install dependencies the design never uses. Keep the submission to the hardware sources, generated RTL, constraints, the one project, tests and results.

### M4 — TX gap 0 and an untested judge environment

The guide warns that the BL616 can drop back-to-back response bytes, and `src/uart/config.ml` sets `extra_idle_cycles = 0`. We have about 1,700 packets with zero drops on this board, so the evidence is decent. But it's all one Linux host with the same programming flow.

Do one full judge-style run before freeze:

- Windows PC;
- Gowin Programmer GUI in SRAM mode, then close it;
- `22_robust_uart_test.py` with only `PORT` changed;
- full-range straight after.

If any byte drops, a one-bit TX gap costs a few LUTs and about 0.1 ms. Latency is the last tiebreak, and runs within 5% count as tied.

### M5 — Work with no ranking value

- **Phase P (PLL).** Latency is the third tiebreak and ties within 5%. FPGA processing is microseconds out of a 16.8 ms round trip, so a faster clock can't change placement but adds risk.
- **H5's timer constraint.** H5 says RX and TX timers can't be shared because RX must watch for unexpected traffic during TX. That exists only to support the sticky fault. After C1, unexpected bytes are simply dropped, and timer sharing is back on the table.

### M6 — A dangling PLL in `test_proj1` (new in `9330a63`)

`9330a63` adds `src/gowin_rpll/gowin_rpll.v` (module `Gowin_rPLL`) to `test_proj1/test_proj1/test_proj1.gprj`. That project's `gqh_competition_top.v` (G2, `6c7f220c…`) never instantiates `Gowin_rPLL`.

- **Two candidate top modules.** Top-module selection is not committed (C3; the observed build used `"TopModule": ""`), so the project now has two uninstantiated modules for auto-detection to choose from.
- **It misleads readers.** It suggests the competition design uses a 270 MHz PLL.

Keep the PLL experiment out of every competition project.

### L1 — Process versus deadline

The Phase H plan wants ledgers, hash bundles and multi-state status for every candidate, but packaging (C2–C4, H1–H2) hasn't started. The build-identity bookkeeping waived at F/G closure is exactly what judges now check: they rebuild from committed source and confirm it behaves like the submitted `.fs`.

Freeze on one image and tie the source, RTL, project settings, reports and `.fs` together for that image only.

### L2 — Which LUT number qualifies

Guide §11 says to take the total LUT line of the synthesis report's Resource Usage Summary. On `main` that's **347** (34 LUT2 + 158 LUT3 + 155 LUT4). The Phase H plan quotes 351, which comes from the Utilization line. Both are far below 542, so it doesn't affect qualification, but the README should cite the guide's line.

For placement, minimize the "Logic" total, which includes ALUs and RAM16 (6 per RAM16): 468 in synthesis on `main`, 475 after P&R.

---

## Appendix — glitch testbench (C1 reproduction)

Save as `glitch_tb.v` at the root of a `main` checkout, then run the commands in C1.
On `7469d98` and `9330a63` the 540- and 3000-cycle runs never recover. A fixed
design should answer indices 0, 1 and 2 correctly in all three runs.

```verilog
// Stray-byte / line-glitch regression for gqh_competition_top (review finding C1).
//
// Injects one low pulse on uart_rx_i while the board is idle, waits 2 ms, then
// runs three stop-and-wait requests (indices 0, 1, 2) like the judge would.
//
//   iverilog -g2012 -o /tmp/glitch glitch_tb.v rtl/gqh_competition_top.v
//   vvp -n /tmp/glitch +GLITCH=0      # control: all three answered
//   vvp -n /tmp/glitch +GLITCH=540    # ~19 us glitch -> decodes as one stray byte
//   vvp -n /tmp/glitch +GLITCH=3000   # ~111 us low  -> framing error
//
// On main @ 7469d98 and 9330a63 the 540 and 3000 runs never recover (sticky protocol fault).
// A fixed design should answer indices 0, 1 and 2 correctly in all three runs.
`timescale 1ns/100ps
module tb;
  reg clk = 0; always #18.5 clk = ~clk;          // ~27 MHz
  reg rx = 1, btn = 0; wire tx, l0, l1;
  gqh_competition_top dut(.sys_clk(clk), .reset_btn(btn), .uart_rx_i(rx),
                          .uart_tx_o(tx), .led0_n(l0), .led1_n(l1));
  localparam BIT = 234;
  integer glitch_cycles; integer got; reg [63:0] resp;
  task send_byte(input [7:0] b); integer k; begin
    rx = 0; repeat (BIT) @(posedge clk);
    for (k = 0; k < 8; k = k + 1) begin rx = b[k]; repeat (BIT) @(posedge clk); end
    rx = 1; repeat (BIT) @(posedge clk); end endtask
  // Host-side UART receiver on tx.
  reg [7:0] rb; integer j;
  initial begin got = 0; resp = 0;
    forever begin @(negedge tx); repeat (BIT/2) @(posedge clk);
      for (j = 0; j < 8; j = j + 1) begin repeat (BIT) @(posedge clk); rb[j] = tx; end
      repeat (BIT) @(posedge clk); resp = {resp[55:0], rb}; got = got + 1; end end
  task request(input [15:0] idx, input [15:0] pa, input [15:0] pb); integer t; begin
    got = 0; resp = 0;
    send_byte(idx[15:8]); send_byte(idx[7:0]); send_byte(8'h11);
    send_byte(pa[15:8]); send_byte(pa[7:0]); send_byte(8'h22);
    send_byte(pb[15:8]); send_byte(pb[7:0]);
    t = 0; while (got < 8 && t < 40000) begin @(posedge clk); t = t + 1; end
    if (got < 8) $display("idx %0d: TIMEOUT (%0d/8 bytes)  led1_n(fault)=%b", idx, got, l1);
    else $display("idx %0d: response %016h  led1_n(fault)=%b", idx, resp, l1);
  end endtask
  initial begin
    if (!$value$plusargs("GLITCH=%d", glitch_cycles)) glitch_cycles = 0;
    repeat (2000) @(posedge clk);
    if (glitch_cycles > 0) begin
      $display("-- injecting a %0d-cycle (%0d us) low pulse on uart_rx_i, then 2 ms idle",
               glitch_cycles, glitch_cycles * 37 / 1000);
      rx = 0; repeat (glitch_cycles) @(posedge clk); rx = 1;
    end else $display("-- control run: no glitch");
    repeat (54000) @(posedge clk);
    request(0, 16'd100, 16'd200);
    request(1, 16'd101, 16'd201);
    request(2, 16'd102, 16'd202);
    $finish;
  end
endmodule
```
