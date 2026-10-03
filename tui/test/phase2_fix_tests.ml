open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let backend () = Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn
let state () = Mock_backend.state (backend ())
let series count =
  let _, states = List.fold (List.init count ~f:Fn.id) ~init:(backend (), [])
    ~f:(fun (backend, states) _ ->
      let backend = Mock_backend.advance backend in backend, Mock_backend.state backend :: states) in
  List.rev states
let best (levels : level list) = (List.hd_exn levels).price_ticks

(* Catches reintroducing header wrapping or cropping fields outside the width. *)
let%expect_test "header is one line at 100 and 80 columns" =
  List.iter [ 100; 80 ] ~f:(fun width ->
    let view = Status_bar.view ~theme ~state:(state ()) ~clock:"13:37:02.417" ~width in
    printf "%d columns: one line %b; fits %b\n" width (View.height view = 1) (View.width view <= width);
    Bonsai_term_test.print_view view);
  [%expect {|
    100 columns: one line true; fits true
    tickweave ▸ MOCK UP │ build m01 │ run demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ trace loss 0
    80 columns: one line true; fits true
    tickweave ▸ MOCK UP │ r demo-03 │ cfg ✓ACK v12 │ ● ARMED │ book ✓VALID │ loss 0
    |}]

(* Fails when levels/quantities/spread are static or mean reversion is removed. Quantities move
   at random, a few levels in each snapshot rather than every level in every one. *)
let%expect_test "seeded market varies its quantities and crosses the rule threshold" =
  let states = state () :: series 40 in
  let pairs = List.zip_exn (List.drop_last_exn states) (List.tl_exn states) in
  (* A level is its price: the touch moves, so a position is a different level each time. *)
  let quantities (market : snapshot) =
    Int.Map.of_alist_exn (List.map (market.bids @ market.asks) ~f:(fun level -> level.price_ticks, level.quantity_units)) in
  let changed_per_pair = List.map pairs ~f:(fun (before, after) ->
    let before = quantities before.market and after = quantities after.market in
    let held = Map.filter_mapi after ~f:(fun ~key ~data -> Option.map (Map.find before key) ~f:(fun was -> was, data)) in
    Map.count held ~f:(fun (was, now) -> was <> now), Map.length held) in
  let moving = List.count changed_per_pair ~f:(fun (changed, _) -> changed > 0) in
  let qty_changes = moving * 10 >= List.length pairs * 9
                    && List.for_all changed_per_pair ~f:(fun (changed, held) -> changed < held) in
  let spreads = List.map states ~f:(fun state -> best state.market.asks - best state.market.bids) in
  let crossings = List.count pairs ~f:(fun (a, b) ->
    not (Bool.equal (best a.market.asks > 1005) (best b.market.asks > 1005))) in
  let imbalance_values = List.map states ~f:(fun state -> snd (Market_panel.metrics state.market))
      |> List.dedup_and_sort ~compare:String.compare in
  let mean = List.sum (module Float) (series 400)
      ~f:(fun state -> Float.of_int (best state.market.bids)) /. 400. in
  printf "ten levels %b; some but not all quantities change each snapshot %b; imbalance varies %b\n"
    (List.for_all states ~f:(fun state -> List.length state.market.bids = 10 && List.length state.market.asks = 10))
    qty_changes (List.length imbalance_values > 10);
  printf "spread 1/2/3 %b; regular crossings %b; centered around 1003 %b\n"
    (List.for_all [ 1; 2; 3 ] ~f:(List.mem spreads ~equal:Int.equal))
    (crossings >= 4) (Float.(mean >= 1001. && mean <= 1005.));
  [%expect {|
    ten levels true; some but not all quantities change each snapshot true; imbalance varies true
    spread 1/2/3 true; regular crossings true; centered around 1003 true
  |}]

let%expect_test "enabled mock produces admitted blocked and no-signal evaluations" =
  let states = series 200 in
  let rule = List.hd_exn (List.last_exn states).rules in
  printf "admitted %b; blocked %b; no signal %b; counters reconcile %b\n"
    (rule.admitted > 0) (rule.blocked > 0) (rule.matched < 200)
    (rule.matched = rule.admitted + rule.blocked);
  [%expect {| admitted true; blocked true; no signal true; counters reconcile true |}]

