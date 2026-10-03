open! Core
open! Hardcaml
open! Hardcaml_gqh

(* Only this module touches simulation/Bits. Transfers use before-edge outputs;
   registered publication, faults and completion use after-edge outputs. All
   scenarios have finite schedules, so a stuck DUT fails rather than hanging. *)
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let scope () = Scope.create ~flatten_design:true ()
(* Explicit sequencing: collection builders may evaluate callbacks in reverse order. *)
let collect count f =
  let rec loop left acc =
    if left = 0 then List.rev acc else (
      let observation = f () in
      loop (left - 1) (observation :: acc)) in
  loop count []
;;
module Decoder = struct
  module Dut = Protocol.Request_decoder
  module Sim = Cyclesim.With_interface (Dut.I) (Dut.O)
  type observation = { valid : bool; fault : bool; fields : int list }
  [@@deriving sexp, equal, compare]
  type t = { i : Bits.t ref Dut.I.t; cycle : unit -> observation * observation }
  let create () =
    let sim = Sim.create (Dut.create (scope ())) in
    let i = Cyclesim.inputs sim in
    let snapshot edge () =
      let o = Cyclesim.outputs ~clock_edge:edge sim in
      { valid = get o.request_valid = 1; fault = get o.protocol_fault = 1
      ; fields = [get o.request.index; get o.request.slot1_id; get o.request.slot1_price;
                  get o.request.slot2_id; get o.request.slot2_price] } in
    let cycle () =
      Cyclesim.cycle_check sim;
      Cyclesim.cycle_before_clock_edge sim;
      let before = snapshot Side.Before () in
      Cyclesim.cycle_at_clock_edge sim;
      Cyclesim.cycle_after_clock_edge sim;
      before, snapshot Side.After () in
    { i; cycle }
  ;;
  let reset t =
    set t.i.reset 1;
    ignore (t.cycle () : observation * observation);
    set t.i.reset 0; set t.i.byte_valid 0; set t.i.framing_error 0;
    set t.i.request_ready 0; set t.i.receive_enable 1;
    snd (t.cycle ())
  ;;
  let byte t value =
    set t.i.byte_data value; set t.i.byte_valid 1;
    let result = t.cycle () in
    set t.i.byte_valid 0;
    result
  ;;
  let packet = [0xab; 0xcd; 0x22; 0x12; 0x34; 0x11; 0xfe; 0xdc]
  let fields = [0xabcd; 0x22; 0x1234; 0x11; 0xfedc]
  let load t = List.iter packet ~f:(fun b -> ignore (byte t b : observation * observation))
  let run_reset count =
    let t = create () in
    ignore (reset t : observation);
    List.iter (List.take packet count) ~f:(fun b -> ignore (byte t b : observation * observation));
    let cleared = reset t in
    let publications = List.map packet ~f:(fun b -> (snd (byte t b)).valid) in
    let held = snd (t.cycle ()) in
    set t.i.request_ready 1;
    let before, after = t.cycle () in
    cleared, publications, held, before.valid, after.valid
  ;;
  type collision = Framing | Unexpected_byte [@@deriving sexp]
  type collision_result =
    { accepted : bool; before : observation; after : observation; locked : observation
    ; recovered : observation }
  [@@deriving sexp]
  let run_collision kind ready =
    let t = create () in
    ignore (reset t : observation); load t;
    set t.i.request_ready (Bool.to_int ready);
    (match kind with
     | Framing -> set t.i.framing_error 1
     | Unexpected_byte -> set t.i.byte_data 0x99; set t.i.byte_valid 1);
    let before, after = t.cycle () in
    set t.i.byte_valid 0; set t.i.framing_error 0;
    load t;
    let locked = snd (t.cycle ()) in
    ignore (reset t : observation); load t;
    let recovered = snd (t.cycle ()) in
    { accepted = ready && before.valid; before; after; locked; recovered }
  ;;
  let run_final_error () =
    let t = create () in
    ignore (reset t : observation);
    List.iter (List.take packet 7) ~f:(fun b -> ignore (byte t b : observation * observation));
    set t.i.framing_error 1;
    snd (byte t 0xdc)
  ;;
end

