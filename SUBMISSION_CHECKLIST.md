# Final submission checklist and agent handoff

**Status: preparation only; final design selection is pending.** Created October 4,
2026. This is the working source of truth for **packaging and submitting** this
project. Check boxes only when completed and supported by evidence. Implementation
progress remains in `resource_optimization.md` and `REQUEST_RESPONSE_PLAN.md`.

**Deadline: Sunday, October 4, 2026, 11:00 am EDT (15:00 UTC), for both submission
and board return. Submit first, then return the board to Reitz Room 2345.**
The 9:00 am freeze mentioned in `PLAN.md` is an internal target, not the deadline.

**Deliverable:** a public team GitHub repository containing reproducible source,
project settings, constraints, and the matching final `.fs`, identified by its
**full commit SHA on Devpost** at <https://gqhacks.devpost.com>. There is no ZIP
submission and no team-code upload to the organizer repository.

## 1. Authority and references

Read these if a requirement is unclear; the Participant Guide wins over the
organizer Markdown summaries. The announcement supplements the guide and leaves
the submission channel and deadline unchanged.

- [Participant Guide](gqh_hw_guide.pdf): Part 3 submission; Part 1 return;
  Part 2 build/programming and protocol. At review this copy is byte-identical to
  the organizer PDF (SHA-256
  `d01aa81f34dd95e073dda2ca310c94b99b9f046a5148f14bb80d59d55f544693`).
- [Official instructions repository](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission),
  local checkout `../GQH-Hardware-Track-Submission/`, reviewed tracked revision
  `80467b5d0e481373daf126de9a0f57e67f19906b`:
  [checklist](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission/blob/80467b5d0e481373daf126de9a0f57e67f19906b/SUBMISSION_CHECKLIST.md),
  [README template](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission/blob/80467b5d0e481373daf126de9a0f57e67f19906b/TEAM_README_TEMPLATE.md),
  [layout](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission/blob/80467b5d0e481373daf126de9a0f57e67f19906b/REPOSITORY_STRUCTURE.md),
  [judging/testing](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission/blob/80467b5d0e481373daf126de9a0f57e67f19906b/JUDGING_AND_TESTING.md).
- [Placement supplement, preserved verbatim](docs/placement-supplement-20261003.md):
  the announcement supplied by the user, including attachment provenance.
- [Pinned organizer inputs](tools/official/README.md),
  [board-test runner](test/runner/README.md), and [Gowin notes](gowin/README.md).

### What the announcement adds

| Stage | Rule |
| --- | --- |
| Qualification, official run | **100/100** under the guide's rubric. Judges may rerun once if the latency tier is missed. |
| Qualification, hidden run | Immediately afterward, **without reprogramming**, full-range unsigned 16-bit prices (`0..65535`); every packet/action correct, no timeouts. Latency and LUTs are not re-scored here. Index 0 must start a new session without a physical reset. |
| Placement among qualifiers | Lowest **total logic**, then fewer **total registers**, then lower **median latency over 5 runs** (within 5% is a tie). |
| Resource measurement | Judges re-synthesize with **Gowin V1.9.11.03**, using committed project settings. Resource Usage Summary total logic includes LUTs, ALUs and other logic; BSRAM is allowed and excluded from logic. Self-reported counts do not decide placement. |
| Reproduction | Judges rebuild committed source and verify behavior matches the submitted `.fs`. |
| Nonqualifiers | Below all qualifiers, ordered by rubric score. |

Keep **synthesis total LUTs for qualification** separate from **total logic for
placement**. Under the published references, full rubric points require 84/84
scored packets, 168/168 actions, synthesis LUTs ≤542, and average judge-PC round
trip ≤20.7825 ms (1.25 × 16.626 ms). Local practice is evidence, not an official
100/100 award. Five-run timing is the judges' last tie-break, not an additional
required upload or a reason to delay an otherwise complete submission.

## 2. Resume here when the user is ready

The next agent should inspect the current working tree and fill this table before
packaging. Do not select the newest file or lowest historical count by inference.

