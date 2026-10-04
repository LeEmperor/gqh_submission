# H2–H5 optimization run, October 4, 2026 UTC

This records the preceding H2–H5 search. The subsequent
[BSRAM/register search](bsram-register-optimization.md) selects the measured
302-logic / 109-register candidate and preserves these earlier identities.
The no-Git-mutation statement below describes this historical search; the user
later authorized committing and publishing the completed handoff on `newop`.

The local search preserves direct 27 MHz, divisor 234, complete UART stop bits,
independent RX/TX timers, full unsigned 16-bit prices, exact 20-bit committed
sums, heartbeat, and diagnostic defaults. No Git index, refs, or history were
changed. The original untracked planning documents were preserved.

## Design identities and promotion

- Working branch starts at `7469d98`. Its working tree now contains the selected
  H2/H4 implementation, generated RTL, selectable H5 experiments, and tests.
- `9330a63` contains the H1 RAM attribute and an unaccepted H2 source change.
- Historical, accepted H1 RTL is specifically
  `9330a63:test_proj2/test_proj2/src/gqh_competition_top.v`. Its documented
  result is 412 logic, 363 registers, 337 synthesis LUTs, and one BSRAM. That
  acceptance remains historical and is not reopened by this run.

The evidence directory is
[`results/phase-h-search-20261004`](../results/phase-h-search-20261004).
Its `fallback/` contains both original and history-only H1 RTL with hashes.
The first H1 rebuild reached routing but yielded no complete P&R report or
bitstream, so `H1-first-attempt/manifest.json` marks it invalid and contains no
resource measurement. Windows tool restoration is pending. Following the user's
authorization to continue without Gowin, selection uses a separately labelled
open-source screen. This is a local implementation selection, not vendor or
board promotion. H0/H1 historical acceptance remains unchanged.

## Selected implementation and measured search

**Selected: H2 comparison flags plus both H4 packet-copy removals.** The H2 source
matches `9330a63:src/engine/update.ml` byte for byte. All six H3 arithmetic
variants and all nine H5 control variants were implemented, tested and measured;
none improved the selected open-source ranking. Retaining the smaller design
does not discard those implementations: their source patches and results remain
in the evidence bundles.

Selected RTL SHA-256:
`cbd88a4e72e8476fa7e22acd464c6e3e596d8c81a89ca3a5d5c4192a10ebe818`.
Selected open-source bitstream SHA-256:
`8a4f55cd05ee81627b1d92c06531efc7919dde9642292b33b8e24f876bc35ce3`.
The [final handoff](../results/phase-h-final-20261004/README.md) identifies the
review patch, matching image/reports, verification commands and full evidence
archive. Nothing has been programmed or pushed by this run.

The [open-source ledger](../results/phase-h-open-20261004/candidate-ledger.csv)
contains twenty whole-design screens with explicit parents. Each retains input
hashes, commands, tool identities, complete logs/netlists, timing, resource
reports and a matching bitstream. The ranking proxy is **final routed LUT4 +
ALU cells**, then DFFs. It includes tool-inserted helper cells, is not Gowin
Logic or a proven occupied-site count, and excludes separately reported wide
mux resources. Full native resource vectors remain in the JSON ledger.

| Candidate | Final LUT4 | Final ALU | Open-source proxy | DFF |
| --- | ---: | ---: | ---: | ---: |
| Historical H1, newly built open source | 599 | 162 | 761 | 375 |
| H2 | 572 | 144 | 716 | 347 |
| H3 shared 20-bit arithmetic | 611 | 122 | 733 | 367 |
| H3 comparator reuse | 717 | 110 | 827 | 368 |
| H3 serial 8-bit | 662 | 116 | 778 | 389 |
| H3 serial 4-bit | 620 | 116 | 736 | 386 |
| H3 serial 2-bit | 640 | 116 | 756 | 387 |
| H3 serial 1-bit | 643 | 114 | 757 | 388 |
| H4 response borrowing on H2 | 540 | 144 | 684 | 311 |
| H4 request borrowing on H2 | 483 | 144 | 627 | 283 |
| **H4 both on H2, selected** | **441** | **144** | **585** | **247** |

Every build uses one BSRAM and passes the reported 27 MHz clock constraint.
The selected report gives 150.85 MHz Fmax; this is a nextpnr estimate, not a
clock change or board latency result. Relative to the same-flow H1 baseline,
the selected proxy falls 23.1% and DFFs fall 34.1%. These percentages must not
be applied to the historical Gowin 412-logic result.

