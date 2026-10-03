open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Tickweave_tui

let ensure = Shell_tests.ensure

(* What decides how long the screen is behind the stream and behind a key: when a frame is
   woken, when it is allowed to paint, and how long a highlight stays on. The wall-clock
   numbers come from [bench_pty.py]; these are the rules those numbers follow from. *)

(* --- The wake is the harness's to leave alone ------------------------------------------------ *)

let%expect_test "without a driver there is no wake: the harness's clock is the only clock" =
  printf "live %b\n" (Wake.live Wake.off);
  Wake.now Wake.off;
  Wake.at Wake.off (Time_ns.add (Time_ns.now ()) Time_ns.Span.second);
  printf "still live %b\n" (Wake.live Wake.off);
  [%expect {|
    live false
    still live false
    |}]

(* --- A paint is released at once when it can be, and never more often than the cap ------------- *)

let at ms = Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms ms)

let%expect_test "a view that arrives after a quiet interval is painted in the call that brought it" =
  let clock = ref (at 1000.) in
  let throttle = Paint_throttle.create ~now:(fun () -> !clock) () in
  let delays = List.map [ 0.; 40.; 300.; 301.; 5000. ] ~f:(fun gap ->
    clock := Time_ns.add !clock (Time_ns.Span.of_ms gap);
    let view = View.text "x" in
    let arrived = !clock in
    let shown = Paint_throttle.release throttle view in
    (* Painted in this call, at the instant of the arrival: nothing waited. *)
    ensure (phys_equal shown view) "a view after a quiet interval was held";
    Time_ns.diff !clock arrived |> Time_ns.Span.to_ms) in
  printf "waits: %s; paints %d\n" (String.concat ~sep:" " (List.map delays ~f:(sprintf "%.1f")))
    (Paint_throttle.paints throttle);
  [%expect {| waits: 0.0 0.0 0.0 0.0 0.0; paints 5 |}]

let%expect_test "a flood of new views, one every millisecond, is painted at most sixty times a second" =
  let clock = ref (at 1000.) in
  let throttle = Paint_throttle.create ~now:(fun () -> !clock) () in
  let start = !clock in
  let longest_wait = ref 0. and held_since = ref None in
  for ms = 0 to 999 do
    clock := Time_ns.add start (Time_ns.Span.of_ms (Float.of_int ms));
    (* The same size throughout: a view of another size is a resize, and is painted at once. *)
    let view = View.text (sprintf "%4d" ms) in
    let before = Paint_throttle.paints throttle in
    ignore (Paint_throttle.release throttle view : View.t);
    let painted = Paint_throttle.paints throttle > before in
    (match painted, !held_since with
     | true, Some since -> longest_wait := Float.max !longest_wait (Time_ns.diff !clock since |> Time_ns.Span.to_ms);
       held_since := None
     | false, None -> held_since := Some !clock
     | true, None | false, Some _ -> ())
  done;
  let paints = Paint_throttle.paints throttle in
  printf "paints in a second: %d; a view waited at most %.0f ms\n" paints !longest_wait;
  ensure (paints <= 60) "more than sixty paints in a second";
  [%expect {| paints in a second: 59; a view waited at most 16 ms |}]

let%expect_test "a resize inside the interval is painted at once, in the new size" =
  let clock = ref (at 1000.) in
  let throttle = Paint_throttle.create ~now:(fun () -> !clock) () in
  let small = View.text "small" and same_size = View.text "SMALL" and large = View.text "a larger view" in
  let offered view =
    let shown = Paint_throttle.release throttle view in
    sprintf "%s (paints %d)" (if phys_equal shown view then "painted" else "held") (Paint_throttle.paints throttle) in
  printf "first: %s\n" (offered small);
  clock := Time_ns.add !clock (Time_ns.Span.of_ms 2.);
  printf "same size, 2 ms later: %s\n" (offered same_size);
  clock := Time_ns.add !clock (Time_ns.Span.of_ms 2.);
  printf "new size, 4 ms later: %s\n" (offered large);
  [%expect {|
    first: painted (paints 1)
    same size, 2 ms later: held (paints 1)
    new size, 4 ms later: painted (paints 2)
    |}]

(* --- Fast streams are polled with room, and every stream still delivers its rate ----------------- *)

