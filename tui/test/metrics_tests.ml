open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let ensure condition message = if not condition then failwith message
let at seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds)
let contains text substring = String.is_substring text ~substring

let base =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4.
  |> Or_error.ok_exn |> Mock_backend.state

(* Cumulative backend counters, as the application state carries them. *)
let counters ?(connected = true) ~decisions ~admitted ~blocked ~loss () =
  let rule = List.hd_exn base.rules in
  { base with connected; trace_loss = loss
            ; decisions = { base.decisions with next_sequence = decisions }
            ; rules = [ { rule with admitted; blocked } ] }

let observed steps =
  List.fold steps ~init:Metrics_state.empty ~f:(fun metrics (seconds, state) ->
    Metrics_state.observe metrics ~now:(at seconds) state)

let show series =
  List.map series ~f:(fun (time, value) ->
    sprintf "%.0fs=%s" (Time_ns.diff time Time_ns.epoch |> Time_ns.Span.to_sec)
      (Option.value_map value ~default:"-" ~f:(sprintf "%.2f")))
  |> String.concat ~sep:" "

let render ~width ~height view =
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width; height }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return (view ())) in
  Bonsai_test.Handle.show_into_string handle

(* Braille: dots 1,2,3,7 fill the left column top to bottom, 4,5,6,8 the right. *)
let%expect_test "braille encodes rows, flat lines, steps and breaks" =
  let plot points = Sparkline.braille ~now:(at 60.) ~width:1 points in
  printf "diagonal |%s|\n" (plot [ at 0., Some 0; at 60., Some 3 ]);
  printf "top |%s|\n" (plot [ at 0., Some 0; at 60., Some 0 ]);
  printf "bottom |%s|\n" (plot [ at 0., Some 3; at 60., Some 3 ]);
  let wide points = Sparkline.braille ~now:(at 60.) ~width:2 points in
  printf "break |%s|\n" (wide [ at 0., Some 0; at 30., None; at 60., Some 3 ]);
  printf "stale |%s|\n" (Sparkline.braille ~now:(at 130.) ~width:2 [ at 0., Some 0 ]);
  printf "rows %d %d %d flat %d\n"
    (Sparkline.row ~low:0. ~high:10. 10.) (Sparkline.row ~low:0. ~high:10. 0.)
    (Sparkline.row ~low:0. ~high:10. 5.) (Sparkline.row ~low:3. ~high:3. 3.);
  [%expect {|
    diagonal |⢁|
    top |⠉|
    bottom |⣀|
    break |⠁⢀|
    stale |  |
    rows 0 3 2 flat 3
    |}]

let%expect_test "summary reports min, max and the newest value, or nothing" =
  let summary series =
    match Metrics_state.summarize series with
    | None -> "none"
    | Some s -> sprintf "min %.1f max %.1f last %s" s.min s.max
                  (Option.value_map s.last ~default:"-" ~f:(sprintf "%.1f")) in
  printf "%s\n" (summary [ at 1., Some 2.; at 2., None; at 3., Some 5.; at 4., Some 1. ]);
  printf "%s\n" (summary [ at 1., Some 2.; at 2., Some 5.; at 3., None ]);
  printf "%s\n" (summary [ at 1., None ]);
  printf "%s\n" (summary []);
  [%expect {|
    min 1.0 max 5.0 last 1.0
    min 2.0 max 5.0 last -
    none
    none
    |}]

let%expect_test "rates and ratios come from counter deltas over fixture times" =
  let metrics = observed
      [ 0., counters ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 ()
      ; 1., counters ~decisions:4 ~admitted:1 ~blocked:3 ~loss:0 ()
      ; 2., counters ~decisions:4 ~admitted:1 ~blocked:3 ~loss:2 ()
      ; 4., counters ~decisions:12 ~admitted:5 ~blocked:3 ~loss:2 () ] in
  printf "decisions/s %s\n" (show (Metrics_state.decisions_per_second metrics));
  printf "admit ratio %s\n" (show (Metrics_state.admit_ratio metrics));
  printf "trace loss/s %s\n" (show (Metrics_state.trace_loss_per_second metrics));
  [%expect {|
    decisions/s 1s=4.00 2s=0.00 4s=4.00
    admit ratio 1s=0.25 2s=- 4s=1.00
    trace loss/s 1s=0.00 2s=2.00 4s=0.00
    |}]

