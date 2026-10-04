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
let create ?(borrow_command = false) ?(delta_arithmetic = false)
  ?(difference_relation = false) ?(records_in_bram = false) _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let state_next = wire 2 in
  let state = reg spec state_next -- "engine_state" in
  let idle = state ==:. 0 in
  let clear = idle &: i.session_clear in
  let scalar_spec = Reg_spec.create ~clock:i.clock ~clear:(i.reset |: clear) () in
  let update_ready = idle &: ~:(i.reset) &: ~:(i.session_clear) in
  let accept = update_ready &: i.update_valid in
  let command = if borrow_command then i.update
    else Payload.Update.map i.update ~f:(reg spec ~enable:accept) in
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
      (* Gowin's supported inference control applies to this array only. Keep
         the unreset synchronous read-first model and engine schedule intact;
         actual BSRAM mapping must be checked in the exact-device build. *)
      ~attributes:[Rtl_attribute.create
        ~applies_to:[Rtl_attribute.Applies_to.Memories]
        ~value:(Rtl_attribute.Value.String "block_ram") "syn_ramstyle"]
      ~collision_mode:Ram.Collision_mode.Read_before_write
      ~write_ports:[| { Write_port.write_clock = i.clock
        ; write_enable = commit; write_address = address
        ; write_data = command.price } |]
      ~read_ports:[| { Read_port.read_clock = i.clock
        ; read_enable = read &: ~:(i.reset); read_address = address } |] ()
    |> fun q -> q.(0)
  in
  let old_sum, previous_below, previous_above, held, commit_record =
    if records_in_bram then (
      let record_next = wire 24 in
      let record_valid item suffix =
        reg scalar_spec ~enable:(commit &: (command.item_select ==:. item)) vdd
        -- ("record_valid_" ^ suffix)
      in
      let valid_a = record_valid 0 "a" and valid_b = record_valid 1 "b" in
      let valid = mux2 command.item_select valid_b valid_a in
      let stored =
        Ram.create ~name:"engine_records" ~size:2
          ~attributes:[Rtl_attribute.create
            ~applies_to:[Rtl_attribute.Applies_to.Memories]
            ~value:(Rtl_attribute.Value.String "block_ram") "syn_ramstyle";
            Rtl_attribute.create ~applies_to:[Rtl_attribute.Applies_to.Memories]
            ~value:(Rtl_attribute.Value.String "block") "ram_style"]
          ~collision_mode:Ram.Collision_mode.Read_before_write
          ~write_ports:[| { Write_port.write_clock = i.clock
            ; write_enable = commit; write_address = command.item_select
            ; write_data = record_next } |]
          ~read_ports:[| { Read_port.read_clock = i.clock
            ; read_enable = read &: ~:(i.reset); read_address = command.item_select } |] ()
        |> fun q -> q.(0)
      in
      (* Resettable validity prevents stale or poisoned RAM from affecting either
         item's zero initial scalar state. Memory is never reset or initialized. *)
      let record = mux2 valid stored (zero 24) in
      let old_sum = Signal.select record ~high:19 ~low:0 in
      let previous_below = bit record ~pos:20 and previous_above = bit record ~pos:21 in
      let held = Signal.select record ~high:23 ~low:22 in
      old_sum, previous_below, previous_above, held,
      (fun sum action below above ->
        record_next <-- concat_msb [action; above; below; sum])
    ) else (
      let sum_next = wire 20 and action_next = wire 2 in
      let below_next = wire 1 and above_next = wire 1 in
      let scalar item suffix =
        let enable = commit &: (command.item_select ==:. item) in
        let sum = reg scalar_spec ~enable sum_next -- ("sum_" ^ suffix) in
        (* Commit the relation on warm-up too: index 15 prepares index 16.
           Clear means zero price versus zero average (both flags false). *)
        let below = reg scalar_spec ~enable below_next -- ("previous_below_" ^ suffix) in
        let above = reg scalar_spec ~enable above_next -- ("previous_above_" ^ suffix) in
        let held = reg scalar_spec ~enable action_next -- ("held_" ^ suffix) in
        sum, below, above, held
      in
      let sum_a, below_a, above_a, held_a = scalar 0 "a" in
      let sum_b, below_b, above_b, held_b = scalar 1 "b" in
      let select a b = mux2 command.item_select b a in
      let old_sum = select sum_a sum_b in
      let previous_below = select below_a below_b in
      let previous_above = select above_a above_b in
      let held = select held_a held_b in
      old_sum, previous_below, previous_above, held,
      (fun sum action below above ->
        sum_next <-- sum; action_next <-- action;
        below_next <-- below; above_next <-- above)
    )
  in
  let new_sum =
    if delta_arithmetic then (
      (* Both prices are unsigned 16 bits, so their signed difference fits
         exactly in 17 bits. Extend its sign into the full 20-bit sum. Mask
         stale history before subtraction during warm-up. *)
      let outgoing = mux2 command.warmup (zero 16) oldest in
      let delta = uresize command.price ~width:17 -: uresize outgoing ~width:17 in
      old_sum +: sresize delta ~width:20)
    else mux2 command.warmup old_sum (old_sum -: uresize oldest ~width:20)
           +: uresize command.price ~width:20 in
  let new_average = Signal.select new_sum ~high:19 ~low:4 in
  let current_below, current_above =
    if difference_relation then (
      let difference = uresize command.price ~width:17 -: uresize new_average ~width:17 in
      let below = msb difference in
      below, ~:below &: (Signal.select difference ~high:15 ~low:0 <>:. 0))
    else command.price <: new_average, command.price >: new_average in
  let buy = ~:previous_above &: current_above in
  let sell = ~:previous_below &: current_below in
  let action = mux2 command.warmup (zero 2)
    (mux2 buy (of_int_trunc ~width:2 Payload.action_buy)
       (mux2 sell (of_int_trunc ~width:2 Payload.action_sell) held)) in
  commit_record new_sum action current_below current_above;
  let action = reg scalar_spec ~enable:commit action in
  { O.update_ready; result_valid = result &: ~:(i.reset); action }

let hierarchical ?instance ?borrow_command ?delta_arithmetic ?difference_relation ?records_in_bram scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_update_engine"
    (create ?borrow_command ?delta_arithmetic ?difference_relation ?records_in_bram) i
