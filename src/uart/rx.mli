open! Hardcaml

module I : sig
  type 'a t = { clock : 'a; reset : 'a; rx : 'a } [@@deriving hardcaml]
end
module O : sig
  type 'a t =
    { byte_data : 'a [@bits 8]; byte_valid : 'a; framing_error : 'a }
  [@@deriving hardcaml]
end
(** [rx] is an already synchronized idle-high input. RX reports independent,
    single-cycle [byte_valid] and [framing_error] events. [byte_data] (8 bits) is
    stable while [byte_valid] is high. It shares the receive shift register and
    may change during the data bits of a subsequent frame. The active-high synchronous reset aborts a frame. Other ports are
    one bit. RX owns a timer independent of TX; default is 234 cycles per bit.
    [factored_timer] defaults false and factors timer reload/decrement controls.
    [state_encoding] is an experiment; omission preserves historical behavior. *)
val create
  : ?factored_timer:bool -> ?state_encoding:Always.State_machine.Encoding.t -> ?cycles_per_bit:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  : ?instance:string -> ?factored_timer:bool -> ?state_encoding:Always.State_machine.Encoding.t -> ?cycles_per_bit:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
