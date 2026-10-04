open! Core
open! Hardcaml
open! Hardcaml_gqh
module P = Protocol
module C = P.Transaction_controller
module H = Transaction_harness
let scope () = Scope.create ~flatten_design:true ()
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let check label actual expected =
  if actual <> expected then failwithf "%s: got %d expected %d" label actual expected ()
let resp p = P.Types.Response.to_list p |> List.map ~f:get
let cmd p = P.Types.Update.to_list p |> List.map ~f:get
let set_req p fields = List.iter2_exn (P.Types.Request.to_list p) fields ~f:set
let expected_response = function
  | [index; id1; _; id2; _], a1, a2 -> [index; id1; id2; a1; a2]
  | _ -> failwith "bad request"
let begin_edge sim = Cyclesim.cycle_check sim; Cyclesim.cycle_before_clock_edge sim
let end_edge sim = Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim

(* Independent variable-latency endpoint plus transaction/event scoreboard.
   Requests remain offered while busy and every live payload changes after
   acceptance. Distinct actions depend on command ordinal, not item order. *)
let mocks () =
  let module S = Cyclesim.With_interface(C.I)(C.O) in
  let sim = S.create (C.create (scope ())) in
  let i = Cyclesim.inputs sim in
  let rng = Random.State.make [|0x612026|] in
  let total_commands = ref 0 and total_packets = ref 0 and total_clears = ref 0 in
  let earliest = ref 0 in
  for reset_target = 0 to 8 do
    let stage = ref 0 and pointer = ref 0 and engine = ref 0 and latency = ref 0 in
    let stored = ref [0;17;0;34;0] and slot = ref 0 and actions = ref [0;0] in
    let clears = ref 0 and commands = ref 0 and results = ref 0 in
    let completed = ref 0 and next_index = ref 0 and drain = ref 0 in
    let injected = ref false and initial = ref true and edges = ref 0 in
    let target_edges = ref 0 in
    while !completed < 40 do
      incr edges;
      if !edges > 10000 then failwith "mock progress timeout";
      if not !injected && !stage = reset_target then incr target_edges;
      let waiting_target = not !injected && !stage = reset_target in
      let reset = !initial || (waiting_target &&
        (reset_target = 0 || reset_target = 2 || !target_edges >= 5)) in
      if not !initial && reset then injected := true;
      initial := false;
      let index = !next_index % 20 in
      let swapped = index % 2 = 0 in
      let offered = [index; (if swapped then 34 else 17); Random.State.int rng 65536;
                     (if swapped then 17 else 34); Random.State.int rng 65536] in
      set_req i.request offered; set i.request_valid 1; set i.reset (Bool.to_int reset);
      let ur = !engine = 0 && !stage <> 2 && Random.State.int rng 4 = 0
        && not (waiting_target && List.mem [1;3;5] reset_target ~equal:Int.equal) in
      let rv = !engine = 2
        && not (waiting_target && List.mem [4;6] reset_target ~equal:Int.equal) in
      let rr = Random.State.int rng 5 = 0 && not (waiting_target && reset_target = 7) in
      let done_ = !stage = 8 && !drain >= 12 in
      set i.update_ready (Bool.to_int ur); set i.result_valid (Bool.to_int rv);
      set i.action (if !slot = 1 then 1 else 2);
      set i.response_ready (Bool.to_int rr); set i.response_done (Bool.to_int done_);
      begin_edge sim;
      let o = Cyclesim.outputs ~clock_edge:Before sim in
      let active b = Bool.to_int (b && not reset) in
      check "request ready/lifecycle" (get o.request_ready) (active (!stage = 0));
      check "receive enable/lifecycle" (get o.receive_enable) (active (!stage = 0));
      check "command valid" (get o.update_valid) (active (!stage = 3 || !stage = 5));
      check "result ready" (get o.result_ready) (active (!stage = 4 || !stage = 6));
      check "response valid" (get o.response_valid) (active (!stage = 7));
      check "clear pulse" (get o.session_clear) (active (!stage = 2));
      if not reset then begin
        check "shared pointer" (get o.update.window_position) !pointer;
        if get o.update_valid = 1 then begin
          let v = Array.of_list !stored in
          let second = !stage = 5 in
          let id = v.(if second then 3 else 1) and price = v.(if second then 4 else 2) in
          assert ([%equal: int list] (cmd o.update) [Bool.to_int (id = 34); price; !pointer; Bool.to_int (v.(0) < 16)]);
          assert (!engine = 0);
          if ur then begin
            incr commands; incr total_commands; slot := !commands;
            latency := Random.State.int rng 15;
            if !latency = 0 then incr earliest;
            engine := (if !latency = 0 then 2 else 1)
          end
        end else if !engine = 1 then begin
          if !latency = 0 then engine := 2 else decr latency
        end;
        if get o.session_clear = 1 then begin
          assert (!engine = 0 && !commands = 0 && !results = 0);
          incr clears; incr total_clears
        end;
        if get o.result_ready = 1 && rv then begin
          incr results; assert (!results = !commands);
          actions := (if !stage = 4 then [1;0] else [1;2]); engine := 0
        end;
        if get o.response_valid = 1 then begin
          let a = Array.of_list !actions in
          assert ([%equal: int list] (resp o.response) (expected_response (!stored,a.(0),a.(1))));
          assert (!commands = 2 && !results = 2);
          check "clear count per request" !clears (Bool.to_int (List.hd_exn !stored = 0));
          if rr then incr total_packets
        end;
        (match !stage with
         | 0 -> stored := offered; commands := 0; results := 0; clears := 0;
                actions := [0;0];
                if index = 0 then (pointer := 0; stage := 1) else stage := 3
         | 1 -> if ur && not rv then stage := 2
         | 2 -> stage := 3
         | 3 -> if ur then stage := 4
         | 4 -> if rv then stage := 5
         | 5 -> if ur then stage := 6
         | 6 -> if rv then (pointer := (!pointer + 1) % 16; stage := 7)
         | 7 -> if rr then (stage := 8; drain := 0)
         | 8 -> incr drain; if done_ then (stage := 0; incr completed; incr next_index)
         | _ -> assert false)
      end else begin
        stage := 0; pointer := 0; engine := 0; next_index := 0;
        commands := 0; results := 0; clears := 0
      end;
      end_edge sim
    done;
    assert !injected
  done;
  assert (!earliest > 0);
  printf "PASS mocks: nine reset stages, %d responses, %d commands, %d clear pulses, %d earliest-result commands; random stalls/latency and held offers\n"
    !total_packets !total_commands !total_clears !earliest

