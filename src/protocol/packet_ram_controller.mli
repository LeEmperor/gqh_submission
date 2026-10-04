module Payload = Types
open! Hardcaml

module I : sig
  type 'a t =
    { clock : 'a; reset : 'a; byte_data : 'a [@bits 8]; byte_valid : 'a
    ; framing_error : 'a; update_ready : 'a; result_valid : 'a; action : 'a [@bits 2]
    ; tx_ready : 'a; tx_busy : 'a }
  [@@deriving hardcaml]
end
module O : sig
  type 'a t =
    { update : 'a Payload.Update.t; update_valid : 'a; result_ready : 'a
    ; session_clear : 'a; tx_data : 'a [@bits 8]; tx_valid : 'a; protocol_fault : 'a }
  [@@deriving hardcaml]
end
(** Experimental competition protocol with an unreset synchronous 8x8 byte RAM.
    Price and other update fields stay stable through the result transfer.
    Accepts arbitrary legal byte pauses. No receive during processing or TX.
    Sticky faults preserve the accepted packet until all eight complete TX
    frames drain. Reset invalidates partial packets before any RAM read.
    All scalar ports are one bit except byte/action fields shown above. *)
val create : Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical : ?instance:string -> Scope.t -> Signal.t I.t -> Signal.t O.t
