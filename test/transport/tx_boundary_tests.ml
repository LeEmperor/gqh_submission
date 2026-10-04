open! Core
open! Hardcaml
open! Hardcaml_gqh

let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let eq label actual expected =
  if actual <> expected then failwithf "%s: got %d expected %d" label actual expected ()
let scope () = Scope.create ~flatten_design:true ()
module S = Cyclesim.With_interface (Uart.Tx.I) (Uart.Tx.O)

let check_timing ?factored_timer ?state_encoding ?shift_register period gap =
  let sim = S.create (Uart.Tx.create ?factored_timer ?state_encoding ?shift_register ~cycles_per_bit:period ~extra_idle_cycles:gap (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let cycle () = Cyclesim.cycle sim in
  let idle () =
    eq "idle high" (get o.tx) 1;
    eq "idle ready" (get o.tx_ready) 1;
    eq "idle not busy" (get o.tx_busy) 0 in
  let reset () =
    (* Valid on a reset edge must never accept a byte. *)
    set i.tx_valid 1; set i.reset 1; cycle ();
    eq "reset high" (get o.tx) 1;
    eq "reset inhibits ready" (get o.tx_ready) 0;
    eq "reset clears busy" (get o.tx_busy) 0;
    set i.tx_valid 0; set i.reset 0; cycle (); idle () in
  let frame byte ~held_valid =
    (* The independent oracle samples every clock, including acceptance's
       first start cycle and the last mandatory stop / extra gap cycle. *)
    for tick = 0 to 10 * period + gap - 1 do
      let expected =
        if tick < period then 0
        else if tick < 9 * period then (byte lsr (tick / period - 1)) land 1
        else 1 in
      eq (sprintf "N=%d gap=%d byte=%02x tick=%d" period gap byte tick) (get o.tx) expected;
      eq "busy for complete frame/gap" (get o.tx_busy) 1;
      eq "backpressure for complete frame/gap" (get o.tx_ready) 0;
      (* Change input every clock, and offer both pulses and held valid while
         ready is low. None may alter or queue the accepted payload. *)
      set i.tx_data ((byte + tick + 1) land 255);
      set i.tx_valid (if held_valid then 1 else tick land 1);
      cycle ()
    done;
    idle () in
  reset ();
  for tick = 0 to 31 do
    set i.tx_data tick; set i.tx_valid 0; cycle (); idle ()
  done;
  for byte = 0 to 255 do
    idle (); set i.tx_data byte; set i.tx_valid 1; cycle ();
    frame byte ~held_valid:(byte land 1 = 0);
    (* With valid deasserted after busy offers, nothing is transmitted later. *)
    set i.tx_valid 0;
    for _ = 1 to 10 * period + gap + 2 do cycle (); idle () done
  done;
  (* Hold valid across completion and present the next payload before the
     first ready edge. It is accepted on that edge, exactly once. *)
  set i.tx_valid 1; set i.tx_data 0x96; cycle ();
  frame 0x96 ~held_valid:true;
  set i.tx_data 0x3c; cycle ();
  frame 0x3c ~held_valid:true;
  set i.tx_valid 0; cycle (); idle ();
  (* Abort at both ends of every bit and gap, including the final busy cycle.
     Reset can be held with valid asserted; release can immediately accept. *)
  let offsets = List.concat_map (List.init 10 ~f:Fn.id) ~f:(fun bit ->
    [bit * period; (bit + 1) * period - 1])
    @ (if gap = 0 then [] else [10 * period; 10 * period + gap - 1]) in
  List.iter offsets ~f:(fun offset ->
    reset (); set i.tx_data 0; set i.tx_valid 1; cycle ();
    for _ = 1 to offset do cycle () done;
    eq "abort while busy" (get o.tx_busy) 1;
    set i.reset 1;
    for _ = 1 to 3 do
      cycle (); eq "held reset high" (get o.tx) 1;
      eq "held reset not ready" (get o.tx_ready) 0;
      eq "held reset not busy" (get o.tx_busy) 0
    done;
    set i.reset 0; set i.tx_data 0xa5; cycle ();
    frame 0xa5 ~held_valid:false;
    set i.tx_valid 0; cycle (); idle ())

let () =
  (* Minimum supported divisor, odd/even counts, powers of two and either
     side of counter-width transitions; include the production divisor. *)
  List.iter [1,0; 1,1; 1,2; 2,0; 2,1; 3,3; 7,0; 7,13;
             8,7; 8,8; 8,9; 9,0; 9,16; 234,0; 234,256]
    ~f:(fun (period, gap) ->
      check_timing period gap; check_timing ~factored_timer:true period gap;
      List.iter [Always.State_machine.Encoding.Binary; Onehot] ~f:(fun state_encoding ->
        check_timing ~state_encoding period gap;
        check_timing ~state_encoding ~shift_register:true period gap));
  List.iter [0,0; -1,0; 1,-1] ~f:(fun (period, gap) ->
    match Uart.Tx.create ~cycles_per_bit:period ~extra_idle_cycles:gap (scope ())
      (Uart.Tx.I.map Uart.Tx.I.port_names_and_widths ~f:(fun (name, width) ->
         Signal.input name width)) with
    | exception Invalid_argument _ -> ()
    | _ -> failwith "invalid timing accepted");
  printf "PASS: TX all bytes, 15 timing configurations, exact durations, stalls, idle and reset boundaries\n"
