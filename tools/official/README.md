# Pinned organizer inputs

Copied unchanged on October 2, 2026 from the clean local reference checkout
`/home/wayne/devel/jane/GQH-Hardware-Track-Submission`, upstream
https://github.com/ShayanNazir/GQH-Hardware-Track-Submission at revision
`80467b5d0e481373daf126de9a0f57e67f19906b`. HEAD and relevant file status were
checked before copying. The source paths below are relative to that checkout.

| Source | Project copy | SHA-256 |
| --- | --- | --- |
| `participant-resources/19_tang_nano_20k.cst` | `constraints/19_tang_nano_20k.cst` | `2ac1e8bc9e282f8000a94c79f766123333b67a2cd29910ad2cba90a7554d6f5e` |
| `participant-resources/testing/21_quick_uart_test.py` | `tools/official/21_quick_uart_test.py` | `4a9990ff06d90517f973b7e27bd2e8e59a844d7c4a7270c9591a0ab527a77fb5` |
| `participant-resources/testing/22_robust_uart_test.py` | `tools/official/22_robust_uart_test.py` | `9aa45b8e51b698e2abf96c22ae1c493a79a5fd434bf55421f7e28048167a3f60` |

Both scripts require Python 3 and `pyserial` (install in your own virtual
environment when preparing board tests). Neither script has been run against
a serial device here; the bring-up target cannot answer their packets.
The guide permits only changes to `PORT`; both copies currently remain byte
identical, including PORT. After an authorized PORT edit, retain the original
hash and record that local change separately. The current checksum regression
intentionally checks the pristine copies; adjust that check transparently when
making the allowed local PORT change.

The robust script writes `trade_results_100.csv` and `trade_summary_100.txt` in
its working directory. Use a fresh results directory for every future board
run. Evaluate counts and timeouts, not just exit status. A full pass requires
the actual packet/algorithm implementation, not heartbeat or placeholder actions.
