module Payload = Protocol.Types
open! Hardcaml
open! Signal

module I = struct
  type 'a t =
    { clock : 'a
    ; reset : 'a
    ; session_clear : 'a
    ; update : 'a Payload.Update.t
    ; update_valid : 'a
    ; result_ready : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t = { update_ready : 'a; result_valid : 'a; action : 'a [@bits 2] }
  [@@deriving hardcaml]
end

(* IDLE -> READ -> COMMIT -> RESULT -> IDLE. At the acceptance edge E0,
   capture all fields. E1 reads RAM. E2 commits RAM/scalars and publishes the
   result. E3 is the earliest result transfer. No writes occur in RESULT.
   Reset aborts any command/result; RAM is deliberately neither reset nor init.
   session_clear is legal only in IDLE and wins over command acceptance. *)
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let state_next = wire 2 in
  let state = reg spec state_next -- "engine_state" in
  let idle = state ==:. 0 in
  let clear = idle &: i.session_clear in
  let scalar_spec = Reg_spec.create ~clock:i.clock ~clear:(i.reset |: clear) () in
  let update_ready = idle &: ~:(i.reset) &: ~:(i.session_clear) in
  let accept = update_ready &: i.update_valid in
  let command = Payload.Update.map i.update ~f:(reg spec ~enable:accept) in
  let read = state ==:. 1 in
  let commit = (state ==:. 2) &: ~:(i.reset) in
  let result = state ==:. 3 in
  state_next <-- mux2 idle (mux2 accept (of_int_trunc ~width:2 1) state)
    (mux2 read (of_int_trunc ~width:2 2)
       (mux2 (state ==:. 2) (of_int_trunc ~width:2 3)
          (mux2 i.result_ready (zero 2) state)));
  let address = concat_msb [command.item_select; command.window_position] in
  let oldest =
    Ram.create ~name:"engine_history" ~size:32
      ~collision_mode:Ram.Collision_mode.Read_before_write
      ~write_ports:[| { Write_port.write_clock = i.clock
        ; write_enable = commit; write_address = address
        ; write_data = command.price } |]
      ~read_ports:[| { Read_port.read_clock = i.clock
        ; read_enable = read &: ~:(i.reset); read_address = address } |] ()
    |> fun q -> q.(0)
  in
  let sum_next = wire 20 and action_next = wire 2 in
  let scalar item suffix =
    let enable = commit &: (command.item_select ==:. item) in
    let sum = reg scalar_spec ~enable sum_next -- ("sum_" ^ suffix) in
    let previous = reg scalar_spec ~enable command.price -- ("previous_" ^ suffix) in
    let held = reg scalar_spec ~enable action_next -- ("held_" ^ suffix) in
    sum, previous, held
  in
  let sum_a, previous_a, held_a = scalar 0 "a" in
  let sum_b, previous_b, held_b = scalar 1 "b" in
  let select a b = mux2 command.item_select b a in
  let old_sum = select sum_a sum_b in
  let previous = select previous_a previous_b in
  let held = select held_a held_b in
  let new_sum = mux2 command.warmup old_sum (old_sum -: uresize oldest ~width:20)
                +: uresize command.price ~width:20 in
  let old_average = Signal.select old_sum ~high:19 ~low:4 in
  let new_average = Signal.select new_sum ~high:19 ~low:4 in
  let buy = (previous <=: old_average) &: (command.price >: new_average) in
  let sell = (previous >=: old_average) &: (command.price <: new_average) in
  let action = mux2 command.warmup (zero 2)
    (mux2 buy (of_int_trunc ~width:2 Payload.action_buy)
       (mux2 sell (of_int_trunc ~width:2 Payload.action_sell) held)) in
  sum_next <-- new_sum;
  action_next <-- action;
  let action = reg scalar_spec ~enable:commit action in
  { O.update_ready; result_valid = result &: ~:(i.reset); action }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_update_engine" create i