let%expect_test "panels have one column of padding on both sides" =
  Bonsai_term_test.print_view (Panel.frame ~theme ~focus:Market ~panel:Market
    ~title:"pad" ~width:10 ~height:3 (View.text "123456"));
  [%expect {|
    ╭ pad ───╮
    │ 123456 │
    ╰────────╯
  |}]

let%expect_test "invalid book has a centered stamp box over its muted ladder" =
  let state = state () in
  let state = { state with market = { state.market with valid = false } } in
  Bonsai_term_test.print_view (Market_panel.view ~cumulative:false ~theme ~focus:Market ~state
    ~motion:Market_motion.empty ~now:Time_ns.epoch ~width:52 ~height:17);
  [%expect {|
    ╭ Market · AAPL ───────────────────────────────────╮
    │ px (t) · qty (u)                                 │
    │       qty(u) BID  px(t)│px(t) ASK   qty(u)       │
    │           34 ▉     1003│ 1005 █▏        35       │
    │           33 ▉     1002│ 1006 █▏        32       │
    │           39 █     1001│ 1007 █▎        36       │
    │           44 █▏    1000│ 1008 █▎        38       │
    │ ╭──────────────────────────────────────────────╮ │
    │ │     BOOK INVALID — candidates suppressed     │ │
    │ ╰──────────────────────────────────────────────╯ │
    │           39 █      996│ 1012 █▋        49       │
    │           58 █▋     995│ 1013 █▊        53       │
    │ spread —   mid —                                 │
    │ imbalance —                                      │
    │ ask                                     last 60s │
    │ MOCK #0  updates/s 0.0                           │
    ╰──────────────────────────────────────────────────╯
    |}]

let%expect_test "market renders all available rows up to ten" =
  (* With a rule enabled, one row goes to the maximum_price threshold line, so each height
     is a row taller than the depth it used to show. *)
  List.iter [ 15, 6; 18, 9; 20, 10 ] ~f:(fun (height, expected_depth) ->
    let state = state () in
    let view = Market_panel.view ~cumulative:false ~theme ~focus:Market ~state
      ~motion:Market_motion.empty ~now:Time_ns.epoch ~width:52 ~height in
    let bottom = (List.nth_exn state.market.bids (Int.min expected_depth (List.length state.market.bids) - 1)).price_ticks in
    let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width = 52; height }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
    let text = Bonsai_test.Handle.show_into_string handle in
    printf "%d rows: sufficient depth %b; metrics visible %b\n" height
      (List.length state.market.bids >= expected_depth && String.is_substring text ~substring:(Int.to_string bottom))
      (String.is_substring text ~substring:"updates/s");
    ignore (bottom : int));
  [%expect {|
    15 rows: sufficient depth true; metrics visible true
    18 rows: sufficient depth true; metrics visible true
    20 rows: sufficient depth true; metrics visible true
    |}]

let%expect_test "mock decisions retain inputs IDs and explicit block reasons" =
  let decisions = series 200 |> List.filter_map ~f:(fun state -> state.latest_decision) in
  let admitted = List.find_exn decisions ~f:(fun decision -> equal_decision_outcome decision.outcome Admitted_result) in
  let blocked = List.find_exn decisions ~f:(fun decision -> match decision.outcome with Blocked_result _ -> true | _ -> false) in
  let no_signal = List.find_exn decisions ~f:(fun decision -> equal_decision_outcome decision.outcome No_signal_result) in
  let correct_identity = List.for_all decisions ~f:(fun (decision : decision) ->
    Option.equal Int.equal decision.identity.snapshot_id decision.inputs.identity.snapshot_id
    && Option.is_some decision.identity.decision_id
    && String.equal decision.identity.run_id decision.inputs.identity.run_id
    && Option.equal Int.equal decision.identity.config_version (Some 12)
    && equal_mode decision.mode Mock) in
  let candidates = List.for_all decisions ~f:(fun decision -> match decision.candidate, decision.outcome with
    | None, No_signal_result -> best decision.inputs.asks > 1005
    | Some candidate, (Admitted_result | Blocked_result _) ->
      best decision.inputs.asks <= 1005 && candidate.price_ticks = best decision.inputs.asks
      && candidate.quantity_units = 1 && equal_identity candidate.identity decision.identity
    | _ -> false) in
  printf "correlated MOCK identity %b; candidates match recorded inputs %b\n" correct_identity candidates;
  printf "admitted ask %d t; no-signal ask %d t\n" (best admitted.inputs.asks) (best no_signal.inputs.asks);
  (match blocked.outcome with Blocked_result reason -> print_endline reason | _ -> assert false);
  [%expect {|
    correlated MOCK identity true; candidates match recorded inputs true
    admitted ask 1005 t; no-signal ask 1007 t
    price 1000 t outside [1001, 1005] t
    |}]

