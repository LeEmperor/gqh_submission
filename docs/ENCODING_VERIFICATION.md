# Actual Databento packet encoding check

Verified October 2, 2026 in `/home/srijan/tickweave`, on branch `codex/databento-streamer`.

**Result: all 10 recorded request packets conform to the GQH eight-byte request format.**

Inputs were the operator's historical Databento capture, `results/historical-trades.csv`, and dry-run log, `results/historical-1790990203.csv`. The capture contains 605 trades (572 AAPL, 33 MSFT), which produce 10 fresh pairs. The other 585 updates were superseded by a later update of the same symbol before the next pair was ready.

## Checks and evidence

The standalone external OCaml validator independently reconstructed the requests from the capture. A second audit, `docs/verify_encoding.ml`, decoded the logged hexadecimal bytes directly using only the OCaml standard library. It does not import the streamer's encoder, decoder, or pairing implementation.

For every packet, the second audit checked:

- Exactly eight bytes, represented by 16 hexadecimal characters.
- Unsigned index and prices decoded with the high byte first.
- Field positions: index at bytes 0–1, item 1 at byte 2, price 1 at bytes 3–4, item 2 at byte 5, price 2 at bytes 6–7.
- Item IDs 17 (`0x11`) and 34 (`0x22`), one of each.
- Consecutive indices 0–9 and decoded fields matching logged fields.
- Exact integer price conversion with quantum 10,000,000 nanodollars per wire unit.
- Both symbols updated since the previous packet; the latest pending update was selected for each.
- Selected source prices and event timestamps matching the capture.
- Agreement with the external validator's prices and indices.

The external validator alternates item slots; this recorded run keeps AAPL first. Both layouts are permitted by the guide. The comparison matches prices by item identity, while the byte audit checks the actual logged slot order.

A deliberately corrupted copy, with the first AAPL price's bytes swapped, failed the audit at packet zero. Original input files were preserved.

Full per-packet output: `results/encoding-audit.txt`. Independent capture report: `results/encoding-capture-report.json`. Reconstructed requests: `results/encoding-expected.csv`. These local result files are ignored by Git.

## First packet

```text
00 00 | 11 | 81 12 | 22 | CA 5D
index | A  | price | B  | price
```

| Field | Bytes | Decoded value |
| --- | --- | --- |
| Index | `00 00` | 0 |
| AAPL item | `11` | 17 |
| AAPL price | `81 12` | 33042 cents = $330.42 |
| MSFT item | `22` | 34 |
| MSFT price | `CA 5D` | 51805 cents = $518.05 |

The chosen conversion is `floor(nanodollars / 10000000)`. Packet 6 demonstrates a fractional-cent input: AAPL $330.435 becomes 33043 and MSFT $518.275 becomes 51827. The guide specifies unsigned 16-bit price fields; cents are this project's configured unit. Prices above $655.35 cannot fit with that quantum and are rejected. Timestamps and symbol names stay in the host log; the guide's wire packet contains item IDs and prices.

## Repeat the check

Use new output paths if the external validator's output files already exist.

```bash
cd /home/srijan/tickweave
opam exec -- dune exec --root external/databento_audit ./databento_audit.exe -- validate \
  --input /home/srijan/tickweave/results/historical-trades.csv \
  --symbol-a AAPL --symbol-b MSFT \
  --report /home/srijan/tickweave/results/encoding-recheck-report.json \
  --requests-out /home/srijan/tickweave/results/encoding-recheck-expected.csv
opam exec -- ocaml docs/verify_encoding.ml \
  results/historical-1790990203.csv \
  results/historical-trades.csv \
  results/encoding-recheck-expected.csv
```

The second audit is scoped to a single complete captured session with single-line CSV records, as in this run. It requires capture, log, and independent request counts to match and rejects empty logs. The production reader and external validator support more general CSV records.

## Physical UART check

This run used `dry-run`. It verifies the prepared packet bytes. Electrical UART framing at 115200 baud, 8 data bits, no parity, one stop bit, and the FPGA's actual receipt require a physical serial run. The streamer's serial configuration and transport tests were checked separately in `docs/TEST_RESULTS.md`.

Specification: `/mnt/c/Users/srija/Downloads/GQH_Hardware_Track_Participant_Guide.pdf`, supported by the host streaming section of `/mnt/c/Users/srija/Downloads/GQH_Team_Execution_Plan.md`.
