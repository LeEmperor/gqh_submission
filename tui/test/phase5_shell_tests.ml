open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect

let ensure = Shell_tests.ensure
let contains = Shell_tests.contains
let key = Shell_tests.key

(* --- Rendering helpers ------------------------------------------------------------------- *)

(* A view as the terminal would show it; with [~capability:Ansi] the colours are in the text. *)
let render ?capability view ~width ~height =
  let handle = Bonsai_term_test.create_handle_without_handler ?capability
      ~initial_dimensions:{ width; height }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  Handle.show_into_string handle

(* --- Incremental render: what each event recomputes ------------------------------------------ *)

(* The real shell on a Monitor screen, with the per-node recompute hook counting. The table is
   the test's own record of what ran. *)
let counting_app ?(preset = Ui_types.Monitor) ?(initial = Shell_tests.state Enabled) dimensions =
  let counts = String.Table.create () in
  let on_compute name = Hashtbl.update counts name ~f:(fun n -> Option.value n ~default:0 + 1) in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
      ~to_view_with_handler:fst
      ~handle_incoming:(fun (_, inject) state -> inject state)
      (fun ~dimensions (local_ graph) ->
        let state, inject = Bonsai.state initial graph in
        let ~view, ~handler =
          App.component ~on_compute ~initial_preset:preset ~theme:Shell_tests.theme ~state
            ~clock:(Bonsai.return Shell_tests.clock) ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
        let%arr view and handler and inject in
        ((~view, ~handler), inject)) in
  handle, counts

let settle handle counts =
  Handle.recompute_view_until_stable handle;
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.1);
  Handle.recompute_view_until_stable handle;
  Hashtbl.clear counts

let tick handle seconds =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec seconds);
  Handle.recompute_view_until_stable handle

let count counts name = Option.value (Hashtbl.find counts name) ~default:0
let summary counts =
  Hashtbl.to_alist counts |> List.sort ~compare:[%compare: string * int]
  |> List.map ~f:(fun (name, n) -> sprintf "%s:%d" name n) |> String.concat ~sep:" "

(* Catches a clock that feeds the whole view: any recompute here is work with no change to show. *)
let%expect_test "a quiet disconnected app recomputes nothing however long the clock runs" =
  let handle, counts = counting_app ~initial:(Shell_tests.state Connection_lost) { width = 120; height = 36 } in
  settle handle counts;
  for _ = 1 to 120 do tick handle 0.25 done;
  printf "after 30 s: [%s]\n" (summary counts);
  [%expect {| after 30 s: [] |}]

(* The stream moves the book, the update counter and the decisions. Of the panels, the header
   and the cold ones must not notice. *)
let%expect_test "a stream tick recomputes the market-data panels and not the header or cold panels" =
  let backend = Shell_tests.fixture Enabled in
  let handle, counts = counting_app ~initial:(Mock_backend.state backend) { width = 120; height = 36 } in
  settle handle counts;
  Bonsai_term_test.do_actions handle [ Mock_backend.state (Mock_backend.advance backend) ];
  Handle.recompute_view_until_stable handle;
  List.iter [ "Market"; "Heatmap"; "header"; "footer"; "Latency"; "Configuration"; "Inspector" ] ~f:(fun name ->
    printf "%-13s %s\n" name (if count counts name > 0 then "recomputed" else "untouched"));
  [%expect {|
    Market        recomputed
    Heatmap       recomputed
    header        untouched
    footer        untouched
    Latency       untouched
    Configuration untouched
    Inspector     untouched
    |}]

(* Focus is the one input every panel shares; each reads only whether it is the focused one. *)
let%expect_test "a focus move recomputes the two panels it moves between, and the footer" =
  let handle, counts = counting_app { width = 120; height = 36 } in
  settle handle counts;
  Bonsai_term_test.send_event handle (key Tab);
  Handle.recompute_view_until_stable handle;
  printf "%s\n" (summary counts);
  [%expect {| Heatmap:1 Market:1 body:1 footer:1 frame:1 |}]

(* The animation clock runs while the stream moves and for the length of the longest fade,
   ticks slowly while a chart still holds data, and then stops altogether. *)
