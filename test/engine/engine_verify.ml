open! Core
open! Hardcaml
open! Hardcaml_gqh
module U = Engine.Update
let scope () = Scope.create ~flatten_design:true ()
let enabled name = String.equal (Option.value (Sys.getenv name) ~default:"0") "1"
let create = U.create ~records_in_bram:(enabled "HOPT_RECORDS_IN_BRAM")
  ~borrow_command:(enabled "HOPT_BORROW_COMMAND")
  ~delta_arithmetic:(enabled "HOPT_DELTA_ARITHMETIC")
  ~difference_relation:(enabled "HOPT_DIFFERENCE_RELATION")
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let emit path =
  let module C = Circuit.With_interface (U.I) (U.O) in
  let circuit = C.create_exn ~name:"gqh_update_engine" (create (scope ())) in
  let data = Rtl.create Verilog [circuit] |> Rtl.full_hierarchy |> Rope.to_string in
  Out_channel.write_all path ~data
let replay path =
  let module S = Cyclesim.With_interface (U.I) (U.O) in
  let sim = S.create ~config:Cyclesim.Config.trace_all (create (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let scalar_nodes =
    if enabled "HOPT_RECORDS_IN_BRAM" then []
    else List.map ["sum_a"; "sum_b"; "previous_below_a"; "previous_above_a";
                   "previous_below_b"; "previous_above_b"; "held_a"; "held_b"]
      ~f:(fun name -> Option.value_exn (Cyclesim.lookup_node_or_reg_by_name sim name))
  in
  let record_state = if not (enabled "HOPT_RECORDS_IN_BRAM") then None else (
    let records = Option.value_exn (Cyclesim.lookup_mem_by_name sim "engine_records") in
    let validity = List.map ["record_valid_a"; "record_valid_b"]
      ~f:(fun name -> Option.value_exn (Cyclesim.lookup_node_or_reg_by_name sim name)) in
    let physical = [| 0xFEDCBA; 0xABCDEF |] in
    for address = 0 to 1 do
      Cyclesim.Memory.of_bits records ~address (Bits.of_int_trunc ~width:24 physical.(address))
    done;
    let accepted_item = ref 0 in
    Some (records, validity, physical, accepted_item))
  in
  let memory = Option.value_exn (Cyclesim.lookup_mem_by_name sim "engine_history") in
  (* Poison every initial cell: the software simulator's default zero memory is
     not evidence that warm-up ignores unwritten RAM. *)
  for address = 0 to 31 do
    Cyclesim.Memory.of_bits memory ~address (Bits.of_int_trunc ~width:16 (65535 - address))
  done;
  let check line what actual expected =
    if actual <> expected then failwithf "line %d %s: got %d expected %d" line what actual expected () in
  let count = ref 0 in
  In_channel.with_file path ~f:(fun file ->
    In_channel.iter_lines file ~f:(fun line ->
      incr count;
      let v = String.split line ~on:' ' |> List.map ~f:Int.of_string |> Array.of_list in
      if Array.length v <> 54 then failwith "invalid trace row";
      List.iteri [i.reset; i.session_clear; i.update_valid; i.result_ready;
        i.update.item_select; i.update.price; i.update.window_position; i.update.warmup]
        ~f:(fun idx p -> set p v.(idx));
      Cyclesim.cycle_check sim;
      Cyclesim.cycle_before_clock_edge sim;
      let before = Cyclesim.outputs ~clock_edge:Before sim in
      List.iteri [before.update_ready; before.result_valid; before.action]
        ~f:(fun idx p -> check !count "pre-edge handshake" (get p) v.(8+idx));
      Cyclesim.cycle_at_clock_edge sim;
      Cyclesim.cycle_after_clock_edge sim;
      List.iteri [o.update_ready; o.result_valid; o.action]
        ~f:(fun idx p -> check !count "post-edge output" (get p) v.(11+idx));
      List.iteri scalar_nodes ~f:(fun idx node ->
        check !count "scalar/direct window consistency" (Cyclesim.Node.to_int node) v.(14 + idx));
      Option.iter record_state ~f:(fun (records, validity, physical, accepted_item) ->
        if v.(8) = 1 && v.(2) = 1 then accepted_item := v.(4);
        if v.(12) = 1 && v.(9) = 0 then (
          let item = !accepted_item in
          let address = item in
          physical.(address) <- v.(14 + item)
            lor (v.(16 + 2 * item) lsl 20)
            lor (v.(17 + 2 * item) lsl 21)
            lor (v.(20 + item) lsl 22));
        List.iteri validity ~f:(fun item valid ->
          let address = item in
          let stored = Cyclesim.Memory.to_int records ~address in
          check !count "record RAM preservation/exact once" stored physical.(address);
          let logical = if Cyclesim.Node.to_int valid = 0 then 0 else stored in
          List.iteri [logical land 0xFFFFF; (logical lsr 20) land 1;
                     (logical lsr 21) land 1; logical lsr 22]
            ~f:(fun field actual ->
              let column = if field = 0 then 14 + item else if field = 3 then 20 + item
                else 15 + 2 * item + field in
              check !count "scalar record/direct window consistency" actual v.(column))););
      for address = 0 to 31 do
        if v.(22+address) >= 0 then
          check !count "RAM exact-once/preservation" (Cyclesim.Memory.to_int memory ~address) v.(22+address)
      done));
  printf "PASS Cyclesim: %d edges, handshake, actions, scalars and all known RAM cells\n" !count
(* Measure scheduling through public handshakes so default regressions follow
   the selected hardware candidate without requiring an environment setting. *)
let latency () =
  let module S = Cyclesim.With_interface (U.I) (U.O) in
  let sim = S.create (create (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  set i.reset 1; Cyclesim.cycle sim; set i.reset 0;
  set i.update.warmup 1; set i.update_valid 1; Cyclesim.cycle sim;
  set i.update_valid 0;
  let elapsed = ref 0 in
  while get o.result_valid = 0 do
    incr elapsed;
    if !elapsed > 100 then failwith "engine latency watchdog";
    Cyclesim.cycle sim
  done;
  printf "%d\n" !elapsed
let () =
  match Array.to_list (Sys.get_argv ()) with
  | [_; "latency"] -> latency ()
  | [_; "emit"; path] -> emit path
  | [_; "replay"; path] -> replay path
  | _ -> failwith "usage: engine_verify.exe (latency | emit RTL | replay TRACE)"