module Sequencer = struct
  module Dut = Protocol.Response_sequencer
  module Sim = Cyclesim.With_interface (Dut.I) (Dut.O)
  type observation = { ready : bool; done_ : bool; valid : bool; data : int }
  [@@deriving sexp, equal, compare]
  type t = { i : Bits.t ref Dut.I.t; cycle : unit -> observation * observation }
  let create () =
    let sim = Sim.create (Dut.create (scope ())) in
    let i = Cyclesim.inputs sim in
    let snapshot edge () =
      let o = Cyclesim.outputs ~clock_edge:edge sim in
      { ready = get o.response_ready = 1; done_ = get o.response_done = 1
      ; valid = get o.tx_valid = 1; data = get o.tx_data } in
    let cycle () =
      Cyclesim.cycle_check sim;
      Cyclesim.cycle_before_clock_edge sim;
      let before = snapshot Side.Before () in
      Cyclesim.cycle_at_clock_edge sim;
      Cyclesim.cycle_after_clock_edge sim;
      before, snapshot Side.After () in
    { i; cycle }
  ;;
  let reset t =
    set t.i.reset 1;
    let result = t.cycle () in
    set t.i.reset 0; set t.i.response_valid 0; set t.i.tx_ready 0; set t.i.tx_busy 0;
    result
  ;;
  let offer t fields =
    match fields with
    | [index; id1; action1; id2; action2] ->
      set t.i.response.index index; set t.i.response.slot1_id id1;
      set t.i.response.slot1_action action1; set t.i.response.slot2_id id2;
      set t.i.response.slot2_action action2; set t.i.response_valid 1
    | _ -> failwith "response must have five fields"
  ;;
  let bytes = function
    | [index; id1; action1; id2; action2] ->
      [index lsr 8; index land 255; id1; action1; id2; action2; 0; 0]
    | _ -> failwith "response must have five fields"
  ;;
  let first = [0xabcd; 0x22; 2; 0x11; 1]
  let second = [0x1357; 0x11; 1; 0x22; 0]
  type result = { bytes : int list; acceptances : int; completions : int }
  [@@deriving sexp, equal, compare]
  let run_pair first second stalls drain =
    let t = create () in
    ignore (reset t : observation * observation);
    let accepted = ref 0 and completions = ref 0 and sent = ref [] in
    let tick () =
      let before, after = t.cycle () in
      if before.ready && get t.i.response_valid = 1 then incr accepted;
      if before.valid && get t.i.tx_ready = 1 then sent := before.data :: !sent;
      if after.done_ then incr completions;
      before, after in
    let quiet o =
      [%test_result: bool] o.ready ~expect:false;
      [%test_result: bool] o.done_ ~expect:false in
    let send expected =
      List.iteri (bytes expected) ~f:(fun idx value ->
        set t.i.tx_ready 0;
        for _ = 1 to List.nth_exn stalls idx do
          let before, after = tick () in
          quiet before; quiet after;
          [%test_result: bool] before.valid ~expect:true;
          [%test_result: int] before.data ~expect:value;
          [%test_result: observation] after ~expect:before
        done;
        set t.i.tx_ready 1;
        let before, _ = tick () in
        quiet before;
        [%test_result: bool] before.valid ~expect:true;
        [%test_result: int] before.data ~expect:value);
      set t.i.tx_ready 0;
      for _ = 1 to drain do
        let before, after = tick () in
        quiet before; quiet after;
        [%test_result: bool] after.valid ~expect:false
      done;
      set t.i.tx_busy 0;
      let _, after = tick () in
      [%test_result: bool] after.done_ ~expect:true;
      [%test_result: bool] after.ready ~expect:true in
    offer t first;
    ignore (tick () : observation * observation);
    (* A compliant producer holds the second response through Send and Drain. *)
    offer t second; set t.i.tx_busy 1;
    send first;
    ignore (tick () : observation * observation);
    set t.i.response_valid 0;
    (* Disturb every live input field after capture. *)
    offer t [0; 0; 0; 0; 0]; set t.i.response_valid 0; set t.i.tx_busy 1;
    send second;
    for _ = 1 to 12 do
      let _, after = tick () in
      [%test_result: bool] after.done_ ~expect:false;
      [%test_result: bool] after.valid ~expect:false;
      [%test_result: bool] after.ready ~expect:true
    done;
    { bytes = List.rev !sent; acceptances = !accepted; completions = !completions }
  ;;
  let run_reset position =
    let t = create () in
    ignore (reset t : observation * observation);
    offer t first; ignore (t.cycle () : observation * observation);
    set t.i.response_valid 0; set t.i.tx_busy 1; set t.i.tx_ready 1;
    for _ = 1 to position do ignore (t.cycle () : observation * observation) done;
    set t.i.tx_ready 0;
    for _ = 1 to 3 do ignore (t.cycle () : observation * observation) done;
    (* Also assert offers during reset: neither interface can transfer. *)
    offer t second; set t.i.tx_ready 1;
    let before, after = reset t in
    let idle = collect 12 (fun () -> snd (t.cycle ())) in
    offer t second;
    let accepted, _ = t.cycle () in
    set t.i.response_valid 0; set t.i.tx_ready 1; set t.i.tx_busy 1;
    let sent = collect 8 (fun () ->
      let before, _ = t.cycle () in
      [%test_result: bool] before.valid ~expect:true;
      [%test_result: bool] before.ready ~expect:false;
      before.data) in
    set t.i.tx_ready 0;
    let _, waiting = t.cycle () in
    set t.i.tx_busy 0;
    let _, done_ = t.cycle () in
    let _, next = t.cycle () in
    before, after, idle, accepted.ready, sent, waiting, done_, next
  ;;
end
