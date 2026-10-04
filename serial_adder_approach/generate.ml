open! Core
open! Hardcaml
open! Signal
open! Hardcaml_gqh

let create ~lfsr_tx scope (i : _ Board.Top.I.t) =
  let reset = Board.Reset_release.hierarchical ~instance:"reset_release" scope
    { Board.Reset_release.I.clock = i.sys_clk; reset_btn = i.reset_btn } in
  let spec = Reg_spec.create ~clock:i.sys_clk ~clear:reset.reset () in
  let sync signal = reg spec ~clear_to:vdd ~initialize_to:Bits.vdd signal in
  let rx = Uart.Rx.hierarchical ~instance:"uart_rx" scope
    { Uart.Rx.I.clock = i.sys_clk; reset = reset.reset; rx = sync (sync i.uart_rx_i) } in
  let tx_data = wire 8 and tx_valid = wire 1 in
  let tx_input = { Uart.Tx.I.clock = i.sys_clk; reset = reset.reset; tx_data; tx_valid } in
  let tx = if lfsr_tx then Serial_tx.hierarchical scope tx_input
    else Uart.Tx.hierarchical ~instance:"uart_tx" scope tx_input in
  let update_ready = wire 1 and result_valid = wire 1 and action = wire 2 in
  let controller = Protocol.Packet_ram_controller.hierarchical ~instance:"packet_ram_controller" scope
    { Protocol.Packet_ram_controller.I.clock = i.sys_clk; reset = reset.reset
    ; byte_data = rx.byte_data; byte_valid = rx.byte_valid; framing_error = rx.framing_error
    ; update_ready; result_valid; action; tx_ready = tx.tx_ready; tx_busy = tx.tx_busy } in
  let engine = Serial_engine.hierarchical scope
    { Serial_engine.I.clock = i.sys_clk; reset = reset.reset
    ; session_clear = controller.session_clear; update = controller.update
    ; update_valid = controller.update_valid; result_ready = controller.result_ready } in
  update_ready <-- engine.update_ready; result_valid <-- engine.result_valid;
  action <-- engine.action; tx_data <-- controller.tx_data; tx_valid <-- controller.tx_valid;
  { Board.Top.O.uart_tx_o = tx.tx; led0_n = vdd; led1_n = vdd }

let () =
  let root = Option.value (Sys.getenv "DUNE_SOURCEROOT") ~default:"." in
  let output = match Sys.get_argv () with
    | [| _; output |] -> output
    | _ -> Filename.concat root "serial_adder_approach" in
  let emit name build =
    let scope = Scope.create ~flatten_design:false () in
    let circuit = build scope in
    let data = Rtl.create ~database:(Scope.circuit_database scope) Verilog [circuit]
      |> Rtl.full_hierarchy |> Rope.to_string in
    let path = Filename.concat output name in
    Out_channel.write_all path ~data;
    printf "Generated %s\n" path in
  let module Top = Circuit.With_interface (Board.Top.I) (Board.Top.O) in
  emit "gqh_serial_top.v" (fun scope ->
    Top.create_exn ~name:"gqh_competition_top" (create ~lfsr_tx:true scope));
  emit "gqh_serial_engine_only_top.v" (fun scope ->
    Top.create_exn ~name:"gqh_competition_top" (create ~lfsr_tx:false scope));
  let module Engine = Circuit.With_interface (Serial_engine.I) (Serial_engine.O) in
  emit "serial_engine_test.v" (fun scope ->
    Engine.create_exn ~name:"gqh_update_engine" (Serial_engine.create scope))
