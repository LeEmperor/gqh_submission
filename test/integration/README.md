# G2 production serial verification

Status: **Locally verified — awaiting manual checks**. From the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune build @test/integration/runtest
```

`dune` explicitly owns only `serial_verify.ml` in its executable. The focused
alias runs `run_checks.py` with the production generator and that executable;
its declared inputs include the testbench, production RTL and F's pinned oracle.
No sibling checkout or extra package is required. Installed Python, Icarus/vvp
and Yosys are used; no board, IDE or serial device is accessed.

The actual `Board.Competition_top` runs in Cyclesim with divisor 16 and shortened
heartbeat for efficient broad replay. Its independent serial stimulus and pin
waveform decoder check every byte, response count, whole stop bit and no early
TX. This is a timing supplement, not the production baud test.

The emitted production RTL runs in Icarus with a 27 MHz clock (37.037037 ns),
divisor **234**, zero extra TX gap, and an independent **115200 baud** source and
receiver (8680.555556 ns/bit = 234.375 core clocks). The host does not copy the
DUT's rounded divisor. It checks all response bytes/counts/reserved zeros,
acceptance before TX, full 234-clock stop bits, receive rearm after TX drain,
legal multi-byte pauses, true startup initialization without a button reset,
sticky framing/busy-input lockout and reset recovery. Populated-history reset
cases cover each of eight receive byte data fields, all three engine phases on
both slots, and data bits in each of eight response frames. Each is followed by
fresh index-zero/warm-up/first-scored replay on the same DUT. Default heartbeat
is checked after 13,500,005 clocks from reset release.

Both simulators replay **1,394 packets** on one simulated system: the 800 saved
oracle records, 336 directed crossing/full-range/equality/truncation records and
258 seeded full-range random records. Index-zero sessions retain physical RAM
between runs. Warm-up and steady slot swaps, index 16, multiple wraps, distinct
histories, NONE/BUY/SELL and held actions are counted in `coverage.json`.
Expected actions come from F's pinned direct-window Python model (recomputing
`sum(window)`), independently checked against every saved fixture. Coverage
inspection of direct windows never supplies expected DUT rolling-sum values.

RTL generation is repeated byte-for-byte, compared with the checked-in candidate,
and subjected to Yosys hierarchy/process/check plus exact six scalar directions
and widths; the complete nine-module hierarchy is checked. Icarus elaborates
and simulates that same production file. No Gowin resource/timing inference is
made from these checks.

To save a reproducible run (new directory recommended):

```sh
opam exec --switch=5.2.0+ox -- dune build bin/generate.exe test/integration/serial_verify.exe
PYTHONDONTWRITEBYTECODE=1 python3 test/integration/run_checks.py \
  _build/default/bin/generate.exe _build/default/test/integration/serial_verify.exe \
  /tmp/new-g2-check
```

The saved `latency.csv` measures rising-edge controller request acceptance
(`request_valid && request_ready`) to the first rising-edge observation of
`response_valid` with computed payload ready for the sequencer. Session index
zero includes idle observation/clear; other rows include both engine updates.
The endpoints are pre-edge observations, and UART synchronization/byte capture,
sequencer capture, TX serialization and USB/host overhead are excluded.
This is core latency, not official UART round-trip latency. The replay trace,
coverage and exact RTL are also saved. Failed checks exit nonzero.
