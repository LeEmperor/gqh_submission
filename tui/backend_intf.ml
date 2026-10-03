open! Core
open Async

(* Application commands only. Acceptance queues backend work; [next] consumes
   asynchronous progress. The frontend never dispatches individual apply steps. *)
module type S = sig
  type t
  val state : t -> Model_adapter.application_state
  val handle_command : t -> Model_adapter.command -> t
  (* Whether a poll can bring anything. The app polls only while this is true, and is woken
     when a command or a poll makes it true again. *)
  val polling : t -> bool
  val next : t -> t Deferred.t
end
