open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
open Mock_backend
module Effect = Bonsai_term.Effect

let theme = Theme.create No_color
let clock = "13:37:02"
let fixture scenario =
  Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn
let state scenario = Mock_backend.state (fixture scenario)
let contains text substring = String.is_substring text ~substring
let ensure condition message = if not condition then failwith message
let key ?(mods = []) key = Event.Key_press { key; mods }

(* Demo shows every panel the original dashboard did, plus Metrics and Latency. *)
let handle ?(initial = state Connected_disarmed) ?(exit = fun () -> Effect.Ignore)
    ?(preset = Ui_types.Demo) dimensions =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
    ~to_view_with_handler:fst
    ~handle_incoming:(fun (_, inject) state -> inject state)
    (fun ~dimensions (local_ graph) ->
      let state, inject = Bonsai.state initial graph in
      let ~view, ~handler = App.component ~initial_preset:preset ~theme ~state ~clock:(Bonsai.return clock)
          ~exit ~dimensions graph in
      let%arr view and handler and inject in
      ((~view, ~handler), inject))

let screen handle = Handle.show_into_string handle
let expect_focus handle name =
  let text = screen handle in
  ensure (contains text ("focus: " ^ name)) ("Wrong focus: " ^ name);
  print_endline name

(* Catches broken wraparound in either focus direction. Tab walks the preset's panels in
   screen order: Demo's left column, then its right column. *)
let%expect_test "tab visits every Demo panel and wraps" =
  let handle = handle { width = 100; height = 30 } in
  expect_focus handle "Market";
  List.iter [ "Decisions"; "Metrics"; "Rules"; "Inspector"; "Configuration"; "Latency"; "Market" ]
    ~f:(fun focus -> Bonsai_term_test.send_event handle (key Tab); expect_focus handle focus);
  Bonsai_term_test.send_event handle (key ~mods:[ Shift ] Tab);
  expect_focus handle "Latency";
  Bonsai_term_test.send_event handle (key (ASCII '2'));
  expect_focus handle "Rules";
  [%expect {|
    Market
    Decisions
    Metrics
    Rules
    Inspector
    Configuration
    Latency
    Market
    Latency
    Rules
  |}]

(* Catches missing mode, identity, link, acknowledgment, safety, loss, or clock. *)
let%expect_test "header includes every required field in each mode" =
  List.iter [ Mock; Simulation; Hardware ] ~f:(fun mode ->
    let state = { (state Connected_disarmed) with mode } in
    Bonsai_term_test.print_view (Status_bar.view ~theme ~state ~clock ~width:120));
  [%expect {|
    tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ○ DISARMED │ book ✓VALID │ trace loss 0 │ 13:37:02 UTC
    tickweave ▸ SIM UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ○ DISARMED │ book ✓VALID │ trace loss 0 │ 13:37:02 UTC
    tickweave ▸ HW UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ○ DISARMED │ book ✓VALID │ trace loss 0 │ 13:37:02 UTC
    |}]

(* Catches optimistic acknowledgment and treating unknown as disarmed. *)
let%expect_test "header preserves lifecycle status and last acknowledged version" =
  List.iter [ Update_pending; Update_failed; Connection_lost; Book_invalid ] ~f:(fun scenario ->
    let state = state scenario in
    let text = screen (handle ~initial:state { width = 100; height = 30 }) in
    let wanted = match scenario with
      | Update_pending -> "cfg ◐APPLYING(write) last v12"
      | Update_failed -> "cfg ✗FAILED last v12"
      | Connection_lost -> "cfg ?UNKNOWN last v12"
      | Book_invalid -> "book ✗INVALID"
      | _ -> assert false
    in
    ensure (contains text wanted) wanted;
    if equal_engine state.engine Engine_unknown then (
      ensure (contains text "MOCK LOST") "Lost connection missing";
      ensure (not (contains text "DISARMED")) "Unknown shown as disarmed");
    print_endline wanted);
  [%expect {|
    cfg ◐APPLYING(write) last v12
    cfg ✗FAILED last v12
    cfg ?UNKNOWN last v12
    book ✗INVALID
  |}]

(* Catches overlap/clipping and state loss when the terminal is resized. *)
let%expect_test "resize keeps all panels and controls at both supported sizes" =
  let handle = handle { width = 120; height = 36 } in
  Bonsai_term_test.send_event handle (key (ASCII '4'));
  List.iter [ 120, 36; 100, 30; 120, 36 ] ~f:(fun (width, height) ->
    Bonsai_term_test.set_dimensions handle { width; height };
    let text = screen handle in
    let dimensions = Bonsai_term_test.last_dimensions handle in
    ensure (Dimensions.equal dimensions { width; height }) "Layout exceeds terminal";
    List.iter [ "Market · AAPL"; "Rules"; "Decisions"; "Inspector"; "Configuration"
              ; "Tab/⇧Tab focus"; "1–5 panel"; "? help"; "q quit"; "focus: Inspector"
              ; "MOCK"; "build m01"; "run demo-03"; "book ✓VALID"; "loss 0" ]
      ~f:(fun label -> ensure (contains text label) ("Missing control or panel: " ^ label));
    printf "%dx%d: five panels, controls visible, Inspector focus preserved\n" width height);
  [%expect {|
    120x36: five panels, controls visible, Inspector focus preserved
    100x30: five panels, controls visible, Inspector focus preserved
    120x36: five panels, controls visible, Inspector focus preserved
  |}]

(* Catches dashboard shortcuts leaking through help, or resize hiding the overlay. *)
let%expect_test "help captures focus shortcuts and escape restores the dashboard" =
  let handle = handle { width = 120; height = 36 } in
  Bonsai_term_test.send_event handle (key (ASCII '?'));
  Bonsai_term_test.send_event handle (key Tab);
  Bonsai_term_test.send_event handle (key (ASCII '5'));
  Bonsai_term_test.set_dimensions handle { width = 100; height = 30 };
  let text = screen handle in
  ensure (contains text "Help · Phase 5 / MOCK") "Help missing";
  List.iter [ "Shift-Tab"; "1 Market"; "5 Configuration"; "Ctrl-C"; "Esc" ]
    ~f:(fun binding -> ensure (contains text binding) ("Hidden binding: " ^ binding));
  print_endline "Help remains visible after resize";
  Bonsai_term_test.send_event handle (key Escape);
  ensure (not (contains (screen handle) "Help · Phase 5")) "Help stayed open";
  expect_focus handle "Market";
  [%expect {|
    Help remains visible after resize
    Market
  |}]

let%expect_test "undersized terminal gives a useful resize message and recovers" =
  let handle = handle { width = 80; height = 24 } in
  let message = screen handle in
  ensure (contains message "Resize to at least 100×30" && contains message "now 80×24")
    "Resize warning missing";
  Bonsai_term_test.set_dimensions handle { width = 100; height = 30 };
  ensure (contains (screen handle) "Configuration") "Panels did not recover";
  print_endline "Resize warning at 80x24; dashboard restored at 100x30";
  [%expect {| Resize warning at 80x24; dashboard restored at 100x30 |}]

let%expect_test "market arrival changes snapshot identity without stealing focus" =
  let initial = fixture Enabled in
  let handle = handle ~initial:(Mock_backend.state initial) { width = 100; height = 30 } in
  Bonsai_term_test.send_event handle (key (ASCII '3'));
  let next = Mock_backend.advance initial in
  Bonsai_term_test.do_actions handle [ Mock_backend.state next ];
  let text = screen handle in
  ensure (contains text "MOCK #1") "Market update not rendered";
  expect_focus handle "Decisions";
  [%expect {| Decisions |}]

let%expect_test "quit during applying needs explicit confirmation" =
  let exits = ref 0 in
  let exit () = Effect.of_thunk (fun () -> incr exits) in
  let handle = handle ~initial:(state Update_pending) ~exit { width = 100; height = 30 } in
  Bonsai_term_test.send_event handle (key (ASCII 'q'));
  ensure (contains (screen handle) "Quit · apply in flight") "Confirmation missing";
  ensure (!exits = 0) "Exited before confirmation";
  Bonsai_term_test.send_event handle (key Escape);
  ignore (screen handle : string);
  ensure (!exits = 0) "Escape quit";
  Bonsai_term_test.send_event handle (key (ASCII 'q'));
  ignore (screen handle : string);
  Bonsai_term_test.send_event handle (key (ASCII 'y'));
  ignore (screen handle : string);
  ensure (!exits = 1) "Confirmation did not quit";
  print_endline "No premature exit; Esc dismisses; y confirms once";
  [%expect {| No premature exit; Esc dismisses; y confirms once |}]

let%expect_test "mock stream is seeded and identities remain attached" =
  let run seed =
    let initial = Mock_backend.create ~scenario:Enabled ~seed ~rate_hz:4. |> Or_error.ok_exn in
    List.init 20 ~f:Fn.id |> List.folding_map ~init:initial ~f:(fun backend _ ->
      let next = Mock_backend.advance backend in
      next, Mock_backend.state next)
  in
  let first = run 42 and second = run 42 and other = run 43 in
  ensure (List.equal equal_application_state first second) "Same seed diverged";
  ensure (not (List.equal equal_application_state first other)) "Different seeds did not vary";
  List.iteri first ~f:(fun index state ->
    let identity = state.market.identity in
    ensure (String.equal identity.run_id "demo-03") "Run identity lost";
    ensure (Option.equal Int.equal identity.snapshot_id (Some (index + 1))) "Snapshot identity lost";
    ensure (Option.equal Int.equal identity.config_version (Some 12)) "Config version drifted";
    ensure (Option.is_none identity.decision_id) "Fabricated decision identity";
    ensure (equal_mode state.mode Mock && equal_mode state.market.mode Mock) "Mock provenance lost");
  print_endline "20 reproducible snapshots; distinct seed varies; run/version/MOCK preserved";
  List.iter [ 0.; -1.; 1e-300; 0.01; Float.nan; Float.infinity; 61. ] ~f:(fun rate_hz ->
    ensure (Or_error.is_error (Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz)) "Invalid rate accepted");
  print_endline "Invalid rates rejected";
  [%expect {|
    20 reproducible snapshots; distinct seed varies; run/version/MOCK preserved
    Invalid rates rejected
  |}]

let%expect_test "all scenario fixtures remain visibly mock" =
  List.iter Mock_backend.scenarios ~f:(fun (name, scenario) ->
    let text = screen (handle ~initial:(state scenario) { width = 100; height = 30 }) in
    ensure (contains text "MOCK") "Fixture lost provenance";
    printf "%s: MOCK\n" name);
  [%expect {|
    connected_disarmed: MOCK
    enabled: MOCK
    no_signal: MOCK
    admitted: MOCK
    blocked: MOCK
    received: MOCK
    update_pending: MOCK
    update_failed: MOCK
    connection_lost: MOCK
    book_invalid: MOCK
    update_ok: MOCK
    fail_at_idle: MOCK
    fail_at_verify: MOCK
    lost_at_activate: MOCK
    stale_base: MOCK
  |}]

(* Catches lost focus transitions when key events share a rendering frame. *)
let%expect_test "batched tabs use the latest focus state" =
  let handle = handle { width = 100; height = 30 } in
  List.iter [ Event.Key.Tab; Event.Key.Tab; Event.Key.Tab ] ~f:(fun event -> Bonsai_term_test.send_event handle (key event));
  expect_focus handle "Rules";
  [%expect {| Rules |}]

let%expect_test "help quit keys exit or request applying confirmation" =
  List.iter [ Connected_disarmed; Update_pending ] ~f:(fun scenario ->
    let exits = ref 0 in
    let exit () = Effect.of_thunk (fun () -> incr exits) in
    let handle = handle ~initial:(state scenario) ~exit { width = 100; height = 30 } in
    Bonsai_term_test.send_event handle (key (ASCII '?'));
    Bonsai_term_test.send_event handle (key ~mods:[ Ctrl ] (ASCII 'c'));
    let text = screen handle in
    match scenario with
    | Connected_disarmed ->
      ensure (!exits = 1) "Ctrl-C from help ignored";
      print_endline "Help + Ctrl-C quits"
    | Update_pending ->
      ensure (!exits = 0 && contains text "Quit · apply in flight") "Help quit skipped confirmation";
      print_endline "Help + Ctrl-C asks for applying confirmation"
    | _ -> assert false);
  [%expect {|
    Help + Ctrl-C quits
    Help + Ctrl-C asks for applying confirmation
  |}]

(* Exercises the real live Clock.every -> Async next -> state injection path. *)
let%expect_test "live Async stream advances at its configured period under help" =
  let _scheduler = Async.Scheduler.t () in
  (* The two-column help box spans 95 columns; at 160 wide the Market counter stays visible. *)
  let handle = Bonsai_term_test.create_handle
      ~initial_dimensions:{ width = 160; height = 45 }
      (App.live ~initial_preset:Demo (module Mock_backend) ~theme ~backend:(fixture Enabled)
         ~exit:(fun () -> Effect.Ignore)) in
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.017);
  ensure (contains (screen handle) "MOCK #0") "Initial snapshot missing";
  Bonsai_term_test.send_event handle (key (ASCII '?'));
  ignore (screen handle : string);
  for snapshot = 1 to 2 do
    Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.25);
    Handle.recompute_view_until_stable handle;
    Async.Scheduler.External.run_cycles_until_determined
      (Async.Scheduler.yield_until_no_jobs_remain ());
    Handle.recompute_view_until_stable handle;
    (* The throttle releases the new snapshot's view on the next 60 Hz tick. *)
    Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.017);
    let text = screen handle in
    ensure (contains text (sprintf "MOCK #%d" snapshot)) ("Live timer did not deliver snapshot: " ^ String.concat ~sep:" / " (List.take (String.split_lines text) 3));
    ensure (contains text "Help · Phase 5 / MOCK") "Stream closed overlay";
    printf "Snapshot #%d at %.2fs; help remains open\n" snapshot (Float.of_int snapshot *. 0.25)
  done;
  [%expect {|
    Snapshot #1 at 0.25s; help remains open
    Snapshot #2 at 0.50s; help remains open
  |}]