let replay path =
  let module S = Cyclesim.With_interface(H.I)(H.O) in
  let sim = S.create ~config:Cyclesim.Config.trace_all (H.create (scope ())) in
  let i = Cyclesim.inputs sim in
  let tick () = begin_edge sim; let before = Cyclesim.outputs ~clock_edge:Before sim in
    let c = before.controller in
    let snapshot = (get c.request_ready, get c.response_valid, resp c.response,
                    get c.update_valid, cmd c.update, get c.session_clear,
                    get c.result_ready, get before.engine.result_valid, get before.engine.update_ready) in
    end_edge sim; snapshot in
  set i.reset 1; ignore (tick ()); set i.reset 0;
  let records = ref 0 and clears = ref 0 and commands = ref 0 in
  let counts = Hashtbl.create (module String) in
  let process line =
    let v = String.split line ~on:' ' |> List.map ~f:Int.of_string |> Array.of_list in
    assert (Array.length v = 7);
    let fields = Array.to_list (Array.sub v ~pos:0 ~len:5) in
    let expected = expected_response (fields,v.(5),v.(6)) in
    set_req i.request fields; set i.request_valid 1;
    set i.response_ready 0; set i.response_done 0;
    let ready,_,_,_,_,_,_,_,_ = tick () in check "request acceptance" ready 1;
    set_req i.request [65535;34;65535;17;65535]; (* all fields change *)
    let elapsed = ref 0 and update_count = ref 0 and result_count = ref 0 and clear_count = ref 0 in
    let response_seen = ref false and publication = ref (-1) in
    while not !response_seen do
      incr elapsed; if !elapsed > 100 then failwith "real engine timeout";
      let ready,valid,response,uv,command,clear,result_ready,result_valid,update_ready = tick () in
      if !publication < 0 && get (Cyclesim.outputs sim).controller.response_valid = 1
      then publication := !elapsed;
      check "busy offer" ready 0;
      if clear = 1 then begin
        assert (uv=0 && result_valid=0 && update_ready=0);
        incr clears; incr clear_count
      end;
      if uv = 1 && update_ready = 1 then begin
        let n = !update_count in
        let id = v.(if n = 0 then 1 else 3) and price = v.(if n = 0 then 2 else 4) in
        assert ([%equal: int list] command [Bool.to_int (id = 34);price;v.(0)%16;Bool.to_int(v.(0)<16)]);
        incr update_count; incr commands
      end;
      if result_ready = 1 && result_valid = 1 then incr result_count;
      if valid = 1 then begin
        assert ([%equal: int list] response expected && !update_count = 2 && !result_count = 2);
        check "real clear count" !clear_count (Bool.to_int (v.(0)=0));
        response_seen := true
      end
    done;
    check "publication versus transfer edge" !elapsed (!publication + 1);
    let key = if v.(0)=0 then "session_start" else if v.(0)<16 then "warmup" else "steady" in
    check "H3a bounded path latency" !elapsed (if v.(0)=0 || v.(0)>=16 then 13 else 11);
    Hashtbl.update counts key ~f:(function None -> !elapsed | Some n -> check "path latency" !elapsed n; n);
    for _ = 1 to 7 do
      let ready,valid,response,_,_,_,_,_,_ = tick () in
      check "response stall valid" valid 1; check "response stall ready" ready 0;
      assert ([%equal: int list] response expected)
    done;
    set i.response_ready 1; ignore (tick ());
    for _ = 1 to 9 do
      let ready,valid,_,uv,_,clear,_,_,_ = tick () in
      assert (ready=0 && valid=0 && uv=0 && clear=0)
    done;
    set i.response_done 1; ignore (tick ()); set i.response_done 0;
    (* Leave offered valid high throughout busy, drop before the next idle edge. *)
    set i.request_valid 0;
    incr records in
  let lines = In_channel.read_lines path in
  List.iter lines ~f:process;
  (* Abort on every elapsed edge through session-clear, both engine updates,
     stalled response and drain, then refill/scored replay on this SAME instance.
     This verifies controller + engine reset together, with stale physical RAM. *)
  for index = 0 to 1 do
   for offset = 0 to 14 do
    (* Refill a full window before the rolling reset sweep, on this instance. *)
    if index = 1 then List.iter (List.take lines 35) ~f:process;
    set_req i.request (if index = 0 then [0;34;65535;17;0] else [35;34;65535;17;0]);
    set i.request_valid 1;
    set i.response_ready 0; set i.response_done 0;
    ignore (tick ());
    for elapsed = 1 to offset do
      if elapsed = 14 then set i.response_ready 1;
      ignore (tick ())
    done;
    set i.reset 1;
    let ready,valid,_,uv,_,clear,result_ready,_,_ = tick () in
    assert (ready=0 && valid=0 && uv=0 && clear=0 && result_ready=0);
    let after = Cyclesim.outputs sim in
    assert (get after.engine.update_ready=0 && get after.engine.result_valid=0);
    ignore (tick ()); set i.reset 0; set i.request_valid 0;
    List.iter (List.take lines 35) ~f:process
  done;
  done;
  printf "PASS real engine: %d records, %d commands, %d session clears\n" !records !commands !clears;
  Hashtbl.iteri counts ~f:(fun ~key ~data -> printf "latency %s: publication E0+%d; earliest response transfer E0+%d\n" key (data-1) data)

