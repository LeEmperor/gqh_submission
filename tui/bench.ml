open! Core
open Async
open Bonsai_term
open Bonsai.Let_syntax

(* [console --mode mock --bench]: run the real app in this terminal for [duration], then
   restore the terminal and print what Frame_meter measured. MOCK data only. *)

let max_rate_hz = 1000.
let duration = Time_ns.Span.of_sec 20.
let target_frames_per_second = 60.
(* Enough to keep every painted frame of a run, so percentiles cover the whole run. *)
let window = 200_000

(* The bench always runs the Monitor preset, so numbers from different machines compare. It
   neither reads the operator's saved preset nor writes one, whatever keys are pressed. *)
let preset = Ui_types.Monitor

type staleness = { p50 : float; p99 : float; max : float }

let format_report ~(dimensions : Dimensions.t) ~rate_hz ~seconds ~events ~staleness
    ~(stats : Ui_types.frame_stats) =
  let verdict = if Float.(stats.p99_ms < Frame_meter.budget_ms) then "PASS" else "FAIL" in
  String.concat ~sep:"\n"
    [ sprintf "tickweave bench · MOCK · %s %dx%d · %.0f s · stream %.0f Hz"
        (Presets.name preset) dimensions.width dimensions.height seconds rate_hz
    ; sprintf "frame work, painted frames only (flush + compute + paint to tty): p50 %.2f ms · p99 %.2f ms · max %.2f ms"
        stats.p50_ms stats.p99_ms stats.max_ms
    ; sprintf "stream to paint, from a state reaching the app to the end of the paint that shows it: \
               p50 %.1f ms · p99 %.1f ms · max %.1f ms"
        staleness.p50 staleness.p99 staleness.max
    ; sprintf "p99 < %.0f ms: %s" Frame_meter.budget_ms verdict
    ; sprintf "renders %d (%.1f/s, cap %.0f/s) · stream events received %d · coalesced %d"
        stats.render_count (Float.of_int stats.render_count /. seconds)
        target_frames_per_second events stats.coalesced_frames
    ; "coalesced = stream events that shared a painted frame with an earlier one \
       (per painted frame: events since the previous painted frame, minus one)" ]

type outcome =
  { dimensions : Dimensions.t; stats : Ui_types.frame_stats; staleness : staleness }

(* How long the screen is behind the stream. A state "reaches the app" when the backend hands it
   over, which is when the app could first draw it; a frame that began at [start] draws the newest
   state that had reached the app by then, and the delay is from that arrival to the end of the
   paint. The arrival times are kept, oldest first, until a frame has passed them. *)
module Log = struct
  type t = { arrivals : Time_ns.t Queue.t; mutable newest : Time_ns.t option; delays : float Queue.t }
  let create () = { arrivals = Queue.create (); newest = None; delays = Queue.create () }
  let arrived t time = Queue.enqueue t.arrivals time
  let painted t ~start ~finish =
    while Option.exists (Queue.peek t.arrivals) ~f:(fun time -> Time_ns.(time <= start)) do
      t.newest <- Queue.dequeue t.arrivals
    done;
    Option.iter t.newest ~f:(fun arrival ->
      Queue.enqueue t.delays (Time_ns.diff finish arrival |> Time_ns.Span.to_ms))
  let staleness t =
    let sorted = Array.of_list (Queue.to_list t.delays) in
    Array.sort sorted ~compare:Float.compare;
    let at p = Option.value (Metrics_state.percentile sorted ~p) ~default:0. in
    { p50 = at 50.; p99 = at 99.; max = at 100. }
end

(* The app under test, as [Bonsai_term.start_with_exit] runs it. [events] counts what the backend
   delivers, outside the app: this is the stream, not the frames. *)
let app ~theme ~backend ~events ~log ~exit ~dimensions (local_ graph) =
  let module Backend = struct
    type t = Mock_backend.t
    let state = Mock_backend.state
    let handle_command = Mock_backend.handle_command
    let next t =
      let%map.Deferred next = Mock_backend.next t in
      Bonsai.Expert.Var.update events ~f:(fun total ->
        total + (Mock_backend.state next).updates - (Mock_backend.state t).updates);
      Log.arrived log (Time_ns.now ());
      next
  end in
  let ~view, ~handler =
    App.live ~initial_preset:preset ~on_preset:(Bonsai.return (fun (_ : Ui_types.preset) -> Effect.return (Ok ())))
      (module Backend) ~theme ~backend ~exit:(fun () -> exit None) ~dimensions graph in
  (* App.live throttles to 60 fps itself, so this meter observes the painted frames. It is
     the bench's own, with a window that keeps the whole run; the app's F12 meter stays off. *)
  let meter = Frame_meter.probe ~window ~on_paint:(Log.painted log) ~enabled:(Bonsai.return false)
      ~updates:(Bonsai.Expert.Var.value events) ~buffers:(Bonsai.return []) graph in
  Frame_meter.observe meter ~view graph;
  let read_dimensions = Bonsai.peek dimensions graph in
  let finish =
    let%arr snapshot = meter.snapshot and read_dimensions in
    let open Effect.Let_syntax in
    let%bind stats = snapshot in
    match%bind read_dimensions with
    | Inactive -> exit None
    | Active dimensions -> exit (Some { dimensions; stats; staleness = Log.staleness log }) in
  Bonsai.Clock.every ~when_to_start_next_effect:`Every_multiple_of_period_blocking
    ~trigger_on_activate:false (Bonsai.return duration) finish graph;
  ~view, ~handler

let run ~theme ~backend ~rate_hz =
  let events = Bonsai.Expert.Var.create 0 and log = Log.create () in
  match%map.Deferred
    Bonsai_term.start_with_exit ~mouse:All_mouse_events_except_hover ~target_frames_per_second
      (app ~theme ~backend ~events ~log)
  with
  | Error error -> Error error
  | Ok None -> print_endline "bench interrupted: no report"; Ok ()
  | Ok (Some { dimensions; stats; staleness }) ->
    print_endline (format_report ~dimensions ~rate_hz ~seconds:(Time_ns.Span.to_sec duration)
                     ~events:(Bonsai.Expert.Var.get events) ~staleness ~stats);
    Ok ()
