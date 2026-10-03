open! Core
open Bonsai.Let_syntax
open Model_adapter

(* Rolling 60 s of cumulative backend counters, sampled once a second. Rates are
   deltas between consecutive samples, so nothing here depends on the stream rate. *)

type counters = { decisions : int; admitted : int; blocked : int; trace_loss : int }
(* [None] while disconnected: the counters cannot be trusted, so rates are unknown. *)
type sample = { time : Time_ns.t; counters : counters option }
(* Newest first. *)
type t = { mode : mode; run_id : string; samples : sample list }

let window = Time_ns.Span.of_sec 60.
let sample_period = Time_ns.Span.of_sec 1.
let empty = { mode = Mock; run_id = ""; samples = [] }

let counters_of_state (state : application_state) =
  if not state.connected then None
  else Some { decisions = state.decisions.next_sequence
            ; admitted = List.sum (module Int) state.rules ~f:(fun rule -> rule.admitted)
            ; blocked = List.sum (module Int) state.rules ~f:(fun rule -> rule.blocked)
            ; trace_loss = state.trace_loss }

let regressed ~before ~after =
  after.decisions < before.decisions || after.admitted < before.admitted
  || after.blocked < before.blocked || after.trace_loss < before.trace_loss

(* A new run, or counters that went backwards, start a fresh window. A lost stream is recorded
   once, as the sample where the series stops; the ticks after it say nothing new, so they leave
   the state as it is (the same value, nothing to repaint) except to let old samples age out. *)
let observe t ~now (state : application_state) =
  let counters = counters_of_state state in
  let newest = List.find_map t.samples ~f:(fun sample -> sample.counters) in
  let restarted =
    not (String.equal t.run_id state.run_id)
    || (match counters, newest with
        | Some after, Some before -> regressed ~before ~after
        | _ -> false) in
  let cutoff = Time_ns.sub now window in
  let kept = if restarted then [] else
      List.filter t.samples ~f:(fun sample -> Time_ns.(sample.time >= cutoff)) in
  let records = Option.is_some counters
                || (match kept with { counters = Some _; _ } :: _ -> true | _ -> false) in
  let samples = if records then { time = now; counters } :: kept else kept in
  if (not records) && equal_mode t.mode state.mode && String.equal t.run_id state.run_id
     && List.length samples = List.length t.samples
  then t
  else { mode = state.mode; run_id = state.run_id; samples }

let connected t =
  match t.samples with { counters = Some _; _ } :: _ -> true | _ -> false

(* When the newest sample was taken; charts anchor their right edge here while the
   stream is fresh, so they advance once per sample, not once per repaint. *)
let newest t = Option.map (List.hd t.samples) ~f:(fun sample -> sample.time)

type series = (Time_ns.t * float option) list

(* One point per consecutive sample pair, stamped with the later time. *)
let intervals t ~f : series =
  let rec go = function
    | (newer : sample) :: (older : sample) :: rest ->
      let seconds = Time_ns.diff newer.time older.time |> Time_ns.Span.to_sec in
      let value = match older.counters, newer.counters with
        | Some before, Some after when Float.(seconds > 0.) -> f ~before ~after ~seconds
        | _ -> None in
      (newer.time, value) :: go (older :: rest)
    | _ -> [] in
  List.rev (go t.samples)

let per_second count ~seconds = Some (Float.of_int count /. seconds)

let decisions_per_second t =
  intervals t ~f:(fun ~before ~after ~seconds -> per_second (after.decisions - before.decisions) ~seconds)

(* admitted ÷ (admitted + blocked) within each interval; undefined with no outcomes. *)
let admit_ratio t =
  intervals t ~f:(fun ~before ~after ~seconds:_ ->
    let admitted = after.admitted - before.admitted and blocked = after.blocked - before.blocked in
    if admitted + blocked = 0 then None
    else Some (Float.of_int admitted /. Float.of_int (admitted + blocked)))

let trace_loss_per_second t =
  intervals t ~f:(fun ~before ~after ~seconds -> per_second (after.trace_loss - before.trace_loss) ~seconds)

type summary = { min : float; max : float; last : float option }

let summarize (series : series) =
  let values = List.filter_map series ~f:snd in
  match List.min_elt values ~compare:Float.compare, List.max_elt values ~compare:Float.compare with
  | Some min, Some max -> Some { min; max; last = Option.bind (List.last series) ~f:snd }
  | _ -> None

(* Nearest rank: the smallest value with at least [p]% of the sorted samples at or below it. *)
let percentile sorted ~p =
  let count = Array.length sorted in
  if count = 0 then None
  else (
    let rank = Int.max 1 (Float.iround_up_exn (p *. Float.of_int count /. 100.)) in
    Some sorted.(Int.min count rank - 1))

let has_samples t = List.exists t.samples ~f:(fun sample -> Option.is_some sample.counters)

(* Whether the sampler has anything to do: the stream is up, or real samples remain in the window. *)
let needs_sampler (state : application_state) t = state.connected || has_samples t

(* Sampled on the second, while the stream is up or real samples remain to age out of the
   window. A lost stream with nothing left in the window needs no sampler, so it runs no timer. *)
let component ~state (local_ graph) =
  let metrics, inject =
    Bonsai.state_machine_with_input ~default_model:empty
      ~apply_action:(fun context input t () ->
        match input with
        | Bonsai.Computation_status.Inactive -> t
        | Active state ->
          observe t state
            ~now:(Bonsai.Time_source.now (Bonsai.Apply_action_context.time_source context)))
      state graph in
  let sampling = let%arr state and metrics in needs_sampler state metrics in
  let tick = Anim_clock.each_second ~enabled:sampling graph in
  (* The first value is the clock's start, not a tick. *)
  Bonsai.Edge.on_change' ~equal:Time_ns.equal tick
    ~callback:(let%arr inject in fun previous (_ : Time_ns.t) ->
      if Option.is_some previous then inject () else Bonsai_term.Effect.Ignore) graph;
  metrics
