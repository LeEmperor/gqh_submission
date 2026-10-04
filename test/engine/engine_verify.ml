open! Core
open! Hardcaml
open! Hardcaml_gqh
module U = Engine.Update
let scope () = Scope.create ~flatten_design:true ()
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let emit path =
  let module C = Circuit.With_interface (U.I) (U.O) in
  let circuit = C.create_exn ~name:"gqh_update_engine" (U.create (scope ())) in
  let data = Rtl.create Verilog [circuit] |> Rtl.full_hierarchy |> Rope.to_string in
  Out_channel.write_all path ~data
let replay path =
  let module S = Cyclesim.With_interface (U.I) (U.O) in
  let sim = S.create ~config:Cyclesim.Config.trace_all (U.create (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let nodes = List.map ["sum_a"; "sum_b"; "previous_below_a"; "previous_above_a"; "previous_below_b"; "previous_above_b"; "held_a"; "held_b"]
    ~f:(fun name -> Option.value_exn (Cyclesim.lookup_node_or_reg_by_name sim name)) in
  let state = Option.value_exn (Cyclesim.lookup_node_or_reg_by_name sim "engine_state") in
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
      if Array.length v <> 55 then failwith "invalid trace row";
      List.iteri [i.reset; i.session_clear; i.update_valid; i.result_ready;
        i.update.item_select; i.update.price; i.update.window_position; i.update.warmup]
        ~f:(fun idx p -> set p v.(idx));
      Cyclesim.cycle_check sim;
      Cyclesim.cycle_before_clock_edge sim;
      let before = Cyclesim.outputs ~clock_edge:Before sim in
      List.iteri [before.update_ready; before.result_valid; before.action]
        ~f:(fun idx p -> check !count "pre-edge handshake" (get p) v.(8+idx));
      check !count "exact commit/write pulse" (Bool.to_int (Cyclesim.Node.to_int state = 2 && get i.reset = 0)) v.(54);
      Cyclesim.cycle_at_clock_edge sim;
      Cyclesim.cycle_after_clock_edge sim;
      List.iteri [o.update_ready; o.result_valid; o.action]
        ~f:(fun idx p -> check !count "post-edge output" (get p) v.(11+idx));
      List.iteri nodes ~f:(fun idx n ->
        check !count "scalar/window consistency" (Cyclesim.Node.to_int n) v.(14+idx));
      for address = 0 to 31 do
        if v.(22+address) >= 0 then
          check !count "RAM exact-once/preservation" (Cyclesim.Memory.to_int memory ~address) v.(22+address)
      done));
  printf "PASS Cyclesim: %d edges, handshake, actions, scalars and all known RAM cells\n" !count
let () =
  match Array.to_list (Sys.get_argv ()) with
  | [_; "emit"; path] -> emit path
  | [_; "replay"; path] -> replay path
  | _ -> failwith "usage: engine_verify.exe (emit RTL | replay TRACE)"
