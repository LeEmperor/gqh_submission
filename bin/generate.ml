open! Core
open! Hardcaml
open! Hardcaml_gqh

module Bringup = Circuit.With_interface (Board.Top.I) (Board.Top.O)
module History = Circuit.With_interface (History_probe.I) (History_probe.O)
module Competition = Circuit.With_interface (Board.Competition_top.I) (Board.Competition_top.O)
module Transport = Circuit.With_interface (Board.Transport_top.I) (Board.Transport_top.O)

let project_root () =
  let root = Option.value (Sys.getenv "DUNE_SOURCEROOT")
    ~default:(Sys_unix.getcwd ()) in
  let project = Filename.concat root "dune-project" in
  if not (Sys_unix.file_exists_exn project)
     || not (String.is_substring (In_channel.read_all project)
       ~substring:"(name hardcaml_gqh)")
  then failwith "Run from the testing project root or set DUNE_SOURCEROOT to it";
  root

let emit ~scope ~path circuit =
  let root = project_root () in
  let path = if Filename.is_relative path then Filename.concat root path else path in
  Core_unix.mkdir_p (Filename.dirname path);
  let data = Rtl.create ~database:(Scope.circuit_database scope) Verilog [circuit]
    |> Rtl.full_hierarchy |> Rope.to_string in
  Out_channel.write_all path ~data;
  printf "Generated %s (top module %s)\n" path (Circuit.name circuit)

let target ~summary ~default ~build =
  Command.basic ~summary
    (let%map_open.Command path = flag "-output" (optional_with_default default string)
       ~doc:"PATH Output file; relative paths resolve under the project root" in
     fun () ->
       let scope = Scope.create ~flatten_design:false () in
       emit ~scope ~path (build scope))

let bringup = target ~summary:"27 MHz board heartbeat and UART idle -> rtl/gqh_top.v"
  ~default:"rtl/gqh_top.v" ~build:(fun scope ->
    Bringup.create_exn ~name:"gqh_top" (Board.Top.create scope))
let history = target ~summary:"32 x 16 synchronous read-first RAM experiment"
  ~default:"rtl/history_probe.v" ~build:(fun scope ->
    History.create_exn ~name:"history_probe" (History_probe.create scope))
let transport = target ~summary:"UART request/response transport (NONE actions)"
  ~default:"rtl/gqh_transport_top.v" ~build:(fun scope ->
    Transport.create_exn ~name:"gqh_transport_top" (Board.Transport_top.create scope))
let competition_bsram = target
  ~summary:"Measured 302-logic / 109-register competition candidate; board acceptance pending"
  ~default:"rtl/gqh_competition_bsram_top.v" ~build:(fun scope ->
    Competition.create_exn ~name:"gqh_competition_top"
      (Board.Competition_top.create ~packet_ram:true ~records_in_bram:true
         ~borrow_command:true ~delta_arithmetic:true ~difference_relation:true scope))
let state_encoding_arg = Command.Arg_type.create (function
  | "binary" -> Always.State_machine.Encoding.Binary
  | "onehot" -> Always.State_machine.Encoding.Onehot
  | _ -> failwith "state encoding must be binary or onehot")
let competition = Command.basic ~summary:"27 MHz competition system with moving-average engine"
  (let%map_open.Command
     path = flag "-output" (optional_with_default "rtl/gqh_competition_top.v" string)
       ~doc:"PATH Output Verilog file"
   and records_in_bram = flag "-records-in-bram" no_arg ~doc:" Store engine scalar records in BSRAM"
   and borrow_command = flag "-borrow-command" no_arg ~doc:" Borrow retained engine command through commit"
   and delta_arithmetic = flag "-delta-arithmetic" no_arg ~doc:" Use signed price-minus-oldest delta"
   and difference_relation = flag "-difference-relation" no_arg ~doc:" Share price/average comparison subtraction"
   and packet_ram = flag "-packet-ram" no_arg ~doc:" Use byte packet RAM protocol"
   and capture_request = flag "-capture-request" no_arg
       ~doc:" Capture controller request instead of borrowing decoder retention"
   and capture_response = flag "-capture-response" no_arg
       ~doc:" Capture sequencer response instead of borrowing controller retention"
   and controller_encoding = flag "-controller-encoding" (optional state_encoding_arg)
       ~doc:"ENCODING Controller binary/onehot FSM experiment"
   and sequencer_encoding = flag "-sequencer-encoding" (optional state_encoding_arg)
       ~doc:"ENCODING Sequencer binary/onehot FSM experiment"
   and rx_encoding = flag "-rx-encoding" (optional state_encoding_arg)
       ~doc:"ENCODING RX binary/onehot FSM experiment"
   and tx_encoding = flag "-tx-encoding" (optional state_encoding_arg)
       ~doc:"ENCODING TX binary/onehot FSM experiment"
   and tx_shift_register = flag "-tx-shift-register" no_arg
       ~doc:" Serialize TX from a shifting byte register"
   and rx_factored_timer = flag "-rx-factored-timer" no_arg ~doc:" Factor RX timer control"
   and tx_factored_timer = flag "-tx-factored-timer" no_arg ~doc:" Factor TX timer control"
   and tx_indexed = flag "-tx-indexed" no_arg
       ~doc:" Serialize TX from an indexed byte register" in
   fun () ->
     if tx_shift_register && tx_indexed then failwith "choose one TX serialization mode";
     let tx_shift_register = if tx_shift_register then Some true
       else if tx_indexed then Some false else None in
     let scope = Scope.create ~flatten_design:false () in
     emit ~scope ~path (Competition.create_exn ~name:"gqh_competition_top"
       (Board.Competition_top.create ~records_in_bram ~borrow_command ~delta_arithmetic ~difference_relation ~packet_ram ~borrow_request:(not capture_request)
          ~borrow_response:(not capture_response) ?controller_encoding ?sequencer_encoding
          ?rx_encoding ?tx_encoding ?tx_shift_register ~rx_factored_timer ~tx_factored_timer scope)))
let () =
  let argv = Array.to_list (Sys.get_argv ()) in
  let argv = if List.length argv = 1 then argv @ ["bringup"] else argv in
  Command_unix.run ~argv (Command.group ~summary:"Generate self-contained Hardcaml Verilog"
  ["bringup", bringup; "history-probe", history; "transport", transport;
   "competition", competition; "competition-bsram", competition_bsram])
