module Payload = Types
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; response : 'a Payload.Response.t; response_valid : 'a
    ; tx_ready : 'a; tx_busy : 'a
    }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { response_ready : 'a; response_done : 'a
    ; tx_data : 'a [@bits 8]; tx_valid : 'a
    }
  [@@deriving hardcaml]
end
module State = struct
  type t = Idle | Send | Drain
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let sm = State_machine.create (module State) spec in
  (* Every field is replaced together before Send. Payload feeds only tx_data;
     resettable control suppresses tx_valid until capture and the UART ignores
     data without an offer. Keep the bank stable through Send/Drain, but it
     needs neither reset nor power-up initialization. Reset aborts its lifetime. *)
  let payload_spec = Reg_spec.create ~clock:i.clock () in
  let payload = Payload.Response.Of_always.reg payload_spec in
  let position = Variable.reg spec ~width:3 in
  let done_ = Variable.reg spec ~width:1 in
  compile
    [ done_ <--. 0
    ; sm.switch
        [ Idle,
          [ when_ i.response_valid
              (Payload.Response.to_list (Payload.Response.map2 payload i.response
                 ~f:(fun dst src -> dst <-- src))
               @ [ position <--. 0; sm.set_next Send ]) ]
        ; Send,
          [ when_ i.tx_ready
              [ if_ (position.value ==:. 7) [ sm.set_next Drain ]
                  [ position <-- position.value +:. 1 ] ] ]
        ; Drain, [ when_ (~:(i.tx_busy)) [ done_ <--. 1; sm.set_next Idle ] ]
        ]
    ];
  let p = Payload.Response.map payload ~f:(fun v -> v.value) in
  { O.response_ready = sm.is Idle &: ~:(i.reset)
  ; response_done = done_.value
  ; tx_valid = sm.is Send &: ~:(i.reset)
  ; tx_data = mux position.value
      [ select p.index ~high:15 ~low:8; select p.index ~high:7 ~low:0
      ; p.slot1_id; uresize p.slot1_action ~width:8
      ; p.slot2_id; uresize p.slot2_action ~width:8; zero 8; zero 8 ]
  }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_response_sequencer" create i
