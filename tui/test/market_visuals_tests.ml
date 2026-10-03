open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

(* Fixture-driven checks for the Phase 5 market visuals: heatmap, tape, ladder depth,
   quantity deltas and the rule threshold. Everything here is MOCK fixture data. *)

let time seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds)
let truecolor = Theme.create Truecolor
let plain = Theme.create No_color

let identity ?(run_id = "run") id =
  { run_id; snapshot_id = Some id; decision_id = Some id; config_version = None }
let levels pairs = List.map pairs ~f:(fun (price_ticks, quantity_units) : level ->
    { price_ticks; quantity_units })
let snapshot ?(run_id = "run") ?(valid = true) id ~bids ~asks =
  { identity = identity ~run_id id; mode = Mock; instrument = "AAPL"
  ; bids = levels bids; asks = levels asks; valid; source = "MOCK fixture" }

let base_state () =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4.
  |> Or_error.ok_exn |> Mock_backend.state
let state_with ?(rules : rule list option) market =
  let state = base_state () in
  { state with market; rules = Option.value rules ~default:state.rules }

let show = Bonsai_term_test.print_view
let text_of ?(width = 80) ?(height = 20) view =
  Bonsai_test.Handle.show_into_string
    (Bonsai_term_test.create_handle_without_handler ~initial_dimensions:{ width; height }
       (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view))

(* ---- Heatmap colour ramp ---- *)

let hex (r, g, b) = sprintf "#%02X%02X%02X" r g b

let%expect_test "ramp runs dark, deep blue, cyan, amber, white and rises in luminance" =
  let luminance (r, g, b) = (2126 * r) + (7152 * g) + (722 * b) in
  let stops = List.map [ 0.; 0.25; 0.5; 0.75; 1. ] ~f:(Heatmap.ramp_rgb truecolor) in
  List.iter2_exn [ 0.; 0.25; 0.5; 0.75; 1. ] stops ~f:(fun at rgb ->
    printf "%.2f %s\n" at (hex rgb));
  let rising = List.is_sorted_strictly (List.map stops ~f:luminance) ~compare:Int.compare in
  printf "luminance strictly rising: %b; clamps: %s %s\n" rising
    (hex (Heatmap.ramp_rgb truecolor (-3.))) (hex (Heatmap.ramp_rgb truecolor 7.));
  [%expect {|
    0.00 #0B0E14
    0.25 #122C7A
    0.50 #2BC4D8
    0.75 #F5A623
    1.00 #FFFFFF
    luminance strictly rising: true; clamps: #0B0E14 #FFFFFF
    |}]

let%expect_test "ramp degrades through 256, 16 and no colour; no colour uses density glyphs" =
  List.iter [ Theme.Truecolor; Ansi256; Ansi16; No_color ] ~f:(fun capability ->
    let theme = Theme.create capability in
    printf "%-9s low %s high %s\n" (Sexp.to_string [%sexp (capability : Theme.capability)])
      (Sexp.to_string [%sexp (Heatmap.ramp_color theme 0. : Attr.Color.t option)])
      (Sexp.to_string [%sexp (Heatmap.ramp_color theme 1. : Attr.Color.t option)]));
  printf "glyphs |%s|\n"
    (String.concat (List.map [ 0.; 0.1; 0.3; 0.6; 0.9; 1. ] ~f:Heatmap.density_glyph));
  [%expect {|
    Truecolor low ((Rgb_888(11 14 20))) high ((Rgb_888(255 255 255)))
    Ansi256   low ((Palette_index 233)) high ((Palette_index 231))
    Ansi16    low ((Palette_index 0)) high ((Palette_index 15))
    No_color  low () high ()
    glyphs | ░▒▓██|
    |}]

let%expect_test "intensity is a power law above one, so thin liquidity stays near the background" =
  List.iter [ 0; 1; 25; 100 ] ~f:(fun quantity ->
    printf "%3d/100 -> %.2f\n" quantity (Heatmap.intensity ~quantity ~maximum:100));
  printf "empty scale -> %.2f\n" (Heatmap.intensity ~quantity:5 ~maximum:0);
  [%expect {|
      0/100 -> 0.00
      1/100 -> 0.00
     25/100 -> 0.12
    100/100 -> 0.61
    empty scale -> 0.00
    |}]

