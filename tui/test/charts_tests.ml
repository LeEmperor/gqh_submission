open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let at seconds = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec seconds)
let ensure condition message = if not condition then failwith message
let contains text substring = String.is_substring text ~substring

let render ~width ~height view =
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width; height }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  Bonsai_test.Handle.show_into_string handle

(* A ramp: 61 one-second observations rising from 0 to 1 over the window ending at 60 s. *)
let ramp = List.init 61 ~f:(fun second -> at (Float.of_int second), Some (Float.of_int second /. 60.))

let grid ?(fill = Braille_chart.Solid) ?(width = 6) ~height series =
  Braille_chart.cells ~now:(at 60.) ~width ~height ~low:0. ~high:1. ~fill series
  |> Braille_chart.to_strings

let%expect_test "a ramp scales from a one-row sparkline to twenty rows" =
  List.iter [ 1; 2; 4 ] ~f:(fun height ->
    let fill = if height = 1 then Braille_chart.Line_only else Solid in
    printf "height %d\n" height;
    List.iter (grid ~fill ~height ramp) ~f:(printf "  |%s|\n"));
  [%expect {|
    height 1
      |⣠⠤⠴⠒⠚⠉|
    height 2
      |  ⢀⣠⣶⣿|
      |⣤⣶⣿⣿⣿⣿|
    height 4
      |    ⣰⣿|
      |  ⢀⣾⣿⣿|
      | ⣠⣿⣿⣿⣿|
      |⣼⣿⣿⣿⣿⣿|
    |}]

let%expect_test "the top dot is the scale's high and the bottom dot its low, at every height" =
  List.iter [ 1; 2; 3; 5; 8; 13; 20 ] ~f:(fun height ->
    let at_scale value =
      Braille_chart.cells ~now:(at 60.) ~width:4 ~height ~low:0. ~high:1. ~fill:Line_only
        [ at 0., Some value; at 60., Some value ] in
    let lit grid = Array.to_list grid |> List.concat_map ~f:Array.to_list
                   |> List.count ~f:(fun cell -> cell.Braille_chart.bits <> 0) in
    let high = at_scale 1. and low = at_scale 0. in
    let rows = Array.length high in
    ensure (rows = height && Array.for_all high ~f:(fun row -> Array.length row = 4)) "wrong grid size";
    (* The line is on the top row for [high] and only the bottom row for [low]. *)
    let top_lit = Array.for_all high.(0) ~f:(fun cell -> cell.bits <> 0) in
    let only_bottom = Array.foldi low ~init:true ~f:(fun row ok cells ->
        ok && Array.for_all cells ~f:(fun cell -> Bool.equal (cell.bits <> 0) (row = height - 1))) in
    ensure (top_lit && only_bottom) (sprintf "line misplaced at height %d" height);
    printf "height %2d: %d rows; high line on row 0 (%d cells lit), low line on row %d (%d cells lit)\n"
      height rows (lit high) (height - 1) (lit low));
  [%expect {|
    height  1: 1 rows; high line on row 0 (4 cells lit), low line on row 0 (4 cells lit)
    height  2: 2 rows; high line on row 0 (4 cells lit), low line on row 1 (4 cells lit)
    height  3: 3 rows; high line on row 0 (4 cells lit), low line on row 2 (4 cells lit)
    height  5: 5 rows; high line on row 0 (4 cells lit), low line on row 4 (4 cells lit)
    height  8: 8 rows; high line on row 0 (4 cells lit), low line on row 7 (4 cells lit)
    height 13: 13 rows; high line on row 0 (4 cells lit), low line on row 12 (4 cells lit)
    height 20: 20 rows; high line on row 0 (4 cells lit), low line on row 19 (4 cells lit)
    |}]

let%expect_test "a gap breaks the line and is marked as no data, never drawn as zero" =
  let series = [ at 0., Some 0.5; at 20., Some 0.5; at 30., None; at 40., None; at 60., Some 0.5 ] in
  List.iter (grid ~width:12 ~height:2 series) ~f:(printf "|%s|\n");
  let line = Braille_chart.cells ~now:(at 60.) ~width:12 ~height:2 ~low:0. ~high:1. ~fill:Solid series in
  printf "kinds: %s\n" (String.concat_array (Array.map line.(0) ~f:(fun cell ->
      match cell.kind with Blank -> "b" | Fill -> "f" | Line -> "l" | No_data -> "-")));
  [%expect {|
    |⣀⣀⣀⣀·······⢀|
    |⣿⣿⣿⣿·······⢸|
    kinds: llll-------l
    |}]

let%expect_test "area fill: solid below the line, stippled when colour cannot shade it" =
  List.iter [ Braille_chart.Solid; Stipple; Line_only ] ~f:(fun fill ->
    printf "%s\n" (Sexp.to_string (Braille_chart.sexp_of_fill fill));
    List.iter (grid ~fill ~width:6 ~height:3 ramp) ~f:(printf "  |%s|\n"));
  [%expect {|
    Solid
      |   ⢀⣴⣿|
      | ⢀⣴⣿⣿⣿|
      |⣴⣿⣿⣿⣿⣿|
    Stipple
      |   ⢀⡴⡫|
      | ⢀⡴⡫⡪⡪|
      |⡴⡫⡪⡪⡪⡪|
    Line_only
      |   ⢀⡴⠋|
      | ⢀⡴⠋  |
      |⡴⠋    |
    |}]

