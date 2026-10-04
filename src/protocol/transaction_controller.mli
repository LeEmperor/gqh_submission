module Payload = Types
open! Hardcaml

(** Single complete-request transaction controller. All transfers are rising-edge
    valid && ready handshakes. Engine instantiation is outside this module;
    it must be exclusively owned by this controller and reset together with it.
    Unknown/duplicate IDs and nonsequential indices are outside the contract. *)
module I : sig
  type 'a t =
    { clock : 'a; reset : 'a
    ; request : 'a Payload.Request.t; request_valid : 'a
    ; update_ready : 'a; result_valid : 'a; action : 'a [@bits 2]
    ; response_ready : 'a; response_done : 'a
    }
  [@@deriving hardcaml]
end
module O : sig
  type 'a t =
    { request_ready : 'a; receive_enable : 'a
    ; update : 'a Payload.Update.t; update_valid : 'a
    ; result_ready : 'a; session_clear : 'a
    ; response : 'a Payload.Response.t; response_valid : 'a
    }
  [@@deriving hardcaml]
end

(** Directions from the controller's perspective:
    - Decoder supplies [request] (index16, IDs8, prices16), [request_valid];
      controller supplies [request_ready], [receive_enable]. No fault input:
      sticky lockout and acceptance-edge collisions remain decoder-owned.
      Borrowed-storage contract: after request acceptance, the producer must
      retain ALL request fields through the response_done consumption edge,
      regardless of request_valid or faults. The controller disables reception
      until then. Shared reset aborts the transaction and releases the storage.
    - Engine receives [update] (item_select1, price16, window_position4, warmup1),
      [update_valid], [result_ready], [session_clear]; supplies [update_ready],
      [result_valid], [action] (2 bits). A=0x11 maps to 0, B=0x22 maps to 1.
    - Sequencer receives [response] (index16, IDs8, actions2), [response_valid];
      supplies [response_ready], [response_done]. Receive rearm waits for done,
      never merely readiness or response acceptance.
    All other signals are one bit. [clock] and active-high synchronous [reset]
    are shared with decoder/engine/sequencer. Reset masks all handshake/clear
    outputs immediately; its edge aborts work and clears retained state/pointer.
    Restart with index zero and full warm-up; RAM is the engine's responsibility.

    Index zero resets pointer on request acceptance, waits to observe engine
    idle ([update_ready && not result_valid]), then pulses clear for one edge
    with no update_valid. Clear is deasserted before dispatch. Both slots use
    the same position. Results are captured once in slot order; pointer advances
    modulo 16 on the second result transfer. Payload/valid hold through stalls.
    Only one transaction can be outstanding, through final response drain. *)
val create : Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical : ?instance:string -> Scope.t -> Signal.t I.t -> Signal.t O.t
