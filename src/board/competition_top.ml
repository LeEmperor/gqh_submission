open! Hardcaml
open! Signal

module I = Top.I
module O = Top.O

let create ?half_period_cycles ?cycles_per_bit ?extra_idle_cycles scope (i : _ I.t) =
  let reset = Reset_release.hierarchical ~instance:"reset_release" scope
    { Reset_release.I.clock = i.sys_clk; reset_btn = i.reset_btn } in
  let spec = Reg_spec.create ~clock:i.sys_clk ~clear:reset.reset () in
  let sync signal = reg spec ~clear_to:vdd ~initialize_to:Bits.vdd signal in
  let rx_sync = sync (sync i.uart_rx_i) in
  let rx = Uart.Rx.hierarchical ~instance:"uart_rx" ?cycles_per_bit scope
    { Uart.Rx.I.clock = i.sys_clk; reset = reset.reset; rx = rx_sync } in
  let tx_data = wire 8 and tx_valid = wire 1 in
  let tx = Uart.Tx.hierarchical ~instance:"uart_tx" ?cycles_per_bit ?extra_idle_cycles scope
    { Uart.Tx.I.clock = i.sys_clk; reset = reset.reset; tx_data; tx_valid } in
  (* Feedback wires connect exclusively owned components; all transfers use
     their valid/ready contracts, including final-frame response_done. Decoder
     fields are borrowed by the controller: receive_enable stays low from
     acceptance through final drain, retaining payload even on sticky faults. *)
  let request_ready = wire 1 and receive_enable = wire 1 in
  let decoder = Protocol.Request_decoder.hierarchical ~instance:"request_decoder" scope
    { Protocol.Request_decoder.I.clock = i.sys_clk; reset = reset.reset
    ; receive_enable; request_ready; byte_data = rx.byte_data
    ; byte_valid = rx.byte_valid; framing_error = rx.framing_error } in
  let update_ready = wire 1 and result_valid = wire 1 and action = wire 2 in
  let response_ready = wire 1 and response_done = wire 1 in
  let controller = Protocol.Transaction_controller.hierarchical ~instance:"controller" scope
    { Protocol.Transaction_controller.I.clock = i.sys_clk; reset = reset.reset
    ; request = decoder.request; request_valid = decoder.request_valid
    ; update_ready; result_valid; action; response_ready; response_done } in
  let engine = Engine.Update.hierarchical ~instance:"engine" scope
    { Engine.Update.I.clock = i.sys_clk; reset = reset.reset
    ; session_clear = controller.session_clear; update = controller.update
    ; update_valid = controller.update_valid; result_ready = controller.result_ready } in
  let sequencer = Protocol.Response_sequencer.hierarchical ~instance:"response_sequencer" scope
    { Protocol.Response_sequencer.I.clock = i.sys_clk; reset = reset.reset
    ; response = controller.response; response_valid = controller.response_valid
    ; tx_ready = tx.tx_ready; tx_busy = tx.tx_busy } in
  request_ready <-- controller.request_ready;
  receive_enable <-- controller.receive_enable;
  update_ready <-- engine.update_ready;
  result_valid <-- engine.result_valid;
  action <-- engine.action;
  response_ready <-- sequencer.response_ready;
  response_done <-- sequencer.response_done;
  tx_data <-- sequencer.tx_data;
  tx_valid <-- sequencer.tx_valid;
  let heartbeat = Heartbeat.hierarchical ~instance:"heartbeat" ?half_period_cycles scope
    { Heartbeat.I.clock = i.sys_clk; reset = reset.reset } in
  { O.uart_tx_o = tx.tx; led0_n = heartbeat.led_n; led1_n = ~:(decoder.protocol_fault) }

let hierarchical ?instance ?half_period_cycles ?cycles_per_bit ?extra_idle_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_competition_top"
    (create ?half_period_cycles ?cycles_per_bit ?extra_idle_cycles) i
