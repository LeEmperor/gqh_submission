# Observed Gowin build — not yet confirmed as exact programmed file

Original project: test_proj1/test_proj1/test_proj1.gprj; Gowin V1.9.11.03 Education.
Top gqh_competition_top; part GW2AR-LV18QN88C8/I7. RTL/CST/SDC hashes match
candidate inputs. Build timestamp October 3 14:04:59. Source/build reports/fs
were copied read-only; user project was preserved. Bitstream identity is recorded
by SHA-256, but the actual programmed file/mode still requires user confirmation.

PnR whole-design resource summary: total logic 475, total registers 379;
351 LUTs, 76 ALUs, 8 SSRAM(RAM16). Engine synthesis resource hierarchy attributes
all 8 SSRAM to engine; history is distributed SSRAM, not a proven BSRAM mapping.
Synthesis XML reports 69 ALUs versus PnR 76; do not conflate report stages.

STA lists sys_clk 27.000 MHz, 37.037 ns, zero setup/hold violated endpoints and
zero TNS for the analyzed paths. Reported worst setup slack 24.535 ns. This is
report evidence, not a claim that unconstrained asynchronous I/O/reset paths
were fully validated. Recovery/removal tables contain no listed paths.

PR1014 remains: generic routing resource feeds sys_clk_d under the supplied
constraint, potentially adding clock delay/skew. The clock table lists sys_clk_d
on PRIMARY, and clear-related nets on LW; PRIMARY listing does not erase the
input-routing warning. User clock-routing/timing review acknowledgement remains
pending. No constraints were modified and no routing fix was attempted here.
