# Phase 5 verification

Branch `perf-latency`, on top of tag `phase5-pre-perf` (`5be0adf`): the feature-complete
Phase 4 + 5 restore point, pushed to `main`. All market, decision and latency data is
**MOCK** and is labelled so on every panel. Nothing here is hardware evidence.

## What Phase 5 delivers

- **Market:**
  - **Ladder:** a dashed amber `maximum_price` line, ±qty deltas (shown about 1.25 s, binary),
    cumulative depth on `d`, and a 60 s braille bid/ask/mid chart. The axis reads
    `stopped HH:MM:SS UTC` once the stream stops.
  - **Heatmap (`h`):**
    - **Scale:** robust, max(p95, 3×median) with γ 1.2, and white only above 1.5×.
    - **Overlays:** solid best-bid/ask lines and a ▲/✗ decision rail.
    - **Pacing:** at most 5 columns/s, labelled "N ms each".
  - **Tape:** inferred from book deltas, because the contracts carry no trades. Its title says so.
- **Metrics:**
  - **Charts:** multi-row braille charts for decision rate, admit ratio and trace loss.
  - **Latency:** a snapshot→candidate histogram with p50/p99 markers. It is a seeded
    *synthetic* distribution, titled "MOCK synthetic … not a hardware measurement".
  - **F12 frame meter:** frame work, paints, events/s and buffers.
- **Ergonomics:**
  - **Presets:** F1–F4 (Monitor / Decide / Configure / Demo). The last preset is persisted.
  - **Zoom** on `z`.
  - **Mouse:** click to focus, wheel to scroll, click a decision to inspect it.
  - **Themes** on `t`: amber, Tokyo Night, Catppuccin Mocha, with 256/16/NO_COLOR fallbacks.
  - **Layout:** responsive at ≥160×45, works at 100×30, and shows a centred resize message below that.
  - **Time:** every wall clock is UTC, labelled once in the header.
- **Phase 4 fixes:**
  - The stepper shows the pending `○ ACK v13` until the backend ACKs.
  - The dashboard config summary shows range bars.
  - The Inspector shows a placeholder that keeps its mode label.
- **Performance pass:**
  - **Rendering:** push-driven, via `Driver.send_incoming_event`, so stream updates wake the
    render loop instead of waiting for the frame timer.
  - **Throttle:** leading-edge, at most 60 paints/s.
  - **Incremental views:** each panel is its own node, and every cutoff is audited by a test
    that changes each field the view reads.
  - **Fades:** binary, driven by a single cancellable expiry timer.
  - **Polling:** rate-aware, and no polling while the stream is down.
  - **Allocation:** −57% minor words per 200×60 frame. A cell-by-cell comparison of 1223
    renders against the restore point found 0 visual differences.

## Build and tests

```
$ dune build && dune test --force
(exit 0, no output; 324 inline tests)
```
The largest module is `braille_chart.ml` at 372 lines (rule: < 400). There are no mutable globals:
the wake/throttle state is created per run.

## Latency: restore point vs perf

`bench_pty.py W H 1000 <exe>`: a 20 s MOCK stream at 1000 Hz. Each figure is the median of 3
runs, with the two builds interleaved on the same machine state (load average 8–9 from Chrome
and WindowServer).
- *Frame work* = flush + compute + paint to the tty, painted frames only.
- *Stream→paint* = from a state reaching the app to the end of the paint that shows it.

| Size | Build | Frame p50 | Frame p99 | Stream→paint p50 | Stream→paint p99 | Paints/s |
|---|---|---|---|---|---|---|
| 120×36 | restore point | 4.58 ms | 10.58 ms | 19.3 ms | 26.1 ms | 52.8 |
| 120×36 | **perf** | **2.19 ms** | **6.06 ms** | **2.3 ms** | **6.7 ms** | 47.5 |
| 200×60 | restore point | 6.33 ms | 15.40 ms | 19.2 ms | 29.2 ms | 53.2 |
| 200×60 | **perf** | **3.14 ms** | **9.60 ms** | **3.3 ms** | **9.8 ms** | 47.5 |

The p99 < 16 ms target passes at both sizes in all 6 perf runs. Maxima are noisy in **both**
builds under this load (perf: 7.6–90.8 ms; restore point: 12.7–191.8 ms). Those spikes are not
attributed. Key→paint p50 at 1000 Hz was last measured at about 11 ms by the latency agent:
stream paints take most of the 60 paint slots.

## CPU and terminal output

`cost_pty.py 200 60 15 <exe> …`: CPU% from rusage, and output bytes drained from the pty after
a 2 s warm-up.

| Case | Restore point | **Perf** | btop |
|---|---|---|---|
| live MOCK stream, 4 Hz | 7.7% · 223 KiB/s | **2.5% · 130 KiB/s** | 2.8% · 20 KiB/s (2 s refresh) |
| live MOCK stream, 60 Hz | 37.0% · 1099 KiB/s | **15.8% · 973 KiB/s** | 21.5% · 380 KiB/s (100 ms refresh) |
| idle (`connection_lost`) | 1.2% | **0.5% (15 s) · 0.4% (45 s)** | — |