H5 was profiled and evaluated in controller, sequencer, RX, TX, then TX-shift
order. Each binary encoding produced the **identical bitstream** as its parent.
One-hot variants respectively used proxy/DFF counts 620/247, 613/247, 607/247
and 607/248; the TX shifter used 594/247. All were measured on the retained best
parent. No estimated savings were added. Identical-image ties need no distinct
latency selection; five board latency runs remain required if a future vendor
resource tie involves different images. No global-minimum claim is made.

## Implemented search space

Every engine candidate has a separate source patch, ML/MLI, full competition
RTL, hash, verification log, and measured simulation cycle counts under
`candidates/`. H2 was recovered from the existing implementation in `9330a63`.

| Engine | Engine publication clocks after acceptance | Controller response transfer, session / warm-up / steady |
| --- | ---: | --- |
| H2 comparison flags | 2 | 11 / 9 / 9 |
| Shared 20-bit add/subtract | 2 | 11 / 9 / 9 |
| Shared arithmetic and comparator | 4 | 15 / 13 / 13 |
| Serial 8-bit | 9 | 25 / 23 / 23 |
| Serial 4-bit | 13 | 33 / 31 / 31 |
| Serial 2-bit | 23 | 53 / 51 / 51 |
| Serial 1-bit | 43 | 93 / 91 / 91 |

These are simulation cycle counts, not board round-trip measurements. Serial
8 uses a 24-bit padded rotating accumulator; the committed sum remains exactly
20 bits. The shared datapath uses one addition operator with explicit carry-in.

H4 provides independent opt-in request borrowing and response borrowing, with
capture behavior retained by default for standalone/diagnostic modules.
Competition composition enables borrowing. The producer field-lifetime table
is in `protocol-experiments/h4/field-lifetimes.md`. Separate H2-based request,
response and combined RTL variants are preserved. H2 is the selected engine
under the open-source metric; official Gowin ranking remains pending.

H5 provides separate binary/onehot controller, sequencer, RX and TX experiments,
then indexed versus shifting TX serialization. The frozen H5 patch layers on
H4. Initial focused evidence uses the explicitly identified original engine;
the completed ordered screens use the selected H2/H4 combined parent.
Gowin may recode a structurally specified FSM, so source state-bit counts do
not establish resource savings.

## Verification evidence

- The final working tree passes `opam exec --switch=5.2.0+ox -- dune runtest`.
  [Full changed-hardware output](../results/phase-h-open-20261004/final-runtest-first.log)
  includes all 1,394 production-divisor serial packets, RX/engine/TX reset and
  fault recovery, complete stop bits and the unchanged real heartbeat.
  [The final dependency check](../results/phase-h-open-20261004/final-runtest.log)
  also passes after the last runner-test hardening. Raw simulation cycle samples
  are retained separately from unperformed physical latency measurements.
- All seven engines pass independent direct-window oracle checks in Cyclesim
  and Icarus, deterministic emission and Yosys checks, 1,394-packet serial
  Cyclesim replay, and 4,669-packet / 9,338-command controller replay.
- Checks cover warm-up index 15 and first scored index 16, all price/average
  relations, truncation, full-range extremes, swaps, circular wraps, repeated
  sessions, poison/stale RAM, stalls, exact-once commits, and reset phases.
- Seven unbounded combinational SAT lemmas pass for the H2 state relation,
  shared carry/borrow arithmetic, comparator equality, and all serial widths.
  They are transformation lemmas, not whole-system sequential equivalence.
- H2 and H2 plus both H4 boundaries pass full production-divisor emitted-RTL
  serial replay, fault/reset/startup/stop-bit checks, and unchanged heartbeat.
  The H2/H4 combination also passes the full Dune suite. Matching RTL SHA-256:
  `cbd88a4e72e8476fa7e22acd464c6e3e596d8c81a89ca3a5d5c4192a10ebe818`.
- The engine verification patch automatically detects engine latency and
  extends the emitted-RTL reset bench to each new processing phase and digit.
- H5 focused waveform tests cover every byte and 15 TX timing configurations,
  RX rate mismatch and faults; all nine variants pass serial Cyclesim replay.
- Original full Dune regressions, 62 Python runner tests, 22 data-factory tests,
  19 Gowin runner tests and 23 open-source runner failure/parser tests pass. Host socket tests required
  sandbox escalation. Initial failed command logs are preserved separately.
