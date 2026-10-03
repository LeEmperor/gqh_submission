# Organizer placement supplement — October 3, 2026

Source: organizer announcement quoted by the user in the planning conversation
on October 3. This supplements the Participant Guide; the guide is unchanged.
The announcement text below is preserved as supplied.

> This supplements the Participant Guide. Nothing in the guide changes. Since the LUT and latency points are capped, many teams can reach 100/100, so here is how placement works.
>
> Stage 1: Qualification
> You must pass both of these to compete for placement:
>
> 100/100 on the official judge run. If you miss the latency tier, judges may rerun once.
> A second hidden run with full-range 16-bit prices (0 to 65535). The spec says prices are unsigned 16-bit, so don't shrink your datapath to fit the practice range. To pass, you need every packet and action correct with no timeouts. Latency and LUTs are not re-scored on this run. It runs right after the official run without reprogramming.
>
> Practice with large prices before the deadline using the attached 22_robust_uart_test_fullrange.py. Change only PORT, same as the normal test.
>
> Teams that don't qualify are ranked below all qualifiers, ordered by rubric score.
>
> Stage 2: Ranking (qualified teams only)
>
> Lowest total logic count
> If tied, fewer registers
> If still tied, lower median latency over 5 runs (within 5% counts as a tie)
>
> How logic is measured
>
> Judges re-synthesize your submitted source with Gowin V1.9.11.03 using the project settings in your commit.
> The number is the total logic count in the Resource Usage Summary, with LUTs, ALUs, and other logic types combined, so moving math into ALUs won't lower your count. Registers means the total register count in the same summary.
> Self-reported counts are not used. Qualification still uses the normal scoring from the guide. Only the ranking uses this total.
> Judges will rebuild your design from your committed source and confirm it behaves the same as your submitted .fs.
> BSRAM use is allowed and is not counted as logic.
>
> The ranking order above is final. The deadline is unchanged: Sunday, Oct 4, 11:00 am EDT. Post any questions here.

## Attached practice script

User-downloaded file: [`../tools/22_robust_uart_test_fullrange.py`](../tools/22_robust_uart_test_fullrange.py).
SHA-256 at review (including its original `PORT = "COM6"`):
`73295ff02aa06bac869f2c9c5c6ad6f244084b514f697846c176bc4c2ff2fc9c`.
This attachment has separate provenance from the older pinned organizer checkout.

Reviewed behavior: 100 requests, seed `0x1F00D16B`, prices `0..65535`, slot swaps
after warm-up, one-second timeout, and the same reference algorithm/protocol.
Outputs are `trade_results_100_fullrange.csv` and
`trade_summary_100_fullrange.txt`. Like the original robust script, it requires
warm-up responses but does not validate their contents; custom all-byte tests
remain necessary. It reports correctness out of 70, not qualification out of 100,
and exit status alone does not establish passing.

Run PORT-only copies of normal robust then full-range practice on the same
programmed image, without intervening board reset or reprogramming. Each script
opens its own serial connection; this does not itself prove same-connection
session recovery, which the custom replay must also cover. Require 100 complete
responses, 84/84 scored packets, 168/168 actions and zero timeouts in each run,
plus exact warm-up and repeated-session correctness in custom checks. The hidden
judge seed is unpublished; this practice seed is not exhaustive coverage.
