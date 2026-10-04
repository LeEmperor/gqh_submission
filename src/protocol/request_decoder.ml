module Payload = Types
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; receive_enable : 'a
    ; byte_data : 'a [@bits 8]; byte_valid : 'a; framing_error : 'a
    ; request_ready : 'a
    }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { request : 'a Payload.Request.t; request_valid : 'a; protocol_fault : 'a }
  [@@deriving hardcaml]
end

(* Sticky fault belongs here; the harness/controller owns receive_enable.
   No byte counter timeout: arbitrarily long pauses are legal.
   Payload is complete after byte 8 and retained beyond request acceptance:
   only enabled reception writes fields; busy bytes/framing faults leave them
   intact. The production controller holds receive_enable low through final TX
   drain and shares reset, which aborts the retained transaction. *)
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let payload = Payload.Request.Of_always.reg spec in
  let position = Variable.reg spec ~width:3 in
  let valid = Variable.reg spec ~width:1 in
  let fault = Variable.reg spec ~width:1 in
  let receiving = i.receive_enable &: ~:(valid.value) &: ~:(fault.value) in
  let write_low old = concat_msb [ select old ~high:15 ~low:8; i.byte_data ] in
  let write_high old = concat_msb [ i.byte_data; select old ~high:7 ~low:0 ] in
  compile
    [ when_ (valid.value &: i.request_ready) [ valid <--. 0 ]
    ; if_ i.framing_error
        [ fault <--. 1; position <--. 0; valid <--. 0 ]
        [ when_ i.byte_valid
            [ if_ receiving
                [ switch position.value
                    [ of_int_trunc ~width:3 0, [ payload.index <-- write_high payload.index.value ]
                    ; of_int_trunc ~width:3 1, [ payload.index <-- write_low payload.index.value ]
                    ; of_int_trunc ~width:3 2, [ payload.slot1_id <-- i.byte_data ]
                    ; of_int_trunc ~width:3 3, [ payload.slot1_price <-- write_high payload.slot1_price.value ]
                    ; of_int_trunc ~width:3 4, [ payload.slot1_price <-- write_low payload.slot1_price.value ]
                    ; of_int_trunc ~width:3 5, [ payload.slot2_id <-- i.byte_data ]
                    ; of_int_trunc ~width:3 6, [ payload.slot2_price <-- write_high payload.slot2_price.value ]
                    ; of_int_trunc ~width:3 7,
                      [ payload.slot2_price <-- write_low payload.slot2_price.value; valid <--. 1 ]
                    ]
                ; position <-- position.value +:. 1 ]
                [ fault <--. 1; position <--. 0 ]
            ] ]
    ];
  { O.request = Payload.Request.map payload ~f:(fun v -> v.value)
  ; request_valid = valid.value &: ~:(fault.value) &: ~:(i.framing_error)
  ; protocol_fault = fault.value
  }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_request_decoder" create i
