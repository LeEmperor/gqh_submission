# Phase I candidate ledger

Vendor baseline: **363 Logic / 235 Registers / 1 BSRAM**, matching preserved RTL and reports.
Selected vendor result: **302 Logic / 109 Registers / 3 BSRAM**, zero setup/hold violations. The two-BSRAM alternative is **302 / 155 / 2**. Both retain the exact heartbeat RTL.
Open-source comparison baseline: **585 LUT4+ALU / 247 DFF / 1 BSRAM**. These scales are separate.

| Candidate | Open-source logic proxy | DFF | BSRAM | Measurement status |
| --- | ---: | ---: | ---: | --- |
| I-borrow-delta17-difference-relation | 558 | 225 | 1 | open_source_screened |
| I-borrow-command | 609 | 225 | 1 | open_source_screened |
| I-borrow-delta17 | 589 | 225 | 1 | open_source_screened |
| I-borrow-command | — | — | — | invalid |
| I-borrow-difference-relation | 574 | 225 | 1 | open_source_screened |
| I-delta17 | 592 | 247 | 1 | open_source_screened |
| I-delta17-difference-relation-captured | 541 | 247 | 1 | open_source_screened |
| I-difference-relation | 563 | 247 | 1 | open_source_screened |
| I-protocol-packet-ram | 482 | 190 | 2 | open_source_screened |
| I-protocol-rx-timer | 581 | 247 | 1 | open_source_screened |
| I-protocol-tx-timer | 599 | 247 | 1 | open_source_screened |
| i1-records-parallel | — | — | — | invalid |
| i2-records-borrow | — | — | — | invalid |
| i3-records-relation | — | — | — | invalid |
| i4-records-borrow-relation | — | — | — | invalid |
| i5-records-all3 | — | — | — | invalid |
| i6-records-delta-relation | — | — | — | invalid |
| i7-records-all3-inverted | — | — | — | invalid |
| packet-arithmetic | 445 | 190 | 2 | open_source_screened |
| packet-arithmetic-borrow | 422 | 168 | 2 | open_source_screened |
| packet-arithmetic-borrow-rx | 420 | 168 | 2 | open_source_screened |
| packet-arithmetic-rx | 440 | 190 | 2 | open_source_screened |
| packet-records-arithmetic | — | — | — | invalid |
| packet-records-arithmetic-borrow | — | — | — | invalid |

Full manifests, failed reports, input hashes, settings and commands remain in the paths recorded by candidate-ledger.json.
Focused correctness, full production UART verification, physical RAM-model checks, vendor measurement and board acceptance are distinct qualifications. No global-minimum claim is made.
