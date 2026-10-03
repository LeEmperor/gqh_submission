open! Core
open Async
open Bonsai_term

(* Runs an application on the terminal. It is [Bonsai_term.start_with_exit], with two additions
   that the driver's loop, which sleeps until a key or its own timer, needs for an application
   that has things to do between keys:

   - the application can wake the loop ([Wake]), by an incoming event that does nothing but end
     the sleep, so a stream tick, a header second or an expiry is drawn when it happens and not
     at the next timer;
   - the views the application produces pass through a [Paint_throttle] on their way to the
     driver, which rations paints to sixty a second without delaying the first.

   Since everything that has to happen at a given instant asks for its own wake, the
   driver's timer is only a floor under them, in case a wake is lost. It is slow, so an
   application with nothing to do runs nothing. *)

let fallback_frames_per_second = 2.

let run ?(mouse = Mouse_reporting.All_mouse_events_except_hover)
    ?(frames_per_second = Paint_throttle.frames_per_second) app =
  let wake = Wake.create () in
  let throttle = Paint_throttle.create ~wake ~frames_per_second () in
  let open Deferred.Or_error.Let_syntax in
  let%bind driver =
    Bonsai_term.start_with_driver ~mouse ~target_frames_per_second:fallback_frames_per_second
      ~get_view_and_handler:(fun (~view, ~handler) -> ~view:(Paint_throttle.release throttle view), ~handler)
      ~handle_incoming:(fun _ () -> Effect.Ignore)
      (fun ~exit ~dimensions (local_ graph) ->
         Bonsai_term.stitch
           (app ~wake ~paints:(fun () -> Paint_throttle.paints throttle) ~exit ~dimensions graph))
  in
  Wake.connect wake (fun () -> Bonsai_term.Driver.send_incoming_event driver ());
  match%map.Deferred Bonsai_term.Driver.finished driver with
  | Ok exit -> Ok exit
  | Error `Incoming_events_pipe_closed ->
    Or_error.error_string "the terminal's input closed before the application exited"