let%expect_test "a disconnect is unknown, never zero, and the window is 60 seconds" =
  let metrics = observed
      [ 0., counters ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 ()
      ; 1., counters ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 ()
      ; 2., counters ~connected:false ~decisions:5 ~admitted:0 ~blocked:0 ~loss:0 ()
      ; 3., counters ~decisions:9 ~admitted:0 ~blocked:0 ~loss:0 () ] in
  printf "decisions/s %s\n" (show (Metrics_state.decisions_per_second metrics));
  printf "trace loss/s %s\n" (show (Metrics_state.trace_loss_per_second metrics));
  let long = observed (List.init 100 ~f:(fun second ->
      Float.of_int second, counters ~decisions:(second * 2) ~admitted:0 ~blocked:0 ~loss:0 ())) in
  printf "samples kept %d\n" (List.length long.samples);
  let restarted = Metrics_state.observe long ~now:(at 100.)
      (counters ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 ()) in
  printf "after counter reset %d\n" (List.length restarted.samples);
  let other_run = Metrics_state.observe long ~now:(at 100.)
      { (counters ~decisions:300 ~admitted:0 ~blocked:0 ~loss:0 ()) with run_id = "other" } in
  printf "after new run %d\n" (List.length other_run.samples);
  [%expect {|
    decisions/s 1s=5.00 2s=- 3s=-
    trace loss/s 1s=0.00 2s=- 3s=-
    samples kept 61
    after counter reset 1
    after new run 1
    |}]

let%expect_test "nearest-rank percentiles" =
  let sorted n = Array.init n ~f:(fun i -> Float.of_int (i + 1)) in
  let show p values =
    printf "p%g %s\n" p (Option.value_map (Metrics_state.percentile values ~p)
                           ~default:"none" ~f:(sprintf "%g")) in
  List.iter [ 0.; 50.; 99.; 100. ] ~f:(fun p -> show p (sorted 100));
  List.iter [ 50.; 75.; 99. ] ~f:(fun p -> show p [| 10.; 20.; 30.; 40. |]);
  show 99. [| 7. |];
  show 50. [||];
  [%expect {|
    p0 1
    p50 50
    p99 99
    p100 100
    p50 20
    p75 30
    p99 40
    p99 7
    p50 none
    |}]

let%expect_test "frame meter keeps a bounded window and counts coalesced events" =
  let frame meter (seconds, ms, updates) =
    Frame_meter.record meter ~frame_ms:ms ~at:(at seconds) ~updates in
  let meter = List.fold (List.init 100 ~f:(fun i -> Float.of_int i /. 100., Float.of_int (i + 1), i * 10))
      ~init:(Frame_meter.empty ~window:100) ~f:frame in
  let stats = Frame_meter.stats meter ~buffers:[ "decisions", 7 ] in
  printf "last %.1f avg %.2f p50 %.1f p99 %.1f max %.1f\n"
    stats.last_ms stats.avg_ms stats.p50_ms stats.p99_ms stats.max_ms;
  printf "renders %d coalesced %d events/s %.0f buffers %s\n" stats.render_count
    stats.coalesced_frames stats.events_per_second
    (List.map stats.buffer_sizes ~f:(fun (name, size) -> sprintf "%s=%d" name size)
     |> String.concat ~sep:",");
  let small = List.fold [ 0., 1., 0; 1., 2., 0; 2., 3., 5; 3., 4., 5 ]
      ~init:(Frame_meter.empty ~window:3) ~f:frame in
  let stats = Frame_meter.stats small ~buffers:[] in
  printf "window 3: last %.0f max %.0f renders %d coalesced %d\n" stats.last_ms stats.max_ms
    stats.render_count stats.coalesced_frames;
  [%expect {|
    last 100.0 avg 50.50 p50 50.0 p99 99.0 max 100.0
    renders 100 coalesced 891 events/s 1000 buffers decisions=7
    window 3: last 4 max 4 renders 4 coalesced 4
    |}]

let%expect_test "latency histogram is deterministic, bounded and ordered" =
  let first = Latency_panel.samples ~seed:42 ~count:1000 in
  ensure (List.equal Int.equal first (Latency_panel.samples ~seed:42 ~count:1000)) "Same seed diverged";
  ensure (not (List.equal Int.equal first (Latency_panel.samples ~seed:43 ~count:1000))) "Seeds did not vary";
  ensure (List.for_all first ~f:(fun ns -> ns > 0)) "Non-positive latency";
  let histogram = Latency_panel.histogram ~bins:20 first in
  printf "bins %d total %d\n" (Array.length histogram.counts)
    (Array.sum (module Int) histogram.counts ~f:Fn.id);
  let sorted = Array.of_list_map first ~f:Float.of_int in
  Array.sort sorted ~compare:Float.compare;
  let p50 = Metrics_state.percentile sorted ~p:50. |> Option.value_exn in
  let p99 = Metrics_state.percentile sorted ~p:99. |> Option.value_exn in
  ensure Float.(p50 <= p99 && p99 <= sorted.(999)) "Percentiles out of order";
  printf "p50 %.0f p99 %.0f max %.0f ns\n" p50 p99 sorted.(999);
  [%expect {|
    bins 20 total 1000
    p50 233 p99 366 max 440 ns
    |}]

