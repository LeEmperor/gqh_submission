open! Core
open Async

type scenario =
  | Connected_disarmed | Enabled | No_signal | Admitted | Blocked | Received
  | Update_pending | Update_failed | Connection_lost | Book_invalid
  | Update_ok | Fail_at_idle | Fail_at_verify | Lost_at_activate | Stale_base
  [@@deriving equal, sexp]
val scenarios : (string * scenario) list
val scenario_of_string : string -> scenario Or_error.t

type t
(* [create] accepts a stream rate in [0.1, max_rate_hz]; [max_rate_hz] is 60. *)
val max_rate_hz : float
val create : scenario:scenario -> seed:int -> rate_hz:float -> t Or_error.t
(* The same, for a caller that has opted into a higher ceiling, as [--bench] does. *)
val create_with_max_rate :
  max_rate_hz:float -> scenario:scenario -> seed:int -> rate_hz:float -> t Or_error.t
val state : t -> Model_adapter.application_state
(* Pure deterministic advancement adds 1/rate_hz seconds of MOCK backend time.
   Each apply ACK needs 0.5 seconds, independently of market-update frequency. *)
val advance : t -> t
(* [steps_due ~rate_hz ~elapsed ~carried] is how many [advance] steps [next] takes after [elapsed]
   since the previous poll, and the fraction of a step owed (or, below zero, overdrawn) to carry
   into the next poll: the whole steps in [carried + elapsed * rate_hz], at least one and at most
   one second's worth, so over time the stream delivers exactly [rate_hz] a second. *)
val steps_due : rate_hz:float -> elapsed:Time_ns.Span.t -> carried:float -> int * float
(* Polls the stream: yields, then advances by [steps_due] since the previous poll. *)
val next : t -> t Deferred.t

(* Whether a poll can bring anything: the stream is up, or an apply is in flight and ticks with
   the poll. A lost connection with nothing in flight has no next state, so it is not polled. *)
val polling : t -> bool

val handle_command : t -> Model_adapter.command -> t