| Decision / identity | Final value |
| --- | --- |
| User-selected candidate and source state | **TBD** |
| Team/project name and team members | **TBD** |
| Public repository URL | Expected `https://github.com/LeEmperor/gqh_submission`; confirm final destination and visibility |
| Devpost project URL / submitting teammate | **TBD** |
| Board asset tag / person returning it | **TBD** |
| Canonical Gowin project path | **TBD** |
| Top-level module / complete synthesis input list | **TBD** |
| Actual Gowin version / saved settings location | **TBD** |
| RTL regeneration command and options, if applicable | **TBD** |
| Clock / UART divisor / response spacing / LED behavior | **TBD** |
| Final repository `.fs` path | **TBD**, preferably `bitstream/<chosen-name>.fs` |
| Final `.fs` SHA-256 | **TBD** |
| Matching resource/timing report paths | **TBD** |
| Matching board-test evidence directory | **TBD** |
| Synthesis LUTs / total logic / registers / BSRAM | **TBD**, with report labels and paths |
| Normal/full-range correctness and measured latency | **TBD**, with matching run paths |

Record the final **Git commit SHA outside the committed files**, in the handoff
message and Devpost. A committed checklist/README cannot contain its own commit SHA.

### Repository-specific traps observed at preparation time

Recheck these; the user is still working and this snapshot is not a final verdict.

- `gqh_competition.gprj` names `rtl/gqh_competition_top.v` and the official CST/SDC.
  It is a candidate entry point, not an automatic final selection.
- `test_proj2/test_proj2/test_proj2.gprj` was modified with an empty `<FileList/>`;
  `test_proj2/test_proj2/src/gqh_competition_bsram_top.v` was untracked. Preserve
  ongoing work and establish which project/settings actually produced the chosen
  image. An empty project is not a reproducible submission.
- Several bring-up, standalone-engine, diagnostic, PLL and historical `.fs` files
  exist. The README must point unambiguously to one final competition project/image.
- `.gitignore` ignores `impl/` and `results/`. Some historical results are already
  tracked, but new final evidence will not be added automatically. `bitstream/` is
  intended for the required final image. Inspect with `git check-ignore -v PATH`;
  copy selected evidence into a tracked location or explicitly add selected files.
- Current README/Gowin notes mix accepted competition work with old bring-up
  instructions and stale status. Rewrite the judge-facing entry point for the
  chosen design, preserving useful development notes elsewhere as appropriate.
- `tools/prepare_board_tests.py` is an older quick/normal-only helper, hashes the
  baseline RTL, and tells the operator to reset before each test. Use the full
  sequence below for submission verification.
- Existing F/G and H acceptance/waivers are recorded in the development plans.
  They do not identify a later image automatically. Final source/project/image
  association was deliberately deferred until packaging; complete that association
  for the selected candidate without reopening historical phase closures.

## 3. Assemble a reproducible final project

- [ ] Confirm the selected candidate with the user and complete the identity table.
- [ ] Review `git status --short --branch`, `git diff`, and `git remote -v` in
  **`gqh_submission/`**, not the enclosing workspace or organizer checkout.
- [ ] Include the final HDL and all referenced modules, generated/vendor IP,
  initialization/data files and other build dependencies. If using Hardcaml,
  include the matching generator sources, tool versions and generated Verilog.
- [ ] Document the exact generation command/options for this candidate. Do not run
  the generator's default target: it emits bring-up, not the competition image.
  Compare regenerated output before replacing any selected or hand-edited RTL.
- [ ] Include the unchanged organizer `constraints/19_tang_nano_20k.cst`, required
  SDCs and any selected IP settings. Verify the official CST matches the pinned copy.
- [ ] Make all project dependencies available from a fresh clone using portable
  paths. Resolve external paths, submodules and Git LFS objects if present.
- [ ] Save **all settings that affect synthesis/P&R** in versioned project/build
  files or a reproducible build script: top, part, source list, defines, parameters,
  synthesis options, timing constraints and IP configuration. Inspect where Gowin
  actually stores them; a `.gprj` alone is not proof they are all saved. Convert
  essential machine-local/ignored settings into reproducible instructions/files.
- [ ] Confirm part **GW2AR-LV18QN88C8/I7** and the selected top. Retain all six
  official ports: `sys_clk`, `reset_btn`, `uart_rx_i`, `uart_tx_o`, `led0_n`,
  `led1_n`; unused LEDs high. Exclude simulation-only sources from synthesis.
- [ ] Run relevant existing simulation/generator checks for the selected design.
  For the current Hardcaml project, the documented commands include:

  ```sh
  opam exec --switch=5.2.0+ox -- dune build
  opam exec --switch=5.2.0+ox -- dune runtest
  ```

- [ ] Synthesize and place-and-route the selected project with **V1.9.11.03**.
  Require successful completion; review applied constraints, timing and warnings.