let color_to_string color = Sexp.to_string_hum ([%sexp_of: Attr.Color.t option] color)

(* Catches a gradient that stops interpolating, or a 16-colour terminal given colours it
   cannot show: truecolor blends the surface towards the role, 256 quantises that blend,
   16 colours fall back to two tones, and no colour carries nothing. *)
let%expect_test "area gradient fades by row and falls back per terminal capability" =
  let fill capability ~strength =
    match Braille_chart.fill_attrs (Theme.create capability) Info ~strength with
    | [] -> "no attrs"
    | _ -> "fg" in
  let shade capability strength = color_to_string (Braille_chart.shade (Theme.create capability) Info ~strength) in
  List.iter [ 0.; 0.15; 0.55; 1. ] ~f:(fun strength ->
    printf "truecolor %.2f %s\n" strength (shade Truecolor strength));
  List.iter [ 0.15; 0.55 ] ~f:(fun strength ->
    printf "256 %.2f %s\n" strength (shade Ansi256 strength));
  printf "16 colours fill: %s; no colour fill: %s\n" (fill Ansi16 ~strength:0.3) (fill No_color ~strength:0.3);
  let strengths = List.init 5 ~f:(fun row -> Braille_chart.strength ~height:5 ~row) in
  printf "strength by row (top first): %s\n"
    (String.concat ~sep:" " (List.map strengths ~f:(sprintf "%.2f")));
  ensure (List.is_sorted_strictly (List.rev strengths) ~compare:Float.compare) "gradient not monotonic";
  printf "fill style: truecolor %s, 256 %s, 16 %s, none %s\n"
    (Sexp.to_string (Braille_chart.sexp_of_fill (Braille_chart.fill_style (Theme.create Truecolor))))
    (Sexp.to_string (Braille_chart.sexp_of_fill (Braille_chart.fill_style (Theme.create Ansi256))))
    (Sexp.to_string (Braille_chart.sexp_of_fill (Braille_chart.fill_style (Theme.create Ansi16))))
    (Sexp.to_string (Braille_chart.sexp_of_fill (Braille_chart.fill_style (Theme.create No_color))));
  [%expect {|
    truecolor 0.00 ((Rgb_888 (11 14 20)))
    truecolor 0.15 ((Rgb_888 (23 38 55)))
    truecolor 0.55 ((Rgb_888 (54 103 149)))
    truecolor 1.00 ((Rgb_888 (90 176 255)))
    256 0.15 ((Palette_index 235))
    256 0.55 ((Palette_index 60))
    16 colours fill: fg; no colour fill: no attrs
    strength by row (top first): 0.55 0.45 0.35 0.25 0.15
    fill style: truecolor Solid, 256 Solid, 16 Stipple, none Stipple
    |}]

let%expect_test "axis bounds are round numbers that stay put while the data moves" =
  List.iter [ 0.; 0.3; 1.; 1.05; 3.3; 4.4; 14.8; 99.; 101.; 1234.; 15000. ] ~f:(fun value ->
    printf "%g -> %s\n" value (Braille_chart.compact (Braille_chart.nice_ceiling value)));
  ensure (Float.equal (Braille_chart.nice_ceiling Float.nan) 1.) "nan not neutral";
  [%expect {|
    0 -> 1
    0.3 -> 0.3
    1 -> 1
    1.05 -> 1.2
    3.3 -> 4
    4.4 -> 5
    14.8 -> 15
    99 -> 100
    101 -> 120
    1234 -> 1.5k
    15000 -> 15k
    |}]

let%expect_test "a bar fills in eighths and clamps" =
  List.iter [ 0.; 0.06; 0.5; 0.62; 1.; 1.7; -1.; Float.nan ] ~f:(fun fraction ->
    let { Sparkline.full; partial; empty } = Sparkline.bar ~width:8 ~fraction in
    ensure (full + empty + (if String.is_empty partial then 0 else 1) = 8) "bar is not 8 cells";
    printf "%5.2f |%s%s%s|\n" fraction (String.concat (List.init full ~f:(fun _ -> "█")))
      partial (String.make empty '.'));
  [%expect {|
     0.00 |........|
     0.06 |▌.......|
     0.50 |████....|
     0.62 |█████...|
     1.00 |████████|
     1.70 |████████|
    -1.00 |........|
      nan |........|
    |}]

(* The marker sits on the first cell at the low bound, the last at the high bound, and
   halfway for the midpoint; a value outside the range pins to an end with an arrow. *)
