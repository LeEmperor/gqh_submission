open! Core
open! Hardcaml
open! Hardcaml_gqh

let set p n = p := Bits.of_int_trunc ~width:(Bits.width !p) n
let get p = Bits.to_int_trunc !p
let eq what a b = if a <> b then failwithf "%s: got %d expected %d" what a b ()
let bytes hex = List.init 8 ~f:(fun n -> Int.of_string ("0x" ^ String.sub hex ~pos:(2*n) ~len:2))
let () =
  let module S = Cyclesim.With_interface (Board.Competition_top.I) (Board.Competition_top.O) in
  let period = 16 in
  (* Multiple flags select the exact measured parent combination. Omitted
     settings inherit competition defaults, including a selected TX shifter. *)
  let variants = List.drop (Array.to_list (Sys.get_argv ())) 2 in
  let controller_encoding, sequencer_encoding, rx_encoding, tx_encoding, tx_shift_register =
    List.fold variants ~init:(None,None,None,None,None)
      ~f:(fun (controller,sequencer,rx,tx,shift) variant ->
        let binary = Some Always.State_machine.Encoding.Binary
        and onehot = Some Always.State_machine.Encoding.Onehot in
        match variant with
        | "packet-ram" | "rx-factored-timer" | "tx-factored-timer" | "default" -> controller,sequencer,rx,tx,shift
        | "controller-binary" -> binary,sequencer,rx,tx,shift
        | "controller-onehot" -> onehot,sequencer,rx,tx,shift
        | "sequencer-binary" -> controller,binary,rx,tx,shift
        | "sequencer-onehot" -> controller,onehot,rx,tx,shift
        | "rx-binary" -> controller,sequencer,binary,tx,shift
        | "rx-onehot" -> controller,sequencer,onehot,tx,shift
        | "tx-binary" -> controller,sequencer,rx,binary,shift
        | "tx-onehot" -> controller,sequencer,rx,onehot,shift
        | "tx-shift" -> controller,sequencer,rx,tx,Some true
        | "tx-indexed" -> controller,sequencer,rx,tx,Some false
        | _ -> failwith "unknown serial optimization variant") in
  let enabled name = String.equal (Option.value (Sys.getenv name) ~default:"0") "1" in
  let sim = S.create (Board.Competition_top.create
    ~records_in_bram:(enabled "HOPT_RECORDS_IN_BRAM")
    ~borrow_command:(enabled "HOPT_BORROW_COMMAND")
    ~delta_arithmetic:(enabled "HOPT_DELTA_ARITHMETIC")
    ~difference_relation:(enabled "HOPT_DIFFERENCE_RELATION") ~packet_ram:(List.mem variants "packet-ram" ~equal:String.equal)
    ~rx_factored_timer:(List.mem variants "rx-factored-timer" ~equal:String.equal)
    ~tx_factored_timer:(List.mem variants "tx-factored-timer" ~equal:String.equal) ~cycles_per_bit:period
    ?controller_encoding ?sequencer_encoding ?rx_encoding ?tx_encoding ?tx_shift_register
    ~half_period_cycles:11 (Scope.create ~flatten_design:true ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let samples = ref [] in
  let step () = Cyclesim.cycle sim; samples := get o.uart_tx_o :: !samples in
  let hold n level = set i.uart_rx_i level; for _ = 1 to n do step () done in
  let byte b = hold period 0;
    for bit = 0 to 7 do hold period ((b lsr bit) land 1) done; hold period 1 in
  Cyclesim.reset sim; set i.reset_btn 0; hold 12 1;
  In_channel.read_lines (Sys.get_argv ()).(1) |> List.iteri ~f:(fun row line ->
    match String.split line ~on:' ' with
    | [request; expected] ->
      samples := [];
      List.iteri (bytes request) ~f:(fun pos b ->
        byte b;
        if pos < 7 then List.iter !samples ~f:(fun x -> eq "no early TX" x 1);
        if pos = row mod 7 then hold (period*20) 1);
      hold (period*85 + 100) 1;
      let data = Array.of_list_rev !samples in
      let cursor = ref 0 and received = ref [] in
      while !cursor < Array.length data do
        if data.(!cursor) = 1 then incr cursor else (
          let start = !cursor in
          let at offset = data.(start+offset) in
          eq "start center" (at (period/2)) 0;
          let b = ref 0 in
          for bit = 0 to 7 do
            b := !b lor (at (period + bit*period + period/2) lsl bit)
          done;
          (* Check the entire stop bit, not just its center. *)
          for offset = 9*period to 10*period-1 do eq "full stop" (at offset) 1 done;
          received := !b :: !received; cursor := start+10*period)
      done;
      if not (List.equal Int.equal (List.rev !received) (bytes expected))
      then failwithf "serial response row %d" row ();
      eq "fault off" (get o.led1_n) 1
    | _ -> failwith "bad trace");
  printf "PASS: production composition Cyclesim serial oracle replay (divisor 16)\n"