let%expect_test "latency panel is titled synthetic and never shown for real modes" =
  let view state () =
    Latency_panel.view ~theme ~focus:Latency ~state ~width:60 ~height:12 in
  let text = render ~width:60 ~height:12 (view base) in
  ensure (contains text "Latency · MOCK synthetic") "Synthetic title lost";
  ensure (contains text "ns") "Unit missing";
  print_string text;
  let hardware = render ~width:60 ~height:12 (view { base with mode = Hardware }) in
  ensure (not (contains hardware "synthetic")) "Synthetic data shown as hardware";
  ensure (contains hardware "no timestamps") "Missing-source notice lost";
  [%expect {|
    ┌────────────────────────────────────────────────────────────┐
    │╭ Latency · MOCK synthetic ────────────────────────────────╮│
    ││ snapshot→candidate latency, ns · n=2000 · p50 233 ns     ││
    ││      ▃ █ ╎                           ╎                   ││
    ││     ▂█▄█▆▃ ▁                         ╎                   ││
    ││     ██████ █▁                        ╎                   ││
    ││   ▃▇██████▇██▃▇▆▁                    ╎                   ││
    ││   ███████████████▂▂▂ ▂               ╎                   ││
    ││ ▃▇██████████████████▆█▇▄▇▅▃▃▅▂▁▃▂▃▂▂▂▂▁▁▁▁▁▁▁▁▁  ▁▁  ▁▁▁ ││
    ││ ├────────┴───────────────────────────┴─────────────────┤ ││
    ││ 188 ns   p50 233 ns                  p99 366 ns   452 ns ││
    ││ MOCK synthetic, seed 42: not a hardware measurement      ││
    │╰──────────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────────┘
    |}]

let%expect_test "metrics panel plots three series with units and shows trace loss as unknown" =
  let metrics = observed
      (List.init 30 ~f:(fun second ->
         Float.of_int second,
         counters ~decisions:(second * 3) ~admitted:(second / 2) ~blocked:(second / 2) ~loss:0 ()))
  in
  let view metrics () =
    Metrics_panel.view ~theme ~focus:Metrics ~metrics ~now:(at 29.) ~width:64 ~height:12 in
  let text = render ~width:64 ~height:12 (view metrics) in
  ensure (contains text "Metrics · MOCK") "Mode missing from title";
  ensure (contains text "decisions/s") "Decision rate missing";
  print_string text;
  let lost = observed [ 0., counters ~connected:false ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 ()
                      ; 1., counters ~connected:false ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 () ] in
  let text = render ~width:64 ~height:12 (view lost) in
  ensure (contains text "unknown") "Disconnected series not unknown";
  [%expect {|
    ┌────────────────────────────────────────────────────────────────┐
    │╭ Metrics · MOCK ──────────────────────────────────────────────╮│
    ││ decisions/s 3.0/s  min 3.0 · max 3.0                         ││
    ││ 4┤· · · · ·  no data  · · · · · ⠠⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤⡤ ││
    ││ 0┤ · · · · · · · · · · · · · · ·⠨⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪ ││
    ││ admit ratio no outcomes  min 0.50 · max 0.50                 ││
    ││ 1┤· · · · · · no data · · · · · ·⢀·⢀·⡀·⡀·⡀·⡀·⡀·⡀⢀ ⢀ ⢀ ⢀ ⢀ ⢀  ││
    ││ 0┤ · · · · · · · · · · · · · · · ⠨ ⠨ ⡂ ⡂ ⡂ ⡂ ⡂ ⡂⠨·⠨·⠨·⠨·⠨·⠨· ││
    ││ trace loss/s 0.0/s  min 0.0 · max 0.0                        ││
    ││ 1┤· · · · ·  no data  · · · · ·                              ││
    ││ 0┤ · · · · · · · · · · · · · · ·⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀ ││
    ││  └−60s ───────────────────── −30s ────────────────────── now ││
    │╰──────────────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────────────┘
    |}]

let%expect_test "debug overlay labels what each number is" =
  let stats : Ui_types.frame_stats =
    { last_ms = 3.2; avg_ms = 2.8; p50_ms = 2.6; p99_ms = 7.9; max_ms = 9.4
    ; events_per_second = 987.4; render_count = 1203; coalesced_frames = 18797
    ; buffer_sizes = [ "decisions", 10000; "config events", 0 ] } in
  print_string (render ~width:40 ~height:11 (fun () -> Debug_overlay.view ~theme ~stats));
  let slow = { stats with p99_ms = 21.5 } in
  ensure (contains (render ~width:40 ~height:11 (fun () -> Debug_overlay.view ~theme ~stats:slow)) "over budget")
    "Missed budget not stated";
  [%expect {|
    ┌────────────────────────────────────────┐
    │╭ Frame meter ─────────────────────────╮│
    ││ frame work: flush+compute+paint      ││
    ││ last 3.2 · avg 2.8 ms                ││
    ││ p50 2.6 · p99 7.9 · max 9.4 ms       ││
    ││ █████░░░░░ p99 within 16 ms budget   ││
    ││ stream events 987/s                  ││
    ││ paints 1203 · coalesced events 18797 ││
    ││ decisions 10000 · config events 0    ││
    │╰──────────────────────────────────────╯│
    │                                        │
    └────────────────────────────────────────┘
    |}]