Idle is steady state, not startup cost: the 45 s run is barely lower than the 15 s one. What
remains is the 1 Hz UTC header clock plus the runtime.

## Screens

Colour PNGs of every preset at 120×36 and 200×60 are outside the repo, in
`quanthacks-prep/tickweave-phase5-screens/`. Text captures follow.

**Capture note:** 2 of about 25 plain `shot.py` captures showed one duplicated Decisions row. A
variant that freezes the app (SIGSTOP) and drains the pty before reading (`tools/shot_drain.py`)
showed 0 in 10, so the duplicate is the capture reading a half-written frame, not an app defect.
Decide 200×60 below is a drained capture. The F12 numbers visible in screenshots are inflated by
the slow capture reader (and by 8 concurrent captures). The bench above is authoritative.

## Cut or known limits

- No real trade feed: the tape is inferred and the latency histogram is synthetic. Both are labelled.
- Config events carry no timestamps, so the timeline shows the backend `#sequence`.
- The tape's 60 s summary is not marked stale when the stream stops (the chart axis is).
- Mouse hit-testing uses `Layout`, not `bonsai_term_components.click_handler`.
- bonsai_term/Notty emit no synchronized-output (DEC 2026) markers, so a slow terminal can show
  a frame mid-write.

### monitor_120x36

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:16:15 UTC
╭ Market · AAPL ───────────────────────────────────────────╮╭ Heatmap · AAPL · MOCK · scale 117 u ─────────────────────╮
│ px (t) · qty (u)                                         ││ qty 0          117 u (γ1.2, white >1.5×)  ━ ask  ═ bid   │
│       qty(u) BID      px(t)│px(t) ASK       qty(u)       ││     │                                                    │
│ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ ││ 1012┤                                                    │
│   +26     26 ███       1005│ 1006 ████          30 −1    ││     │                                                    │
│   +32     32 ███▊      1004│ 1007 █████▊        43       ││     │                                                    │
│   +34     34 ████      1003│ 1008 ██████▏       46 −2    ││     │  ┏┓                                                │
│    −2     34 ████      1002│ 1009 █████▊        43 −1    ││ 1008┤  ┃┃                                                │
│    +4     29 ███▍      1001│ 1010 ████▊         36 +4    ││     │  ┃┃ ┏┓    ┏┓        ┏━┓┏━━┓                        │
│           39 ████▋     1000│ 1011 █████▉        44       ││ 1006┤  ┃┗━┛┗┓  ┏┛┃       ┏┛╗┗┛╗╔┃┏┓               ┏━┓  ┏ │
│   +11     44 █████▎     999│ 1012 ██████▌       49 +3    ││ 1005┤━━┛║╌╔═┃╌╌┃╌┃╌╌╌╌╌╌┏┛║╚═╝╚╝┗┛┃╌╌┏┓┏┓╌╌┏┓╌╌┏┓┏┛╔┗┓╌┃ │
│           41 ████▉      998│ 1013 █████████     67 +67   ││ 1004┤══╝╚═╝ ┃ ┏┛═┃      ┃╔╝     ╚╗┗┓┏┛┃┃┗━┓┃┗━━┛┗┛╔╝╚┃┏┛ │
│    +4     44 █████▎     997│ 1014 █████▊        43 +43   ││     │       ┗┓┃╝ ┗┓     ┃╝       ╚═┗┛═┗┛║ ┗┛╔═╗║╚═╝  ┗┛╝ │
│    +5     52 ██████▏    996│ 1015 ████████▊     66 +66   ││     │       ╚┃┃  ╚┃ ┏┓  ┃          ╚╝ ╚╝╚═══╝ ╚╝     ╚╝  │
│ spread 1 t   mid 1005.5 t                                ││     │        ┗┛   ┗┓┃┗┓ ┃                                │
│ imbalance -0.07 ▼                                        ││ 1000┤        ╚╝   ╚┗┛═┗━┛                                │
│ ask                               ⠐⠞⠴⡞⠲⣶⣴⠒⠲⠶⠦⠖⠔ last 60s ││     │              ╚╝ ╚═╝                                │
│ MOCK #65  updates/s 4.0                                  ││  dec┤▲▲     ▲▲▲  ▲▲✗▲▲✗✗▲       ▲ ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲  ▲▲▲  │
│                                                          ││ ← older              51 columns · 250 ms each · newest → │
╰──────────────────────────────────────────────────────────╯╰──────────────────────────────────────────────────────────╯
╭ Metrics · MOCK ────────────────────────────╮╭ Latency · MOCK synthetic ─────────╮╭ Tape · MOCK · inferred ───────────╮
│ decisions/s 4.0/s  min 0.0 · max 4.0       ││ snapshot→candidate latency, ns    ││ buy 7 · sell 3 · net +4 ██████░░░ │
│ 5┤· · · · · · · · · · · · · ·  ⢠⣤⣤⣤⣤⣤⣤⣤⣤⣤⣤ ││    ▄█╎                ╎           ││ time (UTC)   side   px(t) qty(u)  │
│  │ · · · ·  no data  · · · · · ⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿ ││    ██▄                ╎           ││ 16:16:11.666 ▲ BUY   1004      1  │
│ 0┤· · · · · · · · · · · · · · ⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿ ││   ▇███▆               ╎           ││ 16:16:08.900 ▲ BUY   1007      3  │
│ admit ratio 1.00  min 0.50 · max 1.00      ││   ██████▄             ╎           ││ 16:16:08.149 ▲ BUY   1007      2  │
│ 1┤· · · · ·  no data  · · · · ·⢸⣿⣿⢸⣿⣇ ⣿⣿⣿⣿ ││  ▅███████▇            ╎           ││ 16:16:02.610 ▼ SELL  1004      3  │
│ 0┤ · · · · · · · · · · · · · · ⢸⣿⣿⢸⣿⣿·⣿⣿⣿⣿ ││  ██████████▃▃         ╎           ││ 16:16:00.094 ▲ BUY   1007      1  │
│ trace loss/s 0.0/s  min 0.0 · max 0.0      ││ ▅████████████▇█▄▆▂▃▃▂▂▂▁▁▁▁▁ ▁ ▁▁ ││                                   │
│ 1┤· · · · · no data · · · · ·              ││ ├────┴────────────────┴─────────┤ ││                                   │
│ 0┤ · · · · · · · · · · · · · ·⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││ 188 ns p50 233  p99 366 ns 452 ns ││                                   │
│  └−60s ──────────── −30s ───────────── now ││ MOCK synthetic, seed 42:          ││                                   │
│ 60 s window · sampled 1 Hz                 ││ not a hardware measurement        ││                                   │
╰────────────────────────────────────────────╯╰───────────────────────────────────╯╰───────────────────────────────────╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ ? help  q quit            Monitor · amber · focus: Market
```

### decide_120x36

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:16:15 UTC
╭ Decisions · MOCK · all ────────────────────────────────────────────╮╭ Inspector ─────────────────────────────────────╮
│ #35   13:37:08.750 ·     no signal     ask 1006 > 1005             ││ Select a decision and press Enter to inspect   │
│ #36   13:37:09.000 ·     no signal     ask 1007 > 1005             ││ · MOCK                                         │
│ #37   13:37:09.250 ·     no signal     ask 1007 > 1005             ││                                                │
│ #38   13:37:09.500 ·     no signal     ask 1006 > 1005             ││                                                │
│ #39   13:37:09.750 ·     no signal     ask 1007 > 1005             ││                                                │
│ #40   13:37:10.000 ·     no signal     ask 1007 > 1005             ││                                                │
│ #41   13:37:10.250 ·     no signal     ask 1007 > 1005             ││                                                │
│ #42   13:37:10.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM        ││                                                │
│ #43   13:37:10.750 ·     no signal     ask 1006 > 1005             ││                                                │
│ #44   13:37:11.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #45   13:37:11.250 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM        ││                                                │
│ #46   13:37:11.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #47   13:37:11.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #48   13:37:12.000 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM        ││                                                │
│ #49   13:37:12.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #50   13:37:12.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #51   13:37:12.750 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM        ││                                                │
│ #52   13:37:13.000 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM ✓RCV   ││                                                │
│ #53   13:37:13.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV   │╰────────────────────────────────────────────────╯
│ #54   13:37:13.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM        │╭ Rules ─────────────────────────────────────────╮
│ #55   13:37:13.750 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││ ▸ #0 buy_below_limit                      ● ON │
│ #56   13:37:14.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││ ask_px ≤ maximum_price → BUY qty @ ask_px      │
│ #57   13:37:14.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM        ││ slot-0 · config v12                            │
│ #58   13:37:14.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││ maximum_price 1005 t                           │
│ #59   13:37:14.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV   ││ quantity         1 u                           │
│ #60   13:37:15.000 ·     no signal     ask 1006 > 1005             ││ matched  42 ▕███████████████████████████▏ 100% │
│ #61   13:37:15.250 ·     no signal     ask 1006 > 1005             ││ admitted 39 ▕█████████████████████████▏░▏  93% │
│ #62   13:37:15.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV   ││ blocked   3 ▕█▉░░░░░░░░░░░░░░░░░░░░░░░░░▏   7% │
│ #63   13:37:15.750 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM        ││ admit       ▕█████████████████████████▏░▏  93% │
│ #64   13:37:16.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV   ││ recent ✓✓✗✓✓✗✗✓·······✓·✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓··✓✓✓· │
│ #65   13:37:16.250 ·     no signal     ask 1006 > 1005             ││ last block: price 1000 t outside [1001, 1005]… │
│ MOCK · G live · / filter · Space pause                             ││ cfg ✓ACK v12 · MOCK                            │
╰────────────────────────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ ? help  q quit          Decide · amber · focus: Decisions
```