let%expect_test "a range bar places the value at the bounds, the midpoint and outside" =
  let show ~low ~high value =
    let left, marker, right = Sparkline.range_bar ~low ~high ~value ~width:11 in
    printf "[%d %s%s%s %d] value %d\n" low left marker right high value in
  show ~low:995 ~high:1010 995;
  show ~low:995 ~high:1010 1010;
  show ~low:995 ~high:1010 1005;
  show ~low:1 ~high:5 3;
  show ~low:1 ~high:5 1;
  show ~low:1 ~high:5 0;
  show ~low:1 ~high:5 9;
  show ~low:7 ~high:7 7;
  List.iter [ 995; 1002; 1003; 1010 ] ~f:(fun value ->
    printf "placement %d: %s\n" value
      (Sexp.to_string (Sparkline.sexp_of_placement (Sparkline.placement ~low:995 ~high:1010 ~value ~width:11))));
  [%expect {|
    [995 ●────────── 1010] value 995
    [995 ━━━━━━━━━━● 1010] value 1010
    [995 ━━━━━━━●─── 1010] value 1005
    [1 ━━━━━●───── 5] value 3
    [1 ●────────── 5] value 1
    [1 ◀────────── 5] value 0
    [1 ━━━━━━━━━━▶ 5] value 9
    [7 ●────────── 7] value 7
    placement 995: (Inside 0)
    placement 1002: (Inside 5)
    placement 1003: (Inside 5)
    placement 1010: (Inside 10)
    |}]

let%expect_test "the time axis keeps its ends and drops the middle label as it narrows" =
  List.iter [ 40; 24; 14; 9; 5; 3 ] ~f:(fun width ->
    let view = Braille_chart.time_axis ~theme ~gutter:0 ~width () in
    ensure (View.width view = width) "axis not the plot width";
    printf "%2d " width;
    Bonsai_term_test.print_view view);
  let gutter = Braille_chart.time_axis ~theme ~gutter:4 ~width:24 () in
  ensure (View.width gutter = 24) "gutter not counted in the width";
  Bonsai_term_test.print_view gutter;
  [%expect {|
    40 −60s ──────────── −30s ───────────── now
    24 −60s ──── −30s ───── now
    14 −60s ───── now
     9 ──────now
     5 ──now
     3 now
       └−60s ── −30s ─── now
    |}]

(* ---- Metrics ---- *)

let base =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn |> Mock_backend.state

let counters ?(connected = true) ~decisions ~admitted ~blocked ~loss () =
  let rule = List.hd_exn base.rules in
  { base with connected; trace_loss = loss
            ; decisions = { base.decisions with next_sequence = decisions }
            ; rules = [ { rule with admitted; blocked } ] }

let observed steps =
  List.fold steps ~init:Metrics_state.empty ~f:(fun metrics (seconds, state) ->
    Metrics_state.observe metrics ~now:(at seconds) state)

(* 40 s of a steady stream: 5 to 7 decisions a second, outcomes every second but a quiet
   stretch from 20 s to 24 s, and trace loss from 30 s. Built by a fold: [List.init] does
   not promise to call [f] in order. *)
let busy =
  let _, steps = List.fold (List.range 0 41) ~init:((0, 0), []) ~f:(fun ((admitted, blocked), steps) second ->
      let admitted, blocked =
        if second >= 20 && second <= 24 then admitted, blocked
        else if second mod 3 = 0 then admitted, blocked + 1
        else admitted + 2, blocked in
      (admitted, blocked),
      (Float.of_int second,
       counters ~decisions:((second * 5) + (second mod 3)) ~admitted ~blocked
         ~loss:(if second >= 30 then 3 else 0) ()) :: steps) in
  observed (List.rev steps)

let metrics_view ?(metrics = busy) ?(now = 40.) ~width ~height () =
  Metrics_panel.view ~theme ~focus:Market ~metrics ~now:(at now) ~width ~height

let%expect_test "metrics fills its rect at every size from 40x6 to 120x20" =
  List.iter [ 6; 8; 10; 13; 20 ] ~f:(fun height ->
    printf "h%-2d" height;
    List.iter [ 40; 60; 80; 120 ] ~f:(fun width ->
      let view = metrics_view ~width ~height () in
      ensure (View.width view = width && View.height view = height) "panel overflowed its rect";
      let text = render ~width ~height view in
      ensure (contains text "Metrics · MOCK") "title lost";
      ensure (contains text "decisions/s" || contains text "dec/s") "decision rate lost";
      ensure (contains text "admit") "admit ratio lost";
      ensure (contains text "loss/s") "trace loss lost";
      printf " %3d:%-12s" width
        (Sexp.to_string (Metrics_panel.sexp_of_layout (Metrics_panel.layout_for ~width ~height))));
    printf "\n");
  [%expect {|
    h6   40:Inline        60:Inline        80:Inline       120:Inline
    h8   40:Inline        60:Inline        80:Side_by_side 120:Side_by_side
    h10  40:Inline        60:Inline        80:Side_by_side 120:Side_by_side
    h13  40:Stacked       60:Stacked       80:Side_by_side 120:Side_by_side
    h20  40:Stacked       60:Stacked       80:Side_by_side 120:Side_by_side
    |}]

let%expect_test "inline rows give each metric a bold value, a sparkline and min/max at 40x6" =
  print_string (render ~width:40 ~height:6 (metrics_view ~width:40 ~height:6 ()));
  [%expect {|
    ┌────────────────────────────────────────┐
    │╭ Metrics · MOCK ──────────────────────╮│
    ││ dec/s  6.0/s · · ⠲⠶⠶⠶⠶⠶⠶⠶⠶ 3.0–6.0   ││
    ││ admit   1.00 · · ⢹⣿⣿⣿⡇⢹⣿⣿⣿ 0.00–1.00 ││
    ││ loss/s 0.0/s · · ⣀⣀⣀⣀⣀⣀⣶⣀⣀ 0.0–3.0   ││
    ││             └−60s ──── now min–max   ││
    │╰──────────────────────────────────────╯│
    └────────────────────────────────────────┘
    |}]