- [ ] Save matching synthesis Resource Usage Summary and implementation/timing
  reports. Record synthesis LUTs, total logic, registers and BSRAM separately;
  retain original report labels rather than combining incompatible subtotals.
- [ ] Copy the resulting `impl/pnr/<project>.fs` to the chosen `bitstream/` path.
  Compare bytes/hashes to the build output and record its SHA-256. Do not use an
  older similarly named image or an image from a different project.
- [ ] Record hashes of the actual synthesis inputs, project/settings and `.fs`
  alongside the matching reports/test evidence. This is packaging provenance;
  source and image must describe the same build.

**Suggested layout is optional.** Keep the existing structure if it is reproducible
and clearly documented; the required files matter more than folder names.

## 4. Verify the exact image being submitted

- [ ] Program the **copied final `.fs`** on the Tang Nano 20K in **SRAM mode**:
  Gowin Programmer → Scan Device → GW2AR-18C → Device Configuration → Access Mode
  `SRAM Mode`, Operation `SRAM Program` → select the final image → Program/Configure.
- [ ] Close Gowin Programmer and other serial terminals before UART testing.
  Confirm the actual serial port; Python 3 and pyserial are needed on the test host.
- [ ] Run official quick, then normal robust, then full-range practice. Change
  **only `PORT`** in copies of organizer scripts. Preserve each run's outputs.
  **No reset, power cycle or reprogramming between normal and full-range.**

The existing full-suite helper supports this sequence plus custom boundary/session,
startup and reset tests. From the repository root, substitute the real port/path:

```sh
python3 tools/validate_board.py --port PORT --label FINAL --fs bitstream/CHOSEN.fs
```

Use `--no-heartbeat` and/or `--no-fault-led` only if those features are disabled in
the selected design. Review `--help` and current helper behavior first; its defaults
refer to H2/test_proj2. `--smoke` is quick-only and `--prepare-only` does not test
hardware. **`--fs` records a path and prompts the operator; it does not program or
hash the image or establish which image is on the board.** Record that separately.
Physical programming/button/LED steps need the operator if the agent lacks access.

| Check | Required evidence / interpretation |
| --- | --- |
| Quick | Actual `PASS` on the final board image. |
| Normal robust | 100 complete responses, 84/84 scored packets, 168/168 actions, zero timeouts; retain `trade_results_100.csv`, `trade_summary_100.txt` and console output. |
| Full-range | Same perfect counts/no timeouts, immediately after normal; retain `trade_results_100_fullrange.csv`, `trade_summary_100_fullrange.txt` and console output. Source: `tools/22_robust_uart_test_fullrange.py`. |
| Warm-up and repeated sessions | Verify exact warm-up responses and session restart using existing custom checks; organizer practice scripts do not validate warm-up contents. All prices must work through 65535, with correct unsigned arithmetic and enough sum range (20 bits for a conventional 16-price sum). |
| Protocol/algorithm | 115200/8N1; exactly 8 bytes each way; big-endian fields; echoed index/slot IDs; routing by ID; reserved zero; no unsolicited/early response; index-0 clear; floor averages; correct crossings and held actions. |
| Startup/bridge behavior | Correct operation after SRAM programming; documented response pacing/buffering and no BL616 corruption/timeouts. Describe actual LED/reset behavior, not old bring-up expectations. |
| Local latency | Record normal-run average and host setup; published full-score target is ≤20.7825 ms. Full-range timing does not re-score qualification. |

- [ ] Inspect actual CSVs/summaries, not only script exit codes. Organizer robust
  summaries report **correctness out of 70**, not a full 100-point award.
- [ ] Preserve the final suite's summary and selected logs in tracked files if the
  README links to them. Confirm the image hash, reports and test runs agree.
- [ ] If anything affecting hardware changes after this test, rebuild and test the
  replacement image. Documentation-only edits do not require another hardware run.

## 5. Finish the judge-facing README

Use the organizer template as a content checklist, adapting it to this repository.

- [ ] Team/project name and team members; board asset tag if available.
- [ ] Brief architecture and what runs on the FPGA. State that all parsing, state,
  computation and responses are on-board; no team host software runs during judging.
- [ ] Tang Nano 20K, exact device, HDL/languages and actual Gowin version.
- [ ] Prominent **final project path, top module and final `.fs` path**.
- [ ] Official CST location; ports, actual clock configuration, UART and LED behavior.
- [ ] Complete fresh-clone build steps, including dependencies, generation if needed,
  source/settings selection, synthesis, P&R and expected output location.
