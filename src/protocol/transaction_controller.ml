module Payload = Types
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a
    ; request : 'a Payload.Request.t; request_valid : 'a
    ; update_ready : 'a; result_valid : 'a; action : 'a [@bits 2]
    ; response_ready : 'a; response_done : 'a
    }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { request_ready : 'a; receive_enable : 'a
    ; update : 'a Payload.Update.t; update_valid : 'a
    ; result_ready : 'a; session_clear : 'a
    ; response : 'a Payload.Response.t; response_valid : 'a
    }
  [@@deriving hardcaml]
end
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  (* Explicit one-hot phases with local next-bit equations. Dispatch/result
     are shared by both slots; the slot bit changes only on result transfer.
     No synthesizer-specific FSM attribute or binary decoder is required. *)
  let idle = Variable.reg spec ~clear_to:vdd ~width:1 in
  let await_clear_idle = Variable.reg spec ~width:1 in
  let clear = Variable.reg spec ~width:1 in
  let dispatch = Variable.reg spec ~width:1 in
  let result = Variable.reg spec ~width:1 in
  let response = Variable.reg spec ~width:1 in
  let drain = Variable.reg spec ~width:1 in
  let second = Variable.reg spec ~width:1 in
  let pointer = Variable.reg spec ~width:4 in
  let action1 = Variable.reg spec ~width:2 in
  let action2 = Variable.reg spec ~width:2 in
  let active = ~:(i.reset) in
  let request_ready = idle.value &: active in
  let accept = request_ready &: i.request_valid in
  let index_zero = i.request.index ==:. 0 in
  (* Observe readiness BEFORE clear: clear suppresses engine readiness.
     Exclusive engine ownership keeps it idle for the following clear edge. *)
  let engine_idle = i.update_ready &: ~:(i.result_valid) in
  let command_accept = dispatch.value &: i.update_ready in
  let result_accept = result.value &: i.result_valid in
  let first_result = result_accept &: ~:(second.value) in
  let second_result = result_accept &: second.value in
  let response_accept = response.value &: i.response_ready in
  let drain_done = drain.value &: i.response_done in
  compile
    [ idle <-- ((idle.value &: ~:accept) |: drain_done)
    ; await_clear_idle <-- ((accept &: index_zero)
                         |: (await_clear_idle.value &: ~:engine_idle))
    ; clear <-- (await_clear_idle.value &: engine_idle)
    ; dispatch <-- ((accept &: ~:index_zero) |: clear.value |: first_result
                 |: (dispatch.value &: ~:(i.update_ready)))
    ; result <-- (command_accept |: (result.value &: ~:(i.result_valid)))
    ; response <-- (second_result |: (response.value &: ~:(i.response_ready)))
    ; drain <-- (response_accept |: (drain.value &: ~:(i.response_done)))
    ; when_ accept [ second <--. 0 ]
    ; when_ first_result [ second <--. 1; action1 <-- i.action ]
    ; when_ second_result [ action2 <-- i.action; pointer <-- pointer.value +:. 1 ]
    ; when_ (accept &: index_zero) [ pointer <--. 0 ]
    ];
  (* Borrow decoder storage: acceptance disables reception until response_done.
     The producer must retain ALL fields through that drain edge, even after
     request_valid drops or a sticky fault occurs. Shared reset aborts the loan. *)
  let p = i.request in
  let second = second.value in
  let id = mux2 second p.slot2_id p.slot1_id in
  { O.request_ready; receive_enable = request_ready
  ; update =
      { Payload.Update.item_select = id ==:. Payload.item_b
      ; price = mux2 second p.slot2_price p.slot1_price
      ; window_position = pointer.value
      ; warmup = p.index <:. 16 }
  ; update_valid = dispatch.value &: active
  ; result_ready = result.value &: active
  ; session_clear = clear.value &: active
  ; response =
      { Payload.Response.index = p.index; slot1_id = p.slot1_id; slot2_id = p.slot2_id
      ; slot1_action = action1.value; slot2_action = action2.value }
  ; response_valid = response.value &: active }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_transaction_controller" create i
