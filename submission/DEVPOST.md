# Devpost copy and final identifiers

## Project description

Our project implements a compact FPGA-based trading-signal engine on the Tang
Nano 20K using Hardcaml. It receives price updates over UART, maintains independent
16-sample moving averages for two instruments, and generates buy/sell signals
entirely on the FPGA. A bit-serial arithmetic engine, block-RAM state storage and
compact UART transmitter reduce the selected design to 195 logic elements and
98 registers while preserving full-range unsigned 16-bit prices. We developed
independent reference-model tests, simulations and on-board validation to check
correctness, repeated sessions and reliable communication.

## Final GitHub Submission

Copy into Devpost after the final commit is pushed and verified:

```text
Repository: https://github.com/LeEmperor/gqh_submission
Final Commit SHA: <paste the full final pushed SHA here, in Devpost only>
```

The selected submission is published to `main` (and retained on `newop`). Submit
the final full commit SHA returned in the submission handoff.
Do not commit a purported self-referential final SHA into this file or the README.

Complete team/member details and every field required by the live Devpost form.
Public visibility, successful submission and board return still need confirmation.
