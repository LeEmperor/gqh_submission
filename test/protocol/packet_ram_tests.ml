open! Core
open! Hardcaml
open! Hardcaml_gqh
module P = Protocol.Packet_ram_controller
module S = Cyclesim.With_interface (P.I) (P.O)
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let eq what a b = if a <> b then failwithf "%s: %d <> %d" what a b ()
let () =
  let sim = S.create (P.create (Scope.create ~flatten_design:true ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let command () = List.map (Protocol.Types.Update.to_list o.update) ~f:get in
  let pending = ref None and delay = ref 0 and frame = ref 0 in
  let commands = ref [] and sent = ref [] and clear_count = ref 0 in
  let tick = ref 0 in
  let step () =
    incr tick;
    set i.update_ready (if !tick mod 5 = 0 then 0 else 1);
    set i.tx_busy (if !frame > 0 then 1 else 0);
    set i.tx_ready (if !frame = 0 && !tick mod 7 <> 0 then 1 else 0);
    set i.result_valid (if Option.is_some !pending && !delay = 0 then 1 else 0);
    set i.action 2;
    (match !pending with None -> () | Some saved ->
      if get i.reset = 0 then
        if not (List.equal Int.equal saved (command ())) then failwith "borrowed command changed before result");
    if get i.reset = 0 then (
      if get o.session_clear = 1 then incr clear_count;
      if get o.update_valid = 1 && get i.update_ready = 1 then (
        if Option.is_some !pending then failwith "overlapping update";
        pending := Some (command ()); delay := 19;
        commands := !commands @ [command ()]);
      if get o.result_ready = 1 && get i.result_valid = 1 then pending := None;
      if get o.tx_valid = 1 && get i.tx_ready = 1 then (
        sent := !sent @ [get o.tx_data]; frame := 23));
    Cyclesim.cycle sim;
    if !frame > 0 then decr frame;
    if !delay > 0 then decr delay
  in
  let reset () = set i.reset 1; pending := None; delay := 0; frame := 0;
    set i.byte_valid 0; set i.framing_error 0; step (); set i.reset 0; step () in
  let byte b pause = set i.byte_data b; set i.byte_valid 1; step (); set i.byte_valid 0;
    for _ = 1 to pause do step () done in
  let packet index id1 p1 id2 p2 =
    [index lsr 8;index land 255;id1;p1 lsr 8;p1 land 255;id2;p2 lsr 8;p2 land 255] in
  reset ();
  let pointer = ref 0 in
  for n = 0 to 255 do
    let index = List.nth_exn [0;1;15;16;255;256;65535] (n mod 7) in
    let id1=n and id2=255-n and p1=(n*257) land 65535 and p2=65535-((n*257) land 65535) in
    commands := []; sent := []; clear_count := 0;
    List.iteri (packet index id1 p1 id2 p2) ~f:(fun pos b -> byte b ((pos*13+n) mod 17));
    for _ = 1 to 400 do step () done;
    if index = 0 then pointer := 0;
    let expected id price = [Bool.to_int (id=Protocol.Types.item_b);price;!pointer;Bool.to_int (index<16)] in
    if not (List.equal (List.equal Int.equal) !commands [expected id1 p1;expected id2 p2]) then failwithf "commands trial %d" n ();
    if not (List.equal Int.equal !sent [index lsr 8;index land 255;id1;2;id2;2;0;0]) then failwithf "echo trial %d" n ();
    eq "session clear" !clear_count (Bool.to_int (index=0));
    pointer := (!pointer+1) land 15
  done;
  (* Reset every clock from packet completion through RAM field reads,
     stalled dispatch, result wait, every response byte and final drain. *)
  for offset = 0 to 290 do
    reset (); commands := []; sent := [];
    List.iter (packet 16 0x11 0xffff 0x22 0x8000) ~f:(fun b -> byte b 0);
    for _ = 1 to offset do step () done;
    reset (); commands := []; sent := [];
    for _ = 1 to 400 do step () done;
    if not (List.is_empty !commands && List.is_empty !sent) then failwithf "stale reset work offset %d" offset ();
    List.iter (packet 0 0x22 0x1234 0x11 0x5678) ~f:(fun b -> byte b 0);
    for _ = 1 to 400 do step () done;
    if not (List.equal Int.equal !sent [0;0;0x22;2;0x11;2;0;0]) then failwith "reset fresh packet"
  done;
  (* Faults during accepted RAM reads/result/TX cannot change its bytes. *)
  for offset = 0 to 220 do
    reset (); commands := []; sent := [];
    List.iter (packet 0x1234 0x22 0xbeef 0x11 0xffff) ~f:(fun b -> byte b 0);
    for _ = 1 to offset do step () done;
    set i.framing_error (offset mod 2); set i.byte_valid 1; set i.byte_data 0xaa; step ();
    set i.framing_error 0; set i.byte_valid 0;
    for _ = 1 to 400 do step () done;
    eq "sticky busy/framing fault" (get o.protocol_fault) 1;
    if not (List.equal Int.equal !sent [0x12;0x34;0x22;2;0x11;2;0;0]) then failwithf "accepted fault response offset %d" offset ();
    let saved = !sent in
    List.iter (packet 0 0x11 0 0x22 0) ~f:(fun b -> byte b 0);
    for _ = 1 to 400 do step () done;
    if not (List.equal Int.equal saved !sent) then failwith "fault failed to lock out"
  done;
  printf "PASS: packet RAM all byte values, wide index/price cases, stalls, command borrowing, 291 reset offsets, 221 fault offsets, final drain\n"
