# Reproducible WSL / Windows competition builds

`tools/run_gowin.py` stages immutable inputs in the current Windows `%TEMP%`
directory and invokes the installed V1.9.11.03 Education `gw_sh.exe`.
Windows execution and writes require the execution environment's sandbox
escalation. Only one runner job can hold `/tmp/gqh-gowin-build.lock` at a time.
The top `gqh_competition_top` and part `GW2AR-LV18QN88C8/I7` are pinned.

The options file was recovered with the installed release's
`saveto -all_options` on October 4, 2026 UTC. It explicitly pins those defaults,
matching the archived G2 process settings except the explicit top and neutral
output name `competition`. `gowin/competition.tcl` exports resolved settings
again for each build. No heartbeat, clock, UART, or diagnostic behavior changes
are made by these automation files.

Example (run from the repository root):

```sh
python3 tools/run_gowin.py \
  --candidate H2-relations --parent H1-reproduced \
  --rtl rtl/gqh_competition_top.v \
  --verification-status locally_verified \
  --verification-evidence /tmp/h2-verification.json \
  --source-id SOURCE_ARCHIVE_OR_PATCH_HASH \
  --output results/phase-h-H2-relations
```

The verification JSON must contain `rtl_sha256` matching the exact supplied
RTL. Include commands, results and log identities in that JSON; its full content
is preserved and hashed. Historical baseline reproductions can use
`--verification-status historical_accepted`. That status asserts historical
acceptance and does not establish fresh local simulation or board acceptance.

Every output directory must be fresh. The runner preserves input hashes,
requested/resolved options, executable hash, plain-text `launch.ps1`, exact
command arguments, logs, all Gowin output, and bitstream identity. The normal
timeout is 900 seconds, which is also the maximum. PowerShell retains the
launched process handle and kills only its process tree on timeout. An outer
watchdog checks the recorded PID, executable, and launch time before cleanup.
No image-wide process termination, programming, cache, or artifact deletion
occurs. The script supplies no Windows execution-policy override.

Missing or malformed reports, missing native exit status, tool failures,
timeouts, empty bitstreams, changed inputs and nonfinite slack invalidate the
measurement. The parser reads actual P&R Logic and Register totals and the
synthesis utilization summary's LUT count, which includes inverter LUTs.
Zero-use optional memory rows are omitted by this report schema; only those
absent memory rows produce zero counts. Resource screening is distinct from
board acceptance; inspect timing, constraints and warnings before promotion.

Test the parser and failure handling without starting Gowin:

```sh
python3 -m unittest discover -s test/gowin -v
```

The first history-only H1 attempt is preserved under
`results/phase-h-search-20261004/H1-first-attempt`. It is invalid: the Windows launcher ended during
routing without reports or a bitstream, and `gw_sh.exe` disappeared from the
installation. Norton logged PowerShell detections at the same time. The failed
bundle retains the minimal relevant security-history rows. Windows security
review and trusted-tool recovery remain user-operated; no security settings
were altered and no retry bypassed the detected block.
