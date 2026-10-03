open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect

let ensure = Shell_tests.ensure
let theme = Shell_tests.theme
let cells = Braille_chart.display_width

(* A view as the terminal shows it, one string per row. The test terminal frames its output
   in a box; the frame is cut off, so a row is exactly what the view drew. *)
let rows view ~width ~height =
  String.split_lines (Phase5_shell_tests.render view ~width ~height)
  |> List.filter_map ~f:(fun line ->
    Option.bind (String.chop_prefix line ~prefix:"│") ~f:(String.chop_suffix ~suffix:"│"))

(* The display column at which [needle] starts on [line]: cells, not bytes. *)
let column line needle =
  Option.map (String.substr_index line ~pattern:needle) ~f:(fun at -> cells (String.prefix line at))

let row_with lines needle = List.find_exn lines ~f:(fun line -> String.is_substring line ~substring:needle)

(* --- 1. Padding is by display cells --------------------------------------------------------- *)

(* The first words of each help entry's description. A key that is wider in bytes than in
   cells (F1–F4, ↑/↓, ·) must not push its description out of the column. *)
let left_descriptions = [ "next panel"; "Monitor Decide"; "zoom focused"; "heatmap on/off"; "cumulative depth"
                        ; "theme amber"; "focus the panel"; "scroll Decisions"; "toggle frame meter"; "toggle help"
                        ; "close overlay"; "quit" ]
let right_descriptions = [ "select rule"; "first / last rule"; "select / top"; "half-page down"; "freeze Inspector"
                         ; "filter; Enter"; "pause / resume"; "deselect; G"; "open review"; "select / edit value"
                         ; "confirm Apply"; "reconcile UNKNOWN" ]

let%expect_test "help entries start their descriptions in one column per side" =
  let dimensions : Dimensions.t = { width = 100; height = 40 } in
  let lines = rows (Help_overlay.view ~theme ~dimensions ~quitting:false) ~width:100 ~height:40 in
  let columns descriptions =
    List.map descriptions ~f:(fun text ->
      Option.value_exn (column (row_with lines text) text) ~message:text) in
  let left = List.dedup_and_sort (columns left_descriptions) ~compare:Int.compare
  and right = List.dedup_and_sort (columns right_descriptions) ~compare:Int.compare in
  printf "left columns %s; right columns %s\n"
    (String.concat ~sep:"," (List.map left ~f:Int.to_string))
    (String.concat ~sep:"," (List.map right ~f:Int.to_string));
  ensure (List.length left = 1 && List.length right = 1) "descriptions are not aligned by cell";
  [%expect {| left columns 15; right columns 68 |}]

(* A rule whose parameter name and unit are wider in bytes than in cells. *)
let wide_state () =
  let state = Shell_tests.state Enabled in
  let widen (rule : rule) = { rule with parameters = [ "débit", 5, "µs"; "maximum_price", 1005, "ticks" ] } in
  { state with rules = List.mapi state.rules ~f:(fun i rule -> if i = 0 then widen rule else rule)
             ; configuration = { state.configuration with parameters = [ "débit", 5; "maximum_price", 1005 ] }
             ; manifest = { state.manifest with parameter_ranges =
                 [ "débit", "µs", 0, 100; "maximum_price", "ticks", 990, 1010 ] } }

let%expect_test "the Rules parameter table lines its units up when names and units are not ASCII" =
  let state = wide_state () in
  let selected = Option.map (List.hd state.rules) ~f:(fun rule -> rule.rule_id) in
  let view = Rules_panel.view ~theme ~focus:Keymap.Rules ~state ~selected ~width:60 ~height:30 in
  let lines = rows view ~width:60 ~height:30 in
  let at needle = Option.value_exn (column (row_with lines needle) needle) ~message:needle in
  let units = [ at " µs"; at " t" ] in
  printf "µs and t start at columns %s\n" (String.concat ~sep:" and " (List.map units ~f:Int.to_string));
  ensure (List.all_equal units ~equal:Int.equal |> Option.is_some) "units are misaligned";
  [%expect {| µs and t start at columns 20 and 20 |}]

let%expect_test "Configuration parameter rows fill their width however wide the unit is in bytes" =
  let state = wide_state () in
  let widths = List.map (Config_review.parameter_rows theme state ~width:60) ~f:View.width in
  printf "row widths %s\n" (String.concat ~sep:"," (List.map widths ~f:Int.to_string));
  ensure (List.for_all widths ~f:(Int.equal 60)) "a parameter row is not the width it was given";
  [%expect {| row widths 60,60 |}]

(* --- 2. The market chart's time axis spans the plot ----------------------------------------- *)

let sample seconds ~bid ~ask : Market_motion.sample =
  { time = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds); bid = Some bid; ask = Some ask
  ; delta_updates = 1 }

let chart ~width ~height samples =
  Market_chart.view ~theme ~samples:(Age_deque.of_list samples) ~now:(Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec 60.))
    ~threshold:None ~width ~height
  |> rows ~width ~height

let steady = List.init 31 ~f:(fun i -> sample (Float.of_int (60 - (2 * i))) ~bid:1003 ~ask:1004)

let%expect_test "the time axis ends on 'now' at the last plot column at every width" =
  let short = List.filter_map [ 24; 30; 36; 46; 80; 120 ] ~f:(fun width ->
      let axis = String.rstrip (List.last_exn (chart ~width ~height:10 steady)) in
      Option.some_if (cells axis <> width || not (String.is_suffix axis ~suffix:"now")) (width, cells axis)) in
  printf "axis rows that stop short: %s\n"
    (String.concat ~sep:" " (List.map short ~f:(fun (w, c) -> sprintf "%d->%d" w c)));
  ensure (List.is_empty short) "an axis row does not span its chart";
  [%expect {| axis rows that stop short: |}]

(* --- 12. The legend states the mid whenever both sides are known ----------------------------- *)

let%expect_test "the chart legend gives mid = (bid + ask) / 2 when both are known" =
  let legend samples = String.strip (List.hd_exn (chart ~width:60 ~height:10 samples)) in
  print_endline (legend steady);
  print_endline (legend [ sample 60. ~bid:1003 ~ask:1006 ]);
  print_endline (legend [ { (sample 60. ~bid:1003 ~ask:1004) with ask = None } ]);
  [%expect {|
    t ask 1004  bid 1003  mid 1003.5 ┄
    t ask 1006  bid 1003  mid 1004.5 ┄
    t ask —  bid —  mid — ┄
    |}]

let%expect_test "the legend drops whole parts as the chart narrows and never clips a price" =
  let legend width = String.strip (List.hd_exn (chart ~width ~height:10 steady)) in
  let whole = [ "t"; "t ask 1004"; "t ask 1004  bid 1003"; "t ask 1004  bid 1003  mid 1003.5 ┄" ] in
  let clipped = List.filter (List.range 12 80) ~f:(fun width -> not (List.mem whole (legend width) ~equal:String.equal)) in
  printf "widths whose legend is cut mid-part: %s\n" (String.concat ~sep:"," (List.map clipped ~f:Int.to_string));
  ensure (List.is_empty clipped) "a legend clips a price";
  [%expect {| widths whose legend is cut mid-part: |}]

(* --- 10. A long block reason is cut, never flagged as an error ------------------------------- *)