let%expect_test "invalid and disarmed books suppress mock evaluation" =
  List.iter [ Mock_backend.Book_invalid; Connected_disarmed; Connection_lost ] ~f:(fun scenario ->
    let backend = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
    let state = Mock_backend.advance backend |> Mock_backend.state in
    let rule = List.hd_exn state.rules in
    printf "evaluation absent %b; counters zero %b\n" (Option.is_none state.latest_decision)
      (rule.matched = 0 && rule.admitted = 0 && rule.blocked = 0));
  [%expect {|
    evaluation absent true; counters zero true
    evaluation absent true; counters zero true
    evaluation absent true; counters zero true
  |}]

let%expect_test "10-second seeded stream statistics" =
  let states = series 40 in
  let bids = List.map states ~f:(fun state -> best state.market.bids) in
  let asks = List.map states ~f:(fun state -> best state.market.asks) in
  let crossings = List.zip_exn (List.drop_last_exn asks) (List.tl_exn asks)
      |> List.count ~f:(fun (a, b) -> not (Bool.equal (a > 1005) (b > 1005))) in
  let rule = List.hd_exn (List.last_exn states).rules in
  printf "40 updates: bid %d..%d t, ask %d..%d t, threshold crossings %d\n"
    (List.min_elt bids ~compare:Int.compare |> Option.value_exn)
    (List.max_elt bids ~compare:Int.compare |> Option.value_exn)
    (List.min_elt asks ~compare:Int.compare |> Option.value_exn)
    (List.max_elt asks ~compare:Int.compare |> Option.value_exn) crossings;
  printf "matched %d admitted %d blocked %d no-signal %d\n" rule.matched rule.admitted rule.blocked (40 - rule.matched);
  Option.iter rule.last_block_reason ~f:print_endline;
  [%expect {|
    40 updates: bid 999..1006 t, ask 1000..1009 t, threshold crossings 11
    matched 22 admitted 19 blocked 3 no-signal 18
    price 1000 t outside [1001, 1005] t
    |}]

let%expect_test "narrow UNKNOWN and invalid headers never shorten loss numbers" =
  let state = Mock_backend.create ~scenario:Connection_lost ~seed:42 ~rate_hz:4.
    |> Or_error.ok_exn |> Mock_backend.state in
  List.iter [ 80; 100 ] ~f:(fun width ->
    List.iter [ 10; Int.max_value ] ~f:(fun trace_loss ->
      let state = { state with trace_loss; market = { state.market with valid = false } } in
      let view = Status_bar.view ~theme ~state ~clock:"13:37:02.417" ~width in
      let handle = Bonsai_term_test.create_handle_without_handler
        ~initial_dimensions:{ width; height = 1 }
        (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
      let text = Bonsai_test.Handle.show_into_string handle in
      printf "%d cols loss %d: one row %b; count whole or explicit %b; UNKNOWN %b\n"
        width trace_loss (View.height view = 1)
        (String.is_substring text ~substring:(sprintf "loss %d" trace_loss)
         || String.is_substring text ~substring:"loss TOO WIDE")
        (String.is_substring text ~substring:"UNKNOWN")));
  [%expect {|
    80 cols loss 10: one row true; count whole or explicit true; UNKNOWN true
    80 cols loss 4611686018427387903: one row true; count whole or explicit true; UNKNOWN true
    100 cols loss 10: one row true; count whole or explicit true; UNKNOWN true
    100 cols loss 4611686018427387903: one row true; count whole or explicit true; UNKNOWN true
  |}]
