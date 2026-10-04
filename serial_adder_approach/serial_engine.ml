open! Hardcaml
open! Signal
module I = Hardcaml_gqh.Engine.Update.I
module O = Hardcaml_gqh.Engine.Update.O

(* Borrow the command until result_valid. IDLE -> PRIME -> twenty RUN cycles
   -> RESULT. Read bit k+1 while computing/writing bit k. RAM is never reset;
   per-item validity masks the sum and metadata after reset/session_clear.
   A reset can interrupt bit writes: the caller must restart at index zero and
   fully warm up, just as for the existing packet controller/engine contract.

   Architecture inspired by blacklist-gqh's bit-addressed RAM serial engine.
   Retain our comparison flags instead of storing/re-comparing previous prices. *)
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let data_spec = Reg_spec.create ~clock:i.clock () in
  let state_d = wire 2 in
  let state = reg spec state_d -- "engine_state" in
  let idle = state ==:. 0 and prime = state ==:. 1 and run = state ==:. 2 in
  let active = ~:(i.reset) in
  let update_ready = idle &: active &: ~:(i.session_clear) in
  let accept = update_ready &: i.update_valid in
  let digit_d = wire 5 in
  let digit = reg data_spec digit_d -- "engine_digit" in
  let finish = run &: (digit ==:. 19) &: active in
  let read = (prime |: run) &: active in
  let write = run &: active in
  let next_digit = digit +:. 1 in
  digit_d <-- mux2 accept (zero 5) (mux2 run next_digit digit);
  state_d <-- mux2 idle (mux2 accept (of_int_trunc ~width:2 1) state)
    (mux2 prime (of_int_trunc ~width:2 2)
       (mux2 run (mux2 finish (of_int_trunc ~width:2 3) state)
          (mux2 i.result_ready (zero 2) state)));
  let command = i.update in
  let scalar_spec = Reg_spec.create ~clock:i.clock
    ~clear:(i.reset |: (idle &: i.session_clear)) () in
  let valid_a = reg scalar_spec ~enable:(finish &: ~:(command.item_select)) vdd
    -- "record_valid_a" in
  let valid_b = reg scalar_spec ~enable:(finish &: command.item_select) vdd
    -- "record_valid_b" in
  let valid = mux2 command.item_select valid_b valid_a in
  let attributes = [Rtl_attribute.create
    ~applies_to:[Rtl_attribute.Applies_to.Memories]
    ~value:(Rtl_attribute.Value.String "block_ram") "syn_ramstyle"] in
  let ram name size we wa wd re ra =
    Ram.create ~name ~size ~attributes
      ~collision_mode:Ram.Collision_mode.Read_before_write
      ~write_ports:[| { Write_port.write_clock = i.clock; write_enable = we
        ; write_address = wa; write_data = wd } |]
      ~read_ports:[| { Read_port.read_clock = i.clock; read_enable = re
        ; read_address = ra } |] () |> fun q -> q.(0)
  in
  let rd_digit = mux2 prime (zero 5) next_digit in
  let price_step = ~:(msb digit) in
  let price_bit = price_step &: mux (sel_bottom digit ~width:4) (bits_lsb command.price) in
  let history_address bit_index =
    concat_msb [command.item_select; command.window_position; sel_bottom bit_index ~width:4] in
  let oldest = ram "serial_history" 512 (write &: price_step)
    (history_address digit) price_bit read (history_address rd_digit) in
  let sum_next = wire 1 in
  let sum = ram "serial_sums" 64 write
    (concat_msb [command.item_select; digit]) sum_next read
    (concat_msb [command.item_select; rd_digit]) in
  let meta_next = wire 4 in
  let meta = ram "serial_metadata" 2 finish command.item_select meta_next
    (prime &: active) command.item_select in
  let sum_bit = valid &: sum in
  let old_bit = ~:(command.warmup) &: price_step &: oldest in
  let carry_d = wire 1 and borrow_d = wire 1 in
  let carry = reg data_spec carry_d and borrow = reg data_spec borrow_d in
  let add_bit = sum_bit ^: price_bit ^: carry in
  let new_bit = add_bit ^: old_bit ^: borrow in
  sum_next <-- new_bit;
  let carry_next = (sum_bit &: price_bit) |: (carry &: (sum_bit ^: price_bit)) in
  let borrow_next = (~:add_bit &: old_bit) |: (borrow &: ~:(add_bit ^: old_bit)) in
  carry_d <-- mux2 accept gnd (mux2 run carry_next carry);
  borrow_d <-- mux2 accept gnd (mux2 run borrow_next borrow);
  let delay_d = wire 4 in
  let delay = reg data_spec delay_d in
  delay_d <-- mux2 run (concat_msb [sel_bottom delay ~width:3; price_bit]) delay;
  let above_d = wire 1 and below_d = wire 1 in
  let above = reg data_spec above_d and below = reg data_spec below_d in
  let different = (digit >=:. 4) &: (msb delay ^: new_bit) in
  (* LSB first: every more-significant unequal bit supersedes the relation. *)
  let next_above = mux2 different (msb delay) above in
  let next_below = mux2 different new_bit below in
  above_d <-- mux2 accept gnd (mux2 run next_above above);
  below_d <-- mux2 accept gnd (mux2 run next_below below);
  let previous_below = valid &: bit meta ~pos:0 in
  let previous_above = valid &: bit meta ~pos:1 in
  let held = mux2 valid (sel_top meta ~width:2) (zero 2) in
  let buy = ~:previous_above &: next_above in
  let sell = ~:previous_below &: next_below in
  let action = mux2 command.warmup (zero 2)
    (mux2 buy (of_int_trunc ~width:2 2)
       (mux2 sell (of_int_trunc ~width:2 1) held)) in
  meta_next <-- concat_msb [action; next_above; next_below];
  let action = reg scalar_spec ~enable:finish action in
  { O.update_ready; result_valid = (state ==:. 3) &: active; action }

let hierarchical scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~instance:"engine" ~scope ~name:"gqh_update_engine" create i
