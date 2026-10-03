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
module State = struct
  type t = Idle | Await_clear_idle | Clear | Dispatch1 | Result1
         | Dispatch2 | Result2 | Response | Drain
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let sm = State_machine.create (module State) spec in
  let request = Payload.Request.Of_always.reg spec in
  let pointer = Variable.reg spec ~width:4 in
  let action1 = Variable.reg spec ~width:2 in
  let action2 = Variable.reg spec ~width:2 in
  let active = ~:(i.reset) in
  let request_ready = sm.is Idle &: active in
  let accept = request_ready &: i.request_valid in
  compile
    [ sm.switch
        [ Idle, [ when_ accept
            (Payload.Request.to_list (Payload.Request.map2 request i.request
               ~f:(fun dst src -> dst <-- src))
             @ [ if_ (i.request.index ==:. 0)
                   [ pointer <--. 0; sm.set_next Await_clear_idle ]
                   [ sm.set_next Dispatch1 ] ]) ]
        (* Observe readiness BEFORE clear: clear suppresses engine readiness.
           No engine command is offered in these states. With exclusive engine
           ownership, observed idle remains idle for the following clear edge. *)
        ; Await_clear_idle,
          [ when_ (i.update_ready &: ~:(i.result_valid)) [ sm.set_next Clear ] ]
        ; Clear, [ sm.set_next Dispatch1 ]
        ; Dispatch1, [ when_ i.update_ready [ sm.set_next Result1 ] ]
        ; Result1, [ when_ i.result_valid
            [ action1 <-- i.action; sm.set_next Dispatch2 ] ]
        ; Dispatch2, [ when_ i.update_ready [ sm.set_next Result2 ] ]
        ; Result2, [ when_ i.result_valid
            [ action2 <-- i.action; pointer <-- pointer.value +:. 1
            ; sm.set_next Response ] ]
        ; Response, [ when_ i.response_ready [ sm.set_next Drain ] ]
        ; Drain, [ when_ i.response_done [ sm.set_next Idle ] ]
        ] ];
  let p = Payload.Request.map request ~f:(fun v -> v.value) in
  let second = sm.is Dispatch2 |: sm.is Result2 in
  let id = mux2 second p.slot2_id p.slot1_id in
  { O.request_ready; receive_enable = request_ready
  ; update =
      { Payload.Update.item_select = id ==:. Payload.item_b
      ; price = mux2 second p.slot2_price p.slot1_price
      ; window_position = pointer.value
      ; warmup = p.index <:. 16 }
  ; update_valid = (sm.is Dispatch1 |: sm.is Dispatch2) &: active
  ; result_ready = (sm.is Result1 |: sm.is Result2) &: active
  ; session_clear = sm.is Clear &: active
  ; response =
      { Payload.Response.index = p.index; slot1_id = p.slot1_id; slot2_id = p.slot2_id
      ; slot1_action = action1.value; slot2_action = action2.value }
  ; response_valid = sm.is Response &: active }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_transaction_controller" create i