let%expect_test "at the real cadence of the poll loop, a stream delivers exactly its rate" =
  (* The loop's wait is the stream's period, or for a faster stream the paint interval plus
     [poll_margin]; the poll itself, and the timer, add a little more. *)
  let live_wait ~rate_hz =
    Time_ns.Span.max (Time_ns.Span.of_sec (1. /. rate_hz)) (Time_ns.Span.( + ) App.frame App.poll_margin) in
  List.iter [ 0.1; 4.; 40.; 60.; 1000. ] ~f:(fun rate_hz ->
    let wait = Time_ns.Span.( + ) (live_wait ~rate_hz) (Time_ns.Span.of_ms 0.4) in
    let polls = Float.to_int (60. /. Time_ns.Span.to_sec wait) in
    let steps, _ = List.fold (List.range 0 polls) ~init:(0, 0.) ~f:(fun (total, carried) _ ->
        let steps, carried = Mock_backend.steps_due ~rate_hz ~elapsed:wait ~carried in
        total + steps, carried) in
    let seconds = Time_ns.Span.to_sec wait *. Float.of_int polls in
    let wanted = rate_hz *. seconds in
    printf "%7.1f Hz: %d polls in %.1f s, %d steps, wanted %.0f, off by %.2f%%, %.1f paints/s\n"
      rate_hz polls seconds steps wanted (100. *. (Float.of_int steps -. wanted) /. wanted)
      (Float.of_int polls /. seconds));
  [%expect {|
       0.1 Hz: 5 polls in 50.0 s, 5 steps, wanted 5, off by -0.00%, 0.1 paints/s
       4.0 Hz: 239 polls in 59.8 s, 239 steps, wanted 239, off by -0.16%, 4.0 paints/s
      40.0 Hz: 2362 polls in 60.0 s, 2399 steps, wanted 2400, off by -0.03%, 39.4 paints/s
      60.0 Hz: 3066 polls in 60.0 s, 3599 steps, wanted 3599, off by -0.01%, 51.1 paints/s
    1000.0 Hz: 3066 polls in 60.0 s, 59991 steps, wanted 59991, off by -0.00%, 51.1 paints/s
    |}]

(* --- A highlight is on, and then it is off; the clock ticks only to take it off --------------------- *)

let%expect_test "every highlight has one strength, and expires where Market_motion says it does" =
  let levels = List.map [ 1.; 0.5; 0.01; 0.; -1. ] ~f:Fade.level in
  printf "levels: %s\n" (String.concat ~sep:" " (List.map levels ~f:(sprintf "%.0f")));
  let snapshot = (Shell_tests.state Enabled).market in
  let changed = { snapshot with bids = [ { price_ticks = 1001; quantity_units = 40 } ]
                              ; asks = [ { price_ticks = 1002; quantity_units = 12 } ] } in
  let first = Market_motion.observe Market_motion.empty ~now:(at 0.) ~snapshot ~updates:0 in
  let second = Market_motion.observe first ~now:(at 5000.) ~snapshot:changed ~updates:1 in
  let relative = List.map (Market_motion.expiries second) ~f:(fun time ->
      Time_ns.diff time (at 5000.) |> Time_ns.Span.to_ms |> Float.round_nearest |> Float.to_int)
                 |> List.sort ~compare:Int.compare in
  printf "expiries after the second observation, ms after it: %s\n"
    (String.concat ~sep:" " (List.map relative ~f:Int.to_string));
  [%expect {|
    levels: 1 1 1 0 0
    expiries after the second observation, ms after it: 300 300 1000 1000 2000
    |}]

let%expect_test "the clock's next tick is one grace after the earliest highlight still on" =
  let tick ~after expiries =
    Option.value_map (Anim_clock.next_tick ~after:(at after) (List.map expiries ~f:at)) ~default:"none"
      ~f:(fun time -> sprintf "%.0f" (Time_ns.diff time Time_ns.epoch |> Time_ns.Span.to_ms)) in
  printf "nothing on: %s; all over: %s; one on: %s; three on: %s; the earliest over: %s\n"
    (tick ~after:100. []) (tick ~after:100. [ 10.; 50.; 100. ]) (tick ~after:100. [ 1000. ])
    (tick ~after:100. [ 1800.; 1000.; 400. ]) (tick ~after:500. [ 1800.; 1000.; 400. ]);
  [%expect {| nothing on: none; all over: none; one on: 1250; three on: 650; the earliest over: 1250 |}]

(* --- The wake, on the real clock ------------------------------------------------------------------ *)

(* A wake on a clock of the test's own: time moves only when the test moves it, so what fires
   and when is exact, and a wake owns its state, so no test leaves anything behind for the next. *)