let%expect_test "stacked charts share one time axis" =
  print_string (render ~width:46 ~height:14 (metrics_view ~width:46 ~height:14 ()));
  [%expect {|
    ┌──────────────────────────────────────────────┐
    │╭ Metrics · MOCK ────────────────────────────╮│
    ││ decisions/s 6.0/s  min 3.0 · max 6.0       ││
    ││ 8┤· · · · · · ·⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀⣀⢀ ││
    ││  │ · no data · ⠨⡺⣾⡺⣾⡺⣾⡺⣾⡺⣾⡺⣾⣺⡾⣺⡾⣺⡾⣺⡾⣺⡾⣺⡾⣺⡾ ││
    ││ 0┤· · · · · · ·⠨⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪ ││
    ││ admit ratio 1.00  min 0.00 · max 1.00      ││
    ││ 1┤·  no data  ·⠨⣻⣸⣻⣸⣻⣸⣻⣸⣻⣸⣻⣸· ·⠨⣻⣸⣻⣸⣻⣸⣻⣸⣻⣸ ││
    ││ 0┤ · · · · · · ⠨⡪⣿⡪⣿⡪⣿⡪⣿⡪⣿⡪⣿ · ⠨⣺⡯⣺⡯⣺⡯⣺⡯⣺⡯ ││
    ││ trace loss/s 0.0/s  min 0.0 · max 3.0      ││
    ││ 4┤·  no data  ·                   ⢠⡄       ││
    ││ 0┤ · · · · · · ⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣸⣻⣀⣀⣀⣀⣀⣀ ││
    ││  └−60s ──────────── −30s ───────────── now ││
    ││ 60 s window · sampled 1 Hz                 ││
    │╰────────────────────────────────────────────╯│
    └──────────────────────────────────────────────┘
    |}]

let%expect_test "side by side charts carry current value, min and max, y axis and time axis" =
  print_string (render ~width:100 ~height:12 (metrics_view ~width:100 ~height:12 ()));
  [%expect {|
    ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │╭ Metrics · MOCK ──────────────────────────────────────────────────────────────────────────────────╮│
    ││ decisions/s              6.0/s  admit ratio               1.00  trace loss/s               0.0/s ││
    ││ min 3.0 · max 6.0               min 0.00 · max 1.00             min 0.0 · max 3.0                ││
    ││ 8┤· · · · ·                       1┤· · · · ⠨⣻⡯⡯⣿⣻⣿⡯⣿ ·⣻⡯⣿⣻⣻⡯⣿  4┤· · · · ·                      ││
    ││  │ · · · · ⠠⣤⣤⡤⣤⣤⡤⣤⣤⣤⡤⣤⣤⣤⡤⣤⣤⡤⣤     │ · · · ·⠨⣺⡯⡯⣿⣺⣿⡯⣿· ⣺⡯⣿⣺⣺⡯⣿   │ · · · · ·              ⢠⡄     ││
    ││ 4┤·no data·⠨⣺⣿⡯⣿⣺⡯⣿⣿⣺⡯⣿⣺⣿⡯⣿⣺⡯⣿  0.5┤· · · · ⠨⣺⡯⡯⣿⣺⣿⡯⣿ ·⣺⡯⣿⣺⣺⡯⣿  2┤·no data·               ⢸⡇     ││
    ││  │ · · · · ⠨⡺⡿⡯⡿⡺⡯⡿⡿⡺⡯⡿⡺⡿⡯⡿⡺⡯⡿     │ · · · ·⠨⣺⡯⡯⣿⣺⣿⡯⣿· ⣺⡯⣿⣺⣺⡯⣿   │ · · · · ·              ⢸⡇     ││
    ││  │· · · · ·⠨⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪     │· · · · ⠨⣺⡯⡯⣿⣺⣿⡯⣿ ·⣺⡯⣿⣺⣺⡯⣿   │· · · · ·               ⢸⡇     ││
    ││ 0┤ · · · · ⠨⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪⡪    0┤ · · · ·⠨⣺⡯⡯⣿⣺⣿⡯⣿· ⣺⡯⣿⣺⣺⡯⣿  0┤ · · · · ·⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣸⣇⣀⣀⣀⣀ ││
    ││  └−60s ────── −30s ─────── now     └−60s ───── −30s ────── now   └−60s ─────── −30s ──────── now ││
    ││ 60 s window · sampled 1 Hz · admit ratio = admitted ÷ (admitted + blocked)                       ││
    │╰──────────────────────────────────────────────────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────────────────────────────────────────────────┘
    |}]

