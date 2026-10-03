open! Hardcaml

module I = struct
  type 'a t = { sys_clk : 'a; reset_btn : 'a; uart_rx_i : 'a }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t = { uart_tx_o : 'a; led0_n : 'a; led1_n : 'a }
  [@@deriving hardcaml]
end

let create ?half_period_cycles scope (i : _ I.t) =
  let reset = Reset_release.hierarchical ~instance:"reset_release" scope
    { Reset_release.I.clock = i.sys_clk; reset_btn = i.reset_btn } in
  let heartbeat = Heartbeat.hierarchical ~instance:"heartbeat"
    ?half_period_cycles scope
    { Heartbeat.I.clock = i.sys_clk; reset = reset.reset } in
  { O.uart_tx_o = Signal.vdd; led0_n = heartbeat.led_n; led1_n = Signal.vdd }

let hierarchical ?instance ?half_period_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_top" (create ?half_period_cycles) i
