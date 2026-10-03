# Python test-data factory

Beginner 1's deliverable from the October 2 plan: reproducible request sequences and independently calculated expected responses. Requires Python 3.11 or later, using only its standard library. No API key or FPGA is needed.

The existing OCaml streamer remains the transport system. This directory supplies Python test data and offline checks. The serial replay-and-measure runner is Beginner 2's handoff.

## Run the checks

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/run_checks.py
```

This runs the Python unit tests, verifies the saved fixture hashes/answers, regenerates the entire seed-42 suite byte for byte, and compares all 800 generated packets with the existing OCaml mock. The OCaml comparison requires the project's existing `opam`/Dune environment. It uses temporary files and makes no Databento requests.

For a Python-only machine:

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/run_checks.py --python-only
```

## Reproduce or customize

Output directories must be new; existing fixtures are preserved.

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/factory.py \
  --output-dir "results/python-fixtures-$(date +%s%N)" \
  --scenario all --seed 42 --packets 100
```

To produce just the first assignment:

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/factory.py \
  --output-dir "results/constant-fixtures-$(date +%s%N)" \
  --scenario constant --seed 42 --packets 100
python3 tools/test_data_factory/factory.py \
  --output-dir "results/swapped-fixtures-$(date +%s%N)" \
  --scenario constant_swapped --seed 42 --packets 100
```

All scenarios use consecutive indices starting at zero. `--packets` accepts 1–65536; the supplied fixtures use 100. Use at least 20 packets to include the directed crossing sequence, and more than 64 to exercise both ramp directions. A scenario selection always creates `OUTPUT/<scenario>/`, so paths have the same shape as `--scenario all`.

## Saved scenarios

| Scenario | Coverage |
| --- | --- |
| `constant` | A=100, B=200, all actions NONE, A first |
| `constant_swapped` | Same prices, B first on odd indices, all actions NONE |
| `rising_falling` | A rises while B falls, then directions reverse; alternating slots |
| `crossings` | 16 constant samples, BUY/SELL, held actions, reversed crossings; alternating slots |
| `boundaries` | Zero, 65535, 1 and 65534, large jumps and maximum sums |
| `random` | Recorded seed drives unsigned 16-bit prices and slot order |
| `repeated_sessions` | One continuous fixture with two sessions: crossings followed by constant prices; indices restart at 0 |

There are seven scenario directories, eight 100-request sessions, and 800 records. Each directory contains:

- `fixture.jsonl`: one record per request, in session and index order.
- `metadata.json`: format version, scenario settings, seed, window size, item/action IDs, packet/session counts, and SHA-256 hashes of the data files.
- `requests-session-N.csv`: raw integer requests accepted by the OCaml streamer's `--source requests` option.

Example record:

```json
{"session":0,"index":0,"request_hex":"00001100642200c8","expected_response_hex":"0000110022000000"}
```

The hexadecimal strings contain exactly eight bytes each. All multibyte fields are big-endian. Responses echo index and slot order, with two reserved zero bytes. Prices are wire integers; no Databento currency conversion applies to these fixtures.

## Independent model

`model.py` stores each item's last 16 prices in a Python list. It calls `sum()` directly for both the old and incoming windows, floors the averages with `// 16`, and compares the previous and current prices according to the guide. It keeps no rolling-sum state. Each item's held action follows its ID through slot swaps.

Index zero clears both windows and actions. Indices 0–15 return NONE. Generation of `repeated_sessions` retains the same model instance across both sessions, so its second session tests an index-zero reset after nonzero actions and different price history.

The tests also use a separate complete-history implementation to calculate answers for all generated records and 2,000 random requests. Hand calculations cover the equality and floor boundaries: sixteen 100s followed by 99 returns NONE because the incoming average is 99; followed by 98 returns SELL.

## Hand-checked examples

The initial 100-request constant and alternating-slot sessions were reviewed before generating the crossing/random suite. Every constant response is NONE. Representative vectors:

| Scenario / index | Request hex | Expected response hex | Actions by item |
| --- | --- | --- | --- |
| constant / 0 | `00001100642200c8` | `0000110022000000` | A NONE, B NONE |
| constant_swapped / 1 | `00012200c8110064` | `0001220011000000` | A NONE, B NONE |
| crossings / 16 | `00101100662200c6` | `0010110222010000` | A BUY, B SELL |
| crossings / 17 | `00112200c5110067` | `0011220111020000` | A BUY, B SELL held |
| crossings / 18 | `00121100632200c9` | `0012110122020000` | A SELL, B BUY |
| crossings / 19 | `00132200ca110062` | `0013220211010000` | A SELL, B BUY held |

At index 16, A's old average is 100 and its new average is `1602 // 16 = 100`, so 102 triggers BUY. B's old average is 200 and its new average is `3198 // 16 = 199`, so 198 triggers SELL. At index 18, A's old/new averages are 100 and B's are 199; the incoming prices 99/201 reverse the actions. The odd-index examples demonstrate that responses follow the transmitted slot order.

## Replay one saved fixture in OCaml

```bash
cd /home/srijan/tickweave
opam exec -- dune exec tickweave-stream -- \
  --source requests \
  --input tools/test_data_factory/fixtures/crossings/requests-session-0.csv \
  --packets 100 --transport mock \
  --output "results/python-crossings-mock-$(date +%s%N).csv"
```

To compare all response bytes directly with the Python oracle:

```bash
cd /home/srijan/tickweave
python3 tools/test_data_factory/check_ocaml.py \
  --fixtures-dir tools/test_data_factory/fixtures
```

The comparison uses a fresh mock connection for each fixture session. The Python model's tests cover continuous sessions and resets; this comparison does not establish a physical same-connection reset. The mock also does not verify electrical UART timing or board correctness. Measurements from these tools are custom development results; official organizer scripts remain the scoring-style validation.

## Handoff to the replay runner

Read `metadata.json` first. Send each record's decoded `request_hex` and compare all eight bytes with `expected_response_hex`. Retain one transport connection while advancing through both sessions in `repeated_sessions/fixture.jsonl`; its index-zero record marks the new session. The `session` field is host metadata and is not sent on the wire. Keep metadata with results so the seed and generation settings remain traceable.

Request format: index(2), slot 1 ID(1), slot 1 price(2), slot 2 ID(1), slot 2 price(2). Response format: index(2), slot 1 ID(1), slot 1 action(1), slot 2 ID(1), slot 2 action(1), reserved zeros(2). IDs A=17/B=34; actions NONE=0/SELL=1/BUY=2.