(* Catches an empty void where data has not arrived, and "last —" next to a known min/max. *)
let%expect_test "absent data is an explicit region and a missing newest value says why" =
  let pending = observed [ 0., counters ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 () ] in
  let lost = observed [ 0., counters ~connected:false ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 ()
                      ; 1., counters ~connected:false ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 () ] in
  let quiet = observed (List.init 6 ~f:(fun second ->
      Float.of_int second, counters ~decisions:(second * 4) ~admitted:(Int.min second 3)
                             ~blocked:0 ~loss:0 ())) in
  let screen ~width ~height metrics =
    render ~width ~height (metrics_view ~metrics ~now:5. ~width ~height ()) in
  print_string (screen ~width:60 ~height:10 pending);
  ensure (contains (screen ~width:60 ~height:10 lost) "stream lost") "disconnect not stated";
  ensure (contains (screen ~width:100 ~height:12 quiet) "no outcomes") "undefined newest ratio not named";
  ensure (contains (screen ~width:200 ~height:12 quiet) "now: no outcomes in the last 1 s")
    "undefined newest ratio not defined";
  ensure (not (contains (screen ~width:100 ~height:12 quiet) "last —")) "bare last dash is back";
  print_string (screen ~width:100 ~height:12 quiet);
  [%expect {|
    ┌────────────────────────────────────────────────────────────┐
    │╭ Metrics · MOCK ──────────────────────────────────────────╮│
    ││ decisions/s  — · · · · · no data · collecting  · · · ·   ││
    ││ admit ratio  — · · · · · no data · collecting  · · · ·   ││
    ││ trace loss/s — · · · · · no data · collecting  · · · ·   ││
    ││               └−60s ──────────── −30s ───────────── now  ││
    ││ 60 s window · sampled 1 Hz                               ││
    ││ admit ratio = admitted ÷ (admitted + blocked)            ││
    ││                                                          ││
    ││                                                          ││
    │╰──────────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────────┘
    ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │╭ Metrics · MOCK ──────────────────────────────────────────────────────────────────────────────────╮│
    ││ decisions/s              4.0/s  admit ratio        no outcomes  trace loss/s               0.0/s ││
    ││ min 4.0 · max 4.0               min 1.00 · max 1.00             min 0.0 · max 0.0                ││
    ││   5┤· · · · · · · · · · · ·       1┤· · · · · · · · · · · ·⠨⡫     1┤· · · · · · · · · · · · ·    ││
    ││    │ · · · · · · · · · · · ⠰⡲⡲     │ · · · · · · · · · · · ⠨⡪·     │ · · · · · · · · · · · ·     ││
    ││ 2.5┤· · · · no data · · · ·⠨⡪⡪  0.5┤· · · · no data · · · ·⠨⡪   0.5┤· · · ·  no data  · · · ·    ││
    ││    │ · · · · · · · · · · · ⠨⡪⡪     │ · · · · · · · · · · · ⠨⡪·     │ · · · · · · · · · · · ·     ││
    ││    │· · · · · · · · · · · ·⠨⡪⡪     │· · · · · · · · · · · ·⠨⡪      │· · · · · · · · · · · · ·    ││
    ││   0┤ · · · · · · · · · · · ⠨⡪⡪    0┤ · · · · · · · · · · · ⠨⡪·    0┤ · · · · · · · · · · · · ⢀⣀⣀ ││
    ││    └−60s ───── −30s ────── now     └−60s ───── −30s ────── now     └−60s ────── −30s ─────── now ││
    ││ 60 s window · sampled 1 Hz · admit ratio = admitted ÷ (admitted + blocked)                       ││
    │╰──────────────────────────────────────────────────────────────────────────────────────────────────╯│
    └────────────────────────────────────────────────────────────────────────────────────────────────────┘
    |}]

(* ---- Latency ---- *)

let%expect_test "percentile markers land in their bins, in order, with the tail to their right" =
  let p50, p99, maximum = Latency_panel.percentiles in
  let low = List.min_elt Latency_panel.synthetic ~compare:Int.compare |> Option.value_exn in
  printf "p50 %d p99 %d max %d low %d\n" p50 p99 maximum low;
  List.iter [ 8; 20; 56; 86 ] ~f:(fun bins ->
    let bin = Latency_panel.bin_of ~low ~high:maximum ~bins in
    ensure (bin low = 0 && bin maximum = bins - 1) "bounds are not the first and last bin";
    ensure (bin p50 < bin p99 && bin p99 < bins - 1) "markers out of order or no tail";
    printf "%2d bins: p50 in bin %2d, p99 in bin %2d, tail %d bins\n" bins (bin p50) (bin p99)
      (bins - 1 - bin p99));
  [%expect {|
    p50 233 p99 366 max 452 low 188
     8 bins: p50 in bin  1, p99 in bin  5, tail 2 bins
    20 bins: p50 in bin  3, p99 in bin 13, tail 6 bins
    56 bins: p50 in bin  9, p99 in bin 37, tail 18 bins
    86 bins: p50 in bin 14, p99 in bin 57, tail 28 bins
    |}]

let%expect_test "labels slide to the nearest free column and are dropped, never overlapped" =
  let labels : Latency_panel.label list =
    [ { variants = [ "188 ns" ]; start = 0; role = Muted }
    ; { variants = [ "452 ns" ]; start = 24; role = Muted }
    ; { variants = [ "p99 366 ns"; "p99 366" ]; start = 22; role = Warn }
    ; { variants = [ "p50 233 ns"; "p50 233" ]; start = 5; role = Bid } ] in
  List.iter [ 60; 31; 24 ] ~f:(fun width ->
    let placed = Latency_panel.place ~width labels in
    ensure (List.for_all placed ~f:(fun p -> p.column >= 0 && p.column + String.length p.text <= width)) "label off the row";
    printf "%2d: %s\n" width
      (String.concat ~sep:" | " (List.map placed ~f:(fun p -> sprintf "%d:%s" p.column p.text))));
  [%expect {|
    60: 0:188 ns | 7:p50 233 ns | 24:452 ns | 31:p99 366 ns
    31: 0:188 ns | 13:p99 366 ns | 24:452 ns
    24: 0:188 ns | 7:p50 233 ns | 18:452 ns
    |}]

