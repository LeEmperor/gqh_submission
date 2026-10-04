# Auditable open-source competition builds

`tools/run_open_gowin.py` runs Yosys, nextpnr-himbaechel and Apycula's
`gowin_pack` from a supplied, pinned OSS CAD Suite. These are **open-source
measurements only**. They do not reproduce Gowin's official Logic, Register,
synthesis-LUT qualification, timing or board acceptance results.

The local suite is release **2026-10-03**, Linux x64, archive SHA-256
`41b1e1c669efe199ac6e3969b067b84622c365871b4bc09e6b9357ea2f001dcc`.
Its observed versions are Yosys 0.69+187 (`2f08661dd`),
nextpnr 0.11.1-47 (`e2fe86b3`) and Apycula 0.34. The archive and release
metadata are preserved under `results/local-toolchains/oss-cad-suite-20261003`.
The separate Yosys 0.33 verification installation does not support the required
`synth_gowin -family gw2a` interface and is not used by this runner.

To reproduce the suite, use the official, date-pinned
[2026-10-03 Linux x64 archive](https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-03/oss-cad-suite-linux-x64-20261003.tgz).
From the repository root, prepare a fresh workspace directory and verify its
SHA-256 before extraction. The archive is 746,447,109 bytes and the extracted
suite needs several gigabytes; use a disk-backed directory with enough space.
This downloads and extracts files only, without a system installation:

```sh
mkdir -p results/local-toolchains
mkdir results/local-toolchains/oss-cad-suite-20261003-reproduced
cd results/local-toolchains/oss-cad-suite-20261003-reproduced
curl -L --fail --max-time 600 \
  https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-03/oss-cad-suite-linux-x64-20261003.tgz \
  -o oss-cad-suite-linux-x64-20261003.tgz
printf '%s  %s\n' \
  41b1e1c669efe199ac6e3969b067b84622c365871b4bc09e6b9357ea2f001dcc \
  oss-cad-suite-linux-x64-20261003.tgz > archive.sha256
sha256sum --check archive.sha256 && tar -xzf oss-cad-suite-linux-x64-20261003.tgz
cd ../../..
```

Extraction runs only when the checksum succeeds. Refuse a mismatched download;
do not replace the pin with a moving `latest` URL. Existing preserved archives
can be copied into the fresh directory instead of downloading and checked by
the same checksum step. Point `--oss-root` to the resulting `oss-cad-suite`
directory and retain the date plus verified archive SHA in
`--toolchain-identity`. Network/download commands require the execution
environment's normal approval; no global installation or HOME changes are
needed.

Run a fresh candidate after its focused correctness checks:

```sh
python3 tools/run_open_gowin.py \
  --candidate H2-H4 --parent H2 \
  --rtl rtl/gqh_competition_top.v \
  --verification-status locally_verified \
  --verification-evidence /tmp/candidate-verification.json \
  --source-id SOURCE_ARCHIVE_OR_PATCH_HASH \
  --oss-root results/local-toolchains/oss-cad-suite-20261003/oss-cad-suite \
  --toolchain-identity '2026-10-03 sha256:41b1e1c669efe199ac6e3969b067b84622c365871b4bc09e6b9357ea2f001dcc' \
  --output results/phase-h-open-20261004/H2-H4-audited
```

The verification JSON must contain `rtl_sha256` matching the exact supplied
RTL; include test commands, results, log paths/hashes and cycle observations.
The runner copies and hashes it, checks the captured RTL again, and retains the
evidence. `historical_accepted` is available for accepted baseline reproduction;
it does not assert fresh correctness or board testing. Existing output
directories are refused. Keep large suite/build outputs on the workspace
filesystem when `/tmp` is memory-backed or space constrained.

The fixed synthesis is `synth_gowin -family gw2a -top gqh_competition_top`,
followed by `check -assert`, JSON and Verilog netlists, and JSON statistics.
JSON output is written explicitly after synthesis, retaining normal BRAM
inference. P&R pins device `GW2AR-LV18QN88C8/I7`, family `GW2A-18C`, frequency
27 MHz, unchanged CST and SDC, seed 1 and one thread. Detailed timing and
utilization reports are preserved. Packing explicitly selects `GW2A-18C`.
No timing-allow-fail flag, clock changes, configuration changes or programming
commands are supplied.

The runner invokes the suite's bundled dynamic loader and `libexec` binaries.
This is the same loading mechanism as its distributed wrappers, while omitting
the nextpnr wrapper's optional GUI/font configuration writes beneath HOME.
HOME is not changed. Python imports use the suite's Python home with user-site
imports disabled and inherited `PYTHONPATH` removed. The runner records its
controlled environment overrides, versions, actual binary/loader/Python/chip
database hashes, exact argv, logs, all output hashes and final bitstream hash.
It does not record unrelated environment variables or credentials.

The default and maximum overall timeout is 900 seconds, including version/help
probes. Only one runner holds `/tmp/gqh-open-gowin-build.lock` at a time.
Each subprocess starts in its own process group; timeout cleanup signals only
that group. A failed tool, changed input, missing output, empty bitstream,
malformed/nonfinite count or timing, missing required LUT4/ALU/DFF/BSRAM count,
or incomplete collection makes the measurement invalid. Failed evidence is
retained and never replaced with zero counts.

The parser checks final routed JSON, which nextpnr names module `top` even
when the synthesis top has its original name. It requires the six scalar
competition ports, the six original CST pin declarations and concrete placed
I/O buffer bindings. It rejects temporary `BLOCKER_LUT`/`BLOCKER_FF` cells.
Raw final utilization, synthesis cell counts, routed cell counts and clock
results remain separate. `official_gowin_logic` and
`official_gowin_registers` remain null.

The archived H1 pilot's final JSON reports LUT4 599, ALU 162, DFF 375, BSRAM 1
and achieved 141.48 MHz against 27 MHz. This differs substantially from the
historical vendor result; mixing those count scales would invalidate ranking.
The test fixture preserves that pilot's raw utilization and clock summary.
Its structural pin/cell fixtures are deliberately small and are not a circuit
equivalence proof.

Use **final report JSON** for a documented open-source proxy, never the early
placement log's utilization table. In the pinned nextpnr implementation,
[ALU packing creates temporary LUT blockers](https://github.com/YosysHQ/nextpnr/blob/e2fe86b3/himbaechel/uarch/gowin/pack_luts.cc#L458),
[post-route removes them](https://github.com/YosysHQ/nextpnr/blob/e2fe86b3/himbaechel/uarch/gowin/gowin.cc#L1011),
and [post-placement inserts passthrough LUTs beside some DFFs](https://github.com/YosysHQ/nextpnr/blob/e2fe86b3/himbaechel/uarch/gowin/gowin.cc#L1199).
[Resource buckets classify LUT and ALU cells separately](https://github.com/YosysHQ/nextpnr/blob/e2fe86b3/himbaechel/uarch/gowin/gowin.cc#L1071).
Thus summing final LUT4 and ALU can describe a routed logic-cell proxy including
helper cells, but it is neither Gowin Logic nor a proof of total physical sites.
Wide mux and RAM resources must also be retained for review. The runner leaves
all such ranking choices to the candidate ledger rather than inventing an
official equivalent.

Run the parser and failure tests without starting a synthesis job:

```sh
python3 -m unittest discover -s test/gowin -p 'test_run_open_gowin.py' -v
```

New bitstreams remain locally generated artifacts awaiting physical checks.
Keep the accepted vendor fallback. Board acceptance and official vendor
qualification remain separate from these open-source screens.