(* ---- Heatmap storage ---- *)

let book id = snapshot id ~bids:[ 1000, 10 + id; 999, 5 ] ~asks:[ 1001, 20; 1002, 7 ]
let observe_all snapshots = List.fold snapshots ~init:Heatmap.empty ~f:Heatmap.observe

let%expect_test "heatmap appends one column per snapshot without rebuilding older ones" =
  let first = observe_all [ book 1 ] in
  let second = Heatmap.observe first (book 2) in
  let older = List.hd_exn (Heatmap.columns first) in
  printf "columns %d then %d; first column shared: %b\n"
    (List.length (Heatmap.columns first)) (List.length (Heatmap.columns second))
    (phys_equal older (List.hd_exn (Heatmap.columns second)));
  [%expect {| columns 1 then 2; first column shared: true |}]

let%expect_test "heatmap ring is bounded and drops the oldest column first" =
  let many = observe_all (List.init (Heatmap.capacity + 44) ~f:(fun id -> book id)) in
  let ids = List.filter_map (Heatmap.columns many) ~f:(fun column -> column.snapshot_id) in
  printf "columns %d (capacity %d); oldest id %d; newest id %d\n" (List.length ids)
    Heatmap.capacity (List.hd_exn ids) (List.last_exn ids);
  [%expect {| columns 256 (capacity 256); oldest id 44; newest id 299 |}]

let%expect_test "heatmap resets on a new run and records invalid books as empty columns" =
  let t = observe_all [ book 1; book 2; book 3 ] in
  let t = Heatmap.observe t (snapshot ~valid:false 4 ~bids:[ 1000, 10 ] ~asks:[ 1001, 10 ]) in
  let invalid = List.last_exn (Heatmap.columns t) in
  printf "after invalid: %d columns, newest empty %b valid %b\n"
    (List.length (Heatmap.columns t)) (Array.is_empty invalid.prices) invalid.valid;
  let t = Heatmap.observe t (snapshot ~run_id:"next" 1 ~bids:[ 1000, 1 ] ~asks:[ 1001, 1 ]) in
  printf "after new run: %d column\n" (List.length (Heatmap.columns t));
  [%expect {|
    after invalid: 4 columns, newest empty true valid false
    after new run: 1 column
    |}]

(* The component must append on a changed snapshot only and reset when the run changes. *)
let component_handle initial =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 60; height = 14 }
    ~to_view_with_handler:(fun (_, _) -> ~view:View.none, ~handler:(fun _ -> Effect.Ignore))
    ~handle_incoming:(fun (_, set) state -> set state)
    (fun ~dimensions:_ (local_ graph) ->
      let open Bonsai.Let_syntax in
      let state, set = Bonsai.state initial graph in
      let heatmap = Heatmap.component ~state graph in
      let%arr heatmap and set in heatmap, set)

let%expect_test "heatmap component appends on a changed snapshot only, and resets on a new run" =
  let state_of snapshot = state_with snapshot in
  let handle = component_handle (state_of (book 1)) in
  let columns () =
    ignore (Bonsai_test.Handle.show_into_string handle : string);
    List.length (Heatmap.columns (fst (Bonsai_term_test.last_result handle))) in
  let step state = Bonsai_term_test.do_actions handle [ state ]; columns () in
  let first = columns () in
  let second = step (state_of (book 2)) in
  let unchanged = step (state_of (book 2)) in
  let third = step (state_of (book 3)) in
  let reset = step (state_of (snapshot ~run_id:"next" 1 ~bids:[ 1000, 1 ] ~asks:[ 1001, 1 ])) in
  printf "columns: %d %d %d %d reset %d\n" first second unchanged third reset;
  [%expect {| columns: 1 2 2 3 reset 1 |}]

