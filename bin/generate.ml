open! Core
open! Hardcaml
open! Hardcaml_gqh

module Bringup = Circuit.With_interface (Board.Top.I) (Board.Top.O)
module History = Circuit.With_interface (History_probe.I) (History_probe.O)

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
let () =
  let argv = Array.to_list (Sys.get_argv ()) in
  let argv = if List.length argv = 1 then argv @ ["bringup"] else argv in
  Command_unix.run ~argv (Command.group ~summary:"Generate self-contained Hardcaml Verilog"
  ["bringup", bringup; "history-probe", history])