let latency ~width ~height = Latency_panel.view ~theme ~focus:Latency ~state:base ~width ~height

let%expect_test "latency degrades to one line of histogram with the range at both ends" =
  List.iter [ 12; 7; 5; 4; 3 ] ~f:(fun height ->
    ensure (View.height (latency ~width:60 ~height) = height) "panel overflowed";
    printf "height %d\n" height;
    Bonsai_term_test.print_view (latency ~width:60 ~height));
  [%expect {|
    height 12
    ╭ Latency · MOCK synthetic ────────────────────────────────╮
    │ snapshot→candidate latency, ns · n=2000 · p50 233 ns     │
    │      ▃ █ ╎                           ╎                   │
    │     ▂█▄█▆▃ ▁                         ╎                   │
    │     ██████ █▁                        ╎                   │
    │   ▃▇██████▇██▃▇▆▁                    ╎                   │
    │   ███████████████▂▂▂ ▂               ╎                   │
    │ ▃▇██████████████████▆█▇▄▇▅▃▃▅▂▁▃▂▃▂▂▂▂▁▁▁▁▁▁▁▁▁  ▁▁  ▁▁▁ │
    │ ├────────┴───────────────────────────┴─────────────────┤ │
    │ 188 ns   p50 233 ns                  p99 366 ns   452 ns │
    │ MOCK synthetic, seed 42: not a hardware measurement      │
    ╰──────────────────────────────────────────────────────────╯
    height 7
    ╭ Latency · MOCK synthetic ────────────────────────────────╮
    │ snapshot→candidate latency, ns · n=2000 · p50 233 ns     │
    │     ▄▇▄█▅▄ ▃▁                        ╎                   │
    │ ▁▃▇██████████▇██▆▄▄▄▂▄▃▂▃▂▁▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁  ▁▁  ▁▁▁ │
    │ 188 ns   p50 233 ns                  p99 366 ns   452 ns │
    │ MOCK synthetic, seed 42: not a hardware measurement      │
    ╰──────────────────────────────────────────────────────────╯
    height 5
    ╭ Latency · MOCK synthetic ────────────────────────────────╮
    │ ▁▂▄▄▆█▆█▇│▄▆▅▄▄▄▃▂▂▂▁▂▂▁▂▁▁▁▁▁▁▁▁▁▁▁▁│▁▁▁▁▁▁▁▁▁  ▁▁  ▁▁▁ │
    │ 188 ns   p50 233 ns                  p99 366 ns   452 ns │
    │ MOCK synthetic, seed 42: not a hardware measurement      │
    ╰──────────────────────────────────────────────────────────╯
    height 4
    ╭ Latency · MOCK synthetic ────────────────────────────────╮
    │ 188 ns ▁▂▅▇██▇│▆▅▅▄▃▂▂▂▂▁▂▁▁▁▁▁▁▁▁▁│▁▁▁▁▁▁▁ ▁  ▁▁ 452 ns │
    │ MOCK synthetic, seed 42: not a hardware measurement      │
    ╰──────────────────────────────────────────────────────────╯
    height 3
    ╭ Latency · MOCK synthetic ────────────────────────────────╮
    │ 188 ns ▁▂▅▇██▇│▆▅▅▄▃▂▂▂▂▁▂▁▁▁▁▁▁▁▁▁│▁▁▁▁▁▁▁ ▁  ▁▁ 452 ns │
    ╰──────────────────────────────────────────────────────────╯
    |}]

let%expect_test "a narrow latency panel wraps the MOCK disclaimer rather than clipping it" =
  Bonsai_term_test.print_view (latency ~width:36 ~height:9);
  Bonsai_term_test.print_view (latency ~width:36 ~height:5);
  ensure (contains (render ~width:36 ~height:9 (latency ~width:36 ~height:9)) "not a hardware measurement")
    "disclaimer clipped";
  [%expect {|
    ╭ Latency · MOCK synthetic ────────╮
    │ snapshot→candidate latency, ns   │
    │   ▃▇█▃▂ ▁            ╎           │
    │ ▂▇███████▆▄▃▃▂▂▁▂▁▁▁▁▁▁▁▁▁▁ ▁ ▁▁ │
    │ ├────┴───────────────┴─────────┤ │
    │ 188 ns p50 233 p99 366 ns 452 ns │
    │ MOCK synthetic, seed 42:         │
    │ not a hardware measurement       │
    ╰──────────────────────────────────╯
    ╭ Latency · MOCK synthetic ────────╮
    │ ▁▄▆██│▅▄▅▃▂▂▂▁▁▁▁▁▁▁▁│▁▁▁▁▁ ▁ ▁▁ │
    │ 188 ns p50 233 p99 366 ns 452 ns │
    │ MOCK synthetic: not hardware     │
    ╰──────────────────────────────────╯
    |}]

(* ---- Configuration and Rules ---- *)

