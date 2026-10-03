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
  let transport = Protocol.Transport_harness.hierarchical ~instance:"transport" scope
    { Protocol.Transport_harness.I.clock = i.sys_clk; reset = reset.reset
    ; byte_data = rx.byte_data; byte_valid = rx.byte_valid; framing_error = rx.framing_error
    ; tx_ready = tx.tx_ready; tx_busy = tx.tx_busy } in
  tx_data <-- transport.tx_data;
  tx_valid <-- transport.tx_valid;
  let heartbeat = Heartbeat.hierarchical ~instance:"heartbeat" ?half_period_cycles scope
    { Heartbeat.I.clock = i.sys_clk; reset = reset.reset } in
  { O.uart_tx_o = tx.tx; led0_n = heartbeat.led_n; led1_n = ~:(transport.protocol_fault) }

let hierarchical ?instance ?half_period_cycles ?cycles_per_bit ?extra_idle_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_transport_top"
    (create ?half_period_cycles ?cycles_per_bit ?extra_idle_cycles) i
