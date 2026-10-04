open! Hardcaml
open! Signal
module I = Hardcaml_gqh.Uart.Tx.I
module O = Hardcaml_gqh.Uart.Tx.O

(* Whole 8N1 frame shifter, one LFSR for 234 clocks/bit and another for ten
   complete bit times. Constants are calculated in OCaml, not in hardware.
   No extra idle gap; the mandatory stop bit is always a full 234 clocks.
   Architecture inspired by blacklist-gqh/src/uart_tx.sv. *)
let step_int width taps x =
  let rec parity n p = if n = 0 then p else parity (n lsr 1) (p lxor (n land 1)) in
  ((x lsl 1) land ((1 lsl width) - 1)) lor parity (x land taps) 0

let after width taps seed count =
  let rec loop n x = if n = 0 then x else loop (n - 1) (step_int width taps x) in
  loop count seed

let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let step width taps x =
    let feedback = List.init width (fun b -> b)
      |> List.filter (fun b -> taps land (1 lsl b) <> 0)
      |> List.map (fun b -> bit x ~pos:b)
      |> List.fold_left ( ^: ) gnd in
    concat_msb [sel_bottom x ~width:(width - 1); feedback] in
  let baud_d = wire 8 in
  let baud = reg spec ~clear_to:(ones 8) baud_d in
  let bit_end = baud ==:. after 8 0xb8 255 233 in
  let busy_d = wire 1 in
  let busy = reg spec busy_d in
  let ready = ~:busy &: ~:(i.reset) in
  let accept = ready &: i.tx_valid in
  baud_d <-- mux2 (accept |: bit_end) (ones 8) (step 8 0xb8 baud);
  let position_d = wire 4 in
  let position = reg spec position_d in
  let last = position ==:. after 4 0xc 15 9 in
  let advance = busy &: bit_end in
  position_d <-- mux2 accept (ones 4)
    (mux2 advance (step 4 0xc position) position);
  busy_d <-- mux2 accept vdd (mux2 (advance &: last) gnd busy);
  let frame_d = wire 10 in
  let frame = reg spec ~clear_to:(ones 10) frame_d in
  frame_d <-- mux2 accept (concat_msb [vdd; i.tx_data; gnd])
    (mux2 advance (concat_msb [vdd; sel_top frame ~width:9]) frame);
  { O.tx = mux2 i.reset vdd (lsb frame); tx_ready = ready; tx_busy = busy }

let hierarchical scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~instance:"uart_tx" ~scope ~name:"gqh_uart_tx" create i
