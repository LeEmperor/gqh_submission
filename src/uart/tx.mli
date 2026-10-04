open! Hardcaml

module I : sig
  type 'a t =
    { clock : 'a; reset : 'a; tx_data : 'a [@bits 8]; tx_valid : 'a }
  [@@deriving hardcaml]
end
module O : sig
  type 'a t = { tx : 'a; tx_ready : 'a; tx_busy : 'a } [@@deriving hardcaml]
end
(** Latches [tx_data] (8 bits) on a rising-edge [tx_valid && tx_ready] transfer.
    [tx_busy] remains high through every data bit, the complete stop bit and the
    configured extra gap. Reset aborts the frame and forces idle-high output;
    other ports are one bit. Default timing is 234 cycles per bit and no gap.
    [shift_register] defaults false (indexed accepted-byte serialization).
    [factored_timer] defaults false and factors timer reload/decrement controls.
    [state_encoding] is an experiment; omission preserves historical behavior. *)
val create
  : ?factored_timer:bool -> ?shift_register:bool -> ?state_encoding:Always.State_machine.Encoding.t
  -> ?cycles_per_bit:int -> ?extra_idle_cycles:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  : ?instance:string -> ?factored_timer:bool -> ?shift_register:bool -> ?state_encoding:Always.State_machine.Encoding.t
  -> ?cycles_per_bit:int -> ?extra_idle_cycles:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
