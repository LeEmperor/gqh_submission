open! Hardcaml
open! Signal
open! Hardcaml_gqh
module P = Protocol
module C = P.Transaction_controller
module U = Engine.Update

(* Test-only wiring. No scheduling, routing, classification or pointer logic. *)
module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; request : 'a P.Types.Request.t
    ; request_valid : 'a; response_ready : 'a; response_done : 'a }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t = { controller : 'a C.O.t; engine : 'a U.O.t }
  [@@deriving hardcaml]
end
let create scope (i : _ I.t) =
  let ready = wire 1 and valid = wire 1 and action = wire 2 in
  let c = C.hierarchical ~instance:"controller" scope
    { C.I.clock = i.clock; reset = i.reset; request = i.request
    ; request_valid = i.request_valid; update_ready = ready; result_valid = valid
    ; action; response_ready = i.response_ready; response_done = i.response_done } in
  let e = U.hierarchical ~instance:"engine" scope
    { U.I.clock = i.clock; reset = i.reset; session_clear = c.session_clear
    ; update = c.update; update_valid = c.update_valid; result_ready = c.result_ready } in
  ready <-- e.update_ready; valid <-- e.result_valid; action <-- e.action;
  { O.controller = c; engine = e }

module Payload_I = I
module Byte = struct
  module I = P.Transport_harness.I
  module O = struct
    type 'a t =
      { tx_data : 'a [@bits 8]; tx_valid : 'a; protocol_fault : 'a
      ; controller : 'a C.O.t; request_valid : 'a; response_done : 'a }
    [@@deriving hardcaml]
  end
  let create scope (i : _ I.t) =
    let request_ready = wire 1 and receive_enable = wire 1 in
    let d = P.Request_decoder.hierarchical ~instance:"decoder" scope
      { P.Request_decoder.I.clock = i.clock; reset = i.reset; receive_enable
      ; byte_data = i.byte_data; byte_valid = i.byte_valid
      ; framing_error = i.framing_error; request_ready } in
    let ready = wire 1 and done_ = wire 1 in
    let h = create scope
      { Payload_I.clock = i.clock; reset = i.reset; request = d.request
      ; request_valid = d.request_valid; response_ready = ready; response_done = done_ } in
    let s = P.Response_sequencer.hierarchical ~instance:"sequencer" scope
      { P.Response_sequencer.I.clock = i.clock; reset = i.reset
      ; response = h.controller.response; response_valid = h.controller.response_valid
      ; tx_ready = i.tx_ready; tx_busy = i.tx_busy } in
    request_ready <-- h.controller.request_ready;
    receive_enable <-- h.controller.receive_enable;
    ready <-- s.response_ready; done_ <-- s.response_done;
    { O.tx_data = s.tx_data; tx_valid = s.tx_valid; protocol_fault = d.protocol_fault
    ; controller = h.controller; request_valid = d.request_valid
    ; response_done = s.response_done }
end