let emit kind path =
  let circuit = match kind with
    | "controller" -> let module W = Circuit.With_interface(C.I)(C.O) in
      W.create_exn ~name:"gqh_transaction_controller" (C.create (scope ()))
    | "payload" -> let module W = Circuit.With_interface(H.I)(H.O) in
      W.create_exn ~name:"gqh_transaction_test" (H.create (scope ()))
    | "byte" -> let module W = Circuit.With_interface(H.Byte.I)(H.Byte.O) in
      W.create_exn ~name:"gqh_byte_test" (H.Byte.create (scope ()))
    | _ -> failwith "unknown emit kind" in
  Out_channel.write_all path ~data:(Rtl.create Verilog [circuit] |> Rtl.full_hierarchy |> Rope.to_string)

let bytes path =
  let module S = Cyclesim.With_interface(H.Byte.I)(H.Byte.O) in
  let sim = S.create (H.Byte.create (scope ())) in
  let i = Cyclesim.inputs sim in
  let received = ref [] and accepts = ref 0 and updates = ref 0 and clears = ref 0 in
  let completions = ref 0 in
  let tick () =
    begin_edge sim;
    let o = Cyclesim.outputs ~clock_edge:Before sim in
    let c = o.controller in
    if get o.tx_valid = 1 && get i.tx_ready = 1 then received := !received @ [get o.tx_data];
    if get o.request_valid = 1 && get c.request_ready = 1 then incr accepts;
    if get c.update_valid = 1 then incr updates;
    if get c.session_clear = 1 then incr clears;
    if get o.response_done = 1 then incr completions;
    let view = get c.receive_enable, get o.protocol_fault, get c.response_valid in
    end_edge sim; view in
  let idle () = set i.byte_valid 0; set i.framing_error 0; ignore (tick ()) in
  let reset () =
    set i.reset 1; set i.byte_valid 1; set i.framing_error 1;
    set i.tx_ready 1; set i.tx_busy 1;
    let enabled,_,valid = tick () in assert(enabled=0 && valid=0);
    set i.reset 0; set i.byte_valid 0; set i.framing_error 0;
    set i.tx_ready 0; set i.tx_busy 0; idle ();
    received := []; accepts := 0; updates := 0; clears := 0; completions := 0 in
  let send_byte b = set i.byte_data b; set i.byte_valid 1; ignore (tick ()); set i.byte_valid 0 in
  let wire_request v = [v.(0) lsr 8; v.(0) land 255;v.(1);v.(2) lsr 8;v.(2) land 255;
                        v.(3);v.(4) lsr 8;v.(4) land 255] in
  let send_request v =
    let old_a = !accepts and old_u = !updates and old_c = !clears in
    List.iteri (wire_request v) ~f:(fun n b ->
      for _ = 0 to n*3 do idle () done;
      assert (!accepts=old_a && !updates=old_u && !clears=old_c);
      send_byte b);
    assert (!accepts=old_a && !updates=old_u && !clears=old_c) in
  let finish expected =
    let start = List.length !received in
    let cycles = ref 0 and frame_remaining = ref 0 in
    while List.length !received < start+8 do
      incr cycles; if !cycles>300 then failwith "byte response timeout";
      let ready = !frame_remaining = 0 && !cycles % 4 = 0 in
      set i.tx_ready (Bool.to_int ready);
      set i.tx_busy (Bool.to_int (!frame_remaining > 0));
      let old_length = List.length !received in
      ignore (tick ());
      if List.length !received > old_length then frame_remaining := 3
      else if !frame_remaining > 0 then decr frame_remaining
    done;
    set i.tx_ready 0; set i.tx_busy 1;
    for _ = 1 to 17 do
      let enabled,_,_ = tick () in check "final drain lockout" enabled 0;
      assert (List.length !received = start+8)
    done;
    assert ([%equal: int list] (List.drop !received start) expected);
    set i.tx_busy 0; set i.tx_ready 1;
    let enabled,_,_ = tick () in check "drain completion edge" enabled 0;
    let enabled,_,_ = tick () in check "done consumption edge" enabled 0;
    let enabled,_,_ = tick () in check "rearm following done" enabled 1 in
  reset ();
  let rows = List.take (In_channel.read_lines path) 100 in
  List.iter rows ~f:(fun line ->
    let v = String.split line ~on:' ' |> List.map ~f:Int.of_string |> Array.of_list in
    send_request v;
    finish [v.(0) lsr 8;v.(0) land 255;v.(1);v.(5);v.(3);v.(6);0;0]);
  check "byte accepted requests" !accepts 100; check "byte updates" !updates 200;
  check "byte completions" !completions 100;
  (* Acceptance-edge unexpected byte accepts old request, then locks out.
     Framing-error collision suppresses that same held request handshake. *)
  let v = [|0;34;65535;17;0;0;0|] in
  List.iter [false;true] ~f:(fun framing ->
    reset (); send_request v;
    set i.byte_valid (Bool.to_int (not framing)); set i.byte_data 99;
    set i.framing_error (Bool.to_int framing); ignore (tick ());
    set i.byte_valid 0; set i.framing_error 0;
    check "collision acceptance" !accepts (if framing then 0 else 1);
    if not framing then finish [0;0;34;0;17;0;0;0];
    for _ = 1 to 40 do let _,fault,_ = tick () in check "sticky fault" fault 1 done;
    List.iter (wire_request v) ~f:send_byte;
    check "fault blocks further request" !accepts (if framing then 0 else 1);
    reset (); send_request v; finish [0;0;34;0;17;0;0;0]);
  (* A fault during work permits the accepted transaction to finish. *)
  reset (); send_request v; idle (); send_byte 99;
  finish [0;0;34;0;17;0;0;0];
  let _,fault,_ = tick () in check "busy-byte fault" fault 1;
  reset (); List.iter (List.take (wire_request v) 7) ~f:send_byte;
  set i.byte_valid 1; set i.framing_error 1; ignore (tick ());
  set i.byte_valid 0; set i.framing_error 0;
  for _ = 1 to 20 do idle () done;
  assert (!accepts=0 && !updates=0 && !clears=0 && List.is_empty !received);
  (* Every partial byte position and a held complete request can be reset. *)
  for position = 0 to 8 do
    reset (); List.iter (List.take (wire_request v) position) ~f:send_byte;
    reset (); send_request v; finish [0;0;34;0;17;0;0;0]
  done;
  (* Reset during final drain must discard pending completion and recover. *)
  reset (); send_request v; set i.tx_ready 1; set i.tx_busy 0;
  while List.length !received < 8 do ignore (tick ()) done;
  set i.tx_ready 0; set i.tx_busy 1;
  for _ = 1 to 17 do ignore (tick ()) done;
  assert (List.length !received=8 && !completions=0);
  reset (); for _ = 1 to 5 do idle () done; assert (!completions=0);
  send_request v; finish [0;0;34;0;17;0;0;0];
  printf "PASS byte composition: 100 oracle packets; exact bytes, stalls, drain, fault collisions, partial/drain reset recovery\n"

let () = match Array.to_list (Sys.get_argv ()) with
  | [_; "mocks"] -> mocks ()
  | [_; "replay"; path] -> replay path
  | [_; "bytes"; path] -> bytes path
  | [_; "emit"; kind; path] -> emit kind path
  | _ -> failwith "usage: transaction_verify (mocks | replay TRACE | bytes TRACE | emit KIND RTL)"
