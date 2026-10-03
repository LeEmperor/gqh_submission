open! Core
open Async
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

(* Owns the live backend: the actor that serializes commands against polls, and the poll loop that drives the stream on its own timer. *)

(* The paint interval: the stream is polled once an interval at most, and no faster than its
   own period, since a poll that came sooner would hand it more steps than its rate. *)
let frame = Paint_throttle.default_interval

(* On the real clock, a stream faster than the paint interval is polled this much less often
   than once an interval. A poll answered less than an interval after the last paint is held
   by the throttle until the interval ends, so a stream polled exactly once an interval, whose
   answers each follow a paint by about as long as the paint took, would be shown one
   interval late every time. With this much room (the timer's resolution, a paint's jitter)
   the answer finds the throttle open and is painted at once. *)
let poll_margin = Time_ns.Span.of_ms 2.5

(* About how long a poll takes to answer, for the instant its answer is expected. *)
let poll_latency = Time_ns.Span.of_ms 1.5

(* How long after a poll the next is due: the stream's period, but never less than one paint
   interval (and, on the real clock, the margin above). The poll is scheduled from the instant
   of the last one, not from the end of its work, so the polls keep the stream's cadence and do
   not drift by what each one costs. *)
let poll_delay ~live ~period =
  Time_ns.Span.max period (if live then Time_ns.Span.(frame + poll_margin) else frame)

type 'backend backend_model = { backend : 'backend; revision : int }
type 'backend backend_action =
  | Command_backend of command | Poll_backend of int * 'backend

let start (type backend) ?(wake = Wake.off)
    (module Backend : Backend_intf.S with type t = backend)
    ~(backend : backend) (local_ graph) =
  (* A command and an asynchronous poll may share a frame. Serialize commands
     against the latest backend, and never overwrite them with an older poll. *)
  let backend, inject = Bonsai.actor ~default_model:{ backend; revision = 0 }
      ~recv:(fun _context model action ->
        let model = match action with
          | Command_backend command ->
            { backend = Backend.handle_command model.backend command; revision = model.revision + 1 }
          | Poll_backend (revision, backend) ->
            if revision = model.revision then { backend; revision = revision + 1 } else model in
        model, (model.backend, model.revision)) graph in
  let state = let%arr backend in Backend.state backend.backend in
  (* The poll loop reads the backend and the stream's period from here, a frame stale at worst.
     [Bonsai.peek] would be current, but it answers only at the start of the next frame, and a
     poll that waits a frame for its inputs is a poll every other frame. *)
  let latest = Bonsai.Expert.Var.create None in
  (* A stream that is down is not polled at all: nothing it could answer would differ from what
     is shown. The loop waits here, and the frame that shows a backend that polls again ends the
     wait. Only a command can do that (the mock never reconnects), and a command is a frame. *)
  let resume = ref (Async.Ivar.create ()) in
  let period = let%arr state in Time_ns.Span.of_sec (1. /. state.rate_hz) in
  Bonsai.Edge.before_display
    (let%arr backend and period in
     Effect.of_sync_fun (fun () ->
       let polling = Backend.polling backend.backend in
       Bonsai.Expert.Var.set latest (Some (backend, period, polling));
       if polling then Async.Ivar.fill_if_empty !resume ()) ()) graph;
  let send_command = let%arr inject in fun command ->
    let%map.Effect _ = inject (Command_backend command) in () in
  (* The stream is polled on its own timer, outside the frames: when the backend answers, the
     answer is handed to the graph and the driver is woken, so the frame that shows it begins
     at once, and the delay from the stream to the screen is the frame's own work. A stream
     faster than the paint interval is polled once an interval, and [Backend.next] counts the
     steps owed from the time between polls, so a poll that comes late loses none and the
     stream delivers its rate exactly. A slower one sleeps its own period. Under test there
     is no driver, and the sleep is on the harness's clock, one poll to a frame. *)
  let sleep = Bonsai.Clock.sleep graph in
  let poll_loop =
    let%arr inject and sleep in
    let open Effect.Let_syntax in
    (* [predicted] is the backend the last poll was applied to produce: the graph shows it only
       from the next frame, and a poll that began from the older one would carry a stale
       revision and be dropped. Whichever has the newer revision is the one to poll from; a
       command applied since is newer, and a poll it overtook is simply lost. *)
    let polling_now () = match Bonsai.Expert.Var.get latest with Some (_, _, polling) -> polling | None -> false in
    let wait_until_polling () =
      if polling_now () then Async.return ()
      else (resume := Async.Ivar.create (); Async.Ivar.read !resume) in
    let rec loop predicted ~last_poll =
      let%bind () = Effect.return () in
      let%bind last_poll =
        if polling_now () then Effect.return last_poll
        else (let%map () = Effect.of_deferred_fun wait_until_polling () in None) in
      let live = Wake.live wake in
      let period = match Bonsai.Expert.Var.get latest with
        | Some (_, period, _) -> period
        | None -> Time_ns.Span.zero in
      let delay = poll_delay ~live ~period in
      let current = Time_ns.now () in
      (* The sleep runs from the last poll's instant on the real clock; the harness's clock has
         no such instant, and there it is the delay from now. *)
      let wait = match last_poll with
        | Some at when live -> Time_ns.Span.max Time_ns.Span.zero (Time_ns.diff (Time_ns.add at delay) current)
        | Some _ | None -> delay in
      let%bind () = Effect.of_sync_fun (fun wait ->
          Wake.expect_arrival wake (Time_ns.add current (Time_ns.Span.(wait + poll_latency)))) wait in
      let%bind () = Wake.sleep wake ~fallback:sleep wait in
      let started = Time_ns.now () in
      let newest = match Bonsai.Expert.Var.get latest, predicted with
        | Some (seen, _, _), Some predicted -> Some (if seen.revision >= predicted.revision then seen else predicted)
        | Some (seen, _, _), None -> Some seen
        | None, predicted -> predicted in
      match newest with
      | None -> loop predicted ~last_poll:(Some started)
      | Some { backend; revision } ->
        let%bind next = Effect.of_deferred_fun Backend.next backend in
        (* Not waited for: the action is applied at the start of the next frame either way. *)
        let%bind () = Effect.of_sync_fun Wake.arrived wake in
        let%bind () = Effect.Many [ (let%map _ = inject (Poll_backend (revision, next)) in ()) ] in
        let%bind () = Wake.now_effect wake in
        loop (Some { backend = next; revision = revision + 1 }) ~last_poll:(Some started) in
    loop None ~last_poll:None in
  Bonsai.Edge.lifecycle ~on_activate:poll_loop graph;
  state, send_command
