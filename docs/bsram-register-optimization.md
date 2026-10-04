# BSRAM and register optimization

This continues the H2–H5 search with the exact manually measured H2/H4 parent.
The preserved Gowin V1.9.11.03 Education project reports **363 Logic, 235 Registers,
289 synthesis LUT, 74 P&R ALU and one BSRAM**, with no setup/hold violations.
Its RTL SHA-256 is `cbd88a4e72e8476fa7e22acd464c6e3e596d8c81a89ca3a5d5c4192a10ebe818`.
The project, reports, settings and matching vendor bitstream are under
`results/phase-i-20261004/baseline/gowin-observed`.
The portable selected project, summary reports and reproduction instructions are
checked in under [gowin/bsram_candidate](../gowin/bsram_candidate/README.md), with
the matching vendor bitstream under [bitstream](../bitstream/gqh_competition_bsram.fs).
Paths under `results/` identify retained local working evidence; the handoff
project and published evidence do not require those ignored directories.

## Implemented experiments

- **Packet RAM:** an unreset 8×8 synchronous RAM retains all request bytes through
  final response drain. The controller reads IDs and prices in stages and reuses
  the same bytes for response echoes. Only the high price byte requires a fabric
  latch; the low byte remains in the RAM output. Reset requires eight new bytes
  before dispatch; busy/framing faults preserve an accepted transaction.
- **Scalar record RAM:** each item's exact 20-bit sum, two previous-comparison
  flags and two held-action bits occupy one 24-bit record. Two resettable valid
  bits mask stale memory. Record/history reads and commits happen in parallel,
  preserving the engine's E0 acceptance, E1 read, E2 commit and E3 result transfer.
- **Command borrowing:** competition controllers retain the 22-bit engine command
  through E2, eliminating its optional capture bank. Standalone capture remains
  the default. The pending action is independently held through backpressure.
- **Arithmetic:** a signed 17-bit price-minus-oldest difference feeds the exact
  20-bit sum. A separate 17-bit price-minus-truncated-average subtraction supplies
  both comparison flags. Full-range combinational proofs and transaction tests
  cover the transformations.
- **UART control:** RX/TX reload/decrement factoring is independently selectable.
  RX factoring improves the current combined screen; TX factoring was rejected.
  RX already exposes its data shift register directly, so there is no redundant
  eight-bit RX output bank to remove.

History, diagnostics, precision, clock, divisor, stop bits and heartbeat are
preserved. BSRAM is not reset or initialized in generated hardware.

## Measurements and selection

The selected **Gowin** candidate is packet RAM, scalar record RAM, borrowed
commands and both arithmetic changes, using the original RX/TX timers:
**302 Logic, 109 Registers, 242 LUT, 60 ALU and three BSRAMs**. Setup and hold
violated endpoints are both zero; worst setup slack is 24.321 ns. It uses exactly
the baseline process settings. Its RTL SHA-256 is
`ce77edb9c8221e34c78818d572178617844e7087f8388f92d5e216b967a3ca87`.
The measured vendor bitstream SHA-256 is
`2bc4ab11ad486deac4180d1843429ccf85507aebfd8749d58cd5c9d4b4022e7a`.
The two-BSRAM alternative measures 302 Logic / 155 Registers and also passes
vendor timing. The three-BSRAM candidate therefore wins the register tie-break.

`results/phase-i-20261004/candidate-ledger.json` and `CANDIDATES.md` identify every
parent, measurement manifest and failure. Native open-source results are a
separate comparison scale: the parent is 585 LUT4+ALU / 247 DFF, whereas the
Gowin parent is 363 Logic / 235 Registers. Never compare these totals directly.

The current timing-passing open-source combination is packet RAM, borrowed
commands, both arithmetic changes and RX timer factoring: **420 LUT4+ALU,
168 DFF, two BSRAMs**. Its manual project is
`results/gowin-manual-I-packet-arithmetic-rx`.

The three-BSRAM combination's nextpnr route has hold violations and is **not a
qualifying open-source result**. Its successful vendor route above establishes
the Gowin ranking; the failed nextpnr report is retained without being promoted.
Its separate manual project is
`results/gowin-manual-I-packet-records-arithmetic`.

Final qualification and source packaging remain in the phase-I evidence record.
No new candidate is board-accepted. The 363/235 fallback remains exact; historical
H1 acceptance remains history-only. This is a measured search, not a global
minimum claim.

## Reproduction

Use the existing `5.2.0+ox` switch. Generate the selected design with
`opam exec --switch=5.2.0+ox -- dune exec bin/generate.exe -- competition-bsram`.
The generated deliverable is `rtl/gqh_competition_bsram_top.v`; its Verilog top
is still `gqh_competition_top`. The ordinary `competition` target deliberately
retains the measured 363/235 fallback pending board promotion.

The generator's explicit opt-in experiment flags on `competition` are
`-packet-ram`, `-borrow-command`, `-delta-arithmetic`, `-difference-relation`,
`-records-in-bram`, `-rx-factored-timer` and `-tx-factored-timer`.
Focused tests use the corresponding `HOPT_*` settings recorded with each candidate.
The selected serial regression is reproducible with
`opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest-bsram`.
Do not compare latency columns with different endpoints: the packet controller
records final request-byte acceptance to first TX-byte acceptance; the legacy
controller records request acceptance to response offer. Five-run board medians
remain the tie-break only after vendor logic and registers.

Open-source mapping uses the pinned 2026-10-03 suite, not Yosys 0.33's incorrect
18-bit physical RAM address mapping. `tools/verify_gowin_memory_mapping.py`
simulates mapped logic with installed Gowin SP/SPX9/DPX9B functional RAM models
and poisoned physical storage. This checks physical addresses and RAM behavior;
it is not vendor synthesis, post-route timing simulation or board acceptance.
The proprietary model is read locally and is not included in the evidence bundle.

## Board acceptance

After the exact candidate passes local verification and vendor timing, identify
its RTL/bitstream hash before programming. Run quick PASS, then normal robust
immediately followed by full-range without reset, custom packet checks, and
startup/button-reset tests. Record five latency runs if resource counts tie.
Keep the accepted fallback available. Board programming and acceptance remain
user-operated.

## Research

The [Gowin BSRAM guide](https://cdn.gowinsemi.com.cn/UG285E.pdf) documents the
32/36-bit single-port configurations used for the 24-bit records and physical
address rules. [GowinSynthesis](https://cdn.gowinsemi.com.cn/SUG550E.pdf) documents
RAM inference controls. The [Yosys memory guide](https://yosyshq.readthedocs.io/projects/yosys/en/0.43/using_yosys/synthesis/memory.html)
explains synchronous-memory inference and the fabric cost of unsupported reset
or collision behavior. Actual primitive/report inspection accompanies each
memory experiment; source arrays alone do not establish BSRAM use.