(* ---- Heatmap rendering and markers ---- *)

let decision (snapshot : snapshot) ~outcome ~candidate_price =
  let candidate = Option.map candidate_price ~f:(fun price_ticks ->
      { identity = snapshot.identity; mode = Mock; rule_id = "slot-0"; side = Buy
      ; price_ticks; quantity_units = 1 }) in
  { identity = snapshot.identity; mode = Mock; rule_id = "slot-0"; inputs = snapshot
  ; maximum_price_ticks = 1002; quantity_units = 1; candidate; outcome
  ; occurred_at = time 0.; receipt_at = None; build_id = "m01"; slot = 0
  ; predicate_result = Some true
  ; bounds = { min_qty = 1; max_qty = 10; min_price_ticks = 900; max_price_ticks = 1100 } }

let wave =
  [ snapshot 1 ~bids:[ 1000, 40; 999, 10 ] ~asks:[ 1001, 12; 1002, 30 ]
  ; snapshot 2 ~bids:[ 1000, 60; 999, 10 ] ~asks:[ 1001, 80; 1002, 30 ]
  ; snapshot 3 ~bids:[ 1001, 20; 1000, 90 ] ~asks:[ 1002, 8; 1003, 55 ]
  ; snapshot 4 ~bids:[ 1001, 5; 1000, 90 ] ~asks:[ 1002, 8; 1003, 55 ] ]

let render_heatmap ?(theme = plain) ?(width = 40) ?(height = 13) heatmap =
  let state = state_with (List.last_exn wave) in
  show (Heatmap.view ~theme ~focus:Heatmap ~heatmap ~state ~width ~height)

let%expect_test "markers sit on the decision's snapshot column, on a rail under the map, in glyphs not colour" =
  let heatmap = observe_all wave in
  let heatmap = Heatmap.note_decision heatmap
      (decision (List.nth_exn wave 1) ~outcome:Admitted_result ~candidate_price:(Some 1001)) in
  let heatmap = Heatmap.note_decision heatmap
      (decision (List.nth_exn wave 2) ~outcome:(Blocked_result "MOCK qty") ~candidate_price:(Some 1003)) in
  let heatmap = Heatmap.note_decision heatmap
      (decision (List.nth_exn wave 3) ~outcome:No_signal_result ~candidate_price:None) in
  render_heatmap heatmap;
  [%expect {|
    ╭ Heatmap · AAPL · MOCK · scale 95 u ──╮
    │ qty 0 ░░░▒▒▓██ 95 u  ━ ask  ═ bid    │
    │     │                                │
    │ 1005┤                           ╌╌╌╌ │
    │ 1004┤                                │
    │     │                             ▒▒ │
    │ 1002┤                           ░░┏━ │
    │ 1001┤                           ━━┛═ │
    │ 1000┤                           ══╝▓ │
    │     │                           ░░   │
    │  dec┤                            ▲✗  │
    │   4 columns · 250 ms each · newest → │
    ╰──────────────────────────────────────╯
    |}]

let%expect_test "no colour paints density glyphs; colour paints the ramp instead" =
  let heatmap = observe_all wave in
  let text theme =
    let handle = Bonsai_term_test.create_handle_without_handler
        ~initial_dimensions:{ width = 40; height = 13 }
        (fun ~dimensions:_ (local_ _graph) ->
          Bonsai.return (Heatmap.view ~theme ~focus:Heatmap ~heatmap
            ~state:(state_with (List.last_exn wave)) ~width:40 ~height:13)) in
    Bonsai_test.Handle.show_into_string handle in
  let has glyphs text = List.exists glyphs ~f:(fun g -> String.is_substring text ~substring:g) in
  printf "no colour density glyphs: %b; truecolor density glyphs: %b\n"
    (has [ "░"; "▒"; "▓"; "█" ] (text plain)) (has [ "░"; "▒"; "▓"; "█" ] (text truecolor));
  [%expect {| no colour density glyphs: true; truecolor density glyphs: false |}]

