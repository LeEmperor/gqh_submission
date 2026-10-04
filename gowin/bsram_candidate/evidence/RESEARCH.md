# Further resource and register reduction research

## Measured parent

The captured manual Gowin V1.9.11.03 Education build matches selected RTL SHA-256 cbd88a4e72e8476fa7e22acd464c6e3e596d8c81a89ca3a5d5c4192a10ebe818. P&R reports363 total Logic,235 Registers,1 BSRAM,0 SSRAM; synthesis reports289 LUT and67 ALU while P&R reports74 ALU. Setup/hold violated endpoints are0; worst setup slack24.927ns. PR1014 is retained. Raw project, settings, reports and bitstream are preserved in baseline/gowin-observed. These are resource measurements, not new board acceptance.

## Hypotheses being implemented

1. Move both24-bit scalar records (sum20, relation2, held action2) into synchronous BSRAM. Invalidate stale records with two resettable valid bits instead of resetting RAM. Read scalar and history memories in parallel first; separately compare sharing address space/ports. This targets48 scalar flip-flops and the item-state mux. Extra memory ports, validity gates and staging must be measured.
2. Borrow the controller's engine command through commit, eliminating22 captured command bits only in the competition composition. Standalone capture behavior remains default. Stability must cover every processing stage and reset; pending results remain separately held.
3. Store the eight request bytes in8x8 synchronous BSRAM, serialize needed field reads, and reuse the RAM for echoed response bytes. This targets the69-register request decoder and controller/sequencer field muxes. Retain arbitrary byte pauses and framing/busy fault semantics, and prevent receive rearm until final TX drain.
4. Express price-oldest as a signed17-bit delta plus the exact20-bit sum, and separately derive both price/average relations from one17-bit subtraction. Prove full-range equality/borrow and floor truncation, then compare whole-design mapping.
5. Factor UART timer reload/decrement control while retaining independent RX/TX timers, exact234-clock bits and complete stop intervals. Keep heartbeat unchanged.

Register count is tracked alongside total logic; preserve the nondominated logic/register choices. Native Gowin reports determine vendor ranking. Open-source mapped counts remain a separate screen and must not be compared numerically with363.

## Primary references and practical limits

- Gowin BSRAM & SSRAM User Guide UG285-1.4E, https://cdn.gowinsemi.com.cn/UG285E.pdf: mode/width table and address mapping;512x32/36 is supported in single/semi-dual port mode, true dual-port configurations top out at16/18 bits. Read latency, output register mode, and collision behavior are part of correctness. We use mutually exclusive reads/writes where possible.
- GowinSynthesis User Guide, https://cdn.gowinsemi.com.cn/SUG550E.pdf: RAM inference controls and hardware mapping. A source array alone is not evidence of BSRAM use; inspect the exact-device report.
- Yosys memory handling, https://yosyshq.readthedocs.io/projects/yosys/en/0.43/using_yosys/synthesis/memory.html: synchronous read ports and memory-output register inference; unsupported reset/collision behavior can require fabric emulation. Prefer unreset data RAM plus explicit validity.
- Installed Gowin GW2A functional library IDE/simlib/gw2a/prim_sim.v supplies SP/SPX9 behavior at8/16/32 and9/18/36-bit widths. The old18-bit-only independent shim is not adequate for new wider memories. New mapped checks must use the appropriate documented model or installed vendor memory primitive and record model identity.

BSRAM is plentiful relative to this design, so adding a block is acceptable when measured logic/register reductions justify it. ROM-based narrow arithmetic or microcoded control are further possible experiments, but may add state/address registers and cycles; they are not credited as savings without implementation and whole-design measurement. No external DDR/PSRAM, PLL, reduced price precision or heartbeat changes are part of this run.
