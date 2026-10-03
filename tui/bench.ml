open! Core
open Async
open Bonsai_term
open Bonsai.Let_syntax

(* [console --mode mock --bench]: run the real app in this terminal for [duration], then
   restore the terminal and print what Frame_meter measured. MOCK data only. *)

let max_rate_hz = 1000.
let duration = Time_ns.Span.of_sec 20.
(* Enough to keep every painted frame of a run, so percentiles cover the whole run. *)
let window = 200_000

(* The bench always runs the Monitor preset, so numbers from different machines compare. It
   neither reads the operator's saved preset nor writes one, whatever keys are pressed. *)
let preset = Ui_types.Monitor

type staleness = { p50 : float; p99 : float; max : float }

let format_report ~(dimensions : Dimensions.t) ~rate_hz ~seconds ~events ~staleness ~keys ~key_count
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
    ; (if key_count = 0 then "key to paint: no keys sent (give bench_pty.py a keys-per-second argument)"
       else sprintf "key to paint, from a key reaching the app to the end of the paint that shows it \
                     (%d keys): p50 %.1f ms · p99 %.1f ms · max %.1f ms"
           key_count keys.p50 keys.p99 keys.max)
    ; sprintf "p99 < %.0f ms: %s" Frame_meter.budget_ms verdict
    ; sprintf "renders %d (%.1f/s, cap %.0f/s) · stream events received %d · coalesced %d"
        stats.render_count (Float.of_int stats.render_count /. seconds)
        Paint_throttle.frames_per_second events stats.coalesced_frames
    ; "coalesced = stream events that shared a painted frame with an earlier one \
       (per painted frame: events since the previous painted frame, minus one)" ]

type outcome =
  { dimensions : Dimensions.t; stats : Ui_types.frame_stats; staleness : staleness
  ; keys : staleness; key_count : int }

(* How long the screen is behind what it was told. Something "reaches the app" when the app
   could first draw it: a state when the backend hands it over, a key when its handler is
   called. A paint that began at [start] shows everything that had reached the app by then,
   and the delay is from that arrival to the end of the paint. A paint that shows nothing
   new (the header's clock, a highlight clearing) is not a reply to anything and is not
   timed. A stream's states supersede one another, so only the newest of those a paint shows
   is timed; every key was pressed, so each of them is. The arrival times are kept, oldest
   first, until a paint has passed them. *)
module Log = struct
  type t = { arrivals : Time_ns.t Queue.t; every : bool; delays : float Queue.t }
  let create ?(every = false) () = { arrivals = Queue.create (); every; delays = Queue.create () }
  let arrived t time = Queue.enqueue t.arrivals time
  let painted t ~start ~finish =
    let rec shown newest_first =
      match Queue.peek t.arrivals with
      | Some time when Time_ns.(time <= start) -> shown (Queue.dequeue_exn t.arrivals :: newest_first)
      | Some _ | None -> newest_first in
    let shown = shown [] in
    List.iter (if t.every then shown else List.take shown 1) ~f:(fun arrival ->
      Queue.enqueue t.delays (Time_ns.diff finish arrival |> Time_ns.Span.to_ms))
  let count t = Queue.length t.delays
  let staleness t =
    let sorted = Array.of_list (Queue.to_list t.delays) in
    Array.sort sorted ~compare:Float.compare;
    let at p = Option.value (Metrics_state.percentile sorted ~p) ~default:0. in
    { p50 = at 50.; p99 = at 99.; max = at 100. }
end

(* The app under test, as [Runner.run] runs it. [events] counts what the backend delivers,
   outside the app: this is the stream, not the frames. *)
let app ?(wake = Wake.off) ~theme ~backend ~events ~log ~keys ?paints ~exit ~dimensions (local_ graph) =
  let module Backend = struct
    type t = Mock_backend.t
    let state = Mock_backend.state
    let handle_command = Mock_backend.handle_command
    let polling = Mock_backend.polling
    let next t =
      let%map.Deferred next = Mock_backend.next t in
      Bonsai.Expert.Var.update events ~f:(fun total ->
        total + (Mock_backend.state next).updates - (Mock_backend.state t).updates);
      Log.arrived log (Time_ns.now ());
      next
  end in
  let ~view, ~handler =
    App.live ~wake ?paints ~initial_preset:preset
      ~on_preset:(Bonsai.return (fun (_ : Ui_types.preset) -> Effect.return (Ok ())))
      (module Backend) ~theme ~backend ~exit:(fun () -> exit None) ~dimensions graph in
  let handler = let%arr handler in fun (event : Event.t) ->
    (match event with Key_press _ -> Log.arrived keys (Time_ns.now ()) | _ -> ());
    handler event in
  (* The runner throttles to 60 fps itself, so this meter observes the painted frames. It is
     the bench's own, with a window that keeps the whole run; the app's F12 meter stays off. *)
  let on_paint ~start ~finish = Log.painted log ~start ~finish; Log.painted keys ~start ~finish in
  let meter = Frame_meter.probe ~window ~on_paint ~enabled:(Bonsai.return false)
      ~updates:(Bonsai.Expert.Var.value events) ~buffers:(Bonsai.return []) graph in
  Frame_meter.observe meter ?paints graph;
  let read_dimensions = Bonsai.peek dimensions graph in
  let finish =
    let%arr snapshot = meter.snapshot and read_dimensions in
    let open Effect.Let_syntax in
    let%bind stats = snapshot in
    match%bind read_dimensions with
    | Inactive -> exit None
    | Active dimensions ->
      exit (Some { dimensions; stats; staleness = Log.staleness log
                 ; keys = Log.staleness keys; key_count = Log.count keys }) in
  let sleep = Bonsai.Clock.sleep graph in
  let run_for_duration =
    let%arr finish and sleep in
    let open Effect.Let_syntax in
    let%bind () = Wake.sleep wake ~fallback:sleep duration in
    let%bind () = finish in
    Wake.now_effect wake in
  Bonsai.Edge.lifecycle ~on_activate:run_for_duration graph;
  ~view, ~handler

let run ~theme ~backend ~rate_hz =
  let events = Bonsai.Expert.Var.create 0 and log = Log.create () and keys = Log.create ~every:true () in
  match%map.Deferred
    Runner.run (fun ~wake ~paints ~exit ~dimensions graph ->
      app ~wake ~theme ~backend ~events ~log ~keys ~paints ~exit ~dimensions graph)
  with
  | Error error -> Error error
  | Ok None -> print_endline "bench interrupted: no report"; Ok ()
  | Ok (Some { dimensions; stats; staleness; keys; key_count }) ->
    print_endline (format_report ~dimensions ~rate_hz ~seconds:(Time_ns.Span.to_sec duration)
                     ~events:(Bonsai.Expert.Var.get events) ~staleness ~keys ~key_count ~stats);
    Ok ()