let%expect_test "uppercase Ctrl-C encoding also exits" =
  let exits = ref 0 in
  let exit () = Effect.of_thunk (fun () -> incr exits) in
  let handle = handle ~exit { width = 100; height = 30 } in
  Bonsai_term_test.send_event handle (key ~mods:[ Ctrl ] (ASCII 'C'));
  ignore (screen handle : string);
  printf "Exit count: %d\n" !exits;
  [%expect {| Exit count: 1 |}]

let%expect_test "minimum size shell snapshot" =
  let handle = handle { width = 100; height = 30 } in
  Handle.show handle;
  [%expect {|
    ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ○ DISARMED │ book ✓VALID │ loss 0    │
    │╭ Market · AAPL ─────────────────────────────────╮╭ Rules ─────────────────────────────────────────╮│
    ││ px (t) · qty (u)                               ││ ▸ #0 buy_below_limit                     ○ OFF ││
    ││       qty(u) BID px(t)│px(t) ASK  qty(u)       ││ ask_px ≤ maximum_price → BUY qty @ ask_px      ││
    ││           34 █▎   1003│ 1005 █▊       35       ││ maximum_price 1005 t  quantity 1 u             ││
    ││           33 █▎   1002│ 1006 █▌       32       ││ matched 0  admitted 0  blocked 0               ││
    ││           39 █▍   1001│ 1007 █▊       36       ││ cfg ✓ACK v12 · MOCK                            ││
    ││           44 █▋   1000│ 1008 █▉       38       │╰────────────────────────────────────────────────╯│
    ││           49 █▊    999│ 1009 ██▏      42       │╭ Inspector ─────────────────────────────────────╮│
    ││           43 █▋    998│ 1010 ████     79       ││ Select a decision and press Enter to inspect   ││
    ││ spread 2 t   mid 1004.0 t                      ││ · MOCK                                         ││
    ││ imbalance -0.01 ▼                              ││                                                ││
    ││ ask                                 ⠠ last 60s ││                                                ││
    ││ MOCK #0  updates/s 0.0                         ││                                                ││
    │╰────────────────────────────────────────────────╯│                                                ││
    │╭ Decisions · MOCK · all ────────────────────────╮│                                                ││
    ││                                                │╰────────────────────────────────────────────────╯│
    ││                                                │╭ Configuration · MOCK ──────────────────────────╮│
    ││                                                ││ ✓ ACK v12 · engine ○ DISARMED                  ││
    ││                                                ││ apply · none in flight                         ││
    ││                                                ││ maximum_price 1005 t [995 ━━━━━━━━━●──── 1010] ││
    ││ MOCK · G live · / filter · Space pause         ││ quantity         1 u [1 ●────────────────── 5] ││
    │╰────────────────────────────────────────────────╯│ c review / apply                               ││
    │╭ Metrics · MOCK ────────────────────────────────╮╰────────────────────────────────────────────────╯│
    ││ dec/s  unknown · · no data · stream lost · ·   │╭ Latency · MOCK synthetic ──────────────────────╮│
    ││ admit  unknown · · no data · stream lost · ·   ││ ▁▂▅▅▇██│▆▆▅▄▄▃▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁│▁ ▁▁▁▁▁ ▁▁ ▁ ▁ ││
    ││ loss/s unknown · · no data · stream lost · ·   ││ 188 ns p50 233 ns            p99 366 ns 452 ns ││
    ││               └−60s ─────── −30s ──────── now  ││ MOCK synthetic, seed 42: not hardware          ││
    │╰────────────────────────────────────────────────╯╰────────────────────────────────────────────────╯│
    │Tab/⇧Tab focus  1–5 panel │ F1–F4 preset  z zoom │ ? help  q quit       Demo · amber · focus: Market│
    └────────────────────────────────────────────────────────────────────────────────────────────────────┘
    |}]

