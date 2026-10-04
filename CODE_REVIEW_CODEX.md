# Code review: `main` @ `7469d98` — independent Codex audit

Reviewer: Codex · October 3, 2026 · checked against the supplied Hardware Track
Participant Guide, event guide, October 3 placement supplement, and supplied
Phase H optimization plan.

This review records the independently audited `7469d98` snapshot. The separate
[CODE_REVIEW.md](CODE_REVIEW.md) includes a later re-check at `9330a63`; its
later-commit findings are not independently reverified by this document.
Both reviews are preserved separately.

Audited commit: `7469d98c53c3ce10a70d8b1baccfc3287fad66f7` on `LeEmperor/gqh_submission:main`.
Audit date: October 3, 2026, America/New_York.

**The reviewed FPGA algorithm has no confirmed defect under the published judging contract. Submission packaging has two serious unresolved issues: the repository is private, and the latest tested programming image is not the archived image in the commit.** The strongest resource opportunities are removing the optional heartbeat and moving history from distributed RAM to BSRAM. Four reproducible or directly evidenced defects affect optional host tools.

During this audit, no repository sources, project settings, visibility, branches, or remote files were changed. This document was subsequently added to the review branch at the user's request; no design fix or submission was performed. The private GitHub API and a local clone were used. Physical board operation and a fresh Gowin rebuild were not performed.

**Additional Phase H context supplied during the audit:** H1 already reports a successful block-memory candidate with 1 BSRAM, 0 SSRAM, 412 total logic, 363 registers, and 337 synthesis-summary LUTs. Supplied board results report quick/normal/full-range passes and 1,394/1,394 custom responses; normal/full-range means are 16.807/16.804 ms. The plan explicitly keeps H1 unpromoted pending startup, populated-history reset/fault checks, and settings/inferred-mode review. Those H1 artifacts are absent from the audited `main` commit, which remains unchanged. Treat these as supplied candidate results, not independently inspected raw H1 evidence. Findings about the main baseline's memory mapping and resource costs remain true, but **H1's BSRAM experiment has already been performed** outside that snapshot.

## Authority and scoring

