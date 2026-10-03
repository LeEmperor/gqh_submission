open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let state () =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4.
  |> Or_error.ok_exn |> Mock_backend.state
let render_market bids asks valid =
  let state = state () in
  let state = { state with market = { state.market with bids; asks; valid } } in
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width = 52; height = 13 }
      (fun ~dimensions:_ (local_ _graph) ->
        Bonsai.return (Market_panel.view ~cumulative:false ~theme ~focus:Market ~state ~motion:Market_motion.empty ~now:Time_ns.epoch ~width:52 ~height:13)) in
  Bonsai_test.Handle.show_into_string handle

let%expect_test "empty book shows missing metrics without fabricated prices" =
  let text = render_market [] [] true in
  printf "empty: %b; missing spread: %b; units: %b\n"
    (String.is_substring text ~substring:"BOOK EMPTY")
    (String.is_substring text ~substring:"spread —")
    (String.is_substring text ~substring:"qty (u)");
  print_string text;
  [%expect {|
    empty: true; missing spread: true; units: true
    ┌────────────────────────────────────────────────────┐
    │╭ Market · AAPL ───────────────────────────────────╮│
    ││ px (t) · qty (u)                                 ││
    ││       qty(u) BID  px(t)│px(t) ASK   qty(u)       ││
    ││            —          —│    —            —       ││
    ││ spread —   mid — · BOOK EMPTY                    ││
    ││ imbalance —                                      ││
    ││ no price history yet                             ││
    ││ MOCK #0  updates/s 0.0                           ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    │╰──────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────┘
    |}]

let%expect_test "one-sided book preserves the bid and marks absent ask" =
  let text = render_market [ { price_ticks = 1000; quantity_units = 40 } ] [] true in
  printf "bid: %b; absent ask: %b; missing mid: %b\n"
    (String.is_substring text ~substring:"1000")
    (String.is_substring text ~substring:"ASK EMPTY")
    (String.is_substring text ~substring:"mid —");
  print_string text;
  [%expect {|
    bid: true; absent ask: true; missing mid: true
    ┌────────────────────────────────────────────────────┐
    │╭ Market · AAPL ───────────────────────────────────╮│
    ││ px (t) · qty (u)                                 ││
    ││       qty(u) BID  px(t)│px(t) ASK   qty(u)       ││
    ││           40 ████  1000│    —            —       ││
    ││ spread —   mid — · ASK EMPTY                     ││
    ││ imbalance —                                      ││
    ││ no price history yet                             ││
    ││ MOCK #0  updates/s 0.0                           ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    │╰──────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────┘
    |}]

let%expect_test "invalid book overlays suppression status" =
  let text = render_market [ { price_ticks = 1000; quantity_units = 40 } ]
      [ { price_ticks = 1001; quantity_units = 12 } ] false in
  printf "invalid: %b; suppressed: %b\n"
    (String.is_substring text ~substring:"BOOK INVALID")
    (String.is_substring text ~substring:"candidates suppressed");
  print_string text;
  [%expect {|
    invalid: true; suppressed: true
    ┌────────────────────────────────────────────────────┐
    │╭ Market · AAPL ───────────────────────────────────╮│
    ││ px (t) · qty (u)                                 ││
    ││       qty(u) BID  px(t)│px(t) ASK   qty(u)       ││
    ││           40 ████  1000│ 1001 █▌        12       ││
    ││ spread —   mid —                                 ││
    ││ ╭──────────────────────────────────────────────╮ ││
    ││ │     BOOK INVALID — candidates suppressed     │ ││
    ││ ╰──────────────────────────────────────────────╯ ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    ││                                                  ││
    │╰──────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────┘
    |}]

let%expect_test "rules panel has readable predicate" =
  let view = Rules_panel.view ~theme ~focus:Rules ~state:(state ()) ~selected:(Some "slot-0") ~width:56 ~height:10 in
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width = 56; height = 10 }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  let text = Bonsai_test.Handle.show_into_string handle in
  printf "predicate: %b\n" (String.is_substring text
    ~substring:"ask_px ≤ maximum_price → BUY qty @ ask_px");
  print_string text;
  [%expect {|
    predicate: true
    ┌────────────────────────────────────────────────────────┐
    │╭ Rules ───────────────────────────────────────────────╮│
    ││ ▸ #0 buy_below_limit                            ● ON ││
    ││ ask_px ≤ maximum_price → BUY qty @ ask_px            ││
    ││ maximum_price 1005 t  quantity 1 u                   ││
    ││ matched  0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — ││
    ││ admitted 0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — ││
    ││ blocked  0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — ││
    ││ admit      ▕··································▏ none ││
    ││ cfg ✓ACK v12 · MOCK                                  ││
    │╰──────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────┘
    |}]

let time seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds)

let%expect_test "eighth-block bars scale to the largest displayed quantity" =
  List.iter [ 0; 1; 7; 8; 15; 16; 24; 32 ] ~f:(fun quantity ->
    printf "%2d |%s|\n" quantity
      (Market_panel.quantity_bar ~quantity ~maximum:32 ~width:4));
  [%expect {|
     0 |    |
     1 |▏   |
     7 |▉   |
     8 |█   |
    15 |█▉  |
    16 |██  |
    24 |███ |
    32 |████|
    |}]