let%expect_test "an empty heatmap says so and an invalid newest column is flagged" =
  render_heatmap Heatmap.empty;
  let invalid = snapshot ~valid:false 5 ~bids:[ 1000, 1 ] ~asks:[ 1001, 1 ] in
  render_heatmap (Heatmap.observe (observe_all wave) invalid);
  [%expect {|
    ╭ Heatmap · AAPL · MOCK · scale — u ───╮
    │ no liquidity observed yet            │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    │                                      │
    ╰──────────────────────────────────────╯
    ╭ Heatmap · AAPL · MOCK · scale 95 u ──╮
    │ qty 0 ░░░▒▒▓██ 95 u  ━ ask  ═ bid    │
    │     │                                │
    │ 1005┤                          ╌╌╌╌╌ │
    │ 1004┤                                │
    │     │                            ▒▒  │
    │     │                          ░░┏━  │
    │     │                          ━━┛═  │
    │ 1000┤                          ══╝▓  │
    │     │                          ░░    │
    │  dec┤                                │
    │ ← older      BOOK INVALID · 5 cols → │
    ╰──────────────────────────────────────╯
    |}]

(* ---- Ladder: threshold ---- *)

let ladder_snapshot =
  snapshot 7 ~bids:[ 1003, 40; 1002, 25; 1001, 10 ] ~asks:[ 1004, 12; 1005, 30; 1006, 18 ]

let rule_with ?(enabled = true) parameters : rule =
  { (List.hd_exn (base_state ()).rules) with enabled; parameters }

let ladder ?(cumulative = false) ?(motion = Market_motion.empty) ?(now = time 0.) state =
  Market_panel.view ~cumulative ~theme:plain ~focus:Market ~state ~motion ~now
    ~width:80 ~height:20

