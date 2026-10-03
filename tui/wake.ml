open! Core
open Async
open Bonsai_term

(* The driver's loop sleeps until a terminal event or its frame timer, and for nothing else. A
   state change made by an Async job, or a deadline that falls between two timer ticks, is
   not seen until the next tick. [Bonsai_term.start_with_driver] lets the application queue
   events of its own, and a queued event ends the sleep at once. Everything that has to make
   a frame happen when no key was pressed goes through this module: the stream's polls, the
   header's second, a highlight's expiry, a held paint's release.

   A [t] is made for one run and handed down to whoever needs it; there is no state here that
   outlives a run, so a test makes its own and resets nothing. There are two kinds, and the
   application cannot tell them apart:

   - [off], the default, is a harness that drives the Bonsai clock by hand (the tests). Time
     is the harness's; nothing here sleeps or wakes, and [sleep] is the [fallback] it is
     handed, a sleep on that clock.
   - [create ()] is [Runner] driving the real terminal. Time is the time source's (Async's
     wall clock unless a test gives another), [sleep] really waits, and [now] queues the event
     that wakes the loop. A wake asked for before the driver exists, while the first frame is
     being computed, is kept and sent by [connect]. *)

type live =
  { time_source : Time_source.t
  ; mutable send : (unit -> unit) option  (* the driver's wake, once there is a driver *)
  ; mutable wanted : bool                  (* a wake was asked for before there was one *)
  ; mutable arrival : Time_ns.t option
  ; mutable backstops : (unit, unit) Time_source.Event.t list }

type t = Off | Live of live

let off = Off
let create ?(time_source = Time_source.wall_clock ()) () =
  Live { time_source; send = None; wanted = false; arrival = None; backstops = [] }

let live = function Off -> false | Live _ -> true

let now = function
  | Off -> ()
  | Live live -> (match live.send with Some send -> send () | None -> live.wanted <- true)

let connect t send =
  match t with
  | Off -> ()
  | Live live ->
    live.send <- Some send;
    if live.wanted then (live.wanted <- false; send ())

(* A wake at [time], a no-op if the harness owns the clock. *)
let at t time =
  match t with
  | Off -> ()
  | Live live -> Time_source.run_at live.time_source time now t

(* An effect that returns once [span] has gone by: really, when live, or on the clock of
   [fallback] otherwise. *)
let sleep t ~fallback span =
  match t with
  | Off -> fallback span
  | Live live -> Effect.of_deferred_fun (Time_source.after live.time_source) span

(* The same, until a given instant. *)
let sleep_until t ~fallback time =
  match t with
  | Off -> fallback time
  | Live live -> Effect.of_deferred_fun (Time_source.at live.time_source) time

(* A sleep that a later one on the same timer replaces. Whoever keeps one timer for a moving
   deadline asks it for the new instant and lets the old sleep end [Superseded], without
   having waited out the old instant: at most one sleep of a timer is ever pending, so a
   deadline that moves does not pile up timers in the scheduler. Off, a sleep on the
   harness's clock cannot be called off, and is only ever [Fired]; the owner tells a stale
   one by its own bookkeeping. *)
module Timer = struct
  type wake = t
  type t = { wake : wake; mutable pending : (unit, unit) Time_source.Event.t option }
  type outcome = Fired | Superseded

  let create wake = { wake; pending = None }

  let pending t =
    match t.pending with
    | Some event -> (match Time_source.Event.status event with Scheduled_at _ -> true | Aborted _ | Happened _ -> false)
    | None -> false

  let sleep_until t ~fallback time =
    match t.wake with
    | Off -> let%map.Effect () = fallback time in Fired
    | Live live ->
      Effect.of_deferred_fun (fun time ->
        Option.iter t.pending ~f:(fun event -> Time_source.Event.abort_if_possible event ());
        let event = Time_source.Event.at live.time_source time in
        t.pending <- Some event;
        match%map Time_source.Event.fired event with
        | Happened () -> Fired
        | Aborted () -> Superseded) time
end

(* Ends the loop's sleep when an effect run by an Async job (rather than by a frame) has
   changed what the next frame will show. *)
let now_effect t = Effect.of_sync_fun now t

(* The instant the next state of the stream is expected to reach the app, as the poll loop
   knows it: the end of the sleep it has begun, and the poll's own time. *)
let expect_arrival t time = match t with Off -> () | Live live -> live.arrival <- Some time

(* How long past its expected instant a state may be late before a wake that waits for it gives
   up: the poll's own time is not known better than that on a busy machine. *)
let backstop = Time_ns.Span.of_ms 20.

(* The time a paint takes to be made, which the window of a state held back by it includes. *)
let paint_time = Time_ns.Span.of_ms 4.

(* A state has arrived. The frame it wakes applies every change queued so far, so the wakes
   that were waiting for it are not needed; left to fire, one would run a frame of its own
   just before the next state, and paint whatever was queued in between. *)
let arrived = function
  | Off -> ()
  | Live live ->
    List.iter live.backstops ~f:(fun backstop -> Time_source.Event.abort_if_possible backstop ());
    live.backstops <- []

(* [now], for a change that will repaint the screen but needs no paint of its own: a header
   second, a highlight to take off. Such a paint, made just before a state of the stream
   arrives, would leave the screen newly painted, and the state would be held back by it
   until the paint interval was over, [within], counted from a paint that itself takes
   [paint_time] to be made. So when a state is expected inside that window, or is already
   late, the wake waits for it. The change itself is already queued and is applied by the
   frame the state wakes; the wake that waits is a backstop for a state that is later still. *)
let soft_now t ~within =
  match t with
  | Off -> ()
  | Live live ->
    let current = Time_source.now live.time_source in
    (match live.arrival with
     | Some expected
       when Time_ns.Span.(Time_ns.diff expected current <= within + paint_time)
         && Time_ns.Span.(Time_ns.diff current expected < backstop) ->
       let wake_at = Time_ns.add (Time_ns.max expected current) backstop in
       live.backstops <- Time_source.Event.run_at live.time_source wake_at now t :: live.backstops
     | Some _ | None -> now t)

let soft_now_effect t ~within = Effect.of_sync_fun (fun () -> soft_now t ~within) ()