- The [mapping audit](../results/phase-h-open-20261004/mapping-audit/README.md)
  checks RAM modes/address bits and startup preset cells. All eight new-flow
  mapped engines (H1 plus seven candidates) pass poison/stale-history checks.
  Yosys 0.33 loses two address bits in this 18-bit SPX9 mapping; its retained
  negative control fails. The newer pinned suite fixes that mapping. Yosys 0.33
  remains valid for the original structural and combinational SAT checks.
  Mapped simulation uses a limited independent SPX9 model because the bundled
  RAM primitive is a black box; it is not vendor or postroute simulation.
- The selected whole mapped design passes the production-divisor public-pin
  smoke, including poisoned history, legal byte pauses, full stops, framing and
  busy lockout, RX/TX reset recovery and startup state. Its routed audit retains
  all five RAM address bits, all 32 data connections and all 247 register
  types/default initial values.

The locally verified H2/H4 change is reviewable as
[`H2-H4-review.patch`](../results/phase-h-search-20261004/H2-H4-review.patch).
That earlier patch is preserved as historical local evidence. The final
[working-tree patch](../results/phase-h-final-20261004/review.patch) includes the
selected implementation, experiment options, generated RTL, tests and tooling.
It applies to `7469d98`; no Git index or history changes are required.

## Reproduction and remaining measurement

Use the existing `5.2.0+ox` switch. The missing `ppx_hardcaml` was restored at
its exact pinned version. [Toolchain reproduction](../tools/HOPT_TOOLCHAIN.md)
documents the independently rebuilt isolated Yosys 0.33 / Icarus 12.0 tools.
[Gowin automation](../gowin/AUTOMATION.md) documents native Windows staging,
pinned options, hashes, evidence checks, and the 15-minute serialized runner.
[Open-source automation](../gowin/OPEN_SOURCE_AUTOMATION.md) pins OSS CAD Suite
2026-10-03, Yosys 0.69+187, nextpnr 0.11.1-47 and Apycula 0.34, including the
archive download checksum. Existing diagnostic defaults and generated diagnostic
RTL are preserved. Competition generation defaults to the selected H2/H4 design;
CLI capture/encoding/serialization flags reproduce the control alternatives.

After Windows recovery, rebuild history-only H1 first. Use that identified
measurement as the comparison baseline; preserve the documented 412 result
separately if it differs. Measure H2, ordered H3 candidates, each H4 boundary
and their combination, then one H5 block at a time on the best combined parent.
Retain rejected measurements. Rank successful local screens by whole-design
logic then registers; use five board latency runs only for the requested tie.
Never add savings from separate experiments.

The open-source screens have completed that search locally, but cannot replace
these vendor measurements or establish the ≤542 Gowin synthesis-LUT and board
latency qualification gates. The failed Windows run is not counted as a result.
Accepted H1 RTL is preserved in `fallback/`; the new open-source H1 image does
not inherit the historical board acceptance.

Stop starting candidates at October 4, 08:00 EDT; freeze at 09:00 EDT.
Unfinished experiments remain unverified. No new board acceptance is claimed.

## Board promotion, user operated

1. Program the selected `.fs` only after matching its SHA-256 to its build
   manifest. Record the programming event, candidate, source/RTL hashes and
   Gowin version/settings/reports. Check fresh startup and reset polarity,
   heartbeat, idle-high TX and fault LED recovery.
2. Prepare pristine official quick and normal scripts with only PORT changed:
   `python3 tools/prepare_board_tests.py PORT`. Run quick and require **PASS**.
3. Reset once before normal robust. Immediately follow its 100 responses with
   `tools/22_robust_uart_test_fullrange.py` copied to a fresh output directory
   with only PORT changed. **Do not reset or reprogram between normal and
   full-range runs.** Require 84/84 scored packets, 168/168 actions and zero
   timeouts for each. Save every console, CSV and summary; exit codes alone
   are insufficient. The historical helper's reset-before-each-test advice
   does not apply between this required normal/full-range pair.
4. Replay `results/phase-g2-20261003-candidate1/board-fixture.jsonl` with
   `python3 test/runner/replay.py FIXTURE --port PORT --label CANDIDATE_FS_HASH
   --out-dir FRESH_DIRECTORY`. Require 1,394 matching packets across repeated
   sessions, including all warm-up bytes, with no short/timeouts or unsolicited
   bytes. Preserve the accepted fallback separately.
5. Repeat applicable busy/framing, populated-history reset, active-TX reset and
   startup checks. For resource ties preserve five complete latency runs and
   raw samples. Board qualification and final promotion remain pending until
   these identified-image results are supplied.
