open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

(* Phase 5 polish: the MOCK liquidity walk, the heatmap's scale, lines and fit, the price
   chart and the tape. Everything here is MOCK fixture data, never hardware evidence. *)

let time seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds)
let truecolor = Theme.create Truecolor
let plain = Theme.create No_color

let text_of view =
  Bonsai_test.Handle.show_into_string
    (Bonsai_term_test.create_handle_without_handler
       ~initial_dimensions:{ width = View.width view; height = View.height view }
       (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view))

(* ---- The MOCK liquidity walk ---- *)

let books ?(seed = 42) ?(rate_hz = 4.) count =
  let backend = Mock_backend.create ~scenario:Enabled ~seed ~rate_hz |> Or_error.ok_exn in
  let _, books = List.fold (List.init count ~f:Fn.id) ~init:(backend, [])
      ~f:(fun (backend, books) _ ->
        let backend = Mock_backend.advance backend in
        backend, (Mock_backend.state backend).market :: books) in
  List.rev books

let%expect_test "the walk is deterministic for a seed and differs between seeds" =
  let same = List.equal [%equal: snapshot] (books 120) (books 120) in
  let other = List.equal [%equal: snapshot] (books 120) (books ~seed:7 120) in
  printf "same seed same books: %b; other seed same books: %b\n" same other;
  [%expect {| same seed same books: true; other seed same books: false |}]

let%expect_test "the walk keeps ten contiguous levels a side with sizes in a bounded range" =
  let all = books ~rate_hz:60. 900 @ books 400 in
  let sizes = List.concat_map all ~f:(fun book ->
      List.map (book.bids @ book.asks) ~f:(fun level -> level.quantity_units)) in
  let contiguous (levels : level list) ~step =
    List.for_all (List.zip_exn (List.drop_last_exn levels) (List.tl_exn levels))
      ~f:(fun (a, b) -> b.price_ticks - a.price_ticks = step) in
  printf "ten a side %b; contiguous %b; sizes in [1, 600] %b\n"
    (List.for_all all ~f:(fun book -> List.length book.bids = 10 && List.length book.asks = 10))
    (List.for_all all ~f:(fun book -> contiguous book.bids ~step:(-1) && contiguous book.asks ~step:1))
    (List.for_all sizes ~f:(fun size -> size >= 1 && size <= 600));
  [%expect {| ten a side true; contiguous true; sizes in [1, 600] true |}]

(* The old generator drew every size afresh, so a price's size now said nothing about its
   size a snapshot later. The walk makes it the best predictor. *)
let same_price_pairs books =
  List.concat (List.map2_exn (List.drop_last_exn books) (List.tl_exn books)
      ~f:(fun before after ->
        let at (book : snapshot) = Int.Map.of_alist_reduce ~f:Int.max
            (List.map (book.bids @ book.asks) ~f:(fun level -> level.price_ticks, level.quantity_units)) in
        let after = at after in
        List.filter_map (Map.to_alist (at before)) ~f:(fun (price, size) ->
          Option.map (Map.find after price) ~f:(fun next -> Float.of_int size, Float.of_int next))))

let correlation pairs =
  let count = Float.of_int (List.length pairs) in
  let mean f = List.sum (module Float) pairs ~f /. count in
  let mx = mean fst and my = mean snd in
  let covariance = mean (fun (x, y) -> (x -. mx) *. (y -. my)) in
  covariance /. Float.sqrt (mean (fun (x, _) -> (x -. mx) ** 2.) *. mean (fun (_, y) -> (y -. my) ** 2.))

let%expect_test "a price keeps its size from one snapshot to the next" =
  let pairs = same_price_pairs (books 400) in
  printf "pairs %b; same-price correlation above 0.8: %b\n" (List.length pairs > 2000)
    Float.(correlation pairs > 0.8);
  [%expect {| pairs true; same-price correlation above 0.8: true |}]

(* Longest run of snapshots in which some single price rests above [factor] times the
   median size. A wall is exactly that: a band that persists across many columns. *)
let longest_band books ~factor =
  let sizes = List.concat_map books ~f:(fun (book : snapshot) ->
      List.map (book.bids @ book.asks) ~f:(fun level -> level.quantity_units))
      |> List.sort ~compare:Int.compare in
  let median = List.nth_exn sizes (List.length sizes / 2) in
  let heavy (book : snapshot) = List.filter_map (book.bids @ book.asks) ~f:(fun level ->
      Option.some_if Float.(of_int level.quantity_units > factor * of_int median)
        level.price_ticks) in
  let _, longest = List.fold books ~init:(Int.Map.empty, 0) ~f:(fun (runs, longest) book ->
      let runs = Int.Map.of_alist_exn (List.map (heavy book) ~f:(fun price ->
          price, 1 + Option.value (Map.find runs price) ~default:0)) in
      runs, Map.fold runs ~init:longest ~f:(fun ~key:_ ~data longest -> Int.max longest data)) in
  median, longest

let%expect_test "walls build into bands that persist for seconds, and decay" =
  let median, longest = longest_band (books 400) ~factor:3. in
  printf "median size %d; some price stays above 3x the median for at least 20 snapshots (5 s): %b; \
          but not for the whole run: %b\n"
    median (longest >= 20) (longest < 300);
  [%expect {| median size 43; some price stays above 3x the median for at least 20 snapshots (5 s): true; but not for the whole run: true |}]

