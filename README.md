# tickweave TUI

A terminal operator console for **tickweave**, our FPGA trading-rule engine, built in OCaml/OxCaml with
[bonsai_term](https://github.com/janestreet/bonsai_term).

It shows:
- the order book and a liquidity heatmap
- every rule decision, with the evidence behind it
- config changes, which take effect only after the backend acknowledges them
- live render metrics

> All data is **MOCK** and labelled so on screen. Nothing shown is hardware evidence.

## Run it

Requires the OxCaml switch `5.2.0+ox`.

```sh
eval $(opam env --switch 5.2.0+ox)
dune build && dune test
dune exec -- ./tui/bin/main.exe console --mode mock --scenario enabled
```

Other scenarios: `connected_disarmed`, `blocked`, `book_invalid`, `connection_lost`, `update_ok`,
`lost_at_activate`.

## Keys

| Key | Action |
|---|---|
| `F1`–`F4` | Monitor · Decide · Configure · Demo layouts |
| `Tab` / `1`–`5` | Move focus |
| `z` | Zoom the focused panel |
| `h` / `d` | Heatmap · cumulative depth |
| `Enter` / `/` / `Space` | Inspect · filter · pause decisions |
| `c` | Review and apply a config proposal |
| `t` | Cycle theme |
| `F12` | Frame meter |
| `?` / `q` | Help · quit |

## Performance

Measured with a 1000 Hz mock stream:

| Terminal size | Stream → screen (p50) | Frame time (p99) |
|---|---|---|
| 120×36 | 2.3 ms | 6.1 ms |
| 200×60 | 3.3 ms | 9.6 ms |

Idle CPU is about 0.4%. Reproduce with:

```sh
dune exec -- ./tui/bin/main.exe console --mode mock --bench --rate 1000
```

## Layout

```
tui/        panels, layout, rendering
tui/model/  backend contracts
tui/bin/    entry point
tui/test/   324 expect tests
```

`tui/verification-phase5.md` has the full measurements and screens.
