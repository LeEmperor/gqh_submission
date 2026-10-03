open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect

let ensure = Shell_tests.ensure
let contains = Shell_tests.contains
let render = Phase5_shell_tests.render

(* --- The heatmap's and the tape's cutoffs are sound ------------------------------------------ *)

(* What the application state does to a screen that draws it: for each alteration, whether the
   panel's cutoff calls the state unchanged, and what the screen does. A cutoff that calls a
   state unchanged whose screen differs fails here, and a panel that starts to read a field its
   cutoff ignores fails the same way. *)
let audit ~same ~view states =
  let before = render ~capability:Ansi (view (fst (List.hd_exn states))) ~width:90 ~height:24 in
  List.iter (List.tl_exn states) ~f:(fun (state, (field, state')) ->
    ignore state;
    let drawn = not (String.equal before (render ~capability:Ansi (view state') ~width:90 ~height:24)) in
    let ignored = same state state' in
    ensure (not (ignored && drawn)) (sprintf "the screen draws %s, which its cutoff ignores" field);
    printf "%-26s %s\n" field
      (if ignored then "ignored" else if drawn then "re-rendered" else "re-rendered, same screen"))

let heatmap_fixture () =
  let backend = ref (History_tests.backend 12) in
  let heatmap = ref Heatmap.empty in
  for _ = 1 to 90 do
    backend := Mock_backend.advance !backend;
    let state = Mock_backend.state !backend in
    heatmap := Heatmap.observe_sampled !heatmap ~rate_hz:state.rate_hz state.market
  done;
  Mock_backend.state !backend, !heatmap

let%expect_test "a state the heatmap's cutoff calls unchanged renders the same heatmap" =
  let state, heatmap = heatmap_fixture () in
  let enabled = { state with engine = Armed
                           ; rules = List.map state.rules ~f:(fun rule ->
                               { rule with enabled = true; parameters = [ "maximum_price", 1003, "t" ] }) } in
  let theme = Theme.create Truecolor in
  let view state = Heatmap.view ~theme ~focus:Rules ~heatmap ~state ~width:90 ~height:24 in
  let extra =
    [ "market valid", { enabled with market = { enabled.market with valid = not enabled.market.valid } }
    ; "instrument", { enabled with market = { enabled.market with instrument = "XYZ" } }
    ; "threshold", { enabled with rules = List.map enabled.rules ~f:(fun rule ->
          { rule with parameters = [ "maximum_price", 996, "t" ] }) }
    ; "engine unknown", { enabled with engine = Engine_unknown } ] in
  let states = (enabled, ("", enabled)) :: List.map (Phase5_shell_tests.altered enabled @ extra)
                                              ~f:(fun (field, state') -> enabled, (field, state')) in
  audit ~same:Heatmap.same_inputs ~view states;
  [%expect {|
    mode                       re-rendered
    connected                  ignored
    build_id                   ignored
    run_id                     ignored
    configuration              ignored
    engine                     ignored
    market                     ignored
    trace_loss                 ignored
    updates                    ignored
    rate_hz                    re-rendered
    rules                      ignored
    latest_decision            ignored
    decisions (emptied)        ignored
    decisions (sequence)       ignored
    decisions (evidence)       ignored
    decisions (outcomes)       ignored
    manifest                   ignored
    proposal                   ignored
    config_apply               ignored
    config_events              ignored
    market valid               re-rendered
    instrument                 re-rendered
    threshold                  re-rendered
    engine unknown             re-rendered
    |}]

let tape_fixture () =
  let backend = ref (History_tests.backend 3) in
  let tape = ref Tape_panel.empty in
  for i = 0 to 80 do
    backend := Mock_backend.advance !backend;
    let now = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec (0.25 *. Float.of_int i)) in
    tape := Tape_panel.observe !tape ~now ~snapshot:(Mock_backend.state !backend).market
  done;
  !backend, !tape

let%expect_test "a tape the tape's cutoff calls unchanged renders the same tape" =
  let backend, tape = tape_fixture () in
  let theme = Theme.create Truecolor in
  let now = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec 30.) in
  let view tape = Tape_panel.view ~theme ~focus:Market ~tape ~now ~width:70 ~height:16 in
  let next = Tape_panel.observe tape ~now ~snapshot:(Mock_backend.state (Mock_backend.advance backend)).market in
  let alterations =
    [ "mode", { tape with mode = (match tape.mode with Some Mock -> Some Hardware | _ -> Some Mock) }
    ; "identity", { tape with identity = None }
    ; "top", { tape with top = None }
    ; "prints (dropped)", { tape with prints = Age_deque.trim tape.prints ~keep:(fun ~length _ -> length < Age_deque.length tape.prints) }
    ; "prints (rebuilt, equal)", { tape with prints = Age_deque.of_list (Tape_panel.prints tape) }
    ; "prints (a new print)", { tape with prints = Age_deque.push tape.prints
                                  { time = now; side = Buy; price_ticks = 1; quantity_units = 7 } }
    ; "next snapshot", next ] in
  let before = render ~capability:Ansi (view tape) ~width:70 ~height:16 in
  List.iter alterations ~f:(fun (field, tape') ->
    let drawn = not (String.equal before (render ~capability:Ansi (view tape') ~width:70 ~height:16)) in
    let ignored = Tape_panel.same_inputs tape tape' in
    ensure (not (ignored && drawn)) (sprintf "the tape draws %s, which its cutoff ignores" field);
    printf "%-26s %s\n" field
      (if ignored then "ignored" else if drawn then "re-rendered" else "re-rendered, same screen"));
  [%expect {|
    mode                       re-rendered
    identity                   ignored
    top                        ignored
    prints (dropped)           re-rendered
    prints (rebuilt, equal)    re-rendered, same screen
    prints (a new print)       re-rendered
    next snapshot              ignored
    |}]

(* --- The decisions build no rows while their panel is not shown ------------------------------ *)

let%expect_test "decisions off screen keep the log and build no rows, and show them when back" =
  let backend = History_tests.backend 40 in
  let log = History_tests.log backend in
  let newest = Option.value_exn (List.hd (Decision_buffer.to_list log |> List.rev)) in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 52; height = 17 }
      ~to_view_with_handler:(fun (history, _) ->
        ~view:history.History_panel.view, ~handler:(fun _ -> Effect.return ()))
      ~handle_incoming:(fun (_, set) on_screen -> set on_screen)
      (fun ~dimensions (local_ graph) ->
        let on_screen, set = Bonsai.state true graph in
        let history = History_panel.component ~theme:(Bonsai.return History_tests.theme)
            ~focus:(Bonsai.return Keymap.Decisions) ~on_screen ~log:(Bonsai.return log) ~dimensions graph in
        let%arr history and set in history, set) in
  let shown () = contains (Handle.show_into_string handle) (Decision_row.id newest) in
  let on = shown () in
  Bonsai_term_test.do_actions handle [ false ];
  let off = shown () in
  Bonsai_term_test.do_actions handle [ true ];
  let back = shown () in
  printf "on screen: %b; off screen: %b; back on screen: %b\n" on off back;
  ensure (on && (not off) && back) "the rows are not built exactly while the panel is off screen";
  [%expect {| on screen: true; off screen: false; back on screen: true |}]

(* --- The sample history ---------------------------------------------------------------------- *)

(* A list as the model of the deque: pushed at the front, trimmed at the back. Every few steps
   the deque is walked and compared, so each shape it takes between rebalances is checked. *)
let%expect_test "the age deque is a list that is trimmed at its old end" =
  let random = Random.State.make [| 7 |] in
  let deque = ref Age_deque.empty and model = ref [] and failures = ref 0 in
  for step = 1 to 5000 do
    (match Random.State.int random 3 with
     | 0 | 1 -> deque := Age_deque.push !deque step; model := step :: !model
     | _ ->
       let floor = step - Random.State.int random 40 in
       deque := Age_deque.trim !deque ~keep:(fun ~length:_ oldest -> oldest >= floor);
       model := List.filter !model ~f:(fun element -> element >= floor));
    let walked = ref [] in
    Age_deque.iter_while !deque ~f:(fun element -> walked := element :: !walked; true);
    let early = ref 0 in
    Age_deque.iter_while !deque ~f:(fun _ -> incr early; !early < 3);
    if not ([%equal: int list] (List.rev !walked) !model && Age_deque.length !deque = List.length !model
            && [%equal: int option] (Age_deque.newest !deque) (List.hd !model)
            && !early = Int.min 3 (List.length !model)) then incr failures
  done;
  printf "%d steps differ from the list\n" !failures;
  [%expect {| 0 steps differ from the list |}]

(* A minute of samples at 60 a second, as the market keeps it. A walk asks only for what it
   reads: one second is sixty-one calls (the sixty and the first one out of the window), wherever
   the deque has put its older half, and a walk that goes on into the older half is still newest
   first and still stops where it is told. *)
let%expect_test "a walk of the age deque calls f only on what it reads" =
  let deque = List.fold (List.range 0 3600) ~init:Age_deque.empty ~f:Age_deque.push in
  (* The first trim moves the older half of the deque into its older array. *)
  let deque = Age_deque.trim deque ~keep:(fun ~length _ -> length <= 3601) in
  let newest = Option.value_exn (Age_deque.newest deque) in
  let calls = ref 0 in
  Age_deque.iter_while deque ~f:(fun element -> incr calls; element > newest - 60);
  printf "one second of 3600 samples: %d calls\n" !calls;
  let seen = ref [] in
  Age_deque.iter_while deque ~f:(fun element -> seen := element :: !seen; List.length !seen < 2500);
  let seen = List.rev !seen in
  printf "2500 deep, into the older half: %d elements, newest first %b, ends at %d\n"
    (List.length seen) (List.is_sorted_strictly seen ~compare:(fun a b -> Int.compare b a)) (List.last_exn seen);
  [%expect {|
    one second of 3600 samples: 61 calls
    2500 deep, into the older half: 2500 elements, newest first true, ends at 1100
    |}]

(* --- A stream that stops is said to have stopped, once ------------------------------------------ *)

let%expect_test "the chart's axis says when the stream stopped, after two seconds and not before" =
  let backend = Shell_tests.fixture Enabled in
  let handle, counts = Phase5_shell_tests.counting_app ~initial:(Mock_backend.state backend)
      { width = 200; height = 60 } in
  Phase5_shell_tests.settle handle counts;
  Bonsai_term_test.do_actions handle [ Mock_backend.state (Mock_backend.advance backend) ];
  Handle.recompute_view_until_stable handle;
  let says needle = contains (Handle.show_into_string handle) needle in
  printf "just after an update: now %b, stopped %b\n" (says "−30 s") (says "stopped");
  Phase5_shell_tests.tick handle 1.;
  printf "1 s on: stopped %b\n" (says "stopped");
  Phase5_shell_tests.tick handle 2.;
  printf "3 s on: stopped %b, utc %b\n" (says "stopped") (says " UTC");
  Hashtbl.clear counts;
  for _ = 1 to 240 do Phase5_shell_tests.tick handle 0.5 done;
  printf "Market recomputes in the next two minutes: %d\n" (Phase5_shell_tests.count counts "Market");
  [%expect {|
    just after an update: now true, stopped false
    1 s on: stopped false
    3 s on: stopped true, utc true
    Market recomputes in the next two minutes: 0
    |}]