The supplied Hardware Track Participant Guide, general event guide, downloaded PLAN.md, and organizer clarification in the pasted request were reviewed. The newer clarification takes precedence over outdated planning assumptions. The repository also preserves that clarification in [placement-supplement-20261003.md](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/docs/placement-supplement-20261003.md#L9).

- Qualification: 100/100 on the official normal run, followed immediately by a perfect hidden full-range run without reprogramming. Prices span 0–65535. The hidden run does not re-score resources or latency.
- Ranking among qualifiers: total synthesized logic, then registers, then median latency over five runs, with differences within 5% tied. BSRAM is excluded from logic.
- Qualification still needs full correctness, synthesis LUTs at or below the 542 reference, and normal-run average latency at or below 20.7825 ms for full credit. The judging PC determines the actual latency.
- Deadline: Sunday, October 4, 2026, 11:00 am EDT; repository and Devpost submission must be final before board/accessory return.

## Submission issues

### 1. High: the repository is private

GitHub's authenticated repository API returned `private: true`. Participant Guide Part 3 §6 explicitly says private repositories are not accepted. Existing access by a teammate or this assistant does not satisfy the public-submission rule.

**Action:** before the deadline, make the selected submission repository public and verify logged-out access. Also identify the full final `main` commit SHA in Devpost: this repository's default branch is `oxcaml`, so the root URL alone does not identify the reviewed version. Visibility was not changed during this audit.

### 2. High: the latest tested bitstream is not the committed archived bitstream

The committed competition `.fs` has SHA-256:

`eb348fabe16924242114f9f86123ec1d5e82c5e78c8803f2d8bf50c734990632`

The startup evidence in this main snapshot identifies its latest recorded F/G SRAM-programmed image as:

`fac34993701c469f322eba8b77ef9c4f012a7fa2ea086aea8d3662d2bbd773d4`

The evidence explicitly records `matches_archived_bitstream: false` and leaves matching source/reports unresolved. The latest hash is absent from the tracked `.fs` files. See [startup summary](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/results/phase-g2-board-20261003-142516-thv362qq/startup-2ld34y_z/summary.json#L5) and [manual progress](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/results/phase-g2-board-20261003-142516-thv362qq/manual-progress.md#L90).

The current canonical RTL, nested project RTL, historical candidate RTL, and archived Gowin source all match SHA-256 `6c7f220cf209f87d796ec11836d0299913f37faa322f44ccc6b70c5792c32164`. That establishes source-copy consistency; it cannot establish which image the passing board runs exercised. A different bitstream hash does not by itself prove different behavior, but the required association remains unproven.

**Action:** select one final Gowin project/settings bundle, rebuild, archive its source/RTL/reports and `.fs`, program that exact file in SRAM, then save quick, normal→full-range, and custom results for it. Put the selected `.fs` at an explicit submission path such as `bitstream/final.fs`. Judges rebuild committed source and compare behavior with the submitted image. The historical F/G bookkeeping waiver is documented honestly, but final-image packaging is still open.

### 3. Medium: the README still directs readers toward a noncompetition build

[README.md:72](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/README.md#L72) calls the no-subcommand generator plus `rtl/gqh_top.v` the immediate workflow. [bin/generate.ml:49](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/bin/generate.ml#L49) really does default to bringup. That image holds TX idle and cannot answer the judge. The correct competition instructions appear later, so this is a documentation/selection hazard, not a broken competition target.

The README also calls itself a working README and leaves final packaging open. It does not provide a complete team/member identity, one selected final `.fs`, and concise final resource/results/programming instructions. Fresh-machine Hardcaml setup assumes an already-existing `5.2.0+ox` switch rather than documenting how to obtain it.

**Action:** make `generate.exe -- competition`, top `gqh_competition_top`, `gqh_competition.gprj`, the selected final image, exact tools/settings, measured results, team members, and external attribution the primary submission instructions. Move bringup/PLL/diagnostic workflows below them. Generated Verilog already allows Gowin reproduction without first regenerating Hardcaml.

### 4. Low: new evidence is ignored despite the opposite comment

[.gitignore:24](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/.gitignore#L24) says selected reports under `results/` are not blanket ignored, but line 33 ignores `results/`. Existing tracked evidence remains committed; newly created freeze reports can be missed by ordinary `git add`.

**Action:** narrow the ignore rule or deliberately force-add the selected final evidence. Verify the final commit tree contains the expected reports/image rather than relying on the working directory.

## Resource and hardware risks

### 5. High-value ranking opportunity: optional heartbeat costs 45 LUTs and 25 registers

[src/board/competition_top.ml:48](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/board/competition_top.ml#L48) instantiates the heartbeat in the production design. [src/board/heartbeat.ml:17](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/board/heartbeat.ml#L17) implements a 24-bit divider plus LED state. The archived synthesis hierarchy assigns it 45 LUTs and 25 registers. LEDs are optional under the guide.

**Action:** measure a candidate with LED0 held high or a cheaper indicator. Removing this block is an unusually direct resource experiment. Do not promise an exact final saving until the whole design is re-synthesized and verified; optimization can change mapping elsewhere. This is a ranking cost, not a correctness failure.

### 6. High-value ranking opportunity: history uses counted SSRAM rather than excluded BSRAM

[src/engine/update.ml:46](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/engine/update.ml#L46) defines the 32×16 history. The archived hierarchy attributes eight `RAM16S4` distributed RAMs to the engine and the utilization summary has zero BSRAM. Their contribution to the historical total is 48 logic units (`8×6`).

**Action:** test explicit BSRAM mapping or a verified vendor wrapper, preserving synchronous read latency and warm-up invalidation. Compare whole-design totals: address/control costs can offset memory savings. Current functionality is sound; successful BSRAM mapping is not present in the audited main source.

**Phase H update:** the supplied H1 plan reports that this experiment succeeded for its candidate. Prioritize its remaining promotion checks and retain H0 as fallback; do not repeat history mapping merely because main still contains the baseline. Its reported 63-logic reduction compares PnR 475→412, with registers 379→363. That is a useful candidate screen, not proof that the judges' synthesized-total delta is exactly 63. Review the actual BSRAM mode/read-during-write behavior and complete the candidate's startup/reset/fault checks before treating it as the final image.

After those experiments, the archived hierarchy provides further area targets: controller 76 registers, request decoder 69, response sequencer 42, and engine 118. Request fields are captured in both decoder and controller, and response fields are captured again in the sequencer. Encoding fixed item IDs more compactly or changing buffer ownership may reduce storage, but those are design experiments requiring handshake and reset regressions. The fresh production-RTL test reports acceptance-to-response publication at nine clocks for ordinary packets and eleven for index zero; optimizing clock rate is unlikely to materially improve a roughly 17 ms USB/host round trip. A 270 MHz redesign has no demonstrated qualification need in the preserved baseline.

### 7. Measurement caution: resource reports have multiple counts that must not be conflated

Historical archived counts, not a fresh judge rebuild:

| Metric | Synthesis | Place & Route |
|---|---:|---:|
| LUT primitive line | 347 | — |
| LUT component in utilization summary | 351 | 351 |
| Total logic | 468 | 475 |
| ALUs | 69 | 76 |
| Registers | 379 | 379 |
| Distributed RAM16 | 8 | 8 |
| BSRAM | 0 | 0 |

Sources: [synthesis report](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/gwsynthesis/test_proj1_syn.rpt.html#L154) and [PnR report](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/pnr/test_proj1.rpt.txt#L43).

Both LUT representations are below 542. The supplement ranks a judge re-synthesis **total**, so 347/351 LUTs are not the placement score, and PnR 475 is not the same stage as synthesis 468. The archived synthesis utilization decomposes as `351 + 69 + 8×6 = 468`.

**Action:** preserve and label the raw final reports, separately record qualification LUT count and synthesized total logic/register count, and let the judge's rebuild determine the authoritative total. Moving arithmetic into ALUs alone does not improve the combined metric.

**Phase H planning gap:** the new plan repeatedly specifies whole-design **PnR** totals for final candidate selection, while the supplied judge wording specifies re-synthesis. Preserve the corresponding synthesis total for every candidate as well. Main's synthesis 468 and PnR 475 are demonstrably different; do not compare H1's reported 412 PnR total against 468 synthesis or assume its PnR advantage is the exact judge advantage. If organizers intend a particular report stage, settle that interpretation before using close resource differences to discard a candidate.

### 8. Medium confidence gap: clock routing and asynchronous timing coverage

The archived PnR report passes analyzed synchronous setup/hold at 27 MHz, with worst setup slack 24.535 ns and zero listed violations. [PnR log:15](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/results/phase-g2-board-20261003-142516-thv362qq/gowin-build-observed/impl/pnr/test_proj1.log#L15) nevertheless emits PR1014: generic routing feeds `sys_clk_d` and may add delay/skew. [constraints/tang_nano_20k.sdc:2](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/constraints/tang_nano_20k.sdc#L2) defines only the primary clock.

**Action:** inspect clock routing and the final timing coverage of RX synchronization and asynchronous reset release. Document justified constraints rather than blanket false paths. This is a sign-off gap, not a demonstrated 27 MHz malfunction. The synthesis report's default 100 MHz negative slack does not establish failure at the actual 27 MHz constraint. These reports do not validate the separate 270 MHz PLL experiment.

### 9. Medium portability risk: zero additional UART idle time

[src/uart/config.ml:3](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/uart/config.ml#L3) sets `extra_idle_cycles = 0`. The mandatory stop bit is preserved, but there is almost no additional spacing. The guide explicitly warns that BL616 can corrupt/drop tightly spaced responses and turn otherwise correct packets into timeouts.

Committed normal/full-range/custom board results pass with this setting. Therefore **this audit did not demonstrate a UART failure**. The remaining concern is reliability on the judge's bridge/PC and its effect on a perfect qualification run.

**Action:** retain repeated final-image board evidence, compare a small-gap candidate only if warranted, and preserve qualification margin. Increasing idle time consumes judged latency; a gap should be selected from measurements rather than assumed beneficial.

## Optional host-tool defects

These tools are not executed during official judging. They can affect local testing, demos, and evidence preservation.

### 10. Medium: predictable temporary filenames follow symlinks and overwrite unrelated files

[external/databento_audit/safe_output.ml:13](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/external/databento_audit/safe_output.ml#L13) builds `<output>.tmp.<pid>`; line 39 opens it with `O_CREAT|O_TRUNC`, without exclusive creation. [databento_audit.ml:103](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/external/databento_audit/databento_audit.ml#L103) does the same for partial request output.

**Reproduction:** pre-create the predictable temporary sibling as a symlink to another evidence file, then call `write_file ~overwrite:false` for a new output. The victim's contents are replaced and the operation succeeds. This requires a pre-existing alias or someone able to create the sibling; it is not an unconditional remote exploit.

**Fix:** use secure exclusive temporary-file creation in the destination directory, restrictive permissions, and robust cleanup before the atomic final commit.

### 11. Medium: aliases for two output paths destroy the requests CSV

[databento_audit.ml:80](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/external/databento_audit/databento_audit.ml#L80) compares output names only as strings.

**Reproduction:** run validation with `--requests-out /tmp/run/out.csv --report /tmp/run/sub/../out.csv --overwrite` (with the parent directories present). It exits successfully, but the shared output ends up containing report JSON instead of the requests CSV.

**Fix:** resolve existing parent paths, normalize new output names, and reject output aliases before either write. Existing-file identity checks alone do not cover two new destinations.

### 12. Medium: `--pair-timeout` accepts late data and cannot bound a blocking source read

[bin/stream.ml:89](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/bin/stream.ml#L89) checks the deadline before `s.next()`, then accepts its result without a post-read deadline check.

**Reproduction:** a board-free replay FIFO supplies A immediately and B 250 ms later; `--pair-timeout 0.05 --packets 1 --transport dry-run` succeeds and logs a packet instead of timing out at 50 ms. A live source can block under its separate 40-second timeout.

**Fix:** pass the remaining deadline into source reads and recheck it before accepting a completed pair.

### 13. Medium: Python serial writes are unbounded

[test/runner/transport.py:46](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/test/runner/transport.py#L46) sets only the read timeout; lines 51–52 ignore the write result. [replay.py:79](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/test/runner/replay.py#L79) cannot enforce its packet deadline while that write blocks.

**Impact:** a stalled serial driver can hang the custom run, and a short write is not diagnosed at the transport boundary. This follows directly from the implementation; no physical stalled-device test was attempted.

**Fix:** set a finite write timeout consistent with the packet budget and reject incomplete writes.

## Robustness boundaries that are not judge-contract defects

- One framing error or byte received while the transaction is busy latches a permanent decoder fault until physical reset. A later index-zero packet cannot clear it because decoding is already disabled. This behavior is documented and tested. It does not occur on valid stop-and-wait traffic, but matters when diagnosing noise or stray host bytes. See [request_decoder.ml:28](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/protocol/request_decoder.ml#L28).
- Unknown IDs are treated as item A; duplicate IDs can corrupt its history. The shared pointer assumes one update per item per packet and sequential judging indices. The guide's fixed IDs and sequential 0–99 packets make those assumptions valid. Do not call them hidden full-range failures without evidence that the organizers expanded the packet contract. See [transaction_controller.ml:59](https://github.com/LeEmperor/gqh_submission/blob/7469d98c53c3ce10a70d8b1baccfc3287fad66f7/src/protocol/transaction_controller.ml#L59).
- The official practice scripts do not validate warm-up contents and report correctness out of 70, rather than proving 100/100 qualification. The custom all-byte tests close the warm-up coverage gap. A script's exit status alone is insufficient.
- No preserved five-run latency median was established for this image. This limits resource-tied candidate comparison; it is not itself a qualification failure.

## Review of the newly supplied Phase H plan

H2's proposed comparison-state compression is algebraically sound for the specified algorithm. After an item commits, its current price and updated average become that same item's previous price and old average on its next update. Therefore `not previous_above` implements the inclusive old `<=` comparison, and `not previous_below` implements old `>=`. Equal must remain representable; both flags false supplies it. The plan correctly requires computing/storing flags during warm-up, especially index 15, preserving item ownership, and clearing both flags on session reset. No implementation or measured H2 saving is present in the audited main snapshot, so this validates the stated reasoning rather than candidate RTL.

The plan's remaining important checks are concrete:

- H1 source/settings/report/programmed-image association must follow the candidate, independently of the historical F/G bookkeeping waiver. Its new passing board runs do not establish that main's archived `.fs` is the candidate's final file.
- Confirm BSRAM mapping, actual read mode/latency, warm-up overwrite, and reset write suppression in the mapped candidate; a memory-only attribute can leave behavioral simulation unchanged while changing the FPGA primitive.
- Complete the startup and populated-history reset/fault checks already listed as pending. Do not describe H1 as accepted until its scoped promotion conditions are satisfied or explicitly waived.
- Use stage-consistent synthesized totals as well as PnR screens, and keep raw reports for the judge's metric. Reported individual-stage savings cannot be added without building and testing the combined image.
- H4 correctly recognizes that valid/ready stability ends at acceptance. Removing buffers needs explicit storage ownership through the final consumer, not merely fewer payload registers.
- H5 currently preserves heartbeat cadence as an experiment constraint. The guide makes LEDs optional; if the team permits changing that indicator, removing it is a separate simpler experiment. Otherwise optimize its implementation without claiming the entire 45-LUT baseline block can be discarded under H5's stated constraint.

H2–H5 are explicitly unrun in the supplied plan. They are prospective experiments, not missing required FPGA features or evidence of current algorithm defects.

## Evidence supporting the design

The FPGA audit checked 20-bit sum width, full 16-bit prices, unsigned old/new average comparisons, floor truncation, held actions, ID-based routing, slot mirroring, index-zero session clear, stale-RAM invalidation by warm-up, complete-request-before-TX, and final-frame drain before receive rearm. No confirmed valid-traffic algorithm defect was found.

The archived normal/full-range CSVs independently show 100 responses each, 84/84 scored packets, 168/168 scored actions, and no timeout. Means are 16.8114637 ms and 16.9139396 ms. The custom board CSV has 1,394 exact eight-byte matches across 13 sessions, including 208 warm-up responses. Archived build/qualification manifest hashes match their current files. These are historical practice results, not a fresh board test or an unpublished official judge result.

Fresh checks performed during this audit:

- `opam exec --switch=5.2.0+ox -- dune build @all`: passed.
- All four production generator targets reproduced their committed RTL byte-for-byte and deterministically.
- OCaml core, transport, CLI, external-fixture and simulation checks passed; the Databento local mock test passed after allowing its local socket bind.
- Engine Cyclesim exercised 4,774 packets / 9,554 accepted commands; standalone Icarus checked 100,647 edges, including RAM/scalar consistency, resets, and stalled results. Controller/engine checks exercised 4,669 records. UART byte/boundary and production-composition Cyclesim checks passed.
- Python replay suite: 62 tests passed, including board-free serial loopback. Python fixture factory: 22 tests passed. External audit suite: 2,232 checks passed, including the two-million-row test.
- Verilator elaboration/lint completed with generated-code combinational assignment warnings; those warnings are not classified here as proven functional defects.
- Production-rate Icarus serial replay: passed all 1,394 oracle packets at the production divisor against independent 115200-baud stimulus. Startup, full stop bits, legal pauses, framing/busy fault lockout, RX/engine/TX reset recovery and heartbeat checks also passed. It used the committed main RTL, not the uninspected H1 candidate.
- `git diff --check` passed; the repository remained clean.

The aggregate `dune build @runtest` did **not** pass as a whole: Yosys is unavailable in this environment, and the first local socket bind was sandbox-blocked. The latter test was rerun successfully; Yosys-specific hierarchy checks were not rerun. Available Icarus/Cyclesim checks were run separately. No claim of fresh Gowin synthesis, mapped-memory correctness, physical UART reliability, or source-to-bitstream equivalence is made.

## Suggested order before the deadline

1. Resolve final image/project/settings identity and prepare a judge-ready README.
2. Complete the reported H1 candidate's remaining promotion checks and retain H0 as fallback. If further experiments fit the schedule, evaluate H2 and/or a cheap heartbeat candidate under the team's agreed constraints; do not repeat the already measured H1 mapping experiment.
3. Rebuild and program the chosen final image, preserve matching reports and normal→full-range/custom results, and verify latency/LUT qualification margin.
4. Commit the chosen image and evidence explicitly, verify public logged-out access, and put the full final main SHA in Devpost before the deadline/board return.
5. Fix host-tool defects when they affect the team's testing/demo workflow. They have lower deadline priority than the qualifying FPGA submission.

The report records findings supported by the inspected sources and available tests. It is not a guarantee that no additional hardware, host, toolchain, or hidden-seed issue exists.
