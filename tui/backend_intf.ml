open! Core
open Async

(* Application commands only. Acceptance queues backend work; [next] consumes
   asynchronous progress. The frontend never dispatches individual apply steps. *)
module type S = sig
  type t
  val state : t -> Model_adapter.application_state
  val handle_command : t -> Model_adapter.command -> t
  val next : t -> t Deferred.t
end
