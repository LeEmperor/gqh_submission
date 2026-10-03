open! Core
open! Hardcaml
open! Hardcaml_gqh
let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let eq what actual expected =
  if actual <> expected then failwithf "%s: got %d expected %d" what actual expected ()
let scope () = Scope.create ~flatten_design:true ()

let rx_tests () =
  let module S = Cyclesim.With_interface (Uart.Rx.I) (Uart.Rx.O) in
  let sim = S.create (Uart.Rx.create ~cycles_per_bit:100 (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let bytes = ref [] and errors = ref 0 in
  let previous_valid = ref 0 in
  let step level =
    set i.rx level; Cyclesim.cycle sim;
    let v = get o.byte_valid in
    if v = 1 then (
      eq "single cycle valid" !previous_valid 0;
      eq "valid excludes error" (get o.framing_error) 0;
      bytes := !bytes @ [get o.byte_data]);
    previous_valid := v;
    errors := !errors + get o.framing_error in
  let hold n level = for _ = 1 to n do step level done in
  let frame ?(stop=1) period byte =
    hold period 0;
    for bit = 0 to 7 do hold period ((byte lsr bit) land 1) done;
    hold period stop in
  set i.reset 1; hold 3 1; set i.reset 0; hold 10 1;
  for b = 0 to 255 do frame 100 b done;
  hold 100 1;
  eq "all bytes" (List.length !bytes) 256;
  List.iteri !bytes ~f:(fun idx b -> eq "LSB assembly" b idx);
  bytes := [];
  for period = 98 to 102 do
    for phase = 0 to 9 do hold phase 1; frame period (phase * 23) done
  done;
  hold 100 1;
  eq "98..102 clocks mismatch" (List.length !bytes) 50;
  List.iteri !bytes ~f:(fun idx b -> eq "mismatch data" b ((idx mod 10) * 23));
  bytes := [];
  hold 20 0; hold 200 1;
  eq "false start" (List.length !bytes) 0;
  frame ~stop:0 100 0x69; hold 2000 0;
  eq "invalid stop and break" !errors 1;
  eq "invalid frame unpublished" (List.length !bytes) 0;
  hold 100 1; frame 100 0xa5; hold 100 1;
  eq "recover after break" (List.hd_exn !bytes) 0xa5;
  bytes := []; hold 350 0; set i.reset 1; hold 3 0;
  set i.reset 0; hold 1200 0; hold 200 1;
  (* A low input after reset may start one candidate, but never emits a byte. *)
  eq "reset cancels partial frame" (List.length !bytes) 0;
  frame 100 0x31; hold 100 1; eq "post reset byte" (List.hd_exn !bytes) 0x31

let tx_tests gap =
  let module S = Cyclesim.With_interface (Uart.Tx.I) (Uart.Tx.O) in
  let period = 7 in
  let sim = S.create (Uart.Tx.create ~cycles_per_bit:period ~extra_idle_cycles:gap (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let cycle () = Cyclesim.cycle sim in
  set i.reset 1; cycle (); set i.reset 0; cycle ();
  eq "idle" (get o.tx) 1; eq "ready" (get o.tx_ready) 1;
  let send byte =
    set i.tx_valid 1; set i.tx_data byte; cycle ();
    (* Hold valid and change input while busy: payload must have been latched. *)
    set i.tx_data (byte lxor 255);
    for tick = 0 to 10 * period + gap - 1 do
      let expected =
        if tick < period then 0
        else if tick < 9 * period then (byte lsr (tick / period - 1)) land 1
        else 1 in
      eq "full framed bit durations" (get o.tx) expected;
      eq "busy through stop/gap" (get o.tx_busy) 1;
      eq "not ready through stop/gap" (get o.tx_ready) 0;
      cycle ()
    done;
    eq "ready after exact duration" (get o.tx_ready) 1;
    eq "idle after duration" (get o.tx_busy) 0 in
  List.iter [0; 255; 0x81; 0x69; 0x42] ~f:send;
  set i.tx_valid 1; set i.tx_data 0; cycle ();
  for _ = 1 to 12 do cycle () done;
  set i.reset 1; cycle (); eq "reset idle" (get o.tx) 1;
  eq "reset cancels busy" (get o.tx_busy) 0;
  set i.tx_valid 0; set i.reset 0; cycle (); eq "ready after reset" (get o.tx_ready) 1

let decoder_tests () =
  let module S = Cyclesim.With_interface (Protocol.Request_decoder.I) (Protocol.Request_decoder.O) in
  let sim = S.create (Protocol.Request_decoder.create (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let cycle () = Cyclesim.cycle sim in
  let reset () = set i.reset 1; cycle (); set i.reset 0; set i.receive_enable 1; cycle () in
  let byte b = set i.byte_data b; set i.byte_valid 1; cycle (); set i.byte_valid 0; cycle () in
  reset ();
  List.iteri [0xab;0xcd;0x22;0x12;0x34;0x11;0xfe;0xdc] ~f:(fun idx b ->
    byte b; for _ = 1 to idx * 7 do cycle () done;
    eq "publish only byte 7" (get o.request_valid) (if idx = 7 then 1 else 0));
  let check () =
    eq "index endian" (get o.request.index) 0xabcd;
    eq "slot 1 id" (get o.request.slot1_id) 0x22;
    eq "slot 1 price" (get o.request.slot1_price) 0x1234;
    eq "slot 2 id" (get o.request.slot2_id) 0x11;
    eq "byte 7 included" (get o.request.slot2_price) 0xfedc in
  for _ = 1 to 100 do cycle (); check (); eq "held valid" (get o.request_valid) 1 done;
  set i.request_ready 1; cycle (); set i.request_ready 0;
  eq "consumed request" (get o.request_valid) 0;
  set i.receive_enable 0; byte 4; eq "busy input fault" (get o.protocol_fault) 1;
  set i.receive_enable 1; for _ = 1 to 8 do byte 1 done;
  eq "fault inhibits" (get o.request_valid) 0;
  reset (); byte 0xaa; byte 0xbb;
  set i.framing_error 1; cycle (); set i.framing_error 0;
  eq "partial error fault" (get o.protocol_fault) 1;
  for _ = 1 to 8 do byte 0 done; eq "aborted partial" (get o.request_valid) 0;
  reset (); for _ = 1 to 8 do byte 0 done;
  byte 9; eq "held request overflow fault" (get o.protocol_fault) 1;
  eq "fault never publishes new request" (get o.request_valid) 0

let sequencer_tests () =
  let module S = Cyclesim.With_interface (Protocol.Response_sequencer.I) (Protocol.Response_sequencer.O) in
  let sim = S.create (Protocol.Response_sequencer.create (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let cycle () = Cyclesim.cycle sim in
  set i.reset 1; cycle (); set i.reset 0; cycle ();
  set i.response.index 0xabcd; set i.response.slot1_id 0x22; set i.response.slot2_id 0x11;
  set i.response.slot1_action 2; set i.response.slot2_action 1;
  set i.response_valid 1; cycle (); set i.response_valid 0;
  set i.response.index 0; set i.response.slot1_id 0;
  List.iter [0xab;0xcd;0x22;2;0x11;1;0;0] ~f:(fun expected ->
    set i.tx_ready 0; set i.tx_busy 1;
    for _ = 1 to 11 do cycle (); eq "stalled valid" (get o.tx_valid) 1;
      eq "stalled byte" (get o.tx_data) expected; eq "not done" (get o.response_done) 0 done;
    set i.tx_ready 1; cycle (); set i.tx_ready 0);
  eq "exactly eight bytes" (get o.tx_valid) 0;
  for _ = 1 to 100 do cycle (); eq "wait final stop/gap" (get o.response_done) 0 done;
  set i.tx_busy 0; cycle (); eq "done after idle" (get o.response_done) 1;
  cycle (); eq "done pulse" (get o.response_done) 0;
  eq "rearmed" (get o.response_ready) 1

let integration gap =
  let module S = Cyclesim.With_interface (Board.Transport_top.I) (Board.Transport_top.O) in
  let period = 16 in
  let sim = S.create (Board.Transport_top.create ~cycles_per_bit:period
    ~extra_idle_cycles:gap ~half_period_cycles:11 (scope ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let output = ref [] in
  let cycle () = Cyclesim.cycle sim; output := get o.uart_tx_o :: !output in
  let hold n level = set i.uart_rx_i level; for _ = 1 to n do cycle () done in
  let byte b = hold period 0; for bit = 0 to 7 do hold period ((b lsr bit) land 1) done; hold period 1 in
  Cyclesim.reset sim; set i.reset_btn 0; hold 10 1;
  let transact index slot1 slot2 =
    output := [];
    let request = [index lsr 8; index land 255; slot1;0x12;0x34;slot2;0xfe;0xdc] in
    List.iteri request ~f:(fun idx b ->
      byte b;
      if idx < 7 then List.iter !output ~f:(fun level -> eq "no early TX" level 1));
    hold (8 * (10 * period + gap + 4) + 100) 1;
    let samples = Array.of_list (List.rev !output) in
    let cursor = ref 0 and received = ref [] in
    while !cursor < Array.length samples do
      if samples.(!cursor) = 1 then incr cursor else (
        let start = !cursor in
        let at offset = samples.(start + offset) in
        eq "TX start center" (at (period/2)) 0;
        let b = ref 0 in
        for bit = 0 to 7 do b := !b lor (at (period + bit*period + period/2) lsl bit) done;
        eq "TX stop center" (at (9*period + period/2)) 1;
        received := !received @ [!b]; cursor := start + 10*period)
    done;
    if not (List.equal Int.equal !received [index lsr 8;index land 255;slot1;0;slot2;0;0;0])
    then failwith "serial round trip mismatch";
    eq "no fault" (get o.led1_n) 1 in
  transact 0 0x11 0x22; transact 0xabcd 0x22 0x11; transact 1 0x11 0x22;
  (* Abort a partial request, then board reset restores reception. *)
  byte 0xab; byte 0xcd;
  Cyclesim.reset sim; set i.reset_btn 0; hold 10 1;
  transact 0x1234 0x22 0x11

let () =
  rx_tests (); tx_tests 0; tx_tests 13; decoder_tests (); sequencer_tests ();
  integration 0; integration 21;
  printf "PASS: independent RX/TX timing, packet handshakes/faults, serial round trips\n"