let%expect_test "a long last-block reason is truncated with an ellipsis at the panel width" =
  let state = Shell_tests.state Enabled in
  let reason = "price 1000 t outside the admitted band [1001, 1005] set by the active configuration" in
  let state = { state with rules = List.mapi state.rules ~f:(fun i rule ->
      if i = 0 then { rule with last_block_reason = Some reason; blocked = 3 } else rule) } in
  let selected = Option.map (List.hd state.rules) ~f:(fun rule -> rule.rule_id) in
  let width = 40 in
  let lines = rows (Rules_panel.view ~theme ~focus:Keymap.Rules ~state ~selected ~width ~height:20)
      ~width ~height:20 in
  let block = row_with lines "last block:" in
  ensure (not (List.exists lines ~f:(String.is_substring ~substring:"TOO WIDE"))) "the panel shows VALUE TOO WIDE";
  (* Inside the panel's own frame. *)
  print_endline (String.strip block |> String.chop_prefix_if_exists ~prefix:"│"
                 |> String.chop_suffix_if_exists ~suffix:"│" |> String.strip);
  [%expect {| last block: price 1000 t outside th… |}]

(* --- 4. d is the depth toggle everywhere; Ctrl-d and Ctrl-u page ------------------------------ *)

let busy_state () =
  let backend = List.fold (List.range 0 60) ~init:(Shell_tests.fixture Enabled) ~f:(fun backend _ ->
      Mock_backend.advance backend) in
  Mock_backend.state backend

let%expect_test "plain d toggles cumulative depth with Decisions focused; Ctrl-u pages and Ctrl-d does not toggle" =
  let handle = Shell_tests.handle ~initial:(busy_state ()) ~preset:Demo { width = 120; height = 36 } in
  let send event = Bonsai_term_test.send_event handle event in
  let screen () = Shell_tests.screen handle in
  let cumulative () = String.is_substring (screen ()) ~substring:"cumulative qty" in
  send (Shell_tests.key (ASCII '3'));
  ensure (String.is_substring (screen ()) ~substring:"focus: Decisions") "Decisions not focused";
  ensure (not (cumulative ())) "depth starts cumulative";
  send (Shell_tests.key (ASCII 'd'));
  ensure (cumulative ()) "plain d did not toggle depth while Decisions is focused";
  send (Shell_tests.key (ASCII 'd'));
  ensure (not (cumulative ())) "second d did not toggle back";
  let tail = screen () in
  send (Shell_tests.key (ASCII 'u'));
  ensure (String.equal tail (screen ())) "plain u still pages Decisions";
  send (Shell_tests.key ~mods:[ Ctrl ] (ASCII 'u'));
  let paged = screen () in
  ensure (not (String.equal tail paged)) "Ctrl-u did not page Decisions";
  ensure (not (cumulative ())) "Ctrl-u toggled depth";
  send (Shell_tests.key ~mods:[ Ctrl ] (ASCII 'd'));
  ensure (not (String.equal paged (screen ()))) "Ctrl-d did not page Decisions";
  ensure (not (cumulative ())) "Ctrl-d toggled depth";
  print_endline "d toggles depth in Decisions; u is inert; Ctrl-u and Ctrl-d page and leave depth alone";
  [%expect {| d toggles depth in Decisions; u is inert; Ctrl-u and Ctrl-d page and leave depth alone |}]

(* --- 5. The bench is pinned to Monitor and leaves the operator's saved preset alone ---------- *)

(* The test process is single-domain, so changing its environment is safe here. *)
[@@@alert "-unsafe_multidomain"]
let with_state_directory contents ~f =
  let directory = Filename_unix.temp_dir "tickweave-bench" "" in
  let file = Filename.concat directory "last-preset" in
  Out_channel.write_all file ~data:contents;
  Core_unix.putenv ~key:"TICKWEAVE_STATE_DIR" ~data:directory;
  protect ~f:(fun () -> f file)
    ~finally:(fun () -> Core_unix.putenv ~key:"TICKWEAVE_STATE_DIR" ~data:"")

[@@@alert "+unsafe_multidomain"]

let%expect_test "the bench runs Monitor, whatever preset is saved, and never saves one" =
  with_state_directory "Decide\n" ~f:(fun file ->
    let _scheduler = Async.Scheduler.t () in
    let backend = Shell_tests.fixture Enabled in
    let events = Bonsai.Expert.Var.create 0 in
    let handle = Bonsai_term_test.create_handle ~initial_dimensions:{ width = 120; height = 36 }
        (fun ~dimensions (local_ graph) ->
           Bench.app ~theme ~backend ~events ~log:(Bench.Log.create ()) ~keys:(Bench.Log.create ~every:true ())
             ~exit:(fun _ -> Effect.Ignore) ~dimensions graph) in
    let screen () =
      Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.02);
      Handle.recompute_view_until_stable handle;
      Shell_tests.screen handle in
    ensure (String.is_substring (screen ()) ~substring:"Monitor ·") "the bench did not start on Monitor";
    Bonsai_term_test.send_event handle (Shell_tests.key (Function 4));
    ensure (String.is_substring (screen ()) ~substring:"Demo ·") "F4 did not switch the bench's preset";
    printf "saved after F4: %s\n" (String.strip (In_channel.read_all file));
    [%expect {| saved after F4: Decide |}])

let%expect_test "the bench report names the preset and the size" =
  let stats : Ui_types.frame_stats =
    { last_ms = 1.; avg_ms = 1.; p50_ms = 1.; p99_ms = 2.; max_ms = 3.; events_per_second = 0.
    ; render_count = 10; coalesced_frames = 0; buffer_sizes = [] } in
  let report = Bench.format_report ~dimensions:{ width = 200; height = 60 } ~rate_hz:1000. ~seconds:20.
      ~events:5 ~staleness:{ p50 = 1.; p99 = 2.; max = 3. } ~keys:{ p50 = 1.; p99 = 2.; max = 3. }
      ~key_count:0 ~stats in
  print_endline (List.hd_exn (String.split_lines report));
  [%expect {| tickweave bench · MOCK · Monitor 200x60 · 20 s · stream 1000 Hz |}]

(* --- 8. Number keys at a terminal that is too small change and save nothing ------------------- *)

let%expect_test "jumping while the terminal is too small leaves the preset and the saved preset alone" =
  let saved = ref [] in
  let handle = Layout_tests.app ~on_preset:(fun preset -> saved := preset :: !saved; Ok ()) { width = 90; height = 20 } in
  List.iter [ '2'; '4'; '5'; '3' ] ~f:(Layout_tests.press handle);
  Bonsai_term_test.set_dimensions handle { width = 120; height = 36 };
  printf "saved %d; after resize: %s\n" (List.length !saved) (Layout_tests.status handle);
  ensure (List.is_empty !saved) "a jump at too small a size saved a preset";
  [%expect {| saved 0; after resize: Monitor · amber · focus: Market |}]

(* --- 9. Three charts across need 66 inner columns, as the layout comment says ----------------- *)

(* What is drawn, not just which layout is named: side by side, the three titles share a row and
   each chart has its own time axis; stacked, the titles are on separate rows under one axis. *)
let%expect_test "Metrics sets three charts across from 66 inner columns and stacks them at 65" =
  List.iter [ 65; 66 ] ~f:(fun inner ->
    let width = inner + 4 and height = 12 in
    let view = Charts_tests.metrics_view ~width ~height () in
    let lines = rows view ~width ~height in
    let axes = List.sum (module Int) lines ~f:(fun line ->
        List.length (String.substr_index_all line ~may_overlap:false ~pattern:"└−60s")) in
    let one_row = List.exists lines ~f:(fun line ->
        List.for_all [ "decisions/s"; "admit ratio"; "trace loss/s" ] ~f:(fun title ->
          String.is_substring line ~substring:title)) in
    ensure (View.width view = width && View.height view = height) "Metrics does not fill its rect";
    printf "%d inner columns: %s, titles on one row %b, %d time axes\n" inner
      (Sexp.to_string (Metrics_panel.sexp_of_layout (Metrics_panel.layout_for ~width ~height))) one_row axes);
  [%expect {|
    65 inner columns: Stacked, titles on one row false, 1 time axes
    66 inner columns: Side_by_side, titles on one row true, 3 time axes
    |}]

(* --- 11. A lost stream is one break in the series, not a sample a second --------------------- *)

let counters = Metrics_tests.counters
let at = Metrics_tests.at

let%expect_test "while disconnected Metrics_state records the break once and then nothing" =
  let up = counters ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 ()
  and down = counters ~connected:false ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 () in
  let steady = Metrics_tests.observed [ 0., up; 1., up; 2., down ] in
  printf "one break: %d samples, connected %b\n" (List.length steady.samples) (Metrics_state.connected steady);
  let later = List.fold [ 3.; 4.; 5.; 6. ] ~init:steady ~f:(fun metrics seconds ->
      Metrics_state.observe metrics ~now:(at seconds) down) in
  printf "after four more ticks down: %d samples, the same value %b\n" (List.length later.samples)
    (phys_equal later steady);
  let from_cold = List.fold [ 0.; 1.; 2. ] ~init:Metrics_state.empty ~f:(fun metrics seconds ->
      Metrics_state.observe metrics ~now:(at seconds) down) in
  printf "down since the start: %d samples, connected %b\n" (List.length from_cold.samples)
    (Metrics_state.connected from_cold);
  let recovered = Metrics_state.observe later ~now:(at 7.) up in
  printf "back up: %d samples, connected %b\n" (List.length recovered.samples) (Metrics_state.connected recovered);
  ensure (phys_equal later steady) "a tick while disconnected rebuilt the state";
  [%expect {|
    one break: 3 samples, connected false
    after four more ticks down: 3 samples, the same value true
    down since the start: 0 samples, connected false
    back up: 4 samples, connected true
    |}]

let%expect_test "real samples still age out of the window while the stream stays down" =
  let up = counters ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 ()
  and down = counters ~connected:false ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 () in
  let metrics = Metrics_tests.observed [ 0., up; 1., up; 2., down ] in
  let aged = Metrics_state.observe metrics ~now:(at 70.) down in
  printf "after 68 s down: %d samples\n" (List.length aged.samples);
  [%expect {| after 68 s down: 0 samples |}]

(* --- 3. What runs while the application is idle ----------------------------------------------- *)

(* A connected stream that has gone quiet: the backend never delivers another state. *)
module Idle_backend = struct
  type t = Mock_backend.t
  let state = Mock_backend.state
  let handle_command = Mock_backend.handle_command
  let polling = Mock_backend.polling
  let next (_ : t) = Async.Deferred.never ()
end

(* The real [App.live] on an idle stream, with the per-node recompute hook and a count of the
   frames whose final view differs from the one before: each one is a paint. The app starts 0.37 s
   into the test's clock, as a real one starts at an arbitrary instant, not on a whole second. *)
let idle_app scenario =
  let _scheduler = Async.Scheduler.t () in
  let counts = String.Table.create () and paints = ref 0 in
  let on_compute name = Hashtbl.update counts name ~f:(fun n -> Option.value n ~default:0 + 1) in
  let handle = Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 120; height = 36 }
      ~to_view_with_handler:fst ~handle_incoming:(fun (_, start) () -> start ())
      (fun ~dimensions (local_ graph) ->
         let started, set_started = Bonsai.state false graph in
         let app = match%sub started with
           | false -> Bonsai.return (~view:View.none, ~handler:(fun (_ : Event.t) -> Effect.Ignore))
           | true ->
             let ~view, ~handler =
               App.live ~initial_preset:Demo
                 ~on_preset:(Bonsai.return (fun (_ : Ui_types.preset) -> Effect.return (Ok ())))
                 ~on_compute (module Idle_backend) ~theme ~backend:(Shell_tests.fixture scenario)
                 ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
             let%arr view and handler in (~view, ~handler) in
         let view = let%arr app in let ~view, ~handler:_ = app in view in
         Bonsai.Edge.on_change ~trigger:`After_display ~equal:phys_equal view
           ~callback:(Bonsai.return (fun (_ : View.t) -> Effect.of_sync_fun incr paints)) graph;
         let%arr app and set_started in
         (app, fun () -> set_started true)) in
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.37);
  Bonsai_term_test.do_actions handle [ () ];
  Handle.recompute_view_until_stable handle;
  handle, counts, paints

let step handle seconds =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec seconds);
  Handle.recompute_view_until_stable handle

(* Runs [seconds] of idle time in [by] steps, after a warm-up that lets start-up settle. *)
let measure_idle scenario ~seconds ~by =
  let handle, counts, paints = idle_app scenario in
  for _ = 1 to 40 do step handle 0.1 done;
  Hashtbl.clear counts;
  paints := 0;
  for _ = 1 to Float.to_int (seconds /. by) do step handle by done;
  let count name = Option.value (Hashtbl.find counts name) ~default:0 in
  count "header", count "Metrics", Hashtbl.length counts, !paints

let%expect_test "an idle connected app repaints once a second, for the clock and the sampler together" =
  let header, metrics, nodes, paints = measure_idle Enabled ~seconds:30. ~by:0.05 in
  printf "30 s idle, connected: header %d, Metrics %d, nodes that ran %d, paints %d\n" header metrics nodes paints;
  ensure (paints <= 32) "an idle app paints more than once a second";
  [%expect {| 30 s idle, connected: header 30, Metrics 30, nodes that ran 4, paints 30 |}]

let%expect_test "an idle app that has lost its stream repaints only the header clock" =
  let header, metrics, nodes, paints = measure_idle Connection_lost ~seconds:30. ~by:0.05 in
  printf "30 s idle, disconnected: header %d, Metrics %d, nodes that ran %d, paints %d\n" header metrics nodes paints;
  ensure (metrics = 0 && paints <= 32) "a lost stream still costs more than the header clock";
  [%expect {| 30 s idle, disconnected: header 30, Metrics 0, nodes that ran 2, paints 30 |}]

(* The header must change on the second, not up to a tick later. *)
let%expect_test "the header clock changes within one step of each wall-clock second" =
  let handle, _, _ = idle_app Enabled in
  let late = ref [] in
  for _ = 1 to 200 do
    step handle 0.05;
    let now = Bonsai.Time_source.now (Handle.time_source handle) in
    let shown = Time_ns.to_ofday now ~zone:Timezone.utc |> Time_ns.Ofday.to_sec_string in
    if not (String.is_substring (Shell_tests.screen handle) ~substring:shown)
    then late := Time_ns.to_string_utc now :: !late
  done;
  printf "steps at which the header showed an earlier second: %d\n" (List.length !late);
  ensure (List.is_empty !late) "the header clock lagged the wall clock";
  [%expect {| steps at which the header showed an earlier second: 0 |}]

let%expect_test "each_second ticks on the wall-clock second while enabled, and not at all when disabled" =
  let ticks = ref [] in
  let handle = Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 80; height = 24 }
      ~to_view_with_handler:fst ~handle_incoming:(fun (_, set) enabled -> set enabled)
      (fun ~dimensions:_ (local_ graph) ->
         let enabled, set = Bonsai.state false graph in
         let tick = Anim_clock.each_second ~enabled graph in
         let%arr tick and set in
         ticks := Time_ns.Span.to_sec (Time_ns.to_span_since_epoch tick) :: !ticks;
         ((~view:View.none, ~handler:(fun (_ : Event.t) -> Effect.Ignore)), set)) in
  let run seconds =
    ticks := [];
    for _ = 1 to Float.to_int (seconds /. 0.05) do step handle 0.05 done;
    List.rev !ticks in
  (* How far past a whole second each tick is: at most one 0.05 s step. *)
  let late ticks = List.exists ticks ~f:(fun tick -> Float.(tick -. Float.round_down tick > 0.051)) in
  step handle 0.37;
  printf "disabled: %d ticks in 10 s\n" (List.length (run 10.));
  Bonsai_term_test.do_actions handle [ true ];
  let enabled = run 10. in
  printf "enabled at +0.37 s: %d ticks in 10 s, any late %b\n" (List.length enabled) (late (List.tl_exn enabled));
  ensure (not (late (List.tl_exn enabled))) "a tick was not on the second";
  Bonsai_term_test.do_actions handle [ false ];
  printf "disabled again: %d ticks in 10 s\n" (List.length (run 10.));
  Bonsai_term_test.do_actions handle [ true ];
  printf "re-enabled: %d ticks in 3 s\n" (List.length (run 3.));
  [%expect {|
    disabled: 0 ticks in 10 s
    enabled at +0.37 s: 11 ticks in 10 s, any late false
    disabled again: 0 ticks in 10 s
    re-enabled: 4 ticks in 3 s
    |}]

let%expect_test "the metrics sampler is needed while the stream is up or samples remain, not otherwise" =
  let up = Metrics_tests.counters ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 ()
  and down = Metrics_tests.counters ~connected:false ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 () in
  let with_samples = Metrics_tests.observed [ 0., up; 1., up; 2., down ] in
  let aged = Metrics_state.observe with_samples ~now:(at 70.) down in
  let needs state metrics = Metrics_state.needs_sampler state metrics in
  printf "up, no samples %b; up, samples %b; down, samples %b; down, aged out %b\n"
    (needs up Metrics_state.empty) (needs up with_samples) (needs down with_samples) (needs down aged);
  [%expect {| up, no samples true; up, samples true; down, samples true; down, aged out false |}]

(* --- 6. The stream delivers the rate it is configured for ------------------------------------- *)

(* The polls the app makes: the timer's period, rounded up to the 60 Hz frame it can fire on. *)
let poll_interval ~rate_hz = Time_ns.Span.of_sec (Float.round_up (60. /. rate_hz) /. 60.)

let delivered_in_ten_seconds ~rate_hz =
  let interval = poll_interval ~rate_hz in
  let polls = Float.to_int (10. /. Time_ns.Span.to_sec interval) in
  let steps, _ = List.fold (List.range 0 polls) ~init:(0, 0.) ~f:(fun (total, carried) _ ->
      let steps, carried = Mock_backend.steps_due ~rate_hz ~elapsed:interval ~carried in
      total + steps, carried) in
  steps, Time_ns.Span.to_sec interval *. Float.of_int polls

let%expect_test "steps_due delivers the configured rate over ten simulated seconds" =
  List.iter [ 4.; 40.; 1000. ] ~f:(fun rate_hz ->
    let steps, seconds = delivered_in_ten_seconds ~rate_hz in
    let wanted = Float.to_int (rate_hz *. seconds) in
    printf "%4.0f Hz: %d steps in %.2f s, %d owed (whole steps in rate x time)\n" rate_hz steps seconds wanted;
    ensure (abs (steps - wanted) <= 1) (sprintf "%.0f Hz delivered %d, not %d" rate_hz steps wanted));
  [%expect {|
       4 Hz: 40 steps in 10.00 s, 40 owed (whole steps in rate x time)
      40 Hz: 399 steps in 10.00 s, 399 owed (whole steps in rate x time)
    1000 Hz: 9983 steps in 9.98 s, 9983 owed (whole steps in rate x time)
    |}]

let%expect_test "a stalled poll is capped at a second of steps and forgiven; an early one overdraws" =
  let steps, carried = Mock_backend.steps_due ~rate_hz:40. ~elapsed:(Time_ns.Span.of_sec 30.) ~carried:0.4 in
  let early, owed = Mock_backend.steps_due ~rate_hz:40. ~elapsed:(Time_ns.Span.of_sec 0.01) ~carried:0.3 in
  printf "after 30 s: %d steps, %.1f carried; after 10 ms: %d step, %.1f carried\n" steps carried early owed;
  [%expect {| after 30 s: 40 steps, 0.0 carried; after 10 ms: 1 step, -0.3 carried |}]

(* The heatmap labels a column stride / rate_hz seconds wide; that is true only if the stream
   really delivers rate_hz snapshots a second. *)
let%expect_test "at 40 Hz the heatmap makes a column every stride / rate seconds" =
  let rate_hz = 40. in
  let backend = Or_error.ok_exn (Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz) in
  let interval = poll_interval ~rate_hz in
  let polls = Float.to_int (10. /. Time_ns.Span.to_sec interval) in
  let heat, _, _ = List.fold (List.range 0 polls) ~init:(Heatmap.empty, backend, 0.)
      ~f:(fun (heat, backend, carried) _ ->
        let steps, carried = Mock_backend.steps_due ~rate_hz ~elapsed:interval ~carried in
        let backend = Fn.apply_n_times ~n:steps Mock_backend.advance backend in
        Heatmap.observe_sampled heat ~rate_hz (Mock_backend.state backend).market, backend, carried) in
  let seconds_per_column = Float.of_int heat.stride /. rate_hz in
  let columns = Fdeque.length heat.columns in
  printf "stride %d, labelled %.2f s a column; %d columns in 10 s, %.2f s a column in fact\n"
    heat.stride seconds_per_column columns (10. /. Float.of_int columns);
  ensure (columns >= 49 && columns <= 51) "the heatmap's column time is not the labelled one";
  [%expect {| stride 8, labelled 0.20 s a column; 50 columns in 10 s, 0.20 s a column in fact |}]

(* --- 7. Level sizes change stochastically, so the tape shows only real changes ---------------- *)

(* [count] snapshots of a book whose touch does not move, [dt] apart. *)
let still_books ~seed ~dt ~count =
  let walk = Market_walk.create ~seed ~bid:1003 ~spread:1 in
  let walk, first = Market_walk.advance walk ~dt:0.25 ~bid:1003 ~spread:1 ~previous:([], []) in
  let _, books = List.fold (List.range 0 count) ~init:(walk, [ first ]) ~f:(fun (walk, books) _ ->
      let walk, book = Market_walk.advance walk ~dt ~bid:1003 ~spread:1 ~previous:(List.hd_exn books) in
      walk, book :: books) in
  List.rev books

let%expect_test "a walk that is not moving shows an unchanging book" =
  let books = still_books ~seed:42 ~dt:0. ~count:20 in
  let changed = List.count (List.zip_exn (List.drop_last_exn books) (List.tl_exn books)) ~f:(fun (a, b) ->
      not ([%equal: level list * level list] a b)) in
  printf "snapshots that differ from the one before, with the walk frozen: %d of 20\n" changed;
  [%expect {| snapshots that differ from the one before, with the walk frozen: 0 of 20 |}]

let%expect_test "at 4 Hz most levels are unchanged from one snapshot to the next, and some change" =
  let books = still_books ~seed:42 ~dt:0.25 ~count:200 in
  let levels (bids, asks) = bids @ asks in
  let pairs = List.zip_exn (List.drop_last_exn books) (List.tl_exn books) in
  let unchanged, total = List.fold pairs ~init:(0, 0) ~f:(fun (unchanged, total) (before, after) ->
      let same = List.count (List.zip_exn (levels before) (levels after))
          ~f:(fun ((a : level), (b : level)) -> a.quantity_units = b.quantity_units) in
      unchanged + same, total + List.length (levels after)) in
  let share = Float.of_int unchanged /. Float.of_int total in
  printf "unchanged levels: %.0f%%\n" (100. *. share);
  ensure (Float.(share > 0.5 && share < 0.9)) "level changes are not sparse and stochastic";
  [%expect {| unchanged levels: 72% |}]

let%expect_test "the same seed gives the same book and another seed another" =
  let book seed = List.last_exn (still_books ~seed ~dt:0.25 ~count:50) in
  printf "same seed equal %b; other seed equal %b\n"
    ([%equal: level list * level list] (book 42) (book 42)) ([%equal: level list * level list] (book 42) (book 7));
  [%expect {| same seed equal true; other seed equal false |}]

let%expect_test "the tape infers no prints from a book that is not moving" =
  let base = (Shell_tests.state Enabled).market in
  let tape = List.fold (still_books ~seed:42 ~dt:0. ~count:40) ~init:Tape_panel.empty ~f:(fun tape (bids, asks) ->
      Tape_panel.observe tape ~now:Time_ns.epoch ~snapshot:{ base with bids; asks }) in
  printf "prints from a frozen book: %d\n" (List.length (Tape_panel.prints tape));
  [%expect {| prints from a frozen book: 0 |}]

(* --- 13. The heat ramp and the walls ------------------------------------------------------------ *)

let truecolor = Theme.create Truecolor

let%expect_test "white is the saturation zone: nothing below 1.5x the scale reaches it" =
  let top = Heatmap.buckets - 1 in
  let reaches quantity =
    Heatmap.bucket_of_heat (Heatmap.intensity ~quantity ~maximum:100) = top in
  printf "100 u at a scale of 100: white %b; 149 u: white %b; 150 u: white %b; 400 u: white %b\n"
    (reaches 100) (reaches 149) (reaches 150) (reaches 400);
  [%expect {| 100 u at a scale of 100: white false; 149 u: white false; 150 u: white true; 400 u: white true |}]

(* Colours the heatmap would paint: the ramp position each bucket stands for. *)
let shade bucket = Heatmap.ramp_rgb truecolor (Heatmap.bucket_intensity bucket)
let apart (r1, g1, b1) (r2, g2, b2) =
  let square x = x * x in
  let squared = square (r1 - r2) + square (g1 - g2) + square (b1 - b2) in
  Float.(sqrt (of_int squared) >= 24.)

(* How many shades, each at least 24 apart in RGB from every other and each worn by at least
   five cells, the resting cells in [buckets] make. *)
let distinguishable buckets =
  let worn = List.filter (List.dedup_and_sort buckets ~compare:Int.compare) ~f:(fun bucket ->
      List.count buckets ~f:(Int.equal bucket) >= 5) in
  List.fold worn ~init:[] ~f:(fun kept bucket ->
    if List.for_all kept ~f:(fun other -> apart (shade other) (shade bucket)) then bucket :: kept else kept)
  |> List.length

(* The heatmap as a Monitor-sized panel would draw it after [seconds] of the mock walk at 4 Hz:
   the bucket of every resting cell in view, at the scale the heatmap itself chooses. *)
let buckets_in_view ~seconds =
  let rate_hz = 4. in
  let backend = Or_error.ok_exn (Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz) in
  let _, heat = List.fold (List.range 0 (Float.to_int (seconds *. rate_hz))) ~init:(backend, Heatmap.empty)
      ~f:(fun (backend, heat) _ ->
        let backend = Mock_backend.advance backend in
        backend, Heatmap.observe_sampled heat ~rate_hz (Mock_backend.state backend).market) in
  let columns = Heatmap.visible heat ~count:100 in
  let center = Option.value_exn (Array.find_map (Array.rev columns) ~f:Heatmap.mid_price) in
  let bottom, top = Heatmap.fit ~rows:40 ~center in
  let maximum = Heatmap.scale columns ~bottom ~top in
  let grid = Heatmap.grid columns ~bottom ~top ~maximum ~threshold:None in
  Array.concat_map grid ~f:(Array.map ~f:Heatmap.bucket_of) |> Array.to_list
  |> List.filter ~f:(fun bucket -> bucket > 0)

let%expect_test "the heatmap over the mock walk shows five shades, none dominant, and white only off the scale" =
  let frames = List.map [ 30.; 45.; 60.; 75.; 90.; 105.; 120. ] ~f:(fun seconds -> buckets_in_view ~seconds) in
  let percent part whole = 100 * part / whole in
  let largest cells = List.fold cells ~init:0 ~f:(fun best bucket ->
      Int.max best (List.count cells ~f:(Int.equal bucket))) in
  let white cells = List.count cells ~f:(Int.equal (Heatmap.buckets - 1)) in
  List.iter frames ~f:(fun cells ->
    printf "shades %d; largest shade %d%% of %d cells; white %d%%\n" (distinguishable cells)
      (percent (largest cells) (List.length cells)) (List.length cells) (percent (white cells) (List.length cells)));
  ensure (List.for_all frames ~f:(fun cells -> distinguishable cells >= 5)) "fewer than five distinguishable shades";
  ensure (List.for_all frames ~f:(fun cells -> percent (largest cells) (List.length cells) <= 60))
    "one shade covers most of the map";
  ensure (List.for_all frames ~f:(fun cells -> percent (white cells) (List.length cells) <= 2)) "white is not rare";
  [%expect {|
    shades 8; largest shade 37% of 2000 cells; white 0%
    shades 9; largest shade 42% of 2000 cells; white 0%
    shades 7; largest shade 41% of 2000 cells; white 0%
    shades 7; largest shade 41% of 2000 cells; white 0%
    shades 7; largest shade 41% of 2000 cells; white 0%
    shades 7; largest shade 41% of 2000 cells; white 0%
    shades 7; largest shade 37% of 2000 cells; white 0%
    |}]

let%expect_test "no level stays a wall for long: walls build and decay within about 15 s of mock time" =
  let books = still_books ~seed:42 ~dt:0.25 ~count:480 in
  let mean ~price ~ask_side =
    let level = if ask_side then price - 1004 else 1003 - price in
    Market_walk.mean level in
  (* The longest run of snapshots in which one price rests at twice its ordinary size. *)
  let longest = ref 0 and runs = Int.Table.create () in
  List.iter books ~f:(fun (bids, asks) ->
    let big ~ask_side levels = List.filter_map levels ~f:(fun (level : level) ->
        Option.some_if Float.(of_int level.quantity_units >= 2. *. mean ~price:level.price_ticks ~ask_side)
          level.price_ticks) in
    let now = big ~ask_side:false bids @ big ~ask_side:true asks in
    List.iter now ~f:(fun price -> Hashtbl.update runs price ~f:(fun n -> Option.value n ~default:0 + 1));
    Hashtbl.filter_keys_inplace runs ~f:(List.mem now ~equal:Int.equal);
    Hashtbl.iter runs ~f:(fun n -> longest := Int.max !longest n));
  printf "longest stretch at twice the ordinary size: %.1f s\n" (Float.of_int !longest *. 0.25);
  ensure (!longest <= 64) "a level stays a wall for more than 16 s";
  [%expect {| longest stretch at twice the ordinary size: 11.2 s |}]

let%expect_test "every wall builds for at least 2 s, fades for at least 3 s, and is gone within 15 s" =
  let random = Stdlib.Random.State.make [| 42 |] in
  let walls = List.init 500 ~f:(fun _ -> Market_walk.new_wall random ~bid:1003 ~ask:1004 ~age:0.) in
  let each f = List.map walls ~f in
  let lowest f = List.reduce_exn (each f) ~f:Float.min and highest f = List.reduce_exn (each f) ~f:Float.max in
  printf "build >= %.1f s; fade >= %.1f s; longest life %.1f s\n"
    (lowest (fun wall -> wall.Market_walk.build)) (lowest (fun wall -> wall.fade))
    (highest (fun wall -> wall.build +. wall.hold +. wall.fade));
  [%expect {| build >= 2.5 s; fade >= 4.0 s; longest life 14.2 s |}]

let%expect_test "the heatmap legend states the saturation zone" =
  let heatmap = Market_heat_tests.observe_all [ Market_heat_tests.walled ] in
  let state = Market_heat_tests.state_with Market_heat_tests.walled in
  let lines = rows (Heatmap.view ~theme ~focus:Heatmap ~heatmap ~state ~width:120 ~height:20) ~width:120 ~height:20 in
  let legend = row_with lines "qty 0" in
  printf "%s\n" (String.strip legend |> String.chop_prefix_if_exists ~prefix:"│"
                 |> String.chop_suffix_if_exists ~suffix:"│" |> String.strip);
  [%expect {| qty 0 ░░░▒▒▓██ 1023 u = max(p95, 3×median), γ1.2; white above 1.5×  ━ ask  ═ bid  ▲ admitted  ✗ blocked |}]

(* --- 14. A highlight is on or off; it does not fade ------------------------------------------------- *)

(* The real shell in truecolour, with colour escapes in the screen text and the per-node hook. *)
let colored_app ~initial dimensions =
  let counts = String.Table.create () in
  let on_compute name = Hashtbl.update counts name ~f:(fun n -> Option.value n ~default:0 + 1) in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions ~capability:Ansi
      ~to_view_with_handler:fst ~handle_incoming:(fun (_, inject) state -> inject state)
      (fun ~dimensions (local_ graph) ->
        let state, inject = Bonsai.state initial graph in
        let ~view, ~handler =
          App.component ~on_compute ~initial_preset:Monitor ~theme:(Theme.create Truecolor) ~state
            ~clock:(Bonsai.return Shell_tests.clock) ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
        let%arr view and handler and inject in
        ((~view, ~handler), inject)) in
  handle, counts

(* One stream update, then [seconds] of idle clock in 10 ms steps: how many different screens
   the terminal is sent, and how often the Market node ran. *)
let screens_after_an_update ~seconds =
  let backend = Shell_tests.fixture Enabled in
  let handle, counts = colored_app ~initial:(Mock_backend.state backend) { width = 200; height = 60 } in
  Handle.recompute_view_until_stable handle;
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.5);
  Handle.recompute_view_until_stable handle;
  Bonsai_term_test.do_actions handle [ Mock_backend.state (Mock_backend.advance backend) ];
  Handle.recompute_view_until_stable handle;
  Hashtbl.clear counts;
  let seen = String.Hash_set.create () in
  Hash_set.add seen (Shell_tests.screen handle);
  for _ = 1 to Float.to_int (seconds /. 0.01) do
    Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.01);
    Handle.recompute_view_until_stable handle;
    Hash_set.add seen (Shell_tests.screen handle)
  done;
  Hash_set.length seen, Option.value (Hashtbl.find counts "Market") ~default:0

let%expect_test "a highlight is on or off, so one update costs a few screens and not a dozen" =
  let screens, market = screens_after_an_update ~seconds:1.3 in
  printf "screens %d, Market recomputes %d\n" screens market;
  ensure (screens <= 4 && market <= 3) "a highlight repaints more than when it ends";
  [%expect {| screens 4, Market recomputes 2 |}]

(* Notty sends a full colour sequence for every text node, even beside an identical one, and
   resends a whole line when any of it changes, so the bytes of a row follow its node count.
   These are the nodes a view is made of, per line, as the terminal layer will see them. *)
let nodes_per_line view =
  let { Dimensions.width; height } = View.dimensions view in
  Notty.Operation.of_image (0, 0) (width, height) (View.Private.notty_image view)
  |> List.map ~f:(fun operations ->
    let rec count = function
      | Notty.Operation.End -> 0
      | Skip (_, rest) -> count rest
      | Text (_, _, rest) -> 1 + count rest in
    count operations)

let market_with_deltas () =
  let backend = Shell_tests.fixture Enabled in
  let first = Mock_backend.state backend in
  let second = Mock_backend.state (Mock_backend.advance backend) in
  let at seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds) in
  let motion = Market_motion.observe Market_motion.empty ~now:(at 1.) ~snapshot:first.market ~updates:first.updates in
  let motion = Market_motion.observe motion ~now:(at 1.25) ~snapshot:second.market ~updates:second.updates in
  second, motion, at 1.3

let%expect_test "a ladder row is a handful of text nodes, deltas or not" =
  let state, motion, now = market_with_deltas () in
  let view ~motion = Market_panel.view ~cumulative:false ~theme:truecolor ~focus:Market ~state ~motion ~now
      ~width:100 ~height:30 in
  let ladder nodes = List.sub nodes ~pos:3 ~len:10 in
  let quiet = ladder (nodes_per_line (view ~motion:Market_motion.empty))
  and fading = ladder (nodes_per_line (view ~motion)) in
  let most nodes = List.fold nodes ~init:0 ~f:Int.max in
  printf "most nodes in a ladder row: quiet %d, with deltas fading %d\n" (most quiet) (most fading);
  ensure (most quiet <= 10 && most fading <= 14) "a ladder row is made of too many text nodes";
  [%expect {| most nodes in a ladder row: quiet 5, with deltas fading 6 |}]

(* Every cell of a view with the attributes it is drawn in, as the terminal layer will draw it:
   what two views must agree on to look the same, however many text nodes they are made of. *)
let cells_of view =
  let { Dimensions.width; height } = View.dimensions view in
  Notty.Operation.of_image (0, 0) (width, height) (View.Private.notty_image view)
  |> List.map ~f:(fun operations ->
    let rec cells = function
      | Notty.Operation.End -> []
      | Skip (n, rest) -> List.init n ~f:(fun _ -> None) @ cells rest
      | Text (attrs, text, rest) ->
        let glyphs = Stdlib.String.fold_left (fun acc c ->
            if Char.to_int c land 0xC0 = 0x80 then (match acc with last :: more -> (last ^ String.of_char c) :: more | [] -> [])
            else String.of_char c :: acc) [] (Notty.Text.to_string text) |> List.rev in
        List.map glyphs ~f:(fun glyph -> Some (attrs, glyph)) @ cells rest in
    cells operations)

let%expect_test "a panel frame looks exactly as the border box draws it, in fewer text nodes" =
  let reference ~theme ~muted ~focused ~title body ~width ~height =
    let attrs = Theme.attrs theme (if muted then Theme.Muted else if focused then Focus else Border) in
    Bonsai_term_border_box.view ~line_type:Round_corners ~attrs ~title_attrs:(Panel.title_attrs theme ~focused ~muted)
      ~title ~left_padding:1 ~right_padding:1
      (Panel.fit body ~width:(Int.max 0 (width - 4)) ~height:(Int.max 0 (height - 2)))
    |> Panel.fit ~width ~height in
  let differing = ref 0 and checked = ref 0 and nodes = ref 0 in
  List.iter [ Theme.create Truecolor; Theme.create No_color ] ~f:(fun theme ->
    List.iter [ true, false; false, false; false, true ] ~f:(fun (focused, muted) ->
      List.iter [ 4, 3; 5, 4; 12, 5; 30, 6; 60, 10 ] ~f:(fun (width, height) ->
        List.iter [ "Market · AAPL"; "Heatmap · AAPL · MOCK · scale 207 u"; "" ] ~f:(fun title ->
          let body = View.vcat (List.init 20 ~f:(fun i ->
              View.hcat [ View.text ~attrs:(Theme.attrs theme Bid) (sprintf "row %d" i); View.pad ~l:3 (View.text "x") ])) in
          let focus = if focused then Keymap.Market else Keymap.Rules in
          let actual = Panel.frame ~muted ~theme ~focus ~panel:Market ~title ~width ~height body in
          incr checked;
          if not ([%equal: (Notty.A.t * string) option list list]
                    (cells_of actual) (cells_of (reference ~theme ~muted ~focused ~title body ~width ~height)))
          then incr differing;
          if width = 60 then (
            let solid = View.vcat (List.init 20 ~f:(fun _ -> View.text (String.make 56 'x'))) in
            let framed = Panel.frame ~muted ~theme ~focus ~panel:Market ~title ~width ~height solid in
            nodes := Int.max !nodes (List.nth_exn (nodes_per_line framed) 5))))));
  printf "frames compared %d, differing %d; most nodes in an interior row of a 60-wide frame round a full-width line: %d\n"
    !checked !differing !nodes;
  ensure (!differing = 0) "the frame does not look like the border box";
  ensure (!nodes <= 3) "a frame spends more than one text node on each of its two edges";
  [%expect {| frames compared 90, differing 0; most nodes in an interior row of a 60-wide frame round a full-width line: 3 |}]

let%expect_test "a price chart row is a few text nodes, the dashed threshold row too" =
  let view = Market_chart.view ~theme:truecolor ~samples:(Age_deque.of_list steady) ~now:(Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec 60.))
      ~threshold:(Some 1006) ~width:100 ~height:12 in
  let nodes = nodes_per_line view in
  printf "text nodes in each row of a chart with a dashed threshold: %s\n"
    (String.concat ~sep:" " (List.map nodes ~f:Int.to_string));
  ensure (List.for_all (List.drop nodes 1) ~f:(fun count -> count <= 8)) "a chart row is made of too many text nodes";
  [%expect {| text nodes in each row of a chart with a dashed threshold: 5 3 3 3 3 3 3 3 3 3 3 1 |}]

(* How many different intensities a highlight shows between its start and its end, sampled every
   millisecond: each one is a colour a cell is drawn in, and a screen the terminal is sent. *)
let levels_of fade ~seconds =
  List.init (Float.to_int (seconds *. 1000.) + 50) ~f:(fun ms -> fade (Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms (Float.of_int ms))))
  |> List.filter ~f:(fun level -> Float.(level > 0.)) |> List.dedup_and_sort ~compare:Float.compare |> List.length

let%expect_test "the delta, tape and decision highlights each have one level, on until they end" =
  let delta = { Market_motion.change = 3; at = Time_ns.epoch } in
  let print = { Tape_panel.time = Time_ns.epoch; side = Buy; price_ticks = 1; quantity_units = 1 } in
  let counts =
    [ "delta", levels_of (fun now -> Market_motion.delta_intensity ~now delta) ~seconds:1.
    ; "tape", levels_of (fun now -> Tape_panel.freshness ~now print) ~seconds:1.
    ; "decision", levels_of (fun now -> Decision_row.fresh_intensity ~now ~at:Time_ns.epoch) ~seconds:0.8 ] in
  List.iter counts ~f:(fun (name, count) -> printf "%s fade: %d levels\n" name count);
  ensure (List.for_all counts ~f:(fun (_, count) -> count = 1)) "a highlight fades instead of ending";
  [%expect {|
    delta fade: 1 levels
    tape fade: 1 levels
    decision fade: 1 levels
    |}]

(* --- 15. The stream is polled once a frame, however fast it is ------------------------------- *)

module Counting_backend = struct
  type t = Mock_backend.t
  let polls = ref 0
  let state = Mock_backend.state
  let handle_command = Mock_backend.handle_command
  let polling = Mock_backend.polling
  let next t = incr polls; Mock_backend.next t
end

(* The live app on a stream of [rate_hz], [frames] 60 Hz frames long: how often the backend was
   polled and in how many frames the view differed from the one before, each a paint. *)
let polls_and_paints ~rate_hz ~frames =
  let _scheduler = Async.Scheduler.t () in
  Counting_backend.polls := 0;
  let paints = ref 0 in
  let backend = Or_error.ok_exn (Mock_backend.create_with_max_rate ~max_rate_hz:1000. ~scenario:Enabled ~seed:42 ~rate_hz) in
  let handle = Bonsai_term_test.create_handle ~initial_dimensions:{ width = 120; height = 36 }
      (fun ~dimensions (local_ graph) ->
         let ~view, ~handler =
           App.live ~initial_preset:Monitor ~on_preset:(Bonsai.return (fun (_ : Ui_types.preset) -> Effect.return (Ok ())))
             (module Counting_backend) ~theme ~backend ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
         Bonsai.Edge.on_change ~trigger:`After_display ~equal:phys_equal view
           ~callback:(Bonsai.return (fun (_ : View.t) -> Effect.of_sync_fun incr paints)) graph;
         ~view, ~handler) in
  for _ = 1 to frames do
    Handle.advance_clock_by handle (Time_ns.Span.of_sec (1. /. 60.));
    Handle.recompute_view_until_stable handle;
    Async.Scheduler.External.run_cycles_until_determined (Async.Scheduler.yield_until_no_jobs_remain ())
  done;
  !Counting_backend.polls, !paints

let%expect_test "a fast stream is polled and painted once a frame, not once every few frames" =
  let polls, paints = polls_and_paints ~rate_hz:1000. ~frames:300 in
  printf "5 s of 60 Hz frames at 1000 Hz: %d polls, %d paints\n" polls paints;
  ensure (polls >= 270 && paints >= 270) "the stream is polled less than once a frame";
  [%expect {| 5 s of 60 Hz frames at 1000 Hz: 299 polls, 300 paints |}]

let%expect_test "a slow stream is still polled at its own rate" =
  let polls, _ = polls_and_paints ~rate_hz:4. ~frames:300 in
  printf "5 s of 60 Hz frames at 4 Hz: %d polls\n" polls;
  ensure (polls >= 18 && polls <= 24) "a 4 Hz stream is not polled about 4 times a second";
  [%expect {| 5 s of 60 Hz frames at 4 Hz: 19 polls |}]

let%expect_test "the bench times each paint that shows something new, against the newest state it shows" =
  let ms value = Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms value) in
  let log = Bench.Log.create () in
  List.iter [ 0.; 10.; 30. ] ~f:(fun time -> Bench.Log.arrived log (ms time));
  (* Painted from a frame that began after the arrival at 10 ms but before the one at 30 ms. *)
  Bench.Log.painted log ~start:(ms 12.) ~finish:(ms 15.);
  Bench.Log.painted log ~start:(ms 35.) ~finish:(ms 40.);
  (* A repaint for a header clock or a highlight clearing replies to no state, and is not timed. *)
  Bench.Log.painted log ~start:(ms 36.) ~finish:(ms 52.);
  let { Bench.p50; p99; max } = Bench.Log.staleness log in
  printf "delays 5 ms (10 to 15), 10 ms (30 to 40), none for the repaint: p50 %.1f p99 %.1f max %.1f\n" p50 p99 max;
  (* Every key was pressed, so each is timed, against the paint that shows it. *)
  let keys = Bench.Log.create ~every:true () in
  List.iter [ 0.; 4.; 30. ] ~f:(fun time -> Bench.Log.arrived keys (ms time));
  Bench.Log.painted keys ~start:(ms 5.) ~finish:(ms 9.);
  Bench.Log.painted keys ~start:(ms 33.) ~finish:(ms 37.);
  let { Bench.p50; p99; max } = Bench.Log.staleness keys in
  printf "keys at 0, 4 and 30 ms, painted by 9 and 37 ms: %d timed; p50 %.1f p99 %.1f max %.1f\n"
    (Bench.Log.count keys) p50 p99 max;
  [%expect {|
    delays 5 ms (10 to 15), 10 ms (30 to 40), none for the repaint: p50 5.0 p99 10.0 max 10.0
    keys at 0, 4 and 30 ms, painted by 9 and 37 ms: 3 timed; p50 7.0 p99 9.0 max 9.0
    |}]

