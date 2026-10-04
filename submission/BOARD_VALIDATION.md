# Final board validation

**User-confirmed full suite PASS**, October 4, 2026, for the selected serial-adder
design. The operator explicitly confirmed "Full suite passed" during submission
preparation. Programming is operator-confirmed, not a device readback.

Image: `bitstream/gqh_serial.fs`, SHA-256
`a26f7ec1900b6cde817a8df396610a7a3e58f9b262331652e326bf5f1e892fa0`.

Saved run: `board-serial195-20261004-074904-7xcoryuz`, UART `/dev/ttyUSB1`.
Its preserved snapshot is in [board/](board/).

## Saved machine results

- Fresh startup: correct response, no extra bytes.
- Quick: PASS, 21 responses.
- Five normal/full-range pairs: 100 complete responses per run, 84/84 scored
  packets, 168/168 actions, correct warm-up bytes, no timeouts.
- No reset or reprogramming between each normal/full-range pair.
- Custom replay and custom-after-reset: **2,834/2,834 packets**, 26 sessions,
  zero mismatch/short/timeout, no unsolicited or trailing bytes.
- Legal byte pauses and populated-history/partial-request reset: PASS.

| Run | Normal mean RTT (ms) | Full-range mean RTT (ms) |
| --- | ---: | ---: |
| 1 | 16.7952571 | 16.8220343 |
| 2 | 16.8228771 | 16.8120023 |
| 3 | 16.7965579 | 16.8059398 |
| 4 | 16.8146550 | 16.8111103 |
| 5 | 16.8656702 | 16.8035815 |
| Median of run means | **16.8146550** | **16.8111103** |

The snapshot available at review does not yet contain final busy/framing-fault
stages or a machine-written `pass_all: true`. Full-suite completion beyond its
recorded stages is **user-reported**. The raw summary is preserved unchanged;
it has not been rewritten to manufacture a PASS. Local latency and resource
results do not constitute the judges' official qualification or placement.