let%expect_test "rate flag accepts 1000 only for the bench and keeps 60 otherwise" =
  let accepts ?max rate_hz =
    let created = match max with
      | None -> Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz
      | Some max_rate_hz ->
        Mock_backend.create_with_max_rate ~max_rate_hz ~scenario:Enabled ~seed:42 ~rate_hz in
    Or_error.is_ok created in
  let bench max rate_hz = accepts ~max rate_hz in
  printf "normal: 60 %b, 1000 %b\n" (accepts 60.) (accepts 1000.);
  printf "bench: 1000 %b, 1000.5 %b, 0.05 %b, nan %b\n" (bench Bench.max_rate_hz 1000.)
    (bench Bench.max_rate_hz 1000.5) (bench Bench.max_rate_hz 0.05) (bench Bench.max_rate_hz Float.nan);
  (match Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:1000. with
   | Error error -> print_endline (Error.to_string_hum error)
   | Ok _ -> ());
  [%expect {|
    normal: 60 true, 1000 false
    bench: 1000 true, 1000.5 false, 0.05 false, nan false
    --rate must be finite and in [0.1, 60] Hz
    |}]

let%expect_test "a stream faster than the frame rate is delivered as whole steps" =
  let steps rate_hz millis =
    fst (Mock_backend.steps_due ~rate_hz ~elapsed:(Time_ns.Span.of_ms millis) ~carried:0.) in
  printf "1000 Hz over 16.7 ms: %d; 4 Hz over 10 ms: %d; 60 Hz over 40 ms: %d; 1000 Hz after 5 s: %d\n"
    (steps 1000. 16.7) (steps 4. 10.) (steps 60. 40.) (steps 1000. 5000.);
  [%expect {| 1000 Hz over 16.7 ms: 16; 4 Hz over 10 ms: 1; 60 Hz over 40 ms: 2; 1000 Hz after 5 s: 1000 |}]

let%expect_test "bench report states the pass line and defines coalescing" =
  let stats : Ui_types.frame_stats =
    { last_ms = 2.; avg_ms = 2.5; p50_ms = 2.4; p99_ms = 9.1; max_ms = 12.3
    ; events_per_second = 1000.; render_count = 1190; coalesced_frames = 18700
    ; buffer_sizes = [] } in
  let report ?(key_count = 0) p99 =
    Bench.format_report ~dimensions:{ width = 120; height = 36 } ~rate_hz:1000.
      ~seconds:20. ~events:19890 ~staleness:{ p50 = 9.5; p99 = 17.2; max = 21.8 }
      ~keys:{ p50 = 1.6; p99 = 8.4; max = 12.1 } ~key_count
      ~stats:{ stats with p99_ms = p99 } in
  print_endline (report 9.1);
  print_endline (report ~key_count:340 9.1);
  ensure (contains (report 16.5) "FAIL") "Slow p99 passed";
  [%expect {|
    tickweave bench · MOCK · Monitor 120x36 · 20 s · stream 1000 Hz
    frame work, painted frames only (flush + compute + paint to tty): p50 2.40 ms · p99 9.10 ms · max 12.30 ms
    stream to paint, from a state reaching the app to the end of the paint that shows it: p50 9.5 ms · p99 17.2 ms · max 21.8 ms
    key to paint: no keys sent (give bench_pty.py a keys-per-second argument)
    p99 < 16 ms: PASS
    renders 1190 (59.5/s, cap 60/s) · stream events received 19890 · coalesced 18700
    coalesced = stream events that shared a painted frame with an earlier one (per painted frame: events since the previous painted frame, minus one)
    tickweave bench · MOCK · Monitor 120x36 · 20 s · stream 1000 Hz
    frame work, painted frames only (flush + compute + paint to tty): p50 2.40 ms · p99 9.10 ms · max 12.30 ms
    stream to paint, from a state reaching the app to the end of the paint that shows it: p50 9.5 ms · p99 17.2 ms · max 21.8 ms
    key to paint, from a key reaching the app to the end of the paint that shows it (340 keys): p50 1.6 ms · p99 8.4 ms · max 12.1 ms
    p99 < 16 ms: PASS
    renders 1190 (59.5/s, cap 60/s) · stream events received 19890 · coalesced 18700
    coalesced = stream events that shared a painted frame with an earlier one (per painted frame: events since the previous painted frame, minus one)
    |}]