(* The backend [steps] quarter-seconds into applying its proposal: 7 is mid-apply, 14 done. *)
let after_apply ~steps =
  let backend = Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
  let backend = Mock_backend.handle_command backend (Apply_proposal (Mock_backend.state backend).proposal) in
  List.fold (List.range 0 steps) ~init:backend ~f:(fun backend _ -> Mock_backend.advance backend)
  |> Mock_backend.state

let applying = after_apply ~steps:7
let applied = after_apply ~steps:14

let summary ?(width = 62) ~height state =
  Config_review.view ~theme ~focus:Market ~state ~width ~height

let%expect_test "configuration summary: apply progress, preflight and a newest-first timeline" =
  Bonsai_term_test.print_view (summary ~height:22 applying);
  (* The same events in the opposite order must read the same: order is by sequence. *)
  let reversed = { applying with config_events = List.rev applying.config_events } in
  ensure (String.equal (render ~width:62 ~height:22 (summary ~height:22 applying))
            (render ~width:62 ~height:22 (summary ~height:22 reversed))) "timeline follows list order";
  (* After the final ACK the proposal's base version is stale; that is not a failed check. *)
  Bonsai_term_test.print_view (summary ~height:10 applied);
  [%expect {|
    ╭ Configuration · MOCK ──────────────────────────────────────╮
    │ ◐ APPLYING · last ACK v12 · engine ○ DISARMED              │
    │ apply ✓✓✓◐○○ 4/6 write                                     │
    │ preflight ✓ build ✓ base ✓ ranges ✓ engine                 │
    │ proposal mock-proposal-13 · base v12 → v13                 │
    │ Δ maximum_price 1005→1006 · quantity 1→2                   │
    │ maximum_price 1005 t [995 ━━━━━━━━━━━━━━━━━●──────── 1010] │
    │ quantity         1 u [1 ●────────────────────────────── 5] │
    │ manifest m01 · MOCK logical C0 · 1 compiled rule           │
    │ events · newest first · #n is the backend sequence         │
    │ #6  ▸ write started · cfg v12                              │
    │ #5  ✓ wait idle acknowledged · cfg v12                     │
    │ #4  ▸ wait idle started · cfg v12                          │
    │ #3  ✓ disable acknowledged · cfg v12                       │
    │ #2  ▸ disable started · cfg v12                            │
    │ #1  ✓ validate acknowledged · cfg v12                      │
    │ #0  ▸ validate started · cfg v12                           │
    │                                                            │
    │                                                            │
    │                                                            │
    │ c review / apply                                           │
    ╰────────────────────────────────────────────────────────────╯
    ╭ Configuration · MOCK ──────────────────────────────────────╮
    │ ✓ ACK v13 · engine ● ARMED                                 │
    │ apply ✓✓✓✓✓✓ 6/6 acknowledged                              │
    │ preflight · proposal already applied as ACK v13            │
    │ proposal mock-proposal-13 · base v12 → v13                 │
    │ Δ proposal changes nothing                                 │
    │ maximum_price 1006 t [995 ━━━━━━━━━━━━━━━━━━●─────── 1010] │
    │ quantity         2 u [1 ━━━━━━━━●────────────────────── 5] │
    │ c review / apply                                           │
    ╰────────────────────────────────────────────────────────────╯
    |}]

let%expect_test "range bars mark the value at the bounds and the midpoint, and flag a value outside" =
  let with_values values = { base with configuration = { base.configuration with parameters = values } } in
  List.iter [ "low and high", [ "maximum_price", 995; "quantity", 5 ]
            ; "midpoint", [ "maximum_price", 1002; "quantity", 3 ]
            ; "outside", [ "maximum_price", 1200; "quantity", 0 ] ] ~f:(fun (label, values) ->
    printf "%s\n" label;
    Bonsai_term_test.print_view (summary ~width:52 ~height:(Config_review.height (with_values values)) (with_values values)));
  [%expect {|
    low and high
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    │ maximum_price 995 t [995 ●──────────────── 1010] │
    │ quantity        5 u [1 ━━━━━━━━━━━━━━━━━━━━━● 5] │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    midpoint
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    │ maximum_price 1002 t [995 ━━━━━━━●──────── 1010] │
    │ quantity         3 u [1 ━━━━━━━━━━●────────── 5] │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    outside
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    │ maximum_price 1200 t [995 ━━━━━━━━━━━━━━━▶ 1010] │
    │ quantity         0 u [1 ◀──────────────────── 5] │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    |}]

let rule_state ?reason ~matched ~admitted ~blocked () =
  let rule = List.hd_exn base.rules in
  { base with rules = [ { rule with matched; admitted; blocked; last_block_reason = reason } ] }

let rules ?(width = 56) ~height state =
  Rules_panel.view ~theme ~focus:Rules ~state ~selected:(Some "slot-0") ~width ~height

let%expect_test "rules show outcome bars and an admit ratio bar, and degrade to counters" =
  let state = rule_state ~matched:100 ~admitted:60 ~blocked:40 ~reason:"price 1000 t outside [1001, 1005] t" () in
  Bonsai_term_test.print_view (rules ~height:16 state);
  Bonsai_term_test.print_view (rules ~height:8 state);
  Bonsai_term_test.print_view (rules ~height:16 (rule_state ~matched:0 ~admitted:0 ~blocked:0 ()));
  [%expect {|
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                            ● ON │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ slot-0 · config v12                                  │
    │ maximum_price 1005 t                                 │
    │ quantity         1 u                                 │
    │ matched  100 ▕████████████████████████████████▏ 100% │
    │ admitted  60 ▕███████████████████▎░░░░░░░░░░░░▏  60% │
    │ blocked   40 ▕████████████▊░░░░░░░░░░░░░░░░░░░▏  40% │
    │ admit        ▕███████████████████▎░░░░░░░░░░░░▏  60% │
    │ last block: price 1000 t outside [1001, 1005] t      │
    │ cfg ✓ACK v12 · MOCK                                  │
    │                                                      │
    │                                                      │
    │                                                      │
    ╰──────────────────────────────────────────────────────╯
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                            ● ON │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ maximum_price 1005 t  quantity 1 u                   │
    │ matched 100  admitted 60  blocked 40                 │
    │ last block: price 1000 t outside [1001, 1005] t      │
    │ cfg ✓ACK v12 · MOCK                                  │
    ╰──────────────────────────────────────────────────────╯
    ╭ Rules ───────────────────────────────────────────────╮
    │ ▸ #0 buy_below_limit                            ● ON │
    │ ask_px ≤ maximum_price → BUY qty @ ask_px            │
    │ slot-0 · config v12                                  │
    │ maximum_price 1005 t                                 │
    │ quantity         1 u                                 │
    │ matched  0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — │
    │ admitted 0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — │
    │ blocked  0 ▕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▏    — │
    │ admit      ▕··································▏ none │
    │ last block: none (0 blocked)                         │
    │ cfg ✓ACK v12 · MOCK                                  │
    │                                                      │
    │                                                      │
    │                                                      │
    ╰──────────────────────────────────────────────────────╯
    |}]

let%expect_test "rules read their recent outcomes from the decision log" =
  let backend = Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
  let state = List.fold (List.range 0 40) ~init:backend ~f:(fun backend _ -> Mock_backend.advance backend)
              |> Mock_backend.state in
  let text = render ~width:56 ~height:22 (rules ~width:56 ~height:22 state) in
  ensure (contains text "recent") "outcome strip missing";
  ensure (contains text "blocked by reason") "reason table missing";
  printf "strip and reasons present for %d decisions\n" (Map.length state.decisions.records);
  [%expect {| strip and reasons present for 40 decisions |}]

let%expect_test "debug overlay shows how much of the frame budget p99 uses" =
  let stats : Ui_types.frame_stats =
    { last_ms = 3.2; avg_ms = 2.8; p50_ms = 2.6; p99_ms = 8.; max_ms = 9.4
    ; events_per_second = 987.4; render_count = 1203; coalesced_frames = 18797; buffer_sizes = [] } in
  List.iter [ 8.; 16.; 21.5 ] ~f:(fun p99_ms ->
    let view = Debug_overlay.view ~theme ~stats:{ stats with p99_ms } in
    let line = List.find_exn (String.split_lines (render ~width:42 ~height:10 view)) ~f:(fun line -> contains line "budget") in
    printf "%s\n" (String.strip (String.substr_replace_all line ~pattern:"│" ~with_:"")));
  [%expect {|
    █████░░░░░ p99 within 16 ms budget
    ██████████ p99 within 16 ms budget
    ██████████ p99 over budget (16 ms)
    |}]

(* Catches an index error or an overflow at a size nobody looked at: every panel returns
   exactly the rect it was given, with data, without it, and in every colour capability. *)
let%expect_test "no panel raises or overflows at any size, in any colour capability" =
  let widths = [ 0; 1; 2; 3; 4; 5; 6; 8; 10; 12; 16; 20; 24; 30; 36; 40; 48; 56; 64; 66; 70; 80; 100; 120; 160; 200 ]
  and heights = [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11; 12; 14; 16; 20; 24; 40; 60 ] in
  let pending = observed [ 0., counters ~decisions:0 ~admitted:0 ~blocked:0 ~loss:0 () ] in
  let state = rule_state ~matched:100 ~admitted:60 ~blocked:40 ~reason:"price 1000 t outside [1001, 1005] t" () in
  let checked = ref 0 in
  List.iter [ Theme.Truecolor; Ansi256; Ansi16; No_color ] ~f:(fun capability ->
    let theme = Theme.create capability in
    List.iter widths ~f:(fun width ->
      List.iter heights ~f:(fun height ->
        let panels =
          [ "metrics", Metrics_panel.view ~theme ~focus:Metrics ~metrics:busy ~now:(at 40.) ~width ~height
          ; "metrics without data", Metrics_panel.view ~theme ~focus:Metrics ~metrics:pending ~now:(at 40.) ~width ~height
          ; "latency", Latency_panel.view ~theme ~focus:Latency ~state:base ~width ~height
          ; "rules", Rules_panel.view ~theme ~focus:Rules ~state ~selected:(Some "slot-0") ~width ~height
          ; "configuration", Config_review.view ~theme ~focus:Configuration ~state:applying ~width ~height ] in
        List.iter panels ~f:(fun (name, view) ->
          incr checked;
          if View.width view <> width || View.height view <> height then
            failwith (sprintf "%s is %dx%d in a %dx%d rect" name (View.width view) (View.height view) width height)))));
  printf "%d panel renders, each exactly its rect\n" !checked;
  [%expect {| 9880 panel renders, each exactly its rect |}]
