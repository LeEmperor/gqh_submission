open! Core
open Bonsai_term
open Bonsai.Let_syntax

(* The time that animated views read. [Bonsai.Clock.approx_now] ticks for as long as it is
   observed, so a view that reads it is recomputed, and the screen repainted, twenty times a
   second even when nothing on screen moves. This clock moves only for a reason:

   - an event ([Touch]): the stream has brought something, so the views that depend on the
     time read it as of now;
   - an expiry: a highlight that was on for its time ([Fade.level] is binary) must be taken
     off. The clock keeps one timer, for the next expiry and no sooner, and sets it again
     from the highlights still on when it fires.

   Between those it does not move. Each highlight therefore costs two paints, the one that
   shows it and the one that clears it, and a quiet application schedules no timer and
   repaints nothing: with no stream and nothing on, only the header's second ([each_second])
   runs, and the metrics sampler on the same tick while it has samples to age out.

   A highlight ends at its expiry or at the first frame after it (see [grace]), so a stream
   of events that each highlight something does not wake the application once per highlight. *)

(* A highlight is taken off by the first frame at or after its expiry, whatever the frame is
   for: the stream's next event, a keystroke. If none comes within this long, the clock makes
   one. Most of the time the stream is quicker, and the clock's timer is superseded before it
   fires; when it is not, one tick takes off every highlight that has expired by then. So a
   highlight lasts its time plus at most this, and a stream of events that each highlight
   something costs no extra paints. *)
let grace = Time_ns.Span.of_sec 0.25

(* The instant of the next tick for the highlights that end at [expiries]: [grace] after the
   earliest of those still to come after [after]. *)
let next_tick ~after expiries =
  List.filter expiries ~f:(fun expiry -> Time_ns.(expiry > after))
  |> List.min_elt ~compare:Time_ns.compare
  |> Option.map ~f:(fun expiry -> Time_ns.add expiry grace)

(* Runs [action] when the clock reaches [at], and wakes the driver, which sleeps through
   timers it does not know of. The wake is a soft one: a tick is no reason to paint just
   before a state of the stream arrives, see [Wake.soft_now]. A sleep that [timer] has since
   replaced does nothing. *)
let at_time context ~wake ~timer ~at action =
  let time_source = Bonsai.Apply_action_context.time_source context in
  let fallback at =
    Bonsai.Time_source.sleep time_source (Time_ns.diff at (Bonsai.Time_source.now time_source)) in
  Bonsai.Apply_action_context.schedule_event context
    (match%bind.Effect Wake.Timer.sleep_until timer ~fallback at with
     | Superseded -> Effect.Ignore
     | Fired ->
       let%bind.Effect () = Bonsai.Apply_action_context.inject context action in
       Wake.soft_now_effect wake ~within:Paint_throttle.default_interval)

(* What to do about the one timer when the highlights that are on have changed. A timer in
   flight that is due no later than the new target stays: when it fires it looks again at
   what is due and sets itself for the next. So a deadline that keeps moving later, as the
   stream's "stopped" instant does with every sample, arms nothing; only one that comes
   sooner than the timer replaces it. *)
type plan = Keep | Arm of Time_ns.t

let plan ~armed ~target =
  match target, armed with
  | None, (Some _ | None) -> Keep
  | Some target, Some armed when Time_ns.(armed <= target) -> Keep
  | Some target, (Some _ | None) -> Arm target

(* Whether a highlight is still shown by the clock [now] although it has ended by [clock]. *)
let any_due expiries ~now:shown ~clock =
  List.exists expiries ~f:(fun expiry -> Time_ns.(expiry > shown && expiry <= clock))

type model =
  { now : Time_ns.t
  ; touched : Time_ns.t option  (* the latest event, if there has been one *)
  ; generation : int          (* a sleep of an older generation is ignored when it ends *)
  ; armed : Time_ns.t option }  (* the instant the timer in flight is for, if any *)

type action = Sync | Touch | Rearm | Tick of int

(* [activity] changes when the stream has brought something: that is an event. [expiries] are
   the instants at which highlights that the models hold stop, and [after_touch] the lengths
   of highlights that start at each event and that nothing else records. *)