let%expect_test "flash changes only with best prices and expires at 300 ms" =
  let snapshot = (state ()).market in
  let first = Market_motion.observe Market_motion.empty ~now:(time 0.) ~snapshot ~updates:0 in
  let quantities = { snapshot with bids = [ { (List.hd_exn snapshot.bids) with quantity_units = 99 } ] } in
  let same = Market_motion.observe first ~now:(time 1.) ~snapshot:quantities ~updates:1 in
  let changed_snapshot = { snapshot with
    bids = [ { price_ticks = 1001; quantity_units = 40 } ];
    asks = [ { price_ticks = 1002; quantity_units = 12 } ] } in
  let changed = Market_motion.observe same ~now:(time 2.) ~snapshot:changed_snapshot ~updates:2 in
  printf "initial %.2f; quantity-only %.2f\n"
    (Market_motion.flash_intensity ~now:(time 0.) first.bid_changed_at)
    (Market_motion.flash_intensity ~now:(time 1.) same.bid_changed_at);
  List.iter [ 2.; 2.12; 2.24; 2.30; 2.40 ] ~f:(fun seconds ->
    printf "%.2fs bid %.2f ask %.2f\n" seconds
      (Market_motion.flash_intensity ~now:(time seconds) changed.bid_changed_at)
      (Market_motion.flash_intensity ~now:(time seconds) changed.ask_changed_at));
  printf "updates/s %.1f; idle %.1f\n"
    (Market_motion.updates_per_second changed ~now:(time 2.25))
    (Market_motion.updates_per_second changed ~now:(time 4.));
  [%expect {|
    initial 0.00; quantity-only 0.00
    2.00s bid 0.25 ask 0.25
    2.12s bid 0.17 ask 0.17
    2.24s bid 0.08 ask 0.08
    2.30s bid 0.00 ask 0.00
    2.40s bid 0.00 ask 0.00
    updates/s 1.0; idle 0.0
    |}]

let%expect_test "sparkline uses a 60-second time axis and drops stale observations" =
  let sample time ask : Market_motion.sample = { time; bid = None; ask; delta_updates = 1 } in
  let samples = [ sample (time 60.) (Some 1001); sample (time 30.) (Some 1003)
                ; sample (time 0.) (Some 1000); sample (time (-1.)) (Some 9000) ] in
  printf "60s |%s|\n" (Sparkline.ask ~samples ~now:(time 60.) ~width:12);
  printf "expired |%s|\n" (Sparkline.ask ~samples ~now:(time 121.) ~width:12);
  let invalid = [ sample (time 60.) (Some 1001); sample (time 30.) None
                ; sample (time 0.) (Some 1000) ] in
  printf "gap |%s|\n" (Sparkline.ask ~samples:invalid ~now:(time 60.) ~width:12);
  [%expect {|
    60s |⣀⠤⠤⠒⠒⠉⠉⠒⠒⠒⠤⠤|
    expired |            |
    gap |⡀          ⠈|
    |}]

let%expect_test "history is bounded and a new run clears motion" =
  let snapshot = (state ()).market in
  let motion = List.fold (List.init 3661 ~f:Fn.id) ~init:Market_motion.empty
      ~f:(fun motion updates -> Market_motion.observe motion ~now:(time (Float.of_int updates /. 60.))
        ~snapshot ~updates) in
  printf "samples %d\n" (List.length motion.samples);
  let snapshot = { snapshot with identity = { snapshot.identity with run_id = "new-run" } } in
  let fresh = Market_motion.observe motion ~now:(time 62.) ~snapshot ~updates:0 in
  printf "new run samples %d, initial flash %.2f\n" (List.length fresh.samples)
    (Market_motion.flash_intensity ~now:(time 62.) fresh.ask_changed_at);
  [%expect {|
    samples 3601
    new run samples 1, initial flash 0.00
    |}]

let%expect_test "mock counters distinguish matches admissions and blocks" =
  List.iter [ "enabled"; "blocked"; "no_signal"; "connected_disarmed"; "book_invalid" ]
    ~f:(fun name ->
      let scenario = Mock_backend.scenario_of_string name |> Or_error.ok_exn in
      let state = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4.
          |> Or_error.ok_exn |> Mock_backend.advance |> Mock_backend.state in
      let rule = List.hd_exn state.rules in
      printf "%s: matched %d admitted %d blocked %d\n" name rule.matched rule.admitted rule.blocked);
  [%expect {|
    enabled: matched 1 admitted 1 blocked 0
    blocked: matched 1 admitted 0 blocked 1
    no_signal: matched 0 admitted 0 blocked 0
    connected_disarmed: matched 0 admitted 0 blocked 0
    book_invalid: matched 0 admitted 0 blocked 0
    |}]