let%expect_test "the animation clock ticks fast, then slow, then stops" =
  let backend = Shell_tests.fixture Enabled in
  let handle, counts = counting_app ~initial:(Mock_backend.state backend) { width = 120; height = 36 } in
  settle handle counts;
  Bonsai_term_test.do_actions handle [ Mock_backend.state (Mock_backend.advance backend) ];
  Handle.recompute_view_until_stable handle;
  Hashtbl.clear counts;
  for _ = 1 to 20 do tick handle 0.05 done;
  let fast = count counts "Market" in
  Hashtbl.clear counts;
  for _ = 1 to 60 do tick handle 0.5 done;
  let slow = count counts "Market" in
  (* 31 s in; the slow phase ends 65 s after the stream tick. *)
  for _ = 1 to 80 do tick handle 0.5 done;
  Hashtbl.clear counts;
  for _ = 1 to 40 do tick handle 0.5 done;
  let after = count counts "Market" in
  printf "first second: %s\n" (if fast >= 10 && fast <= 12 then "a frame per fade step" else sprintf "unexpected: %d" fast);
  printf "next 30 s: %s\n" (if slow >= 50 && slow <= 70 then "two a second" else sprintf "unexpected: %d" slow);
  printf "from 71 s to 91 s: %d recomputes\n" after;
  [%expect {|
    first second: a frame per fade step
    next 30 s: two a second
    from 71 s to 91 s: 0 recomputes
    |}]

(* A stream tick during the slow phase must restart the fast one at once, not wait out the
   half-second sleep already in flight. *)
let%expect_test "a stream tick in the slow phase restarts the fast clock" =
  let backend = Shell_tests.fixture Enabled in
  let handle, counts = counting_app ~initial:(Mock_backend.state backend) { width = 120; height = 36 } in
  settle handle counts;
  let backend = Mock_backend.advance backend in
  Bonsai_term_test.do_actions handle [ Mock_backend.state backend ];
  for _ = 1 to 10 do tick handle 0.5 done;
  Bonsai_term_test.do_actions handle [ Mock_backend.state (Mock_backend.advance backend) ];
  Handle.recompute_view_until_stable handle;
  Hashtbl.clear counts;
  for _ = 1 to 10 do tick handle 0.05 done;
  printf "frames in the half second after the tick: %s\n"
    (if count counts "Market" >= 4 then "fast" else sprintf "slow: %d" (count counts "Market"));
  [%expect {| frames in the half second after the tick: fast |}]