(* --- 13. The Inspector's empty state wraps instead of losing its mode label ------------------- *)

(* What a panel shows between its frame's edges, one string per row, blank rows left out. *)
let body_rows lines =
  List.filter_map lines ~f:(fun line ->
    Option.bind (String.chop_prefix line ~prefix:"│ ") ~f:(String.chop_suffix ~suffix:" │"))
  |> List.map ~f:String.strip
  |> List.filter ~f:(Fn.non String.is_empty)

let%expect_test "the Inspector placeholder wraps at word boundaries and keeps its mode label at every width" =
  List.iter [ 30; 44; 80 ] ~f:(fun width ->
    List.iter [ Mock; Simulation; Hardware ] ~f:(fun mode ->
      let view = Inspector.view ~theme ~focus:Keymap.Inspector ~mode ~decision:None ~width ~height:12 in
      let lines = body_rows (rows view ~width ~height:12) in
      if equal_mode mode Mock then (
        printf "%d columns:\n" width;
        List.iter lines ~f:(printf "  %s\n"));
      ensure (String.equal (String.concat ~sep:" " lines)
                ("Select a decision and press Enter to inspect · " ^ Status_bar.mode_name mode))
        (sprintf "the placeholder lost words or its mode label at %d columns" width)));
  [%expect {|
    30 columns:
      Select a decision and
      press Enter to inspect
      · MOCK
    44 columns:
      Select a decision and press Enter to
      inspect · MOCK
    80 columns:
      Select a decision and press Enter to inspect · MOCK
    |}]

(* --- 14. Rules prose is cut with an ellipsis, never in the middle of a word ------------------- *)

let rules_rows state ~width ~height =
  let selected = Option.map (List.hd state.rules) ~f:(fun rule -> rule.rule_id) in
  body_rows (rows (Rules_panel.view ~theme ~focus:Keymap.Rules ~state ~selected ~width ~height) ~width ~height)

(* The selected rule and the rule under it both have names longer than a narrow panel. *)
let long_named_state ~blocked ~reason =
  let state = busy_state () in
  let first = { (List.hd_exn state.rules) with name = "buy_below_limit_with_a_long_name"
                                             ; blocked; last_block_reason = reason } in
  let second = { first with rule_id = "slot-1"; slot = 1; name = "sell_above_limit_with_a_long_name"
                          ; enabled = false } in
  { state with rules = [ first; second ] }

let long_reason = "price 1000 t outside the admitted band [1001, 1005] set by the active configuration"

(* A row of the narrow panel is cut if it is a proper prefix of a line the wide panel shows
   whole, and it did not end in an ellipsis. *)
let prose_needles = [ "ask_px"; "last block:"; "blocked by reason"; "· config v"; "· MOCK" ]

let%expect_test "no Rules line is cut without an ellipsis at any width from 30 to 90" =
  List.iter [ "reason", Some long_reason, 3; "unreported", None, 3; "none", None, 0 ] ~f:(fun (name, reason, blocked) ->
    let state = long_named_state ~blocked ~reason in
    let whole = List.map prose_needles ~f:(row_with (rules_rows state ~width:200 ~height:60)) in
    let is_label row = String.is_prefix row ~prefix:"▸ #" || String.is_prefix row ~prefix:"#" in
    let problems = List.concat_map (List.range 30 91) ~f:(fun width ->
        let lines = rules_rows state ~width ~height:60 in
        let cut line = List.exists whole ~f:(fun full ->
            String.length line < String.length full && String.is_prefix full ~prefix:line) in
        let label_lost line =
          not (List.exists [ "● ON"; "○ OFF" ] ~f:(fun status -> String.is_suffix line ~suffix:status))
          || not (String.is_substring line ~substring:"_name" || String.is_substring line ~substring:"…") in
        List.filter_map lines ~f:(fun line ->
          Option.some_if (cut line || (is_label line && label_lost line)) (sprintf "%d: %s" width line))) in
    printf "%s: %s\n" name (String.concat ~sep:" | " problems);
    ensure (List.is_empty problems) (sprintf "Rules lines are cut without an ellipsis (%s)" name));
  [%expect {|
    reason:
    unreported:
    none:
    |}]

let%expect_test "at 30 columns the Rules panel keeps its numbers whole and cuts only prose, with an ellipsis" =
  print_endline (String.concat ~sep:"\n"
                   (rules_rows (long_named_state ~blocked:3 ~reason:(Some long_reason)) ~width:30 ~height:60));
  [%expect {|
    ▸ #0 buy_below_limit… ● ON
    ask_px ≤ maximum_price → …
    slot-0 · config v12
    maximum_price 1005 t
    quantity         1 u
    matched 39  admitted 36
    blocked 3
    recent ✓·✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓·
    last block: price 1000 t …
    blocked by reason · this …
    3× price 1000 t outsid…
    cfg ✓ACK v12 · MOCK
    #1 sell_above_lim… ○ OFF
    |}]