(* ---- The heatmap's scale ---- *)

let snapshot ?(run_id = "run") ?(valid = true) id ~bids ~asks =
  let levels pairs = List.map pairs ~f:(fun (price_ticks, quantity_units) : level ->
      { price_ticks; quantity_units }) in
  { identity = { run_id; snapshot_id = Some id; decision_id = Some id; config_version = None }
  ; mode = Mock; instrument = "AAPL"; bids = levels bids; asks = levels asks; valid
  ; source = "MOCK fixture" }

let base_state () =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn |> Mock_backend.state
let state_with ?(rate_hz = 4.) market = { (base_state ()) with market; rate_hz }

let observe_all ?(rate_hz = 4.) snapshots =
  List.fold snapshots ~init:Heatmap.empty ~f:(fun heatmap snapshot ->
    Heatmap.observe_sampled heatmap ~rate_hz snapshot)

(* Twenty levels of 30 units, and one wall of 1000. *)
let walled =
  snapshot 1 ~bids:(List.init 10 ~f:(fun i -> 1000 - i, 30))
    ~asks:(List.init 10 ~f:(fun i -> 1001 + i, if i = 4 then 1000 else 30))

let%expect_test "the scale is not the largest size: one wall does not black out the rest" =
  let columns = Heatmap.visible (observe_all [ walled ]) ~count:10 in
  let used = Heatmap.scale columns ~bottom:990 ~top:1010 in
  printf "scale %d u (largest 1000 u); a 30 u level reads %.2f; the wall reads %.2f\n" used
    (Heatmap.intensity ~quantity:30 ~maximum:used) (Heatmap.intensity ~quantity:1000 ~maximum:used);
  let outside = Heatmap.scale columns ~bottom:990 ~top:1004 in
  printf "with the wall out of the window the scale is %d u\n" outside;
  [%expect {|
    scale 93 u (largest 1000 u); a 30 u level reads 0.16; the wall reads 1.00
    with the wall out of the window the scale is 93 u
    |}]

let%expect_test "a book with no walls stays cool: its ordinary noise stays blue, never cyan, amber or white" =
  (* Sizes 30 to 57 with a few units of noise: the 95th percentile alone would stretch
     them over the whole ramp, as confetti. *)
  let noisy id = snapshot id
      ~bids:(List.init 10 ~f:(fun i -> 1000 - i, 30 + (3 * i) + (id * 7 + i * 3) % 5))
      ~asks:(List.init 10 ~f:(fun i -> 1001 + i, 30 + (3 * i) + (id * 5 + i * 2) % 5)) in
  let columns = Heatmap.visible (observe_all (List.init 40 ~f:noisy)) ~count:40 in
  let used = Heatmap.scale columns ~bottom:990 ~top:1010 in
  let grid = Heatmap.grid columns ~bottom:990 ~top:1010 ~maximum:used ~threshold:None in
  let buckets = Array.concat_map grid ~f:(fun row -> Array.map row ~f:Heatmap.bucket_of) in
  let hottest = Array.fold buckets ~init:0 ~f:Int.max in
  printf "scale %d u; resting cells %d; hottest cell is bucket %d, ramp %.2f\n" used
    (Array.count buckets ~f:(fun bucket -> bucket > 0)) hottest (Heatmap.bucket_intensity hottest);
  if Float.(Heatmap.bucket_intensity hottest >= 0.5) then failwith "ordinary noise reached cyan";
  [%expect {| scale 141 u; resting cells 800; hottest cell is bucket 3, ramp 0.21 |}]

let%expect_test "the percentile bins are within 9 percent of the exact percentile" =
  let sizes = List.init 1000 ~f:(fun i -> 1 + (i * 37 % 997) * 3) in
  let counts = Array.create ~len:Heatmap.bins 0 in
  List.iter sizes ~f:(fun size -> let bin = Heatmap.bin_of size in counts.(bin) <- counts.(bin) + 1);
  List.iter [ 50; 95 ] ~f:(fun percent ->
    let used = Heatmap.percentile counts ~total:1000 ~percent in
    let exact = List.nth_exn (List.sort sizes ~compare:Int.compare) ((percent * 10) - 1) in
    printf "p%d exact %d, binned %d, within 9%%: %b, never below: %b\n" percent exact used
      Float.(abs (of_int used - of_int exact) /. of_int exact < 0.09) (used >= exact));
  [%expect {|
    p50 exact 1489, binned 1535, within 9%: true, never below: true
    p95 exact 2839, binned 3071, within 9%: true, never below: true
    |}]

let%expect_test "size climbs the ramp in even steps, and only 1.5x the scale reaches white" =
  List.iter [ 0; 1; 20; 40; 57; 85; 100; 120; 149; 150; 400 ] ~f:(fun quantity ->
    printf "%3d/100 -> bucket %2d of %d, ramp %.2f\n" quantity (Heatmap.bucket_for ~maximum:100 quantity)
      (Heatmap.buckets - 1) (Heatmap.bucket_intensity (Heatmap.bucket_for ~maximum:100 quantity)));
  [%expect {|
      0/100 -> bucket  0 of 11, ramp 0.00
      1/100 -> bucket  1 of 11, ramp 0.05
     20/100 -> bucket  1 of 11, ramp 0.05
     40/100 -> bucket  3 of 11, ramp 0.21
     57/100 -> bucket  4 of 11, ramp 0.30
     85/100 -> bucket  6 of 11, ramp 0.48
    100/100 -> bucket  7 of 11, ramp 0.58
    120/100 -> bucket  9 of 11, ramp 0.76
    149/100 -> bucket 10 of 11, ramp 0.85
    150/100 -> bucket 11 of 11, ramp 1.00
    400/100 -> bucket 11 of 11, ramp 1.00
    |}]

(* ---- The heatmap's lines, fit, rail and pace ---- *)

let render ?(theme = plain) ?(width = 40) ?(height = 14) ?(rate_hz = 4.) heatmap snapshot =
  Bonsai_term_test.print_view
    (Heatmap.view ~theme ~focus:Heatmap ~heatmap ~state:(state_with ~rate_hz snapshot) ~width ~height)

(* The bid walks 1000, 1000, 1001, 1001, 1000, 1000 with the ask one tick above. *)
let walk_snapshots =
  List.mapi [ 1000; 1000; 1001; 1001; 1000; 1000 ] ~f:(fun i bid ->
    snapshot i ~bids:[ bid, 20; bid - 1, 20 ] ~asks:[ bid + 1, 20; bid + 2, 20 ])

let%expect_test "the best bid and ask are unbroken stepped lines in different glyph families" =
  let snapshots = walk_snapshots in
  render (observe_all snapshots) (List.last_exn snapshots);
  [%expect {|
    ╭ Heatmap · AAPL · MOCK · scale 63 u ──╮
    │ qty 0 ░░░▒▒▓██ 63 u  ━ ask  ═ bid    │
    │ 1004┤                                │
    │     │                           ░░   │
    │     │                         ░░┏━┓░ │
    │ 1001┤                         ━━┛═┗━ │
    │ 1000┤                         ══╝░╚═ │
    │     │                         ░░  ░░ │
    │     │                                │
    │     │                                │
    │  996┤                                │
    │  dec┤                                │
    │   6 columns · 250 ms each · newest → │
    ╰──────────────────────────────────────╯
    |}]

let ink_range ~low ~high cell = let ink = Heatmap.ink_of cell in ink >= low && ink <= high
let is_bid_ink = ink_range ~low:2 ~high:7
let is_ask_ink = ink_range ~low:8 ~high:13

let%expect_test "every column carries a bid line and an ask line, joined to the one before it" =
  let churn = List.init 24 ~f:(fun i ->
      let bid = 1000 + (i * 7 % 5) - 2 in
      snapshot i ~bids:[ bid, 20; bid - 1, 20 ] ~asks:[ bid + 1 + (i % 2), 20; bid + 3 + (i % 2), 20 ]) in
  let columns = Heatmap.visible (observe_all churn) ~count:24 in
  let grid = Heatmap.grid columns ~bottom:990 ~top:1010 ~maximum:20 ~threshold:None in
  let rows_with grid x ~f = List.filter (List.range 0 (Array.length grid)) ~f:(fun row -> f grid.(row).(x)) in
  let columns_with f = List.count (List.range 0 24) ~f:(fun x -> not (List.is_empty (rows_with grid x ~f))) in
  (* Where the previous column's line stood must still be inked in this one: no gap, even
     across a jump of several ticks. The ask is drawn last, so where the lines cross it wins. *)
  let joined ~best ~is_ink = List.for_all (List.range 1 24) ~f:(fun x ->
      match best columns.(x - 1) with
      | Some price -> is_ink grid.(1010 - price).(x)
      | None -> true) in
  let either cell = is_bid_ink cell || is_ask_ink cell in
  printf "columns %d; with a bid line %d; with an ask line %d\n" 24
    (columns_with is_bid_ink) (columns_with is_ask_ink);
  printf "bid line joined %b; ask line joined %b\n"
    (joined ~best:(fun (c : Heatmap.column) -> c.best_bid) ~is_ink:either)
    (joined ~best:(fun (c : Heatmap.column) -> c.best_ask) ~is_ink:is_ask_ink);
  [%expect {|
    columns 24; with a bid line 24; with an ask line 24
    bid line joined true; ask line joined true
    |}]

let%expect_test "an invalid book breaks the line instead of bridging it" =
  let book id bid = snapshot id ~bids:[ bid, 20 ] ~asks:[ bid + 1, 20 ] in
  let snapshots = [ book 0 1000; book 1 1000; snapshot ~valid:false 2 ~bids:[ 1000, 20 ] ~asks:[ 1001, 20 ]
                  ; book 3 1000; book 4 1000 ] in
  let columns = Heatmap.visible (observe_all snapshots) ~count:5 in
  let grid = Heatmap.grid columns ~bottom:995 ~top:1005 ~maximum:20 ~threshold:None in
  printf "bid ink by column: %s\n"
    (String.concat ~sep:" " (List.init 5 ~f:(fun x ->
         Bool.to_string (is_bid_ink grid.(1005 - 1000).(x)))));
  [%expect {| bid ink by column: true true false true true |}]

let%expect_test "the rule's threshold is a dashed line, only where no price line already is" =
  let columns = Heatmap.visible (observe_all walk_snapshots) ~count:6 in
  let grid = Heatmap.grid columns ~bottom:995 ~top:1005 ~maximum:20 ~threshold:(Some 1002) in
  let row = grid.(1005 - 1002) in
  printf "threshold row inks: %s\n"
    (String.concat ~sep:" " (Array.to_list (Array.map row ~f:(fun cell -> Int.to_string (Heatmap.ink_of cell)))));
  [%expect {| threshold row inks: 1 1 10 8 11 1 |}]

let%expect_test "the window is centred on the mid, holds still for small moves, and covers the book" =
  List.iter [ 1002; 1003; 1004; 1005; 1006; 1010 ] ~f:(fun center ->
    let bottom, top = Heatmap.fit ~rows:29 ~center in
    printf "mid %d -> %d..%d (%d rows)\n" center bottom top (top - bottom + 1));
  let bottom, top = Heatmap.fit ~rows:29 ~center:1004 in
  printf "a 21-tick book 994..1014 fits: %b\n" (bottom <= 994 && top >= 1014);
  [%expect {|
    mid 1002 -> 988..1016 (29 rows)
    mid 1003 -> 988..1016 (29 rows)
    mid 1004 -> 991..1019 (29 rows)
    mid 1005 -> 991..1019 (29 rows)
    mid 1006 -> 991..1019 (29 rows)
    mid 1010 -> 997..1025 (29 rows)
    a 21-tick book 994..1014 fits: true
    |}]

let%expect_test "decisions ride a rail under the map, so they never cover a price line" =
  let decision (snapshot : snapshot) outcome =
    { identity = snapshot.identity; mode = Mock; rule_id = "slot-0"; inputs = snapshot
    ; maximum_price_ticks = 1002; quantity_units = 1; candidate = None; outcome
    ; occurred_at = time 0.; receipt_at = None; build_id = "m01"; slot = 0
    ; predicate_result = Some true
    ; bounds = { min_qty = 1; max_qty = 10; min_price_ticks = 900; max_price_ticks = 1100 } } in
  let heatmap = observe_all walk_snapshots in
  let heatmap = Heatmap.note_decision heatmap (decision (List.nth_exn walk_snapshots 1) Admitted_result) in
  let heatmap = Heatmap.note_decision heatmap (decision (List.nth_exn walk_snapshots 3) (Blocked_result "MOCK qty")) in
  let heatmap = Heatmap.note_decision heatmap (decision (List.nth_exn walk_snapshots 4) No_signal_result) in
  render heatmap (List.last_exn walk_snapshots);
  [%expect {|
    ╭ Heatmap · AAPL · MOCK · scale 63 u ──╮
    │ qty 0 ░░░▒▒▓██ 63 u  ━ ask  ═ bid    │
    │ 1004┤                                │
    │     │                           ░░   │
    │     │                         ░░┏━┓░ │
    │ 1001┤                         ━━┛═┗━ │
    │ 1000┤                         ══╝░╚═ │
    │     │                         ░░  ░░ │
    │     │                                │
    │     │                                │
    │  996┤                                │
    │  dec┤                          ▲ ✗   │
    │   6 columns · 250 ms each · newest → │
    ╰──────────────────────────────────────╯
    |}]

let%expect_test "every colour capability keeps both price lines, told apart by glyph" =
  let heatmap = observe_all walk_snapshots in
  List.iter [ Theme.No_color; Ansi16; Ansi256; Truecolor ] ~f:(fun capability ->
    let text = text_of (Heatmap.view ~theme:(Theme.create capability) ~focus:Heatmap ~heatmap
                          ~state:(state_with (List.last_exn walk_snapshots)) ~width:60 ~height:14) in
    let any glyphs = List.exists glyphs ~f:(fun glyph -> String.is_substring text ~substring:glyph) in
    printf "%-9s bid line %b; ask line %b; legend keys %b\n"
      (Sexp.to_string [%sexp (capability : Theme.capability)])
      (any [ "═"; "║"; "╔"; "╗"; "╚"; "╝" ]) (any [ "━"; "┃"; "┏"; "┓"; "┗"; "┛" ])
      (String.is_substring text ~substring:"ask" && String.is_substring text ~substring:"bid"));
  [%expect {|
    No_color  bid line true; ask line true; legend keys true
    Ansi16    bid line true; ask line true; legend keys true
    Ansi256   bid line true; ask line true; legend keys true
    Truecolor bid line true; ask line true; legend keys true
    |}]

let%expect_test "absurd prices neither raise nor draw nonsense" =
  List.iter [ Int.max_value, Int.max_value - 1; Int.min_value, Int.min_value + 1; 0, -1 ] ~f:(fun (ask, bid) ->
    let book = snapshot 1 ~bids:[ bid, 20 ] ~asks:[ ask, 20 ] in
    let view = Heatmap.view ~theme:plain ~focus:Heatmap ~heatmap:(observe_all [ book ])
        ~state:(state_with book) ~width:50 ~height:12 in
    printf "ask %d: %d x %d view\n" ask (View.width view) (View.height view));
  [%expect {|
    ask 4611686018427387903: 50 x 12 view
    ask -4611686018427387904: 50 x 12 view
    ask 0: 50 x 12 view
    |}]

let%expect_test "a fast stream scrolls the map at five columns a second, a slow one a column per snapshot" =
  let at rate_hz ids = Heatmap.columns (observe_all ~rate_hz (List.map ids ~f:(fun id ->
      snapshot id ~bids:[ 1000, 20 ] ~asks:[ 1001, 20 ]))) in
  (* A frame every 16 snapshots at 1000 Hz, for two seconds. *)
  let fast = at 1000. (List.init 125 ~f:(fun frame -> frame * 16)) in
  let slow = at 4. (List.init 8 ~f:Fn.id) in
  printf "1000 Hz: 125 frames over 2 s -> %d columns; 4 Hz: 8 snapshots -> %d columns\n"
    (List.length fast) (List.length slow);
  [%expect {| 1000 Hz: 125 frames over 2 s -> 10 columns; 4 Hz: 8 snapshots -> 8 columns |}]

let%expect_test "a frame composes only the columns in view, however long the history" =
  let long = observe_all (List.init 400 ~f:(fun i -> snapshot i ~bids:[ 1000, 20 ] ~asks:[ 1001, 20 ])) in
  printf "ring %d columns; view takes %d of them\n" (List.length (Heatmap.columns long))
    (Array.length (Heatmap.visible long ~count:12));
  [%expect {| ring 256 columns; view takes 12 of them |}]

(* ---- The price chart ---- *)

let sample seconds ?bid ?ask () : Market_motion.sample =
  { time = time seconds; bid; ask; delta_updates = 1 }

(* Newest first, as [Market_motion] keeps them: one every two seconds, the bid drifting up
   and back, the book invalid for a few seconds in the middle. *)
let history ?(until = 60.) () =
  let at i =
    let seconds = Float.of_int (i * 2) in
    if Float.(seconds > until) then None
    else if i = 15 || i = 16 then Some (sample seconds ())
    else (
      let bid = 1000 + Float.to_int (4. *. Float.sin (Float.of_int i /. 5.)) in
      Some (sample seconds ~bid ~ask:(bid + 1 + (i % 2)) ())) in
  List.rev (List.filter_map (List.range 0 31) ~f:at)

let chart ?(theme = plain) ?(threshold = Some 1002) ?(width = 46) ?(height = 10) ?(now = 60.) samples =
  Bonsai_term_test.print_view
    (Market_chart.view ~theme ~samples ~now:(time now) ~threshold ~width ~height)

let%expect_test "the chart plots bid, ask and mid on a tick scale with a dashed rule threshold" =
  chart (history ());
  [%expect {|
       t ask 1000  bid 999  mid 999.5 ┄
        │      ⡖⢲ ⡖⡆⢰⠒⡆⢰⢲
    1004┤   ⢰⢲ ⡇⠚⠖⠇⠗⠞⠂⠗⠞⢺ ⡖⢲
        │   ⢸⠉⠍⡏⠉⠉⠉⠉⠉⠉⠉⠉⢹⠍⠇⢹
    1002┤⠉⠉⡍⢽⠉⠉⠉ ⠉ ⠉ ⠉ ⠉⠈⠉⠉⢹⠍⠉ ⠉ ⠉ ⠉ ⠉ ⠉ ⠉ ⠉ ⠉ ⠉ ⠉
        │⢀⣁⡏⠉              ⠈⠉  ⠈⡉⣇⣀⣀            ⡏⣹
        │                      ⢀⣀⣃⡆⣸ ⣀⣀⢀⣀⡀⢀⣀⡀⣀⣀⣀⣇⣀
     998┤                         ⠧⢼⠤⡇⠼⠼⠄⡧⠼⠄⡧⡇⢤⠦⠇
        │                          ⠸⠥⠥⠤⠥⠤⠥⠥⠤⠥⠥⠼
         −60 s─────────────−30 s───────────────now
    |}]

let%expect_test "a book that was invalid breaks the lines rather than being bridged" =
  chart ~threshold:None (history ());
  [%expect {|
       t ask 1000  bid 999  mid 999.5 ┄
        │      ⡖⢲ ⡖⡆⢰⠒⡆⢰⢲
    1004┤   ⢰⢲ ⡇⠚⠖⠇⠗⠞⠂⠗⠞⢺ ⡖⢲
        │   ⢸⠉⠍⡏⠉⠉⠉⠉⠉⠉⠉⠉⢹⠍⠇⢹
    1002┤⠈⠉⡍⢽⠉⠉⠁        ⠈⠉⠉⢹⠍
    1000┤⢀⣁⡏⠉              ⠈⠉  ⠈⡉⣇⣀⣀            ⡏⣹
        │                      ⢀⣀⣃⡆⣸ ⣀⣀⢀⣀⡀⢀⣀⡀⣀⣀⣀⣇⣀
     998┤                         ⠧⢼⠤⡇⠼⠼⠄⡧⠼⠄⡧⡇⢤⠦⠇
        │                          ⠸⠥⠥⠤⠥⠤⠥⠥⠤⠥⠥⠼
         −60 s─────────────−30 s───────────────now
    |}]

let%expect_test "the chart holds still between pixel boundaries, so a frame repaints only its newest column" =
  let render now = text_of (Market_chart.view ~theme:plain ~samples:(history ()) ~now:(time now)
                              ~threshold:None ~width:46 ~height:10) in
  let base = render 60. in
  (* A pixel is 60 s / 88 = 0.68 s wide here. *)
  printf "+0.1 s same: %b; +0.3 s same: %b; +0.9 s same: %b\n"
    (String.equal base (render 60.1)) (String.equal base (render 60.3)) (String.equal base (render 60.9));
  [%expect {| +0.1 s same: true; +0.3 s same: true; +0.9 s same: false |}]

let%expect_test "a stalled stream stops the line at its newest sample" =
  chart ~threshold:None (history ~until:30. ());
  [%expect {|
       t ask 1002  bid 1001  mid 1001.5 ┄
        │      ⡖⢲ ⡖⡆⢰⠒⡆⢰⢲
    1004┤   ⢀⣀ ⡇⣸⣀⡇⣇⣸⡀⣇⣸⣸ ⣀⣀
        │   ⢸⢸ ⡇ ⠄⠇⠇⠄ ⠇⠄⢸ ⡇⢸
        │   ⢸⠚⠒⡗⠒⠒⠒⠒⠒⠒⠒⠒⢺⠒⡇⢺
    1002┤⠠⠤⠤⢼⠤⠥⠇        ⠸⠥⠥⢼⠤
        │  ⡆⢺              ⢸⠂
        │ ⠁⡏⠉              ⠈⠉
    1000┤⠠⠤⠇
         −60 s─────────────−30 s───────────────now
    |}]

let%expect_test "a rule threshold far from the book is named, not plotted" =
  chart ~threshold:(Some 9000) (history ());
  [%expect {|
       t ask 1000  bid 999  mid 999.5 ┄
        │      ⡖⢲ ⡖⡆⢰⠒⡆⢰⢲
    1004┤   ⢰⢲ ⡇⠚⠖⠇⠗⠞⠂⠗⠞⢺ ⡖⢲
        │   ⢸⠉⠍⡏⠉⠉⠉⠉⠉⠉⠉⠉⢹⠍⠇⢹
    1002┤⠈⠉⡍⢽⠉⠉⠁        ⠈⠉⠉⢹⠍
    1000┤⢀⣁⡏⠉              ⠈⠉  ⠈⡉⣇⣀⣀            ⡏⣹
        │                      ⢀⣀⣃⡆⣸ ⣀⣀⢀⣀⡀⢀⣀⡀⣀⣀⣀⣇⣀
     998┤                         ⠧⢼⠤⡇⠼⠼⠄⡧⠼⠄⡧⡇⢤⠦⠇
        │                          ⠸⠥⠥⠤⠥⠤⠥⠥⠤⠥⠥⠼
         −60 s─────────────−30 s───────────────now
    |}]

let%expect_test "without history the chart says so, and absurd prices are not plotted" =
  chart [];
  chart [ sample 59. ~bid:Int.min_value ~ask:Int.max_value () ];
  [%expect {|
    no price history yet
    no price history yet
    |}]


(* ---- The ladder: deltas at every width, and the chart in the free height ---- *)

let ladder_book id bid ask =
  snapshot id ~bids:[ 1003, bid; 1002, 25 ] ~asks:[ 1004, ask; 1005, 30 ]
let before = ladder_book 1 40 12
let after = ladder_book 2 35 24  (* the bid loses 5 units and the ask gains 12 *)

let motion_at ~now =
  let first = Market_motion.observe Market_motion.empty ~now:(time 0.) ~snapshot:before ~updates:0 in
  Market_motion.observe first ~now:(time now) ~snapshot:after ~updates:1

let panel ?(motion = Market_motion.empty) ?(now = 0.) ?(rules = []) ~width ~height market =
  let state = { (state_with market) with rules } in
  Market_panel.view ~cumulative:false ~theme:plain ~focus:Market ~state ~motion ~now:(time now)
    ~width ~height

let%expect_test "quantity deltas show in the ladder at every terminal width from 100 up" =
  let toggles heatmap : Ui_types.market_toggles = { heatmap; cumulative = false } in
  let motion = motion_at ~now:10. in
  List.iter [ 100, 30; 120, 36; 159, 44; 160, 45; 200, 60 ] ~f:(fun (width, height) ->
    List.iter [ Ui_types.Monitor; Demo ] ~f:(fun preset ->
      List.iter [ true; false ] ~f:(fun heatmap ->
        match List.Assoc.find (Layout.compute ~preset ~zoom:None ~toggles:(toggles heatmap)
                                 ~width ~height:(height - 2)) Market ~equal:Ui_types.equal_panel_id with
        | None -> ()
        | Some rect ->
          let text = text_of (panel ~motion ~now:10.25 ~width:rect.width ~height:rect.height after) in
          printf "%3dx%-2d %-7s heatmap %-5b market %3d wide: +12 %b, -5 %b\n" width height
            (Sexp.to_string [%sexp (preset : Ui_types.preset)]) heatmap rect.width
            (String.is_substring text ~substring:"+12") (String.is_substring text ~substring:"−5"))));
  [%expect {|
    100x30 Monitor heatmap true  market  50 wide: +12 true, -5 true
    100x30 Monitor heatmap false market 100 wide: +12 true, -5 true
    100x30 Demo    heatmap true  market  50 wide: +12 true, -5 true
    100x30 Demo    heatmap false market  50 wide: +12 true, -5 true
    120x36 Monitor heatmap true  market  60 wide: +12 true, -5 true
    120x36 Monitor heatmap false market 120 wide: +12 true, -5 true
    120x36 Demo    heatmap true  market  60 wide: +12 true, -5 true
    120x36 Demo    heatmap false market  60 wide: +12 true, -5 true
    159x44 Monitor heatmap true  market  79 wide: +12 true, -5 true
    159x44 Monitor heatmap false market 159 wide: +12 true, -5 true
    159x44 Demo    heatmap true  market  79 wide: +12 true, -5 true
    159x44 Demo    heatmap false market  79 wide: +12 true, -5 true
    160x45 Monitor heatmap true  market  64 wide: +12 true, -5 true
    160x45 Monitor heatmap false market 160 wide: +12 true, -5 true
    160x45 Demo    heatmap true  market  54 wide: +12 true, -5 true
    160x45 Demo    heatmap false market  54 wide: +12 true, -5 true
    200x60 Monitor heatmap true  market  80 wide: +12 true, -5 true
    200x60 Monitor heatmap false market 200 wide: +12 true, -5 true
    200x60 Demo    heatmap true  market  68 wide: +12 true, -5 true
    200x60 Demo    heatmap false market  68 wide: +12 true, -5 true
    |}]

let%expect_test "deltas keep their column and the bars give way, down to a half-width panel" =
  List.iter [ 50; 52; 80 ] ~f:(fun width ->
    Bonsai_term_test.print_view (panel ~motion:(motion_at ~now:10.) ~now:10.25 ~width ~height:11 after));
  [%expect {|
    ╭ Market · AAPL ─────────────────────────────────╮
    │ px (t) · qty (u)                               │
    │       qty(u) BID px(t)│px(t) ASK  qty(u)       │
    │    −5     35 ███  1003│ 1004 ██▋      24 +12   │
    │           25 ██▏  1002│ 1005 ███▍     30       │
    │ spread 1 t   mid 1003.5 t                      │
    │ imbalance +0.19 ▲                              │
    │ ask                           ⠠⠤⠤⠤⠤⠤⠄ last 60s │
    │ MOCK #0  updates/s 1.0                         │
    │                                                │
    ╰────────────────────────────────────────────────╯
    ╭ Market · AAPL ───────────────────────────────────╮
    │ px (t) · qty (u)                                 │
    │       qty(u) BID  px(t)│px(t) ASK   qty(u)       │
    │    −5     35 ████  1003│ 1004 ███▍      24 +12   │
    │           25 ██▊   1002│ 1005 ████▎     30       │
    │ spread 1 t   mid 1003.5 t                        │
    │ imbalance +0.19 ▲                                │
    │ ask                             ⠠⠤⠤⠤⠤⠤⠄ last 60s │
    │ MOCK #0  updates/s 1.0                           │
    │                                                  │
    ╰──────────────────────────────────────────────────╯
    ╭ Market · AAPL ───────────────────────────────────────────────────────────────╮
    │ px (t) · qty (u)                                                             │
    │       qty(u) BID                px(t)│px(t) ASK                 qty(u)       │
    │    −5     35 ██████████████████  1003│ 1004 █████████████           24 +12   │
    │           25 ████████████▊       1002│ 1005 ████████████████▎       30       │
    │ spread 1 t   mid 1003.5 t                                                    │
    │ imbalance +0.19 ▲                                                            │
    │ ask                                                    ⠠⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠄ last 60s │
    │ MOCK #0  updates/s 1.0                                                       │
    │                                                                              │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    |}]

let%expect_test "the free height is a price chart; a short panel keeps the single ask sparkline" =
  let samples = history () in
  let motion = { Market_motion.empty with samples } in
  let rules = [ { (List.hd_exn (base_state ()).rules) with
                  parameters = [ "maximum_price", 1002, "t" ] } ] in
  List.iter [ 30; 14 ] ~f:(fun height ->
    Bonsai_term_test.print_view (panel ~motion ~now:60. ~rules ~width:60 ~height after));
  [%expect {|
    ╭ Market · AAPL ───────────────────────────────────────────╮
    │ px (t) · qty (u)                                         │
    │       qty(u) BID      px(t)│px(t) ASK       qty(u)       │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1002 t ╌╌ │
    │           35 ████████  1003│ 1004 ██████▏       24       │
    │           25 █████▋    1002│ 1005 ███████▋      30       │
    │ spread 1 t   mid 1003.5 t                                │
    │ imbalance +0.19 ▲                                        │
    │    t ask 1000  bid 999  mid 999.5 ┄                      │
    │ 1005┤        ⡖⢲ ⡖⠒⡆⢰⠒⢲ ⡖⢲                                │
    │     │        ⡇⢸ ⡇ ⡇⢸ ⢸ ⡇⢸                                │
    │ 1004┤    ⢠⠤⡄ ⡇⠼⠤⡇⠄⡧⠼⠄⠼⠤⡇⢼ ⢠⠤⡄                            │
    │     │    ⢸ ⡇ ⡇ ⠄⠇ ⠇⠄  ⠄⠇⢸ ⢸ ⡇                            │
    │ 1003┤    ⢸⠄⡧⠤⡧⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⢼⠤⠼⠄⡇                            │
    │     │    ⢸ ⡇⡀⡇          ⢸⡀⡀ ⡇                            │
    │ 1002┤⣀⣀⣀⣀⣸⣀⣀⣀⣇ ⣀ ⣀ ⣀ ⣀ ⣀⢸⣀⣀⣀⣇⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ ⣀ │
    │     │   ⡀⣸                  ⡇⡀                           │
    │     │    ⢸                  ⡇                            │
    │ 1001┤ ⠁⢹⠉⠉                  ⠉⠉   ⠉⠉⡇                 ⢸⠉⢹ │
    │     │  ⢸                           ⡇                 ⢸ ⢸ │
    │ 1000┤ ⠉⠉                         ⠁⠁⡏⠉⠉⢹              ⢸⠁⠉ │
    │     │                              ⠁⠁ ⢸              ⢸   │
    │  999┤                            ⠒⠒⠒⢲⠂⢺ ⡖⢲ ⢰⠒⡆ ⡖⢲ ⡖⠒⠒⢺⠒⠒ │
    │     │                               ⢸ ⢸ ⡇⢸ ⢸ ⡇ ⡇⢸ ⡇ ⡆⢺   │
    │  998┤                               ⠘⠒⢺⠒⡇⠚⠒⠚⠂⡗⠒⡇⠚⠒⡇⠂⡗⠚   │
    │     │                                 ⢸⠄⠇ ⠄⠄ ⠇⠄⠇ ⠄⠇ ⡇    │
    │  997┤                                 ⠸⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠇    │
    │      −60 s──────────────────−30 s────────────────────now │
    │ MOCK #0  updates/s 0.0                                   │
    ╰──────────────────────────────────────────────────────────╯
    ╭ Market · AAPL ───────────────────────────────────────────╮
    │ px (t) · qty (u)                                         │
    │       qty(u) BID      px(t)│px(t) ASK       qty(u)       │
    │ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ maximum_price 1002 t ╌╌ │
    │           35 ████████  1003│ 1004 ██████▏       24       │
    │           25 █████▋    1002│ 1005 ███████▋      30       │
    │ spread 1 t   mid 1003.5 t                                │
    │ imbalance +0.19 ▲                                        │
    │ ask ⠤⠒⠒⠊⠉⠒⠊⠉⠉⠉⠉⠉⠉⠉⠉⠉⠑⠒⠉⠒    ⠤⠤⠤⢄⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⡠⠤⠤ last 60s │
    │ MOCK #0  updates/s 0.0                                   │
    │                                                          │
    │                                                          │
    │                                                          │
    ╰──────────────────────────────────────────────────────────╯
    |}]

(* ---- The tape ---- *)

let top id ~bid ~ask = snapshot id ~bids:[ 1000, bid ] ~asks:[ 1001, ask ]
let tape_script =
  [ 0.0, top 1 ~bid:40 ~ask:30; 0.5, top 2 ~bid:25 ~ask:30; 1.0, top 3 ~bid:25 ~ask:10
  ; 1.5, top 4 ~bid:12 ~ask:10; 2.0, top 5 ~bid:12 ~ask:4 ]

let run_tape ?(script = tape_script) () =
  List.fold script ~init:Tape_panel.empty ~f:(fun tape (at, snapshot) ->
    Tape_panel.observe tape ~now:(time at) ~snapshot)

let%expect_test "the tape totals the last minute and splits it by side, in glyphs as well as colour" =
  Bonsai_term_test.print_view (Tape_panel.view ~theme:plain ~focus:Tape ~tape:(run_tape ()) ~now:(time 5.)
                                 ~width:60 ~height:10);
  [%expect {|
    ╭ Tape · MOCK · inferred from book deltas ─────────────────╮
    │ 60 s: 4 prints · buy 26 u · sell 28 u · net -2 u ███░░░░ │
    │ time (UTC)    side    px(t)  qty(u) size                 │
    │ 00:00:02.000  ▲ BUY    1001       6 █████▋               │
    │ 00:00:01.500  ▼ SELL   1000      13 ████████████▎        │
    │ 00:00:01.000  ▲ BUY    1001      20 ███████████████████  │
    │ 00:00:00.500  ▼ SELL   1000      15 ██████████████▎      │
    │                                                          │
    │                                                          │
    ╰──────────────────────────────────────────────────────────╯
    |}]

let hex (r, g, b) = sprintf "#%02X%02X%02X" r g b

let%expect_test "a fresh print fades from the text colour into its weight over a second" =
  let tape = run_tape () in
  let print = List.hd_exn (Tape_panel.prints tape) in
  List.iter [ 0.; 0.25; 0.5; 0.75; 1.0; 3.0 ] ~f:(fun after ->
    let now = Time_ns.add print.time (Time_ns.Span.of_sec after) in
    printf "%.2fs after the print: %s\n" after
      (hex (Tape_panel.print_rgb truecolor ~now ~largest:print.quantity_units print)));
  [%expect {|
    0.00s after the print: #A8D9C7
    0.25s after the print: #95D8BD
    0.50s after the print: #77D8AC
    0.75s after the print: #5AD79C
    1.00s after the print: #3DD68C
    3.00s after the print: #3DD68C
    |}]

let%expect_test "a narrow tape gives up spaces, milliseconds and the side's word, in that order" =
  List.iter [ 60; 37; 33; 30 ] ~f:(fun width ->
    Bonsai_term_test.print_view (Tape_panel.view ~theme:plain ~focus:Tape ~tape:(run_tape ()) ~now:(time 5.)
                                   ~width ~height:7));
  [%expect {|
    ╭ Tape · MOCK · inferred from book deltas ─────────────────╮
    │ 60 s: 4 prints · buy 26 u · sell 28 u · net -2 u ███░░░░ │
    │ time (UTC)    side    px(t)  qty(u) size                 │
    │ 00:00:02.000  ▲ BUY    1001       6 █████▋               │
    │ 00:00:01.500  ▼ SELL   1000      13 ████████████▎        │
    │ 00:00:01.000  ▲ BUY    1001      20 ███████████████████  │
    ╰──────────────────────────────────────────────────────────╯
    ╭ Tape · MOCK · inferred ───────────╮
    │ buy 26 · sell 28 · net -2 ███░░░░ │
    │ time (UTC)   side   px(t) qty(u)  │
    │ 00:00:02.000 ▲ BUY   1001      6  │
    │ 00:00:01.500 ▼ SELL  1000     13  │
    │ 00:00:01.000 ▲ BUY   1001     20  │
    ╰───────────────────────────────────╯
    ╭ Tape · MOCK · inferred ───────╮
    │ buy 26 · sell 28 · net -2     │
    │ time (UTC) side px(t) qty(u)  │
    │ 00:00:02   ▲     1001      6  │
    │ 00:00:01   ▼     1000     13  │
    │ 00:00:01   ▲     1001     20  │
    ╰───────────────────────────────╯
    ╭ Tape · MOCK · inferred ────╮
    │ buy 26 · sell 28 · net -2  │
    │ time (UTC) side px(t) qty  │
    │ 00:00:02   ▲     1001   6  │
    │ 00:00:01   ▼     1000  13  │
    │ 00:00:01   ▲     1001  20  │
    ╰────────────────────────────╯
    |}]