let%expect_test "rules show off and unknown without implying unknown is disabled" =
  List.iter [ Mock_backend.Connected_disarmed; Connection_lost ] ~f:(fun scenario ->
    let state = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4.
      |> Or_error.ok_exn |> Mock_backend.state in
    let view = Rules_panel.view ~theme ~focus:Rules ~state ~selected:(Some "slot-0") ~width:56 ~height:8 in
    Bonsai_term_test.print_view view);
  [%expect {|
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                           ○ OFF │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ maximum_price 1005 t                                 │
    │ quantity         1 u                                 │
    │ matched 0  admitted 0  blocked 0                     │
    │ cfg ✓ACK v12 · MOCK                                  │
    ╰──────────────────────────────────────────────────────╯
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                       ? UNKNOWN │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ maximum_price 1005 t                                 │
    │ quantity         1 u                                 │
    │ matched 0  admitted 0  blocked 0                     │
    │ cfg ?UNKNOWN last v12 · MOCK                         │
    ╰──────────────────────────────────────────────────────╯
    |}]

let%expect_test "wide numbers remain complete and values beyond capacity are explicit" =
  List.iter [ 123456, 1000000; -123456, 1000000; Int.max_value, Int.max_value ]
    ~f:(fun (price_ticks, quantity_units) ->
      let state = state () in
      let level = { price_ticks; quantity_units } in
      let state = { state with market = { state.market with bids = [ level ]; asks = [ level ] } } in
      let view = Market_panel.view ~cumulative:false ~theme ~focus:Market ~state ~motion:Market_motion.empty
          ~now:Time_ns.epoch ~width:43 ~height:13 in
      Bonsai_term_test.print_view view);
  [%expect {|
    ╭ Market · AAPL ──────────────────────────╮
    │ px (t) · qty (u)                        │
    │  qty(u) BID   px(t)│ px(t) ASK   qty(u) │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ │
    │ 1000000 ████ 123456│123456 ████ 1000000 │
    │ spread 0 t   mid 123456.0 t             │
    │ imbalance +0.00 ·                       │
    │ ask                            last 60s │
    │ MOCK #0  updates/s 0.0                  │
    │                                         │
    │                                         │
    │                                         │
    ╰─────────────────────────────────────────╯
    ╭ Market · AAPL ──────────────────────────╮
    │ px (t) · qty (u)                        │
    │  qty(u) BID   px(t)│  px(t) ASK  qty(u) │
    │ 1000000 ███ -123456│-123456 ███ 1000000 │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ │
    │ spread 0 t   mid -123456.0 t            │
    │ imbalance +0.00 ·                       │
    │ ask                            last 60s │
    │ MOCK #0  updates/s 0.0                  │
    │                                         │
    │                                         │
    │                                         │
    ╰─────────────────────────────────────────╯
    ╭ Market · AAPL ──────────────────────────╮
    │ px (t) · qty (u)                        │
    │ qty/px overflow    │qty/px overflow     │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ │
    │ VALUE TOO WIDE     │VALUE TOO WIDE      │
    │ spread / mid exceed panel width         │
    │ imbalance +0.00 ·                       │
    │ ask                            last 60s │
    │ MOCK #0  updates/s 0.0                  │
    │                                         │
    │                                         │
    │                                         │
    ╰─────────────────────────────────────────╯
    |}]

let%expect_test "tick metrics preserve adjacent large integers and negative half ticks" =
  List.iter [ 9007199254740992, 9007199254740993; -1, 0; Int.min_value, Int.max_value ]
    ~f:(fun (bid, ask) ->
      let snapshot = (state ()).market in
      let snapshot = { snapshot with bids = [ { price_ticks = bid; quantity_units = 40 } ];
        asks = [ { price_ticks = ask; quantity_units = 12 } ] } in
      print_endline (fst (Market_panel.metrics snapshot)));
  let sample seconds price : Market_motion.sample = { time = time seconds; bid = None; ask = Some price; delta_updates = 1 } in
  let samples = [ sample 60. 9007199254740993; sample 0. 9007199254740992 ] in
  printf "large-price variation |%s|\n" (Sparkline.ask ~samples ~now:(time 60.) ~width:12);
  [%expect {|
    spread 1 t   mid 9007199254740992.5 t
    spread 1 t   mid -0.5 t
    spread 9223372036854775807 t   mid -0.5 t
    large-price variation |⣀⣀⠤⠤⠤⠤⠒⠒⠒⠒⠉⠉|
    |}]

let%expect_test "Rules parameters and counters wrap complete large numbers" =
  let state = state () in
  let rule = { (List.hd_exn state.rules) with parameters =
    [ "maximum_price", Int.max_value, "ticks"; "quantity", 1000000, "units" ];
    matched = Int.max_value; admitted = 1000000; blocked = 999999 } in
  let state = { state with rules = [ rule ] } in
  Bonsai_term_test.print_view (Rules_panel.view ~theme ~focus:Rules ~state
    ~selected:(Some rule.rule_id) ~width:56 ~height:10);
  [%expect {|
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                            ● ON │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ slot-0 · config v12                                  │
    │ maximum_price 4611686018427387903 t                  │
    │ quantity                  1000000 u                  │
    │ matched 4611686018427387903  admitted 1000000        │
    │ blocked 999999                                       │
    │ cfg ✓ACK v12 · MOCK                                  │
    ╰──────────────────────────────────────────────────────╯
    |}]