let%expect_test "the enabled rule's maximum_price is a dashed line between the asks it separates" =
  let state = state_with ladder_snapshot ~rules:[ rule_with [ "maximum_price", 1005, "t"; "quantity", 1, "u" ] ] in
  show (ladder state);
  [%expect {|
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │           40 ██████████████████  1003│ 1004 █████▋                  12       │
    │           25 ███████████▎        1002│ 1005 ██████████████▎         30       │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ │
    │           10 ████▌               1001│ 1006 ████████▌               18       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.54 ▲                                                            │
    │ no price history yet                                                         │
    │ MOCK #0  updates/s 0.0                                                       │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    |}]

let%expect_test "no threshold is drawn unless the rule is enabled, known and carries the parameter" =
  let draws state = String.is_substring ~substring:"╌╌" (text_of (ladder state)) in
  let make rules = state_with ladder_snapshot ~rules in
  let parameters = [ "maximum_price", 1005, "t" ] in
  printf "enabled %b; disabled %b; no parameter %b; no rules %b\n"
    (draws (make [ rule_with parameters ]))
    (draws (make [ rule_with ~enabled:false parameters ]))
    (draws (make [ rule_with [ "quantity", 1, "u" ] ]))
    (draws (make []));
  let unknown = { (make [ rule_with parameters ]) with engine = Engine_unknown } in
  let invalid = state_with { ladder_snapshot with valid = false } ~rules:[ rule_with parameters ] in
  let empty_asks = state_with { ladder_snapshot with asks = [] } ~rules:[ rule_with parameters ] in
  printf "engine unknown %b; invalid book %b; no asks %b\n"
    (draws unknown) (draws invalid) (draws empty_asks);
  [%expect {|
    enabled true; disabled false; no parameter false; no rules false
    engine unknown false; invalid book false; no asks false
    |}]

let%expect_test "the line sits above, between or below the asks according to its price" =
  List.iter [ 1003; 1005; 1010 ] ~f:(fun maximum ->
    let state = state_with ladder_snapshot ~rules:[ rule_with [ "maximum_price", maximum, "t" ] ] in
    printf "maximum_price %d\n" maximum;
    List.iter (List.sub (String.split_lines (text_of (ladder state))) ~pos:4 ~len:5)
      ~f:print_endline);
  [%expect {|
    maximum_price 1003
    ││ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1003 t ╌╌ ││
    ││           40 ██████████████████  1003│ 1004 █████▋                  12       ││
    ││           25 ███████████▎        1002│ 1005 ██████████████▎         30       ││
    ││           10 ████▌               1001│ 1006 ████████▌               18       ││
    ││ spread 1 t   mid 1003.5 t                                                    ││
    maximum_price 1005
    ││           40 ██████████████████  1003│ 1004 █████▋                  12       ││
    ││           25 ███████████▎        1002│ 1005 ██████████████▎         30       ││
    ││ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1005 t ╌╌ ││
    ││           10 ████▌               1001│ 1006 ████████▌               18       ││
    ││ spread 1 t   mid 1003.5 t                                                    ││
    maximum_price 1010
    ││           40 ██████████████████  1003│ 1004 █████▋                  12       ││
    ││           25 ███████████▎        1002│ 1005 ██████████████▎         30       ││
    ││           10 ████▌               1001│ 1006 ████████▌               18       ││
    ││ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1010 t ╌╌ ││
    ││ spread 1 t   mid 1003.5 t                                                    ││
    |}]

(* ---- Ladder: cumulative depth ---- *)

let%expect_test "cumulative depth sums from the best level outward and saturates" =
  let sums quantities = Market_panel.running_totals (levels (List.mapi quantities ~f:(fun i q -> 1000 + i, q))) in
  printf "%s\n" (Sexp.to_string [%sexp (sums [ 40; 25; 10 ] : int list)]);
  printf "%s\n" (Sexp.to_string [%sexp (sums [ Int.max_value; 5 ] : int list)]);
  printf "%s\n" (Sexp.to_string [%sexp (sums [] : int list)]);
  [%expect {|
    (40 65 75)
    (4611686018427387903 4611686018427387903)
    ()
    |}]

let%expect_test "cumulative mode shows running totals and scales the bars to the deepest total" =
  let state = state_with ladder_snapshot ~rules:[] in
  show (ladder state);
  show (ladder ~cumulative:true state);
  [%expect {|
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │           40 ██████████████████  1003│ 1004 █████▋                  12       │
    │           25 ███████████▎        1002│ 1005 ██████████████▎         30       │
    │           10 ████▌               1001│ 1006 ████████▌               18       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.54 ▲                                                            │
    │ no price history yet                                                         │
    │ MOCK #0  updates/s 0.0                                                       │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · cumulative qty (u)                                                  │
    │       cum(u) BID                px(t)│px(t) ASK                 cum(u)       │
    │           40 █████████▌          1003│ 1004 ███                     12       │
    │           65 ███████████████▌    1002│ 1005 ██████████▋             42       │
    │           75 ██████████████████  1001│ 1006 ███████████████▏        60       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.54 ▲                                                            │
    │ no price history yet                                                         │
    │ MOCK #0  updates/s 0.0                                                       │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    │                                                                              │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    |}]

(* ---- Ladder: quantity deltas ---- *)

let observed ~before ~after ~at =
  let first = Market_motion.observe Market_motion.empty ~now:(time 0.) ~snapshot:before ~updates:0 in
  Market_motion.observe first ~now:(time at) ~snapshot:after ~updates:1

let before = snapshot 1 ~bids:[ 1003, 40; 1002, 25 ] ~asks:[ 1004, 12; 1005, 30 ]
let after = snapshot 2 ~bids:[ 1003, 35; 1002, 25 ] ~asks:[ 1004, 24; 1005, 30 ]

let%expect_test "a delta is full strength at the change and gone after about one second" =
  let motion = observed ~before ~after ~at:10. in
  let bid = Option.value_exn (Market_motion.delta motion ~bid:true 1003) in
  let ask = Option.value_exn (Market_motion.delta motion ~bid:false 1004) in
  printf "bid change %d, ask change %d; unchanged level: %b\n" bid.change ask.change
    (Option.is_none (Market_motion.delta motion ~bid:true 1002));
  List.iter [ 10.; 10.25; 10.5; 10.9; 11.; 12. ] ~f:(fun seconds ->
    printf "%5.2fs intensity %.2f\n" seconds (Market_motion.delta_intensity ~now:(time seconds) ask));
  [%expect {|
    bid change -5, ask change 12; unchanged level: true
    10.00s intensity 1.00
    10.25s intensity 0.82
    10.50s intensity 0.55
    10.90s intensity 0.18
    11.00s intensity 0.00
    12.00s intensity 0.00
    |}]

let%expect_test "the first observation, invalid books and new runs produce no deltas" =
  let first = Market_motion.observe Market_motion.empty ~now:(time 0.) ~snapshot:before ~updates:0 in
  printf "first: %b\n" (Option.is_none (Market_motion.delta first ~bid:true 1003));
  let invalid = Market_motion.observe first ~now:(time 1.) ~updates:1
      ~snapshot:{ after with valid = false } in
  printf "invalid: %b\n" (Option.is_none (Market_motion.delta invalid ~bid:true 1003));
  let restored = Market_motion.observe invalid ~now:(time 2.) ~snapshot:after ~updates:2 in
  printf "restored change vs last valid book: %d\n"
    (Option.value_exn (Market_motion.delta restored ~bid:true 1003)).change;
  let next_run = Market_motion.observe restored ~now:(time 3.) ~updates:3
      ~snapshot:{ after with identity = identity ~run_id:"next" 1 } in
  printf "new run: %b\n" (Option.is_none (Market_motion.delta next_run ~bid:true 1003));
  [%expect {|
    first: true
    invalid: true
    restored change vs last valid book: -5
    new run: true
    |}]

let%expect_test "deltas render beside the levels with signs, and fade out of the render" =
  let motion = observed ~before ~after ~at:10. in
  let state = state_with after ~rules:[] in
  List.iter [ 10.; 10.5; 10.99; 11. ] ~f:(fun seconds ->
    printf "-- %.2fs\n" seconds;
    show (ladder ~motion ~now:(time seconds) state));
  [%expect {|
    -- 10.00s
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │    −5     35 ██████████████████  1003│ 1004 █████████████           24 +12   │
    │           25 ████████████▊       1002│ 1005 ████████████████▎       30       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.19 ▲                                                            │
    │    t ask 1004  bid 1003  mid 1003.5 ┄                                        │
    │ 1004┤                                                           ⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒ │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                           ⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄ │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │ 1003┤                                                           ⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤ │
    │      −60 s────────────────────────────−30 s──────────────────────────────now │
    │ MOCK #0  updates/s 1.0                                                       │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    -- 10.50s
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │    −5     35 ██████████████████  1003│ 1004 █████████████           24 +12   │
    │           25 ████████████▊       1002│ 1005 ████████████████▎       30       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.19 ▲                                                            │
    │    t ask 1004  bid 1003  mid 1003.5 ┄                                        │
    │ 1004┤                                                          ⠐⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠂ │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                           ⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄ │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │ 1003┤                                                          ⠠⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠄ │
    │      −60 s────────────────────────────−30 s──────────────────────────────now │
    │ MOCK #0  updates/s 1.0                                                       │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    -- 10.99s
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │    −5     35 ██████████████████  1003│ 1004 █████████████           24 +12   │
    │           25 ████████████▊       1002│ 1005 ████████████████▎       30       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.19 ▲                                                            │
    │    t ask 1004  bid 1003  mid 1003.5 ┄                                        │
    │ 1004┤                                                         ⠐⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠂  │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                          ⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄  │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │ 1003┤                                                         ⠠⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠄  │
    │      −60 s────────────────────────────−30 s──────────────────────────────now │
    │ MOCK #0  updates/s 1.0                                                       │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    -- 11.00s
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │           35 ██████████████████  1003│ 1004 █████████████           24       │
    │           25 ████████████▊       1002│ 1005 ████████████████▎       30       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.19 ▲                                                            │
    │    t ask 1004  bid 1003  mid 1003.5 ┄                                        │
    │ 1004┤                                                         ⠐⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠒⠂  │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                          ⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄  │
    │     │                                                                        │
    │     │                                                                        │
    │     │                                                                        │
    │ 1003┤                                                         ⠠⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠄  │
    │      −60 s────────────────────────────−30 s──────────────────────────────now │
    │ MOCK #0  updates/s 0.0                                                       │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    |}]

let%expect_test "delta colour is interpolated RGB from the background to the signed role" =
  List.iter [ 1.; 0.75; 0.5; 0.25; 0. ] ~f:(fun intensity ->
    printf "%.2f up %s down %s\n" intensity
      (hex (Market_panel.delta_rgb truecolor ~change:12 ~intensity))
      (hex (Market_panel.delta_rgb truecolor ~change:(-5) ~intensity)));
  [%expect {|
    1.00 up #3DD68C down #FF6B6B
    0.75 up #31A46E down #C25455
    0.50 up #247250 down #853D40
    0.25 up #184032 down #48252A
    0.00 up #0B0E14 down #0B0E14
    |}]

let%expect_test "delta text keeps its sign and never shows a clipped number" =
  List.iter [ 12; -5; 9999; -99999; 123456; Int.min_value ] ~f:(fun change ->
    printf "%d -> |%s|\n" change (Market_panel.delta_text change));
  [%expect {|
    12 -> |+12|
    -5 -> |−5|
    9999 -> |+9999|
    -99999 -> |−…|
    123456 -> |+…|
    -4611686018427387904 -> |−…|
    |}]

(* ---- Tape ---- *)

let top ?(valid = true) id ~bid ~ask =
  snapshot ~valid id ~bids:[ 1000, bid ] ~asks:[ 1001, ask ]

let tape_script =
  [ 0.0, top 1 ~bid:40 ~ask:30
  ; 0.1, top 2 ~bid:25 ~ask:30      (* bid 40 -> 25: a sell of 15 at 1000 *)
  ; 0.2, top 3 ~bid:25 ~ask:10      (* ask 30 -> 10: a buy of 20 at 1001 *)
  ; 0.3, top 4 ~bid:45 ~ask:10      (* quantity added: not a print *)
  ; 0.4, snapshot 5 ~bids:[ 1000, 45 ] ~asks:[ 1002, 50 ]   (* best ask moved: not a print *)
  ; 0.5, top ~valid:false 6 ~bid:1 ~ask:1
  ; 0.6, top 7 ~bid:5 ~ask:50       (* first valid book after a gap: baseline only *)
  ; 0.7, top 8 ~bid:2 ~ask:50 ]     (* bid 5 -> 2: a sell of 3 at 1000 *)

let run_tape script =
  List.fold script ~init:Tape_panel.empty ~f:(fun tape (at, snapshot) ->
    Tape_panel.observe tape ~now:(time at) ~snapshot)

let render_tape ?(width = 52) ?(height = 9) ?(now = time 5.) tape =
  show (Tape_panel.view ~theme:plain ~focus:Tape ~tape ~now ~width ~height)

let%expect_test "tape infers prints from top-of-book decreases, newest first" =
  let tape = run_tape tape_script in
  List.iter (Tape_panel.prints tape) ~f:(fun print ->
    printf "%.1fs %s %d x %d\n" (Time_ns.diff print.time Time_ns.epoch |> Time_ns.Span.to_sec)
      (match print.side with Buy -> "BUY " | Sell -> "SELL") print.price_ticks print.quantity_units);
  [%expect {|
    0.7s SELL 1000 x 3
    0.2s BUY  1001 x 20
    0.1s SELL 1000 x 15
    |}]

let%expect_test "tape aligns time, side, price and quantity and labels itself inferred" =
  let tape = run_tape tape_script in
  render_tape tape;
  render_tape Tape_panel.empty;
  [%expect {|
    ╭ Tape · MOCK · inferred from book deltas ─────────╮
    │ 60 s: buy 20 u · sell 18 u · net +2 u █████░░░░░ │
    │ time (UTC)    side    px(t)  qty(u) size         │
    │ 00:00:00.700  ▼ SELL   1000       3 █▋           │
    │ 00:00:00.200  ▲ BUY    1001      20 ███████████  │
    │ 00:00:00.100  ▼ SELL   1000      15 ████████▎    │
    │                                                  │
    │                                                  │
    ╰──────────────────────────────────────────────────╯
    ╭ Tape · — · inferred from book deltas ────────────╮
    │ no prints inferred yet                           │
    │                                                  │
    │                                                  │
    │                                                  │
    │                                                  │
    │                                                  │
    │                                                  │
    ╰──────────────────────────────────────────────────╯
    |}]

let%expect_test "tape columns stay aligned across digit widths and the buffer is bounded" =
  let wide =
    [ 0.0, snapshot 1 ~bids:[ 99999, 120000 ] ~asks:[ 100000, 5 ]
    ; 0.1, snapshot 2 ~bids:[ 99999, 100000 ] ~asks:[ 100000, 4 ]
    ; 0.2, snapshot 3 ~bids:[ 99999, 99999 ] ~asks:[ 100000, 4 ] ] in
  render_tape ~height:6 (run_tape wide);
  let churn = List.init 400 ~f:(fun i ->
      Float.of_int i /. 10., top (i + 1) ~bid:(1000 - i) ~ask:(1000 - i)) in
  let tape = run_tape churn in
  printf "prints kept %d (capacity %d); newest is the last observed: %b\n"
    (List.length (Tape_panel.prints tape)) Tape_panel.capacity
    (match Tape_panel.prints tape with
     | newest :: _ -> Time_ns.equal newest.time (time 39.9) | [] -> false);
  [%expect {|
    ╭ Tape · MOCK · inferred from book deltas ─────────╮
    │ 60 s: buy 1 u · sell 20001 u · net -20000 u      │
    │ time (UTC)    side     px(t)  qty(u) size        │
    │ 00:00:00.200  ▼ SELL   99999       1 ██████████  │
    │ 00:00:00.100  ▲ BUY   100000       1 ██████████  │
    ╰──────────────────────────────────────────────────╯
    prints kept 128 (capacity 128); newest is the last observed: true
    |}]

let%expect_test "tape resets on a new run so prints never cross runs" =
  let tape = run_tape (List.take tape_script 3) in
  let after_reset = Tape_panel.observe tape ~now:(time 9.)
      ~snapshot:(snapshot ~run_id:"next" 1 ~bids:[ 1000, 10 ] ~asks:[ 1001, 10 ]) in
  printf "before %d prints; after new run %d\n"
    (List.length (Tape_panel.prints tape)) (List.length (Tape_panel.prints after_reset));
  [%expect {| before 2 prints; after new run 0 |}]

let tape_handle initial =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 52; height = 9 }
    ~to_view_with_handler:(fun (_, _) -> ~view:View.none, ~handler:(fun _ -> Effect.Ignore))
    ~handle_incoming:(fun (_, set) state -> set state)
    (fun ~dimensions:_ (local_ graph) ->
      let open Bonsai.Let_syntax in
      let state, set = Bonsai.state initial graph in
      let tape = Tape_panel.component ~state graph in
      let%arr tape and set in tape, set)

let%expect_test "tape component infers prints from consecutive states" =
  let handle = tape_handle (state_with (top 1 ~bid:40 ~ask:30)) in
  let prints () =
    ignore (Bonsai_test.Handle.show_into_string handle : string);
    List.length (Tape_panel.prints (fst (Bonsai_term_test.last_result handle))) in
  let first = prints () in
  Bonsai_term_test.do_actions handle [ state_with (top 2 ~bid:25 ~ask:30) ];
  let second = prints () in
  Bonsai_term_test.do_actions handle [ state_with (top 2 ~bid:25 ~ask:30) ];
  let repeated = prints () in
  printf "prints: %d %d %d\n" first second repeated;
  [%expect {| prints: 0 1 1 |}]