- [ ] SRAM programming steps and exact file to load.
- [ ] Inputs, expected outputs, demo/test commands and final-image verification results.
- [ ] Synthesis LUT total, separate placement metrics and report links; local latency
  labeled with its setup. Do not copy historical candidate measurements as final.
- [ ] External libraries/IP/starter code/pre-existing resources and their purposes:
  check Hardcaml/Jane Street dependencies, organizer inputs, imported datafactory/
  runner work, Gowin primitives/IP and any PLL actually used. Describe actual usage.
- [ ] Known limitations/incomplete features; distinguish historical experiments from
  the selected design. Remove stale claims that contradict the final build.
- [ ] Public repository URL, Devpost URL if known, and a link to this checklist.
  **Do not put the final Git SHA in the README.**
- [ ] Every judge-needed link/file is in the submitted repository or has a usable
  public upstream link; sibling workspace paths and ignored evidence are not enough.

## 6. Freeze, push and verify the public commit

- [ ] Review the intended public contents for credentials/secrets, as the guide
  requires. Include all required sources/tests/configuration and the final `.fs`;
  avoid accidentally staging temporary files or unrelated ongoing experiments.
- [ ] Set/confirm repository visibility is **public**. Keep it public through
  judging and do not delete or rename it.
- [ ] Stage an explicit reviewed file list. Handle ignored final evidence
  deliberately; do not force-add all of `results/` or all generated IDE output.
- [ ] Review `git diff --cached --stat` and `git diff --cached`, then commit and push
  to the confirmed repository/branch. Example (replace placeholders):

  ```sh
  git status --short --branch
  git add -- <reviewed-final-paths>
  git diff --cached --stat
  git diff --cached
  git commit -m "Final hackathon submission"
  git push origin <submission-branch>
  git rev-parse HEAD
  git ls-remote origin refs/heads/<submission-branch>
  ```

- [ ] Verify the full pushed SHA equals the SHA to be submitted. Inspect files at
  **that commit**, not just the default branch. Confirm the final `.fs` is actually
  tracked (`git ls-tree -r --name-only <SHA>`) and downloadable with the expected hash.
- [ ] Use a fresh clone/check-out of that pushed SHA to verify all build inputs and
  follow the README through synthesis/P&R. Compare rebuilt behavior to the submitted
  image. Bitstream bytes may vary with tool/build metadata; unexplained input,
  settings or behavior differences must be resolved, not dismissed.
- [ ] Open the repository and commit anonymously/logged out; verify README, source,
  project files and final `.fs` are accessible.
- [ ] Confirm no required final changes remain uncommitted or unpushed. If a fix
  creates another commit, repeat commit verification and replace the Devpost SHA.

## 7. Devpost, then physical return

- [ ] Open <https://gqhacks.devpost.com>, complete the project entry and all fields
  actually required by the live form. The guide does not enumerate every Devpost
  field; do not assume a draft is submitted or invent additional required artifacts.
- [ ] Include the public GitHub URL and **full final commit SHA**. If there is no
  dedicated SHA field, paste this into the project description:

  ```text
  Final GitHub Submission
  Repository: https://github.com/LeEmperor/gqh_submission
  Final Commit SHA: <full SHA verified above>
  ```

- [ ] Complete the submission before **11:00 am EDT October 4**. Verify the saved
  submission contains the correct URL/SHA; retain the Devpost URL and confirmation.
- [ ] Once submitted, power down/disconnect the board and gather all loaned cables,
  power supply and box/bag. Return to **Reitz Room 2345 by the same deadline**.
- [ ] Give the team name; have the officer confirm the GitHub submission and board
  asset tag; inspect accessories and sign the check-in sheet. Confirm the officer
  marks the board returned. Changes pushed after drop-off are not judged.

Support: <https://discord.gg/9qPMtN4UB>; board return questions:
`IoTStudentsClub@ece.ufl.edu`. Contact an organizer before the deadline if return
arrangements need changing.

## Completion handoff (outside the final commit)

The executing agent's final message should give:

1. Public repository URL, **full pushed SHA**, final project/top and `.fs` path/hash.
2. Matching build/report and board-test evidence locations, with actual results.
3. Devpost project URL and confirmed submission status/time.
4. Board-return status and responsible person.
5. Any remaining blocker or manual action, explicitly marked **pending**.

Preparing files, running simulations or creating a Devpost draft does not complete
submission. If the agent cannot perform a hardware, account or physical-return
step, give the operator the exact next action and leave that step unchecked.