### configure_120x36

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:16:15 UTC
╭ Rules ───────────────────────────────────────────────────╮╭ Configuration · MOCK ────────────────────────────────────╮
│ ▸ #0 buy_below_limit                                ● ON ││ ✓ ACK v12 · engine ● ARMED                               │
│ ask_px ≤ maximum_price → BUY qty @ ask_px                ││ apply · none in flight                                   │
│ slot-0 · config v12                                      ││ preflight ✓ build ✓ base ✓ ranges ✓ engine               │
│ maximum_price 1005 t                                     ││ proposal mock-proposal-13 · base v12 → v13               │
│ quantity         1 u                                     ││ Δ maximum_price 1005→1006 · quantity 1→2                 │
│ matched  42 ▕█████████████████████████████████████▏ 100% ││ maximum_price 1005 t [995 ━━━━━━━━━━━━━━━●──────── 1010] │
│ admitted 39 ▕██████████████████████████████████▍░░▏  93% ││ quantity         1 u [1 ●──────────────────────────── 5] │
│ blocked   3 ▕██▋░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏   7% ││ manifest m01 · MOCK logical C0 · 1 compiled rule         │
│ admit       ▕██████████████████████████████████▍░░▏  93% ││ events · none yet                                        │
│ recent ····✓✓✓··✓✓✗✓✓✗✗✓········✓·✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓··✓✓✓· ││                                                          │
│ last block: price 1000 t outside [1001, 1005] t          ││                                                          │
│ blocked by reason · this rule's last 65 decisions        ││                                                          │
│    3× price 1000 t outside [1001, 1005] t                ││                                                          │
│ cfg ✓ACK v12 · MOCK                                      ││                                                          │
│                                                          ││                                                          │
│                                                          ││                                                          │
│                                                          ││                                                          │
│                                                          ││ c review / apply                                         │
╰──────────────────────────────────────────────────────────╯╰──────────────────────────────────────────────────────────╯
╭ Decisions · MOCK · all ──────────────────────────────────────────────────────────────────────────────────────────────╮
│ #55   13:37:13.750 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #56   13:37:14.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #57   13:37:14.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM       v12                                                │
│ #58   13:37:14.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #59   13:37:14.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #60   13:37:15.000 ·     no signal     ask 1006 > 1005            v12                                                │
│ #61   13:37:15.250 ·     no signal     ask 1006 > 1005            v12                                                │
│ #62   13:37:15.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #63   13:37:15.750 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM       v12                                                │
│ #64   13:37:16.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms                                        │
│ #65   13:37:16.250 ·     no signal     ask 1006 > 1005            v12                                                │
│ MOCK · G live · / filter · Space pause                                                                               │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ ? help  q quit           Configure · amber · focus: Rules
```

### demo_120x36

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:16:15 UTC
╭ Market · AAPL ───────────────────────────────────────────╮╭ Rules ───────────────────────────────────────────────────╮
│ px (t) · qty (u)                                         ││ ▸ #0 buy_below_limit                                ● ON │
│       qty(u) BID      px(t)│px(t) ASK       qty(u)       ││ ask_px ≤ maximum_price → BUY qty @ ask_px                │
│ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ ││ maximum_price 1005 t  quantity 1 u                       │
│   +26     26 ███       1005│ 1006 ████          30 −1    ││ matched 42  admitted 39  blocked 3                       │
│   +32     32 ███▊      1004│ 1007 █████▊        43       ││ last block: price 1000 t outside [1001, 1005] t          │
│   +34     34 ████      1003│ 1008 ██████▏       46 −2    ││ cfg ✓ACK v12 · MOCK                                      │
│    −2     34 ████      1002│ 1009 █████▊        43 −1    │╰──────────────────────────────────────────────────────────╯
│    +4     29 ███▍      1001│ 1010 ████▊         36 +4    │╭ Inspector ───────────────────────────────────────────────╮
│           39 ████▋     1000│ 1011 █████▉        44       ││ Select a decision and press Enter to inspect · MOCK      │
│           44 █████▎     999│ 1012 ██████▌       49 +3    ││                                                          │
│           41 ████▉      998│ 1013 █████████     67 +67   ││                                                          │
│ spread 1 t   mid 1005.5 t                                ││                                                          │
│ imbalance -0.07 ▼                                        ││                                                          │
│ ask                               ⠐⠾⢴⠞⢢⢦⣴⠒⠢⠦⠶⠶⠆ last 60s ││                                                          │
│ MOCK #65  updates/s 3.0                                  ││                                                          │
╰──────────────────────────────────────────────────────────╯│                                                          │
╭ Decisions · MOCK · all ──────────────────────────────────╮│                                                          │
│ #60   13:37:15.000 ·     no signal                       │╰──────────────────────────────────────────────────────────╯
│ #61   13:37:15.250 ·     no signal                       │╭ Configuration · MOCK ────────────────────────────────────╮
│ #62   13:37:15.500 MATCH BUY 1 @1005 ✓ADM ✓RCV           ││ ✓ ACK v12 · engine ● ARMED                               │
│ #63   13:37:15.750 MATCH BUY 1 @1003 ✓ADM                ││ apply · none in flight                                   │
│ #64   13:37:16.000 MATCH BUY 1 @1004 ✓ADM ✓RCV           ││ preflight ✓ build ✓ base ✓ ranges ✓ engine               │
│ #65   13:37:16.250 ·     no signal                       ││ proposal mock-proposal-13 · base v12 → v13               │
│ MOCK · G live · / filter · Space pause                   ││ maximum_price 1005 t [995 ━━━━━━━━━━━━━━━●──────── 1010] │
╰──────────────────────────────────────────────────────────╯│ quantity         1 u [1 ●──────────────────────────── 5] │
╭ Metrics · MOCK ──────────────────────────────────────────╮│ c review / apply                                         │
│ decisions/s  4.0/s · no data · ⡖⠒⠒⠒⠒ min 0.0 · max 4.0   │╰──────────────────────────────────────────────────────────╯
│ admit ratio   1.00 · no data · ⠉⠉⠓⠉⠉ min 0.50 · max 1.00 │╭ Latency · MOCK synthetic ────────────────────────────────╮
│ trace loss/s 0.0/s · no data · ⣀⣀⣀⣀⣀ min 0.0 · max 0.0   ││ snapshot→candidate latency, ns · n=2000 · p50 233 ns     │
│                   └−60s ──────── now min · max           ││ ▁▂▄▄▆█▆█▇│▄▆▅▄▄▄▃▂▂▂▁▂▂▁▂▁▁▁▁▁▁▁▁▁▁▁▁│▁▁▁▁▁▁▁▁▁  ▁▁  ▁▁▁ │
│ 60 s window · sampled 1 Hz                               ││ 188 ns   p50 233 ns                  p99 366 ns   452 ns │
│ admit ratio = admitted ÷ (admitted + blocked)            ││ MOCK synthetic, seed 42: not a hardware measurement      │
╰──────────────────────────────────────────────────────────╯╰──────────────────────────────────────────────────────────╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ ? help  q quit               Demo · amber · focus: Market
```

