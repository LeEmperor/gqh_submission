open! Hardcaml
open! Signal

module I = Top.I
module O = Top.O

(* The matching Gowin_rPLL_81 wrapper fixes IDIV=1, FBDIV=3 and ODIV=8.
   Keep the established UART bit duration: 702/81MHz = 234/27MHz. *)
let reference_hz = 27_000_000
let multiplier = 3
let core_hz = reference_hz * multiplier
let cycles_per_bit = Uart.Config.cycles_per_bit * multiplier

let create scope (i : _ I.t) =
  let pll = Instantiation.create () ~name:"Gowin_rPLL_81" ~instance:"pll"
    ~inputs:["clkin", i.sys_clk] ~outputs:["clkout", 1; "locked", 1] in
  let core_clk = Instantiation.output pll "clkout" -- "core_clk" in
  let pll_locked = Instantiation.output pll "locked" -- "pll_locked" in
  (* Existing reset_release asserts asynchronously, including when the PLL
     clock stops, and deasserts through two core-clock stages. Reset does not
     feed back to the PLL. All functional state remains in one clock domain. *)
  let reset_btn = i.reset_btn |: ~:pll_locked in
  Competition_top.create ~diagnostics:false ~packet_ram:true ~records_in_bram:true
    ~borrow_command:true ~delta_arithmetic:true ~difference_relation:true
    ~cycles_per_bit ~extra_idle_cycles:0 scope { i with sys_clk = core_clk; reset_btn }
