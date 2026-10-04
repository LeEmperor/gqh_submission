# Serial-adder submission — finalization checklist

**Selected:** `serial_adder_approach/gqh_serial_top.v`, variant `serial_lfsr`,
top `gqh_competition_top`; saved result **195 Logic / 98 Registers / 4 BSRAM**.
Working worktree: `even_smaller`, branch `newop`, remote
`https://github.com/LeEmperor/gqh_submission`.

**Deadline: October 4, 2026, 11:00 am EDT (15:00 UTC), including board return.**
Submit on <https://gqhacks.devpost.com> first, then return all loaned equipment to
Reitz Room 2345. There is no ZIP upload; submit a public GitHub URL and full SHA.

Authority: [Participant Guide](../gqh_hw_guide.pdf),
[organizer submission instructions](https://github.com/ShayanNazir/GQH-Hardware-Track-Submission),
and [placement supplement](../placement-supplement-20261003.md).
The guide remains unchanged. Qualify with official 100/100 plus a perfect hidden
full-range run immediately afterward without reprogramming. Qualified placement
is total logic, then registers, then median latency over five runs (within 5% tied).
Judges rebuild with Gowin V1.9.11.03 using committed settings and compare behavior
with the supplied image. BSRAM is allowed and excluded from logic.

## Prepared submission items

- [x] Selected HDL, official CST/SDC and saved settings identified under
  `serial_adder_approach/`; all paths are enumerated in `submission/manifest.json`.
- [x] Portable selected-design build: `submission/gowin/build.tcl`.
- [x] Judge-facing root README; prior working README preserved as
  `README_DEVELOPMENT.md` with its existing development changes.
- [x] Devpost paragraph and identifier template: `submission/DEVPOST.md`.
- [x] `bitstream/gqh_serial.fs` matches the selected archived image, with all
  manifest hashes passing `python3 submission/check.py`.
- [x] Clean-location Gowin rebuild succeeds with matching selected resources;
  record comparison in `submission/REBUILD.md`.
- [x] Selected serial simulation passes; saved board evidence plus explicit user
  confirmation are documented in `submission/BOARD_VALIDATION.md`.

## 1. Finish validation and attach the actual evidence

The running simulation and ongoing board checks own their output directories.
Preserve them. Do not start another run that overwrites those same files.

- [ ] `serial_adder_approach/evidence/verification.json` exists, says `PASS`, and
  its `serial_lfsr` RTL hash matches the submission manifest.
- [ ] Receive the final board-results path and operator confirmation of the image
  actually programmed. Validate that run against the copied final image:

  ```sh
  python3 submission/check.py --board-run /path/to/board-serial195-RUN
  ```

- [ ] Inspect quick PASS, normal/full-range all 100 responses, 84/84 packets,
  168/168 actions, exact warm-up bytes and zero timeouts. Normal then full-range
  must run without intervening reset/reprogramming. Local normal mean target is
  ≤20.7825 ms; full-range latency is not re-scored by judges.
- [ ] Inspect custom replay, startup, legal pauses, populated/partial-request
  reset, busy-fault and framing-fault recovery results. A prepared-only run or a
  partially written summary is not acceptance.
- [ ] Copy the completed chosen run into `submission/board/`, preserving its
  summary, fixture, console logs and CSVs. Do not overwrite evidence from another
  run. Re-run `python3 submission/check.py --board-run submission/board`.
- [ ] Update README status, final measured normal/full-range latency and evidence
  links from that run. Remove completed pending notes in the serial design README
  as appropriate. Keep local practice results distinct from the official score.

Board-run snapshot: **`submission/board/`**. Final board acceptance:
**user-confirmed full suite PASS**; see `submission/BOARD_VALIDATION.md` for the
distinction between saved stages and operator-confirmed completion.
The selected image SHA-256 must remain
`a26f7ec1900b6cde817a8df396610a7a3e58f9b262331652e326bf5f1e892fa0`.
If hardware/settings change, rebuild the image, refresh the manifest/reports,
and validate that replacement before freezing.

## 2. Complete the README and team information

- [x] User selected GitHub attribution (`LeEmperor`); participant details are on
  Devpost. Board asset tag and project-specific Devpost URL were not supplied.
- [ ] Selected top/project/image, device/tool version, build/programming steps,
  input/output behavior, tests, synthesis LUTs and placement counts are accurate.
- [ ] External resources disclosed, including Hardcaml, organizer inputs and
  BlackList architecture inspiration; known limitations accurately described.
- [ ] Judge-needed links open from this repository; required reports/test files
  will be committed. The old working notes are historical, not final directions.

## 3. Stage only the intended final work

Several working-tree changes predate this packaging task. Review them rather than
resetting, cleaning or indiscriminately staging the worktree.

- [ ] Review `git status --short --branch` and `git diff` in **even_smaller/**.
- [ ] Include root README/checklist/development notes, `submission/`,
  `bitstream/gqh_serial.fs`, and `serial_adder_approach/` source, scripts, constraints,
  options, testbenches and selected evidence. `serial_adder_approach/builds/` is ignored.
- [ ] Include generator/shared-library/integration-test changes used to reproduce
  this candidate. Inspect `bin/generate.ml`, `src/board/competition_top.ml/.mli`,
  `src/protocol/`, `test/integration/` and any required new modules referenced by
  those files. Ensure a clone can build Dune too, not just the generated Verilog.
- [ ] Review unrelated PLL/manual candidate directories and `result/` separately.
  Keep their references consistent if included; do not accidentally omit a required
  module or attribute their results to the selected serial image.
- [ ] Inspect ignored paths with `git check-ignore -v PATH`. New `results/` and
  `impl/` outputs are ignored; selected final evidence and `.fs` must be tracked.
- [ ] No secrets in the public contents, as required by the guide.
- [ ] Review the staged diff and file list before creating the final commit.

Example final commit sequence (reviewed paths and branch, not blind `git add .`):

```sh
git diff --cached --stat
git diff --cached
git commit -m "Prepare serial-adder hardware-track submission"
git push origin HEAD:main HEAD:newop
git rev-parse HEAD
git ls-remote origin refs/heads/main refs/heads/newop
```

## 4. Verify the pushed commit, submit and return

- [ ] Full local SHA equals the pushed `main` and `newop` SHA. All required inputs, saved
  settings, reports and `bitstream/gqh_serial.fs` exist at that exact commit.
- [ ] Fresh checkout of the pushed SHA passes `python3 submission/check.py`
  and the documented Gowin build. Verify final `.fs` download/hash.
- [ ] Repository is public and accessible logged out; keep it public through judging.
- [ ] Complete all required Devpost fields and paste the repository URL and full
  SHA, using the description if there is no SHA field. Do not put the final SHA
  in committed README/checklist files.
- [ ] Confirm Devpost is submitted (not just saved as a draft), with the right SHA,
  before **11:00 am EDT**. Record its URL/confirmation outside the final commit.
- [ ] Power down/disconnect and return board, cables, power supply and box/bag to
  **Reitz Room 2345** by the same deadline. Give team name, check asset tag and
  accessories with the officer, sign check-in and confirm board marked returned.

Changes after drop-off are not judged. Any pre-submission code/settings fix needs
a new matching build/test and final SHA; update Devpost to that pushed SHA.

Final handoff should state repository + full SHA, project/top/image + SHA-256,
evidence paths/results, Devpost status and board-return status. Leave unperformed
manual/account/hardware steps explicitly pending.
