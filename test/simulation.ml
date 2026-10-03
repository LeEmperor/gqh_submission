open! Core
open! Hardcaml
open! Hardcaml_gqh
let set port n = port := Bits.of_int_trunc ~width:(Bits.width !port) n
let get port = Bits.to_int_trunc !port
let equal what actual expected =
  if actual <> expected then failwithf "%s: got %d, expected %d" what actual expected ()
let bringup () =
  (* Cyclesim handles synchronous clear; actual asynchronous button behavior
     is exercised in Icarus on the emitted complete top. *)
  let module Sim = Cyclesim.With_interface (Board.Heartbeat.I) (Board.Heartbeat.O) in
  let sim = Sim.create (Board.Heartbeat.create ~half_period_cycles:3
    (Scope.create ~flatten_design:true ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let step expected_led =
    Cyclesim.cycle sim; equal "LED" (get o.led_n) expected_led in
  set i.reset 1;
  for _ = 1 to 4 do step 1 done;
  set i.reset 0;
  for _ = 1 to 4 do step 1; step 1; step 0; step 0; step 0; step 1 done;
  step 1; step 1; step 0;
  set i.reset 1; step 1; step 1;
  set i.reset 0; step 1; step 1; step 0;
  let module Top_sim = Cyclesim.With_interface (Board.Top.I) (Board.Top.O) in
  let top = Top_sim.create (Board.Top.create ~half_period_cycles:3
    (Scope.create ~flatten_design:true ())) in
  let ti = Cyclesim.inputs top and to_ = Cyclesim.outputs top in
  for cycle = 0 to 31 do
    set ti.uart_rx_i (cycle land 1);
    Cyclesim.cycle top;
    equal "TX idle" (get to_.uart_tx_o) 1;
    equal "unused LED" (get to_.led1_n) 1
  done
let history () =
  let module Sim = Cyclesim.With_interface (History_probe.I) (History_probe.O) in
  let sim = Sim.create (History_probe.create (Scope.create ~flatten_design:true ())) in
  let i = Cyclesim.inputs sim and o = Cyclesim.outputs sim in
  let value addr = (addr * 2053 + 17) land 65535 in
  set i.write_enable 1;
  for addr = 0 to 31 do
    set i.write_address addr; set i.write_data (value addr); Cyclesim.cycle sim
  done;
  set i.write_enable 0;
  for addr = 31 downto 0 do
    set i.read_address addr;
    let old = get o.read_data in
    Cyclesim.cycle_before_clock_edge sim;
    equal "read changes only at edge" (get o.read_data) old;
    Cyclesim.cycle_at_clock_edge sim; Cyclesim.cycle_after_clock_edge sim;
    equal "one edge read" (get o.read_data) (value addr)
  done;
  set i.read_address 7; set i.write_address 7;
  set i.write_enable 1; set i.write_data 65535;
  Cyclesim.cycle sim;
  equal "collision reads old word" (get o.read_data) (value 7);
  set i.write_enable 0; Cyclesim.cycle sim;
  equal "subsequent read sees new word" (get o.read_data) 65535;
  set i.write_data 0; Cyclesim.cycle sim;
  equal "disabled writes preserve word" (get o.read_data) 65535
let () = bringup (); history (); printf "PASS: heartbeat/reset/idle and RAM latency/collision\n"