let%expect_test "rules selection follows stable IDs across reordered updates" =
  let initial = state Enabled in
  let first = List.hd_exn initial.rules in
  let second = { first with rule_id = "slot-1"; slot = 1; name = "second_rule" } in
  let initial = { initial with rules = [ first; second ] } in
  let handle = handle ~initial { width = 100; height = 30 } in
  ignore (screen handle : string);
  Bonsai_term_test.send_event handle (key (ASCII '2'));
  Bonsai_term_test.send_event handle (key (ASCII 'j'));
  ensure (contains (screen handle) "▸ #1 second_rule") "Did not select second rule";
  Bonsai_term_test.do_actions handle [ { initial with rules = [ second; first ] } ];
  ensure (contains (screen handle) "▸ #1 second_rule") "Update moved selected ID";
  Bonsai_term_test.send_event handle (key (ASCII '?'));
  Bonsai_term_test.send_event handle (key (ASCII 'k'));
  Bonsai_term_test.send_event handle (key Escape);
  ensure (contains (screen handle) "▸ #1 second_rule") "Help leaked movement";
  Bonsai_term_test.do_actions handle [ { initial with rules = [ first ] } ];
  ensure (contains (screen handle) "Selected rule unavailable") "Removal stole selection";
  Bonsai_term_test.send_event handle (key (ASCII 'g'));
  ensure (contains (screen handle) "▸ #0 buy_below_limit") "First shortcut failed";
  Bonsai_term_test.do_actions handle [ { initial with rules = [] } ];
  Bonsai_term_test.send_event handle (key (ASCII 'G'));
  ensure (contains (screen handle) "No compiled rules") "Empty rules failed";
  print_endline "ID survives reorder/help; removed ID is explicit; g/G handle empty list";
  [%expect {| ID survives reorder/help; removed ID is explicit; g/G handle empty list |}]
