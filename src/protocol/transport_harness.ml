module Payload = Types
open! Hardcaml
open! Signal

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; byte_data : 'a [@bits 8]
    ; byte_valid : 'a; framing_error : 'a; tx_ready : 'a; tx_busy : 'a }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { tx_data : 'a [@bits 8]; tx_valid : 'a; protocol_fault : 'a }
  [@@deriving hardcaml]
end

(* Diagnostic transport only: no algorithm or production controller. *)
let create scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let accepted = wire 1 and done_ = wire 1 in
  let busy = reg_fb spec ~width:1
    ~f:(fun busy -> mux2 accepted vdd (mux2 done_ gnd busy)) in
  let ready = wire 1 in
  let request = Request_decoder.hierarchical ~instance:"request_decoder" scope
    { Request_decoder.I.clock = i.clock; reset = i.reset; receive_enable = ~:busy
    ; byte_data = i.byte_data; byte_valid = i.byte_valid; framing_error = i.framing_error
    ; request_ready = ready &: ~:busy } in
  let response = Response_sequencer.hierarchical ~instance:"response_sequencer" scope
    { Response_sequencer.I.clock = i.clock; reset = i.reset
    ; response =
        { Payload.Response.index = request.request.index
        ; slot1_id = request.request.slot1_id; slot2_id = request.request.slot2_id
        ; slot1_action = zero 2; slot2_action = zero 2 }
    ; response_valid = request.request_valid &: ~:busy
    ; tx_ready = i.tx_ready; tx_busy = i.tx_busy } in
  ready <-- response.response_ready;
  accepted <-- (request.request_valid &: ready &: ~:busy);
  done_ <-- response.response_done;
  { O.tx_data = response.tx_data; tx_valid = response.tx_valid
  ; protocol_fault = request.protocol_fault }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_transport_harness" create i