### monitor_200x60

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:16:51 UTC
╭ Market · AAPL ───────────────────────────────────────────────────────────────╮╭ Heatmap · AAPL · MOCK · scale 129 u ─────────────────────────────────────────────────────────────────────────────────╮
│ px (t) · qty (u)                                                             ││ qty 0          129 u = max(p95, 3×median), γ1.2; white above 1.5×  ━ ask  ═ bid  ▲ admitted  ✗ blocked               │
│       qty(u) BID                px(t)│px(t) ASK                 qty(u)       ││     │                                                                                                                │
│ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ ││     │                                                                                                                │
│   +29     29 ████████            1006│ 1007 ████████████▎           42 −1    ││     │                                                                                                                │
│    +2     28 ███████▊            1005│ 1008 █████████████▍          46       ││ 1016┤                                                                                                                │
│    −2     30 ████████▎           1004│ 1009 ████████████▌           43       ││     │                                                                                                                │
│    −1     33 █████████▏          1003│ 1010 ██████████▌             36       ││     │                                                                                                                │
│    −2     34 █████████▍          1002│ 1011 ███████████             38 −6    ││     │                                                                                                                │
│    +4     33 █████████▏          1001│ 1012 ███████████████▏        52 +3    ││ 1012┤                                                                                                                │
│    +2     33 █████████▏          1000│ 1013 █████████████████▏      59 −4    ││     │                                                                                                                │
│    +5     49 █████████████▌       999│ 1014 ████████████▊           44 +1    ││     │                                                                                                                │
│           41 ███████████▎         998│ 1015 ███████████████████     65 −1    ││     │                                                           ┏┓                                                   │
│    −2     47 █████████████        997│ 1016 ███████████████████     65 +3    ││ 1008┤                                                ┏┓         ┃┃                                                   │
│ spread 1 t   mid 1006.5 t                                                    ││ 1007┤                                              ┏━┛┃         ┃┃ ┏┓    ┏┓        ┏━┓┏━━┓                        ┏━ │
│ imbalance -0.18 ▼                                                            ││ 1006┤                                              ┃╔╗┃  ┏┓  ┏┓ ┃┗━┛┗┓  ┏┛┃       ┏┛╗┗┛╗╔┃┏┓               ┏━┓  ┏━┛═ │
│    t ask 1007  bid 1006  mid 1006.5 ┄  ╌ maximum_price 1005 t                ││ 1005┤                                          ━━━┓┃║╚┃╌╌┃┗┓╌┃┗━┛║╌╔═┃╌╌┃╌┃╌╌╌╌╌╌┏┛║╚═╝╚╝┗┛┃╌╌┏┓┏┓╌╌┏┓╌╌┏┓┏┛╔┗┓╌┃═╝╌ │
│     │                                                                        ││ 1004┤                                           ╔═┃┃╝ ┃┏┓┃ ┃ ┃══╝╚═╝ ┃ ┏┛═┃      ┃╔╝     ╚╗┗┓┏┛┃┃┗━┓┃┗━━┛┗┛╔╝╚┃┏┛    │
│ 1008┤                                                    ⣤                   ││     │                                          ═╝ ┗┛  ┗┛┗┛╗┃┏┛       ┗┓┃╝ ┗┓     ┃╝       ╚═┗┛═┗┛║ ┗┛╔═╗║╚═╝  ┗┛╝    │
│     │                                                    ⣿                   ││     │                                             ╚╝  ╚╝╚╝╚┃┃╝       ╚┃┃  ╚┃ ┏┓  ┃          ╚╝ ╚╝╚═══╝ ╚╝     ╚╝     │
│     │                                                   ⢸⣽   ⣿ ⣿  ⣿⡏⡇      ⡏ ││     │                                                      ┗┛         ┗┛   ┗┓┃┗┓ ┃                                   │
│     │                                                   ⢸⣿⣶ ⢰⡟⣶⢻ ⢰⣿⣷⣷    ⣶⢰⡗ ││ 1000┤                                                      ╚╝         ╚╝   ╚┗┛═┗━┛                                   │
│ 1005┤⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤ ⠤⣼⣽⡿⣤⠼⡧⣿⢿ ⢼⡿⠽⣿⠤ ⣤ ⡿⣼⠧ ││     │                                                                       ╚╝ ╚═╝                                   │
│     │                                                   ⣿⣿⡇⣿⠂⡇⣿⢸ ⢸⡇ ⣿  ⣿ ⡇⣿  ││     │                                                                                                                │
│ 1004┤                                                  ⠈⣿⢹⠇⣿⠉⠁⣿⢹ ⢸⠁ ⣿⣿⡏⡍⡍⡏⣿  ││     │                                                                                                                │
│     │                                                   ⣿⠘⢲⣿  ⣿⢸ ⢸  ⢻⣿⡇⢳⣷⠃⣿  ││  996┤                                                                                                                │
│ 1002┤                                                   ⠿ ⠸⠼  ⣿⢸⣤⢸  ⠸⠿⠤⠼⠿ ⠿  ││     │                                                                                                                │
│     │                                                         ⣿⢸⣿⣸           ││     │                                                                                                                │
│     │                                                         ⣿⢸⠇⣿           ││     │                                                                                                                │
│ 1000┤                                                         ⠛⠘⠒⣿           ││  992┤                                                                                                                │
│     │                                                            ⠿           ││     │                                                                                                                │
│      −60 s────────────────────────────−30 s──────────────────────────────now ││  dec┤                                           ▲▲▲   ▲▲▲ ▲▲▲ ▲▲     ▲▲▲  ▲▲✗▲▲✗✗▲       ▲ ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲  ▲▲▲     │
│ MOCK #68  updates/s 4.0                                                      ││ ← older                                                                          69 columns · 250 ms each · newest → │
╰──────────────────────────────────────────────────────────────────────────────╯╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭ Metrics · MOCK ──────────────────────────────────────────────────────────╮╭ Latency · MOCK synthetic ──────────────────────────────────╮╭ Tape · MOCK · inferred from book deltas ───────────────────╮
│ decisions/s      4.0/s  admit ratio       1.00  trace loss/s       0.0/s ││ snapshot→candidate latency, ns · n=2000 · p50 233 ns       ││ 60 s: 6 prints · buy 8 u · sell 3 u · net +5 u ████████░░░ │
│ min 2.8 · max 4.1       min 0.50 · max 1.00     min 0.0 · max 0.0        ││        █ ╎                             ╎                   ││ time (UTC)    side    px(t)  qty(u) size                   │
│   5┤· · · · · ·           1┤· · · · · · ⢸⣿⢸⡇⣿⣿    1┤· · · · · · ·        ││        █ ╎                             ╎                   ││ 16:16:51.789  ▲ BUY    1007       1 ███████                │
│    │ · · · · · ·           │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││      ▃ █ ╎                             ╎                   ││ 16:16:47.507  ▲ BUY    1004       1 ███████                │
│    │· · · · · ·            │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││      █ █ ╎                             ╎                   ││ 16:16:44.734  ▲ BUY    1007       3 █████████████████████  │
│    │ · · · · · · ⣤⣤⣤⣶⣠     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││      █ █ ╎                             ╎                   ││ 16:16:43.974  ▲ BUY    1007       2 ██████████████         │
│    │· · · · · ·  ⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││      █▇█▄▅                             ╎                   ││ 16:16:38.431  ▼ SELL   1004       3 █████████████████████  │
│    │ · · · · · · ⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││      █████▄                            ╎                   ││ 16:16:35.916  ▲ BUY    1007       1 ███████                │
│    │· · · · · ·  ⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││      ██████ ▂                          ╎                   ││                                                            │
│    │ · · · · · ·⢀⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││    █▄██████▆█                          ╎                   ││                                                            │
│ 2.5┤· no data · ⢸⣿⣿⣿⣿⣿  0.5┤· no data · ⢸⣿⢸⡇⣿⣿  0.5┤·  no data  ·        ││    ██████████ ▂                        ╎                   ││                                                            │
│    │ · · · · · ·⢸⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││    ██████████▂█ ▄                      ╎                   ││                                                            │
│    │· · · · · · ⢸⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││    ██████████████                      ╎                   ││                                                            │
│    │ · · · · · ·⢸⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││   ▂██████████████                      ╎                   ││                                                            │
│    │· · · · · · ⢸⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││   ███████████████ ▂                    ╎                   ││                      ╭ Frame meter ───────────────────────╮│
│    │ · · · · · ·⢸⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││   █████████████████▄                   ╎                   ││                      │ frame work: flush+compute+paint    ││
│    │· · · · · · ⢸⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││  ▃██████████████████▅▄▇▂ ▇             ╎                   ││                      │ last 7.9 · avg 8.4 ms              ││
│    │ · · · · · ·⢸⣿⣿⣿⣿⣿     │ · · · · · ·⢸⣿⢸⡇⣿⣿     │ · · · · · · ·       ││  ███████████████████████ █▄▁ ▅    ▁    ╎                   ││                      │ p50 4.7 · p99 40.3 · max 40.3 ms   ││
│    │· · · · · · ⢸⣿⣿⣿⣿⣿     │· · · · · · ⢸⣿⢸⡇⣿⣿     │· · · · · · ·        ││ ██████████████████████████████▅▂█▂█▄▃▄▂▃▂▁ ▂▃▁ ▂▁  ▂   ▁▁▂ ││                      │ ██████████ p99 over budget (16 ms) ││
│   0┤ · · · · · ·⢸⣿⣿⣿⣿⣿    0┤ · · · · · ·⢸⣿⢸⡇⣿⣿    0┤ · · · · · · ·⣀⣀⣀⣀⣀⣀ ││ ├────────┴─────────────────────────────┴─────────────────┤ ││                      │ stream events 3/s                  ││
│    └−60s ───────── now     └−60s ───────── now     └−60s ── −30s ─── now ││ 188 ns   p50 233 ns                    p99 366 ns   452 ns ││                      │ paints 88 · coalesced events 0     ││
│ 60 s window · sampled 1 Hz                                               ││ MOCK synthetic, seed 42: not a hardware measurement        ││                      │ decisions 65 · config events 0     ││
╰──────────────────────────────────────────────────────────────────────────╯╰────────────────────────────────────────────────────────────╯╰──────────────────────╰────────────────────────────────────╯╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ t theme  h/d market  c config │ ? help  q quit │ MOCK stream                                              Monitor · amber · focus: Market
```

### decide_200x60

```
tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0 │ 16:18:25 UTC
╭ Decisions · MOCK · all ──────────────────────────────────────────────────────────────╮╭ Inspector ─────────────────────────────────────────────────╮╭ Rules ─────────────────────────────────────────╮
│ #11   13:37:02.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││ Select a decision and press Enter to inspect · MOCK        ││ ▸ #0 buy_below_limit                      ● ON │
│ #12   13:37:03.000 MATCH BUY 1 @1001   ask 1001 ≤ 1005 ✓ADM       v12                ││                                                            ││ ask_px ≤ maximum_price → BUY qty @ ask_px      │
│ #13   13:37:03.250 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││ slot-0 · config v12                            │
│ #14   13:37:03.500 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││ maximum_price 1005 t                           │
│ #15   13:37:03.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM       v12                ││                                                            ││ quantity         1 u                           │
│ #16   13:37:04.000 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││ matched  42 ▕███████████████████████████▏ 100% │
│ #17   13:37:04.250 ·     no signal     ask 1009 > 1005            v12                ││                                                            ││ admitted 39 ▕█████████████████████████▏░▏  93% │
│ #18   13:37:04.500 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││ blocked   3 ▕█▉░░░░░░░░░░░░░░░░░░░░░░░░░▏   7% │
│ #19   13:37:04.750 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││ admit       ▕█████████████████████████▏░▏  93% │
│ #20   13:37:05.000 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││ recent ✓✓✗✓✓✗✗✓·······✓·✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓··✓✓✓· │
│ #21   13:37:05.250 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││ last block: price 1000 t outside [1001, 1005]… │
│ #22   13:37:05.500 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││ blocked by reason · this rule's last 65 decis… │
│ #23   13:37:05.750 MATCH BUY 1 @1001   ask 1001 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││    3× price 1000 t outside [1001, 1005] t      │
│ #24   13:37:06.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM       v12                ││                                                            ││ cfg ✓ACK v12 · MOCK                            │
│ #25   13:37:06.250 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #26   13:37:06.500 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #27   13:37:06.750 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #28   13:37:07.000 MATCH BUY 1 @1001   ask 1001 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #29   13:37:07.250 MATCH BUY 1 @1000   ask 1000 ≤ 1005 ✗BLK price v12                ││                                                            ││                                                │
│ #30   13:37:07.500 MATCH BUY 1 @1002   ask 1002 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #31   13:37:07.750 MATCH BUY 1 @1001   ask 1001 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #32   13:37:08.000 MATCH BUY 1 @1000   ask 1000 ≤ 1005 ✗BLK price v12                ││                                                            ││                                                │
│ #33   13:37:08.250 MATCH BUY 1 @1000   ask 1000 ≤ 1005 ✗BLK price v12                ││                                                            ││                                                │
│ #34   13:37:08.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #35   13:37:08.750 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #36   13:37:09.000 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #37   13:37:09.250 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #38   13:37:09.500 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #39   13:37:09.750 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #40   13:37:10.000 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #41   13:37:10.250 ·     no signal     ask 1007 > 1005            v12                ││                                                            ││                                                │
│ #42   13:37:10.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #43   13:37:10.750 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #44   13:37:11.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #45   13:37:11.250 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #46   13:37:11.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #47   13:37:11.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #48   13:37:12.000 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #49   13:37:12.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #50   13:37:12.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #51   13:37:12.750 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #52   13:37:13.000 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #53   13:37:13.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #54   13:37:13.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #55   13:37:13.750 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #56   13:37:14.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #57   13:37:14.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #58   13:37:14.500 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #59   13:37:14.750 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #60   13:37:15.000 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #61   13:37:15.250 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ #62   13:37:15.500 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #63   13:37:15.750 MATCH BUY 1 @1003   ask 1003 ≤ 1005 ✓ADM       v12                ││                                                            ││                                                │
│ #64   13:37:16.000 MATCH BUY 1 @1004   ask 1004 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms        ││                                                            ││                                                │
│ #65   13:37:16.250 ·     no signal     ask 1006 > 1005            v12                ││                                                            ││                                                │
│ MOCK · G live · / filter · Space pause                                               ││                                                            ││                                                │
╰──────────────────────────────────────────────────────────────────────────────────────╯╰────────────────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯
Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ F12 meter │ t theme  h/d market  c config │ ? help  q quit │ j/k Enter / Space G                                    Decide · amber · focus: Decisions
```

### too_small_90x26

```
tickweave ▸ MOCK UP │ b m01 │ r demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ loss 0











                                Resize to at least 100×30
                               now 90×26 · ? help · q quit