let test_clock () =
  let clock = Async.Time_source.create ~now:Time_ns.epoch () in
  clock, Wake.create ~time_source:(Async.Time_source.read_only clock) ()

let run_jobs () =
  Async.Scheduler.External.run_cycles_until_determined
    (Async.Scheduler.yield_until_no_jobs_remain ())

let advance clock ~ms =
  Async.Time_source.advance_directly_by clock (Time_ns.Span.of_ms ms);
  Async.Time_source.fire_past_alarms clock;
  run_jobs ()

let%expect_test "a wake is sent at its time, and a soft one yields to the state it waits for" =
  let clock, wake = test_clock () in
  let wakes = ref 0 in
  Wake.connect wake (fun () -> incr wakes);
  let within = Paint_throttle.default_interval in
  let now () = Async.Time_source.now (Async.Time_source.read_only clock) in
  let report what = printf "%-52s %d wake(s)\n" what !wakes; wakes := 0 in
  Wake.now wake;
  report "now";
  Wake.at wake (Time_ns.add (now ()) (Time_ns.Span.of_ms 10.));
  report "at +10 ms, at once";
  advance clock ~ms:40.;
  report "at +10 ms, after 40 ms";
  Wake.soft_now wake ~within;
  report "soft, no state expected";
  Wake.expect_arrival wake (Time_ns.add (now ()) (Time_ns.Span.of_ms 5.));
  Wake.soft_now wake ~within;
  report "soft, a state in 5 ms, at once";
  Wake.arrived wake;
  advance clock ~ms:60.;
  report "soft, the state came: the wait is called off";
  Wake.expect_arrival wake (Time_ns.add (now ()) (Time_ns.Span.of_ms 5.));
  Wake.soft_now wake ~within;
  advance clock ~ms:60.;
  report "soft, the state never came: the backstop";
  Wake.expect_arrival wake (Time_ns.add (now ()) (Time_ns.Span.of_ms 200.));
  Wake.soft_now wake ~within;
  report "soft, a state in 200 ms: too far to wait for";
  [%expect {|
    now                                                  1 wake(s)
    at +10 ms, at once                                   0 wake(s)
    at +10 ms, after 40 ms                               1 wake(s)
    soft, no state expected                              1 wake(s)
    soft, a state in 5 ms, at once                       0 wake(s)
    soft, the state came: the wait is called off         0 wake(s)
    soft, the state never came: the backstop             1 wake(s)
    soft, a state in 200 ms: too far to wait for         1 wake(s)
    |}]

let%expect_test "a wake belongs to its run: two runs share nothing, and neither needs a reset" =
  let _, first = test_clock () and _, second = test_clock () in
  let wakes = ref 0 in
  Wake.connect first (fun () -> incr wakes);
  Wake.expect_arrival first (Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms 5.));
  (* [second] was never connected, and [first]'s expected state is not its own. *)
  Wake.soft_now second ~within:Paint_throttle.default_interval;
  Wake.now second;
  printf "first woken by second: %d; second live: %b, off live: %b\n" !wakes (Wake.live second)
    (Wake.live Wake.off);
  [%expect {| first woken by second: 0; second live: true, off live: false |}]

(* --- The clock keeps one timer, however its deadline moves ------------------------------------- *)

(* The stream's "stopped" deadline is the newest sample plus two seconds, and it moves with every
   sample. A timer that followed it would be set again at each one, and each of those would wake
   a frame when its time came: dozens a second, from a stream that is doing nothing. The clock
   keeps one, and looks again when it fires. *)
let%expect_test "a deadline that moves with every sample costs one timer, and a wake only when that is due" =
  let _scheduler = Async.Scheduler.t () in
  let clock, wake = test_clock () in
  let wakes = ref 0 in
  Wake.connect wake (fun () -> incr wakes);
  let handle = Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 80; height = 24 }
      ~to_view_with_handler:fst ~handle_incoming:(fun (_, set) sample -> set sample)
      (fun ~dimensions:_ (local_ graph) ->
         let sample, set = Bonsai.state (0, []) graph in
         let activity = let%arr sample in fst sample in
         let expiries = let%arr sample in snd sample in
         let now = Anim_clock.component ~wake ~activity ~equal:Int.equal ~expiries ~after_touch:[] graph in
         let%arr now and set in
         ignore (now : Time_ns.t);
         ((~view:View.none, ~handler:(fun (_ : Event.t) -> Effect.Ignore)), set)) in
  let move_to ms =
    let time = Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms ms) in
    Bonsai_test.Handle.advance_clock handle ~to_:time;
    Async.Time_source.advance_directly clock ~to_:time;
    Async.Time_source.fire_past_alarms clock;
    run_jobs ();
    Bonsai_test.Handle.recompute_view_until_stable handle;
    run_jobs () in
  let samples = List.range 1 201 in
  List.iter samples ~f:(fun n ->
    let ms = Float.of_int n *. 16. in
    move_to ms;
    Bonsai_term_test.do_actions handle
      [ n, [ Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms (ms +. 2000.)) ] ];
    Bonsai_test.Handle.recompute_view_until_stable handle;
    run_jobs ());
  let next () =
    Option.value_map (Async.Time_source.next_alarm_fires_at (Async.Time_source.read_only clock)) ~default:"none"
      ~f:(fun time -> sprintf "%.0f ms" (Time_ns.diff time Time_ns.epoch |> Time_ns.Span.to_ms)) in
  printf "after %d samples over 3.2 s: %d wakes, next timer at %s\n" (List.length samples) !wakes (next ());
  (* The stream stops. The one timer fires, finds the deadline has moved, and is set once more. *)
  move_to 10_000.;
  printf "after the stream stopped and the deadline passed: %d wakes, timers pending: %s\n" !wakes (next ());
  let wakes_then = !wakes in
  move_to 60_000.;
  printf "a minute on: %d further wakes\n" (!wakes - wakes_then);
  [%expect {|
    after 200 samples over 3.2 s: 1 wakes, next timer at 4506 ms
    after the stream stopped and the deadline passed: 2 wakes, timers pending: none
    a minute on: 0 further wakes
    |}]

