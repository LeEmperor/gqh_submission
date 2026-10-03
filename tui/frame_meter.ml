open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

(* What bonsai_term lets an application measure. Each loop iteration starts by advancing
   the Bonsai clock to the wall time at the top of the frame, flushes and recomputes the
   view, paints it (Notty diff plus a flushed tty write) only when the view changed, then
   runs the after-display lifecycle. The loop then sleeps until the next event or [Wake], or
   until its slow fallback timer. So from inside the graph we can read:

   - frame work: wall time from the top of the frame (the Bonsai clock) to the after-display
     lifecycle, i.e. flush + recompute + paint + tty flush, including any Async jobs that ran
     while the paint was being awaited. It excludes the idle wait and event handling.
   - painted frames: after-display callbacks of a frame in which [Paint_throttle] released a
     view, which is exactly the frames the driver paints.

   Only painted frames are timed: an idle frame that repaints nothing would swamp the
   percentiles with microsecond samples. The frame interval is not reported, because it is
   dominated by the idle wait and says nothing about render cost. The initial full paint
   is not timed either: no view has been released when its frame begins. *)

(* A 60 fps frame is 16.7 ms; 16 ms is the p99 target the bench checks and the overlay flags. *)
let budget_ms = 16.

type t =
  { window : int
  ; frames : float Fqueue.t        (* frame work of the last [window] painted frames, ms *)
  ; last_ms : float
  ; renders : int
  ; coalesced : int
  ; updates : int option           (* cumulative stream events at the previous painted frame *)
  ; recent : (Time_ns.t * int) Fqueue.t }  (* (paint time, cumulative events), last second *)

let empty ~window =
  { window; frames = Fqueue.empty; last_ms = 0.; renders = 0; coalesced = 0; updates = None; recent = Fqueue.empty }

let rec drop_while queue ~f =
  match Fqueue.peek queue with
  | Some head when f head -> drop_while (Fqueue.drop_exn queue) ~f
  | _ -> queue

(* A painted frame absorbs the stream events that arrived since the previous painted frame.
   All but the first of them are coalesced: they shared a frame instead of earning their own. *)
let record t ~frame_ms ~at ~updates =
  let frames = Fqueue.enqueue t.frames frame_ms in
  let frames = if Fqueue.length frames > t.window then Fqueue.drop_exn frames else frames in
  let events = Option.value_map t.updates ~default:0 ~f:(fun before -> Int.max 0 (updates - before)) in
  let cutoff = Time_ns.sub at (Time_ns.Span.of_sec 1.) in
  let recent = Fqueue.enqueue t.recent (at, updates)
               |> drop_while ~f:(fun (time, _) -> Time_ns.(time < cutoff)) in
  { t with frames; recent; last_ms = frame_ms; renders = t.renders + 1
         ; coalesced = t.coalesced + Int.max 0 (events - 1); updates = Some updates }

let events_per_second t =
  match Fqueue.peek t.recent, List.last (Fqueue.to_list t.recent) with
  | Some (first_time, first), Some (last_time, last) ->
    let seconds = Time_ns.diff last_time first_time |> Time_ns.Span.to_sec in
    if Float.(seconds <= 0.) then 0. else Float.of_int (last - first) /. seconds
  | _ -> 0.

let stats t ~buffers : Ui_types.frame_stats =
  let sorted = Array.of_list (Fqueue.to_list t.frames) in
  Array.sort sorted ~compare:Float.compare;
  let at p = Option.value (Metrics_state.percentile sorted ~p) ~default:0. in
  let count = Array.length sorted in
  { last_ms = t.last_ms
  ; avg_ms = if count = 0 then 0. else Array.sum (module Float) sorted ~f:Fn.id /. Float.of_int count
  ; p50_ms = at 50.; p99_ms = at 99.; max_ms = at 100.
  ; events_per_second = events_per_second t; render_count = t.renders
  ; coalesced_frames = t.coalesced; buffer_sizes = buffers }

let buffers_of_state (state : application_state) =
  [ "decisions", Map.length state.decisions.records
  ; "config events", List.length state.config_events ]

type model =
  { meter : t; sizes : (string * int) list
  ; published : Ui_types.frame_stats; published_at : Time_ns.t }
type input = { updates : int; buffers : (string * int) list; enabled : bool }
type action = Painted of { start : Time_ns.t; finish : Time_ns.t }

type probe =
  { stats : Ui_types.frame_stats Bonsai.t
  ; snapshot : Ui_types.frame_stats Effect.t Bonsai.t
  ; paint : unit Effect.t Bonsai.t }

(* The overlay is republished at most twice a second, and only while [enabled], so that
   measuring never keeps an otherwise idle application repainting. *)
let publish_period = Time_ns.Span.of_sec 0.5

let probe ?(window = 600) ?(on_paint = fun ~start:_ ~finish:_ -> ()) ~enabled ~updates ~buffers (local_ graph) =
  let input = let%arr enabled and updates and buffers in { updates; buffers; enabled } in
  let nothing = stats (empty ~window) ~buffers:[] in
  let model, inject =
    Bonsai.state_machine_with_input
      ~default_model:{ meter = empty ~window; sizes = []; published = nothing; published_at = Time_ns.epoch }
      ~apply_action:(fun _context input model (Painted { start; finish }) ->
        match input with
        | Bonsai.Computation_status.Inactive -> model
        | Active input ->
          let frame_ms = Time_ns.diff finish start |> Time_ns.Span.to_ms in
          let meter = record model.meter ~frame_ms ~at:finish ~updates:input.updates in
          let model = { model with meter; sizes = input.buffers } in
          if input.enabled && Time_ns.Span.(Time_ns.diff finish model.published_at >= publish_period)
          then { model with published = stats meter ~buffers:input.buffers; published_at = finish }
          else model)
      input graph in
  let overlay = Bonsai.cutoff ~equal:Ui_types.equal_frame_stats
      (let%arr model in model.published) in
  let read = Bonsai.peek model graph in
  let snapshot = let%arr read in
    let%map.Effect status = read in
    match status with
    | Bonsai.Computation_status.Active model -> stats model.meter ~buffers:model.sizes
    | Inactive -> nothing in
  let get_time = Bonsai.Clock.get_current_time graph in
  let paint = let%arr inject and get_time in
    let open Effect.Let_syntax in
    let%bind start = get_time in
    let%bind finish = Effect.of_sync_fun Time_ns.now () in
    on_paint ~start ~finish;
    inject (Painted { start; finish }) in
  { stats = overlay; snapshot; paint }

(* Time every paint. [paints] counts the views [Paint_throttle] has released, one per paint.
   This runs at the end of every frame, after its paint, and times the frames that raised
   the count. The first frame, which precedes the first paint, raised nothing. Without
   [paints], as under test where nothing paints, nothing is observed: an effect that runs
   after every frame would keep a harness that waits for the frames to settle waiting
   forever. *)
let observe { paint; _ } ?(paints : (unit -> int) option) (local_ graph) =
  match paints with
  | None -> ()
  | Some paints ->
    let seen = ref (paints ()) in
    let after_paint = let%arr paint in
      let open Effect.Let_syntax in
      let%bind count = Effect.of_sync_fun paints () in
      if count = !seen then Effect.Ignore else (seen := count; paint) in
    Bonsai.Edge.after_display after_paint graph
