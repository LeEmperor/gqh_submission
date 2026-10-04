module Payload = Types
open! Hardcaml

module I : sig
  type 'a t =
    { clock : 'a; reset : 'a; response : 'a Payload.Response.t; response_valid : 'a
    ; tx_ready : 'a; tx_busy : 'a
    }
  [@@deriving hardcaml]
end
module O : sig
  type 'a t =
    { response_ready : 'a; response_done : 'a
    ; tx_data : 'a [@bits 8]; tx_valid : 'a
    }
  [@@deriving hardcaml]
end

(** Captures a response (index16, IDs8, actions2) at a rising-edge valid/ready
    handshake and offers eight ordered bytes through [tx_valid && tx_ready].
    [response_done] pulses after [tx_busy] falls following the last byte, so the
    full stop bit has drained. Active-high synchronous reset aborts the packet.
    [borrow_response] defaults false. If true, upstream retains every response
    field through [response_done] or shared reset; valid may drop after acceptance.
    Other than payload and [tx_data], signals are one bit. [state_encoding] is
    an experiment; omission preserves historical encoding and attributes. *)
val create : ?state_encoding:Always.State_machine.Encoding.t -> ?borrow_response:bool -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  : ?instance:string -> ?state_encoding:Always.State_machine.Encoding.t
  -> ?borrow_response:bool -> Scope.t -> Signal.t I.t -> Signal.t O.t