(* --- Every cold panel's cutoff is sound: what it ignores is never on its screen ------------- *)

let altered (state : application_state) =
  let step_progress =
    { proposal_id = "p-x"; steps = []; acknowledged_version = Some 5; failure = None
    ; state_unknown = true; reconciliation = Not_requested } in
  [ "mode", { state with mode = (match state.mode with Mock -> Hardware | _ -> Mock) }
  ; "connected", { state with connected = not state.connected }
  ; "build_id", { state with build_id = state.build_id ^ "-x" }
  ; "run_id", { state with run_id = state.run_id ^ "-x" }
  ; "configuration", { state with configuration = { state.configuration with
        status = Failed "boom"; last_acknowledged_version = Some 99 } }
  ; "engine", { state with engine = (match state.engine with Armed -> Disarmed | _ -> Armed) }
  ; "market", { state with market = { state.market with
        bids = List.map state.market.bids ~f:(fun l -> { l with price_ticks = l.price_ticks + 7 })
      ; asks = List.map state.market.asks ~f:(fun l -> { l with quantity_units = l.quantity_units + 3 }) } }
  ; "trace_loss", { state with trace_loss = state.trace_loss + 5 }
  ; "updates", { state with updates = state.updates + 1 }
  ; "rate_hz", { state with rate_hz = state.rate_hz +. 1. }
  ; "rules", { state with rules = List.map state.rules ~f:(fun rule ->
        { rule with matched = rule.matched + 3; blocked = rule.blocked + 1
                  ; last_block_reason = Some "x" }) }
  ; "latest_decision", { state with latest_decision = None }
  ; "decisions (emptied)", { state with decisions = Decision_buffer.empty }
  ; "decisions (sequence)", { state with decisions = { state.decisions with
        next_sequence = state.decisions.next_sequence + 1 } }
  ; "decisions (evidence)", { state with decisions = { state.decisions with
        records = Map.map state.decisions.records ~f:(fun (decision : decision) ->
          { decision with receipt_at = None; build_id = decision.build_id ^ "-x"
                        ; occurred_at = Time_ns.add decision.occurred_at (Time_ns.Span.of_sec 9.)
                        ; maximum_price_ticks = decision.maximum_price_ticks + 1 }) } }
  ; "decisions (outcomes)", { state with decisions = { state.decisions with
        records = Map.map state.decisions.records ~f:(fun (decision : decision) ->
          { decision with outcome = Blocked_result "order qty 99 above 5 u" }) } }
  ; "manifest", { state with manifest = { state.manifest with build_id = "other"; compiled_rules = [] } }
  ; "proposal", { state with proposal = { state.proposal with proposal_id = "p-other" } }
  ; "config_apply", { state with config_apply = Some step_progress }
  ; "config_events", { state with config_events = state.config_events @
        [ { identity = state.configuration.identity; mode = Mock; proposal_id = "p-x"; sequence = 99
          ; payload = Activation_acknowledged 99 } ] } ]

let%expect_test "a state a panel's cutoff calls unchanged renders the same screen" =
  let state = Mock_backend.state (History_tests.backend 12) in
  let theme = Shell_tests.theme in
  let width = 70 and height = 22 in
  let panels =
    [ "header", Status_bar.same_inputs
    , (fun state -> Status_bar.view ~theme ~state ~clock:"13:37:02" ~width:120)
    ; "Rules", Panel_views.Deps.rules
    , (fun state -> Rules_panel.view ~theme ~focus:Rules ~state ~selected:None ~width ~height)
    ; "Latency", Panel_views.Deps.latency
    , (fun state -> Latency_panel.view ~theme ~focus:Rules ~state ~width ~height)
    ; "Configuration", Panel_views.Deps.configuration
    , (fun state -> Config_review.view ~theme ~focus:Rules ~state ~width ~height) ] in
  List.iter panels ~f:(fun (name, same, view) ->
    let before = render (view state) ~width:120 ~height:height in
    let ignored = List.filter_map (altered state) ~f:(fun (field, state') ->
      ensure (not (equal_application_state state state')) (field ^ ": the alteration changed nothing");
      if not (same state state') then None
      else (
        ensure (String.equal before (render (view state') ~width:120 ~height:height))
          (sprintf "%s draws %s, which its cutoff ignores" name field);
        Some field)) in
    printf "%-13s ignores: %s\n" name (String.concat ~sep:" " ignored));
  [%expect {|
    header        ignores: market updates rate_hz rules latest_decision decisions (emptied) decisions (sequence) decisions (evidence) decisions (outcomes) manifest proposal config_apply config_events
    Rules         ignores: connected build_id market trace_loss updates rate_hz latest_decision decisions (evidence) manifest proposal config_apply config_events
    Latency       ignores: connected build_id run_id configuration engine market trace_loss updates rate_hz rules latest_decision decisions (emptied) decisions (sequence) decisions (evidence) decisions (outcomes) manifest proposal config_apply config_events
    Configuration ignores: run_id market trace_loss updates rate_hz rules latest_decision decisions (emptied) decisions (sequence) decisions (evidence) decisions (outcomes)
    |}]

(* --- The animated panels stop depending on the time ------------------------------------------ *)

let%expect_test "the tape moves with the time only by its highlight, then in half-second steps" =
  let theme = Theme.create Truecolor in
  let backend = History_tests.backend 3 in
  let epoch = Time_ns.epoch in
  let tape, _ =
    List.fold (List.range 0 80) ~init:(Tape_panel.empty, backend) ~f:(fun (tape, backend) i ->
      let backend = Mock_backend.advance backend in
      let now = Time_ns.add epoch (Time_ns.Span.of_sec (0.25 *. Float.of_int i)) in
      Tape_panel.observe tape ~now ~snapshot:(Mock_backend.state backend).market, backend) in
  let newest = (List.hd_exn (Tape_panel.prints tape)).time in
  let at now =
    render ~capability:Ansi ~width:60 ~height:12
      (Tape_panel.view ~theme ~focus:Market ~tape ~now ~width:60 ~height:12) in
  let after seconds = Time_ns.add newest (Time_ns.Span.of_sec seconds) in
  ensure (not (String.equal (at (after 0.05)) (at (after 1.2)))) "A new print is not highlighted: the test cannot see animation";
  (* Past [print_horizon] the app feeds the tape [now] rounded down to a step; the screen must
     be the one the exact time gives. *)
  List.iter [ 1.5; 1.77; 2.3; 4.1; 9.9; 30.3 ] ~f:(fun seconds ->
    let exact = after seconds in
    let rounded = Time_ns.prev_multiple ~can_equal_before:true ~base:epoch ~before:exact
        ~interval:Panel_views.metrics_step () in
    ensure (Time_ns.Span.(Time_ns.diff exact newest >= Panel_views.print_horizon)) "Setup: inside the horizon";
    ensure (String.equal (at exact) (at rounded))
      (sprintf "The tape depends on the time inside a half second, %.2f s after its last print" seconds));
  print_endline "highlight visible at 50 ms; from print_horizon on the screen only moves in half-second steps";
  [%expect {| highlight visible at 50 ms; from print_horizon on the screen only moves in half-second steps |}]

let%expect_test "a new decision row's highlight fades to nothing in eleven even steps" =
  let at = Time_ns.epoch in
  let intensity seconds = Decision_row.fresh_intensity ~now:(Time_ns.add at (Time_ns.Span.of_sec seconds)) ~at in
  let steps = List.map [ 0.; 0.2; 0.4; 0.6; 0.79; 0.8; 5. ] ~f:intensity in
  ensure (List.for_all (List.zip_exn (List.drop_last_exn steps) (List.tl_exn steps))
            ~f:(fun (a, b) -> Float.(a >= b))) "The fade is not monotone";
  ensure (List.for_all steps ~f:(fun x -> Float.(x >= 0. && x <= 1.))) "Intensity out of range";
  printf "%s\n" (String.concat ~sep:" " (List.map steps ~f:(sprintf "%.2f")));
  [%expect {| 1.00 0.82 0.55 0.27 0.09 0.00 0.00 |}]

(* --- Header clock ------------------------------------------------------------------------ *)

let live_app dimensions =
  let _scheduler = Async.Scheduler.t () in
  Bonsai_term_test.create_handle ~initial_dimensions:dimensions
    (App.live ~initial_preset:Ui_types.Monitor (module Mock_backend) ~theme:Shell_tests.theme
       ~backend:(Shell_tests.fixture Enabled) ~exit:(fun () -> Effect.Ignore))

let%expect_test "the header clock is UTC, to the second, and labelled once" =
  let handle = live_app { width = 200; height = 60 } in
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 3.);
  Handle.recompute_view_until_stable handle;
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.05);
  let text = Handle.show_into_string handle in
  let header = List.find_exn (String.split_lines text) ~f:(fun line -> contains line "tickweave ▸") in
  let now = Bonsai.Time_source.now (Handle.time_source handle) in
  let utc = Time_ns.to_ofday now ~zone:Timezone.utc |> Time_ns.Ofday.to_sec_string in
  ensure (contains header (utc ^ " UTC")) (sprintf "Header lacks %s UTC: %s" utc header);
  ensure (List.length (String.substr_index_all header ~pattern:"UTC" ~may_overlap:false) = 1
          && not (contains header (utc ^ ".")))
    "UTC labelled more than once, or the clock is finer than a second";
  print_endline "header ends with the UTC time of day to the second and the label UTC";
  [%expect {| header ends with the UTC time of day to the second and the label UTC |}]

(* --- Decisions rows ---------------------------------------------------------------------- *)

let decisions_of scenario ~steps =
  let backend = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
  let backend = List.fold (List.range 0 steps) ~init:backend ~f:(fun backend _ -> Mock_backend.advance backend) in
  Decision_buffer.to_list (Mock_backend.state backend).decisions

let%expect_test "decision rows gain the comparison, config and receipt columns as room allows" =
  let pick predicate decisions = List.find_exn decisions ~f:predicate in
  let admitted = pick (fun d -> equal_decision_outcome d.outcome Admitted_result && Option.is_some d.receipt_at)
      (decisions_of Enabled ~steps:20)
  and no_signal = pick (fun d -> equal_decision_outcome d.outcome No_signal_result) (decisions_of Enabled ~steps:20)
  and blocked = pick (fun d -> match d.outcome with Blocked_result _ -> true | _ -> false)
      (decisions_of Blocked ~steps:5) in
  List.iter [ 60; 66; 72; 96 ] ~f:(fun width ->
    printf "-- row width %d\n" width;
    List.iter [ admitted; no_signal; blocked ] ~f:(fun d -> printf "%s|\n" (Decision_row.text ~width d)));
  [%expect {|
    -- row width 60
    #1    13:37:00.250 MATCH BUY 1 @1005 ✓ADM ✓RCV|
    #4    13:37:01.000 ·     no signal|
    #1    13:37:00.250 MATCH BUY 6 @1005 ✗BLK qty|
    -- row width 66
    #1    13:37:00.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV|
    #4    13:37:01.000 ·     no signal     ask 1007 > 1005|
    #1    13:37:00.250 MATCH BUY 6 @1005   ask 1005 ≤ 1005 ✗BLK qty|
    -- row width 72
    #1    13:37:00.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12|
    #4    13:37:01.000 ·     no signal     ask 1007 > 1005            v12|
    #1    13:37:00.250 MATCH BUY 6 @1005   ask 1005 ≤ 1005 ✗BLK qty   v12|
    -- row width 96
    #1    13:37:00.250 MATCH BUY 1 @1005   ask 1005 ≤ 1005 ✓ADM ✓RCV  v12  +2.0ms|
    #4    13:37:01.000 ·     no signal     ask 1007 > 1005            v12|
    #1    13:37:00.250 MATCH BUY 6 @1005   ask 1005 ≤ 1005 ✗BLK qty   v12|
    |}]

(* Rows with a candidate keep their columns at one offset, whatever the prices and sides. *)
let%expect_test "the comparison column lines up across rows" =
  let rows = List.filter (decisions_of Enabled ~steps:30) ~f:(fun d -> Option.is_some d.candidate) in
  let offsets = List.map rows ~f:(fun d ->
    String.substr_index_exn (Decision_row.text ~width:72 d) ~pattern:"ask ") in
  ensure (List.length rows > 3) "Too few rows with a candidate";
  ensure (List.for_all offsets ~f:(Int.equal (List.hd_exn offsets))) "Comparison column is ragged";
  print_endline "one offset for the comparison column";
  [%expect {| one offset for the comparison column |}]

(* --- Frames: readable titles, a focus cue that is not colour --------------------------------- *)

let%expect_test "unfocused titles are plain Text, and focus adds bold and reverse video, even without colour" =
  let has attrs attr = List.mem attrs attr ~equal:Attr.equal in
  List.iter Ui_types.all_of_scheme ~f:(fun scheme ->
    let theme = Theme.with_scheme (Theme.create Truecolor) scheme in
    let unfocused = Panel.title_attrs theme ~focused:false ~muted:false in
    ensure (List.equal Attr.equal unfocused (Theme.attrs theme Text)) "Unfocused title is not plain Text";
    let background = Theme.role_rgb theme Bg and text = Theme.role_rgb theme Text in
    ensure Float.(Layout_tests.contrast text background >= 7.) "Title text under 7:1";
    let focused = Panel.title_attrs theme ~focused:true ~muted:false in
    ensure (has focused Attr.bold && has focused Attr.invert) "Focused title lacks bold reverse");
  let none = Theme.create No_color in
  let focused = Panel.title_attrs none ~focused:true ~muted:false in
  ensure (has focused Attr.bold && has focused Attr.invert) "Without colour focus has no cue";
  ensure (not (has (Panel.title_attrs none ~focused:false ~muted:false) Attr.invert)) "Unfocused title reversed";
  let muted = Panel.title_attrs (Theme.create Truecolor) ~focused:true ~muted:true in
  ensure (has muted Attr.invert) "A focused muted panel lost its cue";
  print_endline "titles: Text 7:1 or better when unfocused; bold + reverse when focused, in every scheme and NO_COLOR";
  [%expect {| titles: Text 7:1 or better when unfocused; bold + reverse when focused, in every scheme and NO_COLOR |}]

(* --- Layout bands ------------------------------------------------------------------------ *)

let%expect_test "Monitor's bottom band is Metrics, Latency and Tape side by side at every size" =
  List.iter [ 100, 30; 120, 36; 160, 45; 200, 60 ] ~f:(fun (width, terminal_height) ->
    List.iter [ true; false ] ~f:(fun heatmap ->
      let panels = Layout.compute ~preset:Monitor ~zoom:None ~toggles:{ heatmap; cumulative = false }
          ~width ~height:(Layout.body_height ~height:terminal_height) in
      let rect panel = List.Assoc.find_exn panels panel ~equal:Keymap.equal_focus in
      let band = List.map Keymap.[ Metrics; Latency; Tape ] ~f:rect in
      let first = List.hd_exn band in
      ensure (List.for_all band ~f:(fun r -> r.row = first.row && r.height = first.height)) "Band rows differ";
      ensure (List.sum (module Int) band ~f:(fun r -> r.width) = width) "Band does not span the body";
      ensure (List.for_all (List.zip_exn (List.drop_last_exn band) (List.tl_exn band))
                ~f:(fun (a, b) -> a.col + a.width = b.col)) "Band out of order or gapped";
      ensure ((rect Market).row + (rect Market).height = first.row) "Band is not under the market";
      if heatmap then printf "%dx%d metrics %d | latency %d | tape %d wide, %d rows\n" width terminal_height
          (List.nth_exn band 0).width (List.nth_exn band 1).width (List.nth_exn band 2).width first.height));
  [%expect {|
    100x30 metrics 38 | latency 31 | tape 31 wide, 12 rows
    120x36 metrics 46 | latency 37 | tape 37 wide, 14 rows
    160x45 metrics 61 | latency 49 | tape 50 wide, 18 rows
    200x60 metrics 76 | latency 62 | tape 62 wide, 24 rows
    |}]

(* --- Footer ------------------------------------------------------------------------------ *)

let%expect_test "the footer is one line, separated like the header, and keeps its status whole" =
  List.iter [ 100; 120; 160; 200 ] ~f:(fun width ->
    List.iter Keymap.[ Market; Configuration ] ~f:(fun focus ->
      let view = Footer.view ~theme:Shell_tests.theme ~focus ~preset:Demo ~zoomed:true ~scheme:Tokyo_night
          ~notice:None ~width in
      let text = render view ~width ~height:1 in
      let status = sprintf "Demo · tokyo · ZOOM · focus: %s" (Keymap.name focus) in
      ensure (View.height view = 1 && View.width view <= width) "Footer wraps or overflows";
      ensure (contains text status) (sprintf "Footer lost its status at %d" width);
      ensure (contains text "Tab/⇧Tab focus" && contains text " │ ") "Footer lost its hints or separators"));
  print_endline "100-200 columns: hints grouped by │, status intact";
  [%expect {| 100-200 columns: hints grouped by │, status intact |}]

(* --- Throttle ---------------------------------------------------------------------------- *)

let throttle_app () =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 10; height = 1 }
    ~to_view_with_handler:fst
    ~handle_incoming:(fun (_, set) view -> set view)
    (fun ~dimensions:_ (local_ graph) ->
      let view, set = Bonsai.state (View.text "v0") graph in
      let shown = Frame_meter.throttle ~view graph in
      let%arr shown and set in
      ((~view:shown, ~handler:(fun (_ : Event.t) -> Effect.Ignore)), set))

let%expect_test "the throttle paints a burst once per frame, and an idle view not at all" =
  let handle = throttle_app () in
  let shown () =
    (* The view is drawn in a one-row box: the middle line, without the box. *)
    List.nth_exn (String.split_lines (Handle.show_into_string handle)) 1
    |> String.strip ~drop:(fun c -> Char.is_whitespace c || Char.equal c '|' || Char.(c > '\127')) in
  let frame () = Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.0167); shown () in
  ignore (frame () : string);
  ignore (frame () : string);
  List.iter [ "v1"; "v2"; "v3" ] ~f:(fun v -> Bonsai_term_test.do_actions handle [ View.text v ]; ignore (shown () : string));
  let inside_frame = shown () in
  let next = frame () in
  let later = List.init 30 ~f:(fun _ -> frame ()) in
  printf "within the frame: %s; next frame: %s; 30 idle frames: %s\n" inside_frame next
    (String.concat ~sep:"," (List.dedup_and_sort later ~compare:String.compare));
  [%expect {| within the frame: v1; next frame: v3; 30 idle frames: v3 |}]

(* The shell joins the panels by rows and columns instead of stacking full-size layers, which
   draws each cell once. That is only right if the pieces tile the body exactly. *)
let%expect_test "folding a tiling into rows and columns gives exactly the body" =
  List.iter [ 100, 30; 120, 36; 160, 45; 200, 60 ] ~f:(fun (width, terminal_height) ->
    let height = Layout.body_height ~height:terminal_height in
    List.iter Ui_types.all_of_preset ~f:(fun preset ->
      List.iter [ None; Some Keymap.Rules ] ~f:(fun zoom ->
        let tiling = Layout.create ~preset ~zoom ~toggles:{ heatmap = true; cumulative = false } ~width ~height in
        let view = Option.value_exn (Layout.fold tiling ~row:View.hcat ~column:View.vcat
          ~panel:(fun _ (r : Ui_types.rect) -> View.rectangle ~width:r.width ~height:r.height ())) in
        ensure (View.width view = width && View.height view = height)
          (sprintf "%s %dx%d: tiles do not add up to the body" (Presets.name preset) width terminal_height))));
  print_endline "every preset at every size folds to a body-sized view";
  [%expect {| every preset at every size folds to a body-sized view |}]