(* --- The stream is polled when it has something, and not otherwise ------------------------------ *)

let%expect_test "polls per second follow the stream's rate, a paint interval apart at the most" =
  let per_second ~rate_hz =
    let delay = App.poll_delay ~live:true ~period:(Time_ns.Span.of_sec (1. /. rate_hz)) in
    1. /. Time_ns.Span.to_sec delay in
  List.iter [ 0.1; 4.; 30.; 60.; 1000. ] ~f:(fun rate_hz ->
    let polls = per_second ~rate_hz in
    ensure Float.(polls <= 1. /. Time_ns.Span.to_sec App.frame) "polled more than once a paint interval";
    printf "%7.1f Hz: %6.2f polls/s\n" rate_hz polls);
  [%expect {|
       0.1 Hz:   0.10 polls/s
       4.0 Hz:   4.00 polls/s
      30.0 Hz:  30.00 polls/s
      60.0 Hz:  52.17 polls/s
    1000.0 Hz:  52.17 polls/s
    |}]

(* Polling stops where a poll could show nothing new. Per scenario: whether the backend wants
   polls at the start and after the proposal is applied, and whether a run that polls only
   while it wants them ends in the state of one that polls every time. *)
let%expect_test "no scenario loses a change by not being polled while idle" =
  List.iter Mock_backend.scenarios ~f:(fun (name, scenario) ->
    let backend = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
    let applied = Mock_backend.handle_command backend
        (Model_adapter.Apply_proposal (Mock_backend.state backend).proposal) in
    let run backend ~only_when_polling =
      let polls = ref 0 in
      let backend = List.fold (List.range 0 200) ~init:backend ~f:(fun backend _ ->
        if only_when_polling && not (Mock_backend.polling backend) then backend
        else (incr polls; Mock_backend.advance backend)) in
      backend, !polls in
    let thrifty, polls = run applied ~only_when_polling:true in
    let every, _ = run applied ~only_when_polling:false in
    let same = Model_adapter.equal_application_state (Mock_backend.state thrifty) (Mock_backend.state every) in
    ensure same (sprintf "%s: not polling while idle hid a change" name);
    printf "%-20s polling at start %-5b after apply %-5b, polls in 50 s: %3d, same state as polling always\n"
      name (Mock_backend.polling backend) (Mock_backend.polling applied) polls);
  [%expect {|
    connected_disarmed   polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    enabled              polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    no_signal            polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    admitted             polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    blocked              polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    received             polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    update_pending       polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    update_failed        polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    connection_lost      polling at start false after apply false, polls in 50 s:   0, same state as polling always
    book_invalid         polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    update_ok            polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    fail_at_idle         polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    fail_at_verify       polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    lost_at_activate     polling at start true  after apply true , polls in 50 s:  12, same state as polling always
    stale_base           polling at start true  after apply true , polls in 50 s: 200, same state as polling always
    |}]