Tab/⇧Tab focus  1–5 panel │ ? help  q quit                 Monitor · amber · focus: Market
```

## Files changed since Phase 3 (`fb13adc`)

```
 86 files changed, 12947 insertions(+), 570 deletions(-)
A tui/age_deque.ml
A tui/ake.ml
A tui/anim_clock.ml
M tui/app.ml
M tui/backend_intf.ml
A tui/bench.ml
M tui/bin/main.ml
A tui/braille_chart.ml
A tui/clock_text.ml
M tui/config_review.ml
A tui/config_review_state.ml
A tui/config_stepper.ml
A tui/config_version.ml
A tui/debug_overlay.ml
M tui/decision_row.ml
M tui/dune
A tui/fade.ml
M tui/footer.ml
A tui/frame_meter.ml
A tui/heatmap.ml
M tui/help_overlay.ml
M tui/history_panel.ml
M tui/history_state.ml
M tui/inspector.ml
M tui/keymap.ml
A tui/latency_panel.ml
A tui/layout.ml
A tui/live_poll.ml
A tui/market_chart.ml
A tui/market_heat_paint.ml
M tui/market_motion.ml
M tui/market_panel.ml
A tui/market_walk.ml
A tui/metrics_panel.ml
A tui/metrics_state.ml
A tui/mock_apply.ml
M tui/mock_backend.ml
M tui/mock_backend.mli
A tui/model/config_contract.ml
M tui/model/contracts.ml
A tui/paint_throttle.ml
M tui/panel.ml
A tui/panel_views.ml
A tui/presets.ml
M tui/rules_panel.ml
A tui/runner.ml
A tui/runs.ml
M tui/sparkline.ml
M tui/status_bar.ml
A tui/tape_panel.ml
A tui/test/backend_lifecycle_tests.ml
A tui/test/charts_tests.ml
A tui/test/config_contract_tests.ml
A tui/test/config_integration_tests.ml
A tui/test/config_review_tests.ml
A tui/test/config_stepper_tests.ml
A tui/test/config_version_tests.ml
A tui/test/foundation_tests.ml
M tui/test/history_revision_tests.ml
M tui/test/history_tests.ml
M tui/test/inspector_filter_tests.ml
A tui/test/latency_tests.ml
A tui/test/layout_tests.ml
A tui/test/market_heat_tests.ml
M tui/test/market_rules_tests.ml
A tui/test/market_visuals_tests.ml
A tui/test/metrics_tests.ml
A tui/test/perf_wiring_tests.ml
M tui/test/phase2_fix_tests.ml
A tui/test/phase4-terminal-lost_at_activate-applying.txt
A tui/test/phase4-terminal-lost_at_activate-result.txt
A tui/test/phase4-terminal-lost_at_activate-unknown.txt
A tui/test/phase4-terminal-results.json
A tui/test/phase4-terminal-update_ok-applying.txt
A tui/test/phase4-terminal-update_ok-inspector.txt
A tui/test/phase4-terminal-update_ok-result.txt
A tui/test/phase4_fix_tests.ml
A tui/test/phase4_terminal_check.py
A tui/test/phase5_fix_tests.ml
A tui/test/phase5_shell_tests.ml
M tui/test/shell_tests.ml
A tui/test/view_cost_tests.ml
M tui/theme.ml
A tui/ui_types.ml
A tui/verification-phase4.md
A tui/wake.ml
```