let component ?(wake = Wake.off) ~activity ~equal ~expiries ~after_touch (local_ graph) =
  let timer = Wake.Timer.create wake in
  let model, inject =
    Bonsai.state_machine_with_input
      ~default_model:{ now = Time_ns.epoch; touched = None; generation = 0; armed = None }
      ~apply_action:(fun context input model action ->
        match input with
        | Bonsai.Computation_status.Inactive -> model
        | Active expiries ->
          let clock = Bonsai.Time_source.now (Bonsai.Apply_action_context.time_source context) in
          let ending model = Option.value_map model.touched ~default:[]
              ~f:(fun touched -> List.map after_touch ~f:(Time_ns.add touched)) @ expiries in
          let moved = match action with
            | Sync -> Some { model with now = clock }
            | Touch -> Some { model with now = clock; touched = Some clock }
            | Rearm -> Some model
            | Tick generation when generation <> model.generation -> None
            | Tick _ ->
              (* The clock moves only if a highlight it shows is over; a deadline that moved on
                 since the timer was set is looked at again, and the timer set anew. *)
              let model = { model with armed = None } in
              Some (if any_due (ending model) ~now:model.now ~clock then { model with now = clock } else model) in
          (* The timer follows the highlights that are still on, whatever woke us. *)
          Option.value_map moved ~default:model ~f:(fun model ->
            match plan ~armed:model.armed ~target:(next_tick ~after:clock (ending model)) with
            | Keep -> model
            | Arm at ->
              let generation = model.generation + 1 in
              at_time context ~wake ~timer ~at (Tick generation);
              { model with generation; armed = Some at }))
      expiries graph in
  (* The first value only starts the clock's time; it is no event. *)
  let callback = let%arr inject in fun previous (_ : _) ->
    inject (match previous with None -> Sync | Some _ -> Touch) in
  Bonsai.Edge.on_change' ~equal activity ~callback graph;
  Bonsai.Edge.on_change ~equal:[%equal: Time_ns.t list] expiries
    ~callback:(let%arr inject in fun (_ : Time_ns.t list) -> inject Rearm) graph;
  let now = let%arr model in model.now in
  Bonsai.cutoff now ~equal:Time_ns.equal

(* [now] rounded down to a multiple of [step]: a view that moves in steps of [step] reads
   this instead and is recomputed once per step, not once per tick of a faster clock. *)
let quantized ~now ~step =
  Bonsai.cutoff ~equal:Time_ns.equal
    (let%arr now in
     Time_ns.prev_multiple ~can_equal_before:true ~base:Time_ns.epoch ~before:now ~interval:step ())

(* [now] while an animation that began at [since] still runs. Afterwards a view that moves
   with the time in steps of [slow] reads [now] rounded to [slow], and one that does not
   (no [slow]) reads a constant, so it is not recomputed once the animation has finished.
   [within] must cover the animation; the tests render each animated panel past it and
   require the screen to be the one a minute later. *)
let windowed ?slow ~now ~since ~within () =
  let slow = Option.map slow ~f:(fun step -> quantized ~now ~step) in
  Bonsai.cutoff ~equal:Time_ns.equal
    (match slow with
     | Some slow ->
       let%arr now and since and slow in
       (match since with
        | Some since when Time_ns.Span.(Time_ns.diff now since < within) -> now
        | Some _ | None -> slow)
     | None ->
       let%arr now and since in
       (match since with
        | None -> Time_ns.epoch
        | Some since ->
          if Time_ns.Span.(Time_ns.diff now since < within) then now else Time_ns.add since within))

(* A clock that ticks once a second, on the second, while [enabled] and at no other time. Its
   value is the instant of the latest tick: the first tick is when it is enabled, the rest
   are the wall-clock second boundaries after it, so every user of it wakes together. A sleep
   in flight when [enabled] turns false ends without a tick; turning it on again starts anew. *)
type second_model = { tick : Time_ns.t; waiting : bool }
type second_action = Enable | Boundary

let each_second ?(wake = Wake.off) ~enabled (local_ graph) =
  let timer = Wake.Timer.create wake in
  let model, inject =
    Bonsai.state_machine_with_input ~default_model:{ tick = Time_ns.epoch; waiting = false }
      ~apply_action:(fun context input model action ->
        match input with
        | Bonsai.Computation_status.Inactive -> model
        | Active enabled ->
          let now = Bonsai.Time_source.now (Bonsai.Apply_action_context.time_source context) in
          let wait_for_next_second () =
            let next = Time_ns.next_multiple ~can_equal_after:false ~base:Time_ns.epoch ~after:now
                ~interval:Time_ns.Span.second () in
            at_time context ~wake ~timer ~at:next Boundary;
            { tick = now; waiting = true } in
          (match action with
           | Enable -> if enabled && not model.waiting then wait_for_next_second () else model
           | Boundary -> if enabled then wait_for_next_second () else { model with waiting = false }))
      enabled graph in
  Bonsai.Edge.on_change ~equal:Bool.equal enabled
    ~callback:(let%arr inject in fun (_ : bool) -> inject Enable) graph;
  Bonsai.cutoff ~equal:Time_ns.equal (let%arr model in model.tick)
