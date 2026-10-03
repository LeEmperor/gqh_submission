open! Core
open Bonsai_term
open Bonsai.Let_syntax

(* The time that animated views read. [Bonsai.Clock.approx_now] ticks for as long as it is
   observed, so a view that reads it is recomputed, and the screen repainted, twenty times a
   second even when nothing on screen moves. This clock is demand-driven instead: it
   advances only while something has happened recently, and after the last animation it
   schedules no timer.

   [Touch] is an event that starts or extends an animation. After it the clock ticks once per
   fade step ([Fade.step], eleven a second) for [fast_hold], long enough for the longest fade
   (a second), and then at [slow_period] for [slow_hold], so a 60-second chart keeps sliding for
   as long as it still holds data. After that it stops, and its value stays at the last tick.

   An application whose stream has gone quiet therefore runs exactly these, and no other timer:
   - the header's seconds clock, always, repainting the header once a second ([each_second]);
   - the metrics sampler, while the stream is up or samples remain in the 60 s window, on the
     same wall-clock second, so the two share one repaint a second ([each_second]);
   - the stream's own poll, which waits for the backend and repaints nothing when it brings
     nothing new.
   A stream that is down, with nothing left in the metrics window, repaints only the header. *)

let fast_period = Fade.step
let slow_period = Time_ns.Span.of_sec 0.5
let fast_hold = Time_ns.Span.of_sec 1.1
let slow_hold = Time_ns.Span.of_sec 65.

type model =
  { now : Time_ns.t
  ; touched : Time_ns.t
  ; generation : int  (* a pending sleep of an older generation is ignored when it wakes *)
  ; pending : Time_ns.Span.t option }  (* the period of the sleep in flight, if any *)

type action = Sync | Touch | Tick of int

let period_after ~age =
  if Time_ns.Span.(age < fast_hold) then Some fast_period
  else if Time_ns.Span.(age < slow_hold) then Some slow_period
  else None

let component ~activity ~equal (local_ graph) =
  let model, inject =
    Bonsai.state_machine ~default_model:{ now = Time_ns.epoch; touched = Time_ns.epoch
                                        ; generation = 0; pending = None }
      ~apply_action:(fun context model action ->
        let time_source = Bonsai.Apply_action_context.time_source context in
        let now = Bonsai.Time_source.now time_source in
        (* Ticks fall on multiples of the period, so a fade steps on the same tick whenever it
           began, and a late wake-up does not push the ticks after it out of step. *)
        let sleep_then generation period =
          let next = Time_ns.next_multiple ~can_equal_after:false ~base:Time_ns.epoch ~after:now
              ~interval:period () in
          Bonsai.Apply_action_context.schedule_event context
            (let%bind.Effect () = Bonsai.Time_source.sleep time_source (Time_ns.diff next now) in
             Bonsai.Apply_action_context.inject context (Tick generation)) in
        match action with
        | Sync -> { model with now }
        | Touch ->
          (* A slow sleep may be in flight; waking it for the fast phase needs a new one. *)
          (match model.pending with
           | Some period when Time_ns.Span.equal period fast_period ->
             { model with now; touched = now }
           | _ ->
             let generation = model.generation + 1 in
             sleep_then generation fast_period;
             { now; touched = now; generation; pending = Some fast_period })
        | Tick generation when generation <> model.generation -> model
        | Tick generation ->
          (match period_after ~age:(Time_ns.diff now model.touched) with
           | Some period -> sleep_then generation period; { model with now; pending = Some period }
           | None -> { model with now; pending = None }))
      graph in
  (* The first value only starts the clock's time; it is no event. *)
  let callback = let%arr inject in fun previous (_ : _) ->
    inject (match previous with None -> Sync | Some _ -> Touch) in
  Bonsai.Edge.on_change' ~equal activity ~callback graph;
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

let each_second ~enabled (local_ graph) =
  let model, inject =
    Bonsai.state_machine_with_input ~default_model:{ tick = Time_ns.epoch; waiting = false }
      ~apply_action:(fun context input model action ->
        match input with
        | Bonsai.Computation_status.Inactive -> model
        | Active enabled ->
          let time_source = Bonsai.Apply_action_context.time_source context in
          let now = Bonsai.Time_source.now time_source in
          let wait_for_next_second () =
            let next = Time_ns.next_multiple ~can_equal_after:false ~base:Time_ns.epoch ~after:now
                ~interval:Time_ns.Span.second () in
            Bonsai.Apply_action_context.schedule_event context
              (let%bind.Effect () = Bonsai.Time_source.sleep time_source (Time_ns.diff next now) in
               Bonsai.Apply_action_context.inject context Boundary);
            { tick = now; waiting = true } in
          (match action with
           | Enable -> if enabled && not model.waiting then wait_for_next_second () else model
           | Boundary -> if enabled then wait_for_next_second () else { model with waiting = false }))
      enabled graph in
  Bonsai.Edge.on_change ~equal:Bool.equal enabled
    ~callback:(let%arr inject in fun (_ : bool) -> inject Enable) graph;
  Bonsai.cutoff ~equal:Time_ns.equal (let%arr model in model.tick)
