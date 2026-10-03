open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
module Scheme = Bonsai_term_color_scheme
module Effect = Bonsai_term.Effect

let ensure = Shell_tests.ensure
let contains = Shell_tests.contains
let key = Shell_tests.key
let screen = Shell_tests.screen
let send handle event = Bonsai_term_test.send_event handle event
let press handle c = send handle (key (ASCII c))
let sizes = [ 100, 30; 120, 36; 160, 45; 200, 60 ]

(* --- Pure layout invariants ------------------------------------------------------ *)

let body ~preset ~zoom ~heatmap (width, height) =
  Layout.compute ~preset ~zoom ~toggles:{ heatmap; cumulative = false } ~width
    ~height:(Layout.body_height ~height)

let inside ~width ~height (r : Ui_types.rect) =
  r.col >= 0 && r.row >= 0 && r.width > 0 && r.height > 0
  && r.col + r.width <= width && r.row + r.height <= height
let disjoint (a : Ui_types.rect) (b : Ui_types.rect) =
  a.col + a.width <= b.col || b.col + b.width <= a.col
  || a.row + a.height <= b.row || b.row + b.height <= a.row
let rec pairs = function [] -> [] | x :: rest -> List.map rest ~f:(fun y -> x, y) @ pairs rest

(* Catches overlapping tiles, panels spilling out of the body, gaps, and panels squeezed
   below a usable size, for every preset, toggle and supported terminal size. *)
let%expect_test "every preset tiles the body at every supported size" =
  let checked = ref 0 in
  List.iter sizes ~f:(fun ((width, terminal_height) as size) ->
    let height = Layout.body_height ~height:terminal_height in
    List.iter Ui_types.all_of_preset ~f:(fun preset ->
      List.iter [ true; false ] ~f:(fun heatmap ->
        let panels = body ~preset ~zoom:None ~heatmap size in
        let label = sprintf "%s %dx%d heatmap=%b" (Presets.name preset) width terminal_height heatmap in
        ensure (not (List.is_empty panels)) (label ^ ": empty");
        ensure (List.for_all panels ~f:(fun (_, r) -> inside ~width ~height r)) (label ^ ": outside body");
        ensure (List.for_all (pairs panels) ~f:(fun ((_, a), (_, b)) -> disjoint a b)) (label ^ ": overlap");
        ensure (List.sum (module Int) panels ~f:(fun (_, r) -> r.width * r.height) = width * height)
          (label ^ ": gaps");
        ensure (List.for_all panels ~f:(fun (_, r) -> r.width >= 24 && r.height >= 5))
          (label ^ ": panel too small");
        ensure (List.contains_dup (List.map panels ~f:fst) ~compare:Ui_types.compare_panel_id |> not)
          (label ^ ": duplicate panel");
        incr checked)));
  printf "%d layouts: inside the body, disjoint, gap-free, no panel under 24x5\n" !checked;
  [%expect {| 32 layouts: inside the body, disjoint, gap-free, no panel under 24x5 |}]

let names panels = List.map panels ~f:(fun (panel, _) -> Keymap.name panel) |> String.concat ~sep:" "

let%expect_test "presets show the panels the brief names, wider screens add more" =
  let show preset size ~heatmap =
    printf "%-9s %3dx%-2d heatmap=%-5b %s\n" (Presets.name preset) (fst size) (snd size) heatmap
      (names (body ~preset ~zoom:None ~heatmap size)) in
  List.iter [ 120, 36; 200, 60 ] ~f:(fun size ->
    List.iter Ui_types.all_of_preset ~f:(fun preset -> show preset size ~heatmap:true));
  show Monitor (120, 36) ~heatmap:false;
  [%expect {|
    Monitor   120x36 heatmap=true  Market Heatmap Metrics Latency Tape
    Decide    120x36 heatmap=true  Decisions Inspector Rules
    Configure 120x36 heatmap=true  Rules Configuration Decisions
    Demo      120x36 heatmap=true  Market Decisions Metrics Rules Inspector Configuration Latency
    Monitor   200x60 heatmap=true  Market Heatmap Metrics Latency Tape
    Decide    200x60 heatmap=true  Decisions Inspector Rules
    Configure 200x60 heatmap=true  Rules Configuration Decisions
    Demo      200x60 heatmap=true  Market Decisions Inspector Rules Configuration Metrics Latency
    Monitor   120x36 heatmap=false Market Metrics Latency Tape
    |}]

(* Catches the hidden Heatmap's space going anywhere but Market. *)
let%expect_test "hiding the heatmap gives its space to Market" =
  List.iter sizes ~f:(fun size ->
    let width_of panels panel = (List.Assoc.find_exn panels panel ~equal:Keymap.equal_focus).Ui_types.width in
    let shown = body ~preset:Monitor ~zoom:None ~heatmap:true size
    and hidden = body ~preset:Monitor ~zoom:None ~heatmap:false size in
    ensure (not (List.Assoc.mem hidden Heatmap ~equal:Keymap.equal_focus)) "Heatmap still laid out";
    ensure (width_of hidden Market = width_of shown Market + width_of shown Heatmap) "Space not given to Market");
  print_endline "Market absorbs the Heatmap width at every size";
  [%expect {| Market absorbs the Heatmap width at every size |}]

let%expect_test "zoom fills the body, and is ignored for a panel the preset hides" =
  List.iter sizes ~f:(fun ((width, terminal_height) as size) ->
    let height = Layout.body_height ~height:terminal_height in
    let full = { Ui_types.col = 0; row = 0; width; height } in
    List.iter (body ~preset:Demo ~zoom:None ~heatmap:true size) ~f:(fun (panel, _) ->
      ensure ([%equal: (Keymap.focus * Ui_types.rect) list] (body ~preset:Demo ~zoom:(Some panel) ~heatmap:true size)
                [ panel, full ]) "Zoom is not the full body");
    ensure ([%equal: (Keymap.focus * Ui_types.rect) list] (body ~preset:Decide ~zoom:(Some Market) ~heatmap:true size)
              (body ~preset:Decide ~zoom:None ~heatmap:true size)) "Hidden zoom changed the layout");
  print_endline "zoom = [panel, whole body]; hidden zoom = no zoom";
  [%expect {| zoom = [panel, whole body]; hidden zoom = no zoom |}]

(* --- App-level behaviour ----------------------------------------------------------- *)

let app ?(initial = Shell_tests.state Connected_disarmed)
    ?(on_preset = fun (_ : Ui_types.preset) -> Ok ()) ?(theme = Shell_tests.theme) ?capability
    ?(preset = Ui_types.Monitor) dimensions =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions ?capability
    ~to_view_with_handler:fst
    ~handle_incoming:(fun (_, inject) state -> inject state)
    (fun ~dimensions (local_ graph) ->
      let state, inject = Bonsai.state initial graph in
      let ~view, ~handler =
        App.component ~initial_preset:preset
          ~on_preset:(Bonsai.return (fun preset -> Effect.of_sync_fun on_preset preset))
          ~theme ~state ~clock:(Bonsai.return Shell_tests.clock)
          ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
      let%arr view and handler and inject in
      ((~view, ~handler), inject))

(* The footer's right-hand status: "<preset> · <scheme> · [ZOOM · ]focus: <panel>". *)
let status handle =
  let line = List.find_exn (String.split_lines (screen handle)) ~f:(fun line -> contains line "focus: ") in
  let start = List.filter_map Ui_types.all_of_preset ~f:(fun preset ->
      String.substr_index line ~pattern:(Presets.name preset))
              |> List.fold ~init:(String.length line) ~f:Int.min in
  String.drop_prefix line start |> String.strip |> String.chop_suffix_if_exists ~suffix:"│" |> String.strip
let focused handle = List.last_exn (String.split (status handle) ~on:' ')

let%expect_test "the terminal below 100x30 shows a resize message with the current size" =
  List.iter [ 99, 30; 100, 29; 80, 24; 40, 10 ] ~f:(fun (width, height) ->
    let text = screen (app { width; height }) in
    ensure (contains text "Resize to at least 100×30") "Resize message missing";
    ensure (contains text (sprintf "now %d×%d" width height)) "Current size missing";
    ensure (not (contains text "Market · AAPL")) "Panels drawn below the minimum");
  let handle = app { width = 80; height = 24 } in
  Bonsai_term_test.set_dimensions handle { width = 100; height = 30 };
  ensure (contains (screen handle) "Market · AAPL") "Did not recover at the minimum";
  print_endline "message shows the size; 100x30 recovers";
  [%expect {| message shows the size; 100x30 recovers |}]

(* Catches focus cycling over panels the layout does not show. *)
let%expect_test "Tab cycles exactly the panels in the layout, in screen order" =
  let cycle ?(keys = []) size =
    let handle = app size in
    List.iter keys ~f:(press handle);
    (* [List.init] does not promise an evaluation order, and each step changes focus. *)
    List.folding_map (List.range 0 6) ~init:() ~f:(fun () _ ->
      let name = focused handle in
      send handle (key Tab);
      (), name) in
  printf "120x36: %s\n" (String.concat ~sep:" " (cycle { width = 120; height = 36 }));
  printf "200x60: %s\n" (String.concat ~sep:" " (cycle { width = 200; height = 60 }));
  printf "no heatmap: %s\n" (String.concat ~sep:" " (cycle ~keys:[ 'h' ] { width = 120; height = 36 }));
  [%expect {|
    120x36: Market Heatmap Metrics Latency Tape Market
    200x60: Market Heatmap Metrics Latency Tape Market
    no heatmap: Market Metrics Latency Tape Market Metrics
    |}]

let%expect_test "number keys jump, switching to the preset that shows a hidden panel" =
  let recorded = ref [] in
  let handle = app ~on_preset:(fun preset -> recorded := preset :: !recorded; Ok ()) { width = 120; height = 36 } in
  List.iter [ '1', "Monitor"; '3', "Decide"; '5', "Configure"; '2', "Configure"; '1', "Monitor" ]
    ~f:(fun (digit, expected) ->
      press handle digit;
      let line = status handle in
      ensure (contains line expected) (sprintf "%c: expected %s in %s" digit expected line);
      printf "%c -> %s\n" digit line);
  printf "saved: %s\n" (String.concat ~sep:" " (List.rev_map !recorded ~f:Presets.name));
  [%expect {|
    1 -> Monitor · amber · focus: Market
    3 -> Decide · amber · focus: Decisions
    5 -> Configure · amber · focus: Configuration
    2 -> Configure · amber · focus: Rules
    1 -> Monitor · amber · focus: Market
    saved: Decide Configure Monitor
    |}]

(* Catches F-keys that skip persistence, or persist a preset that did not change. *)
let%expect_test "F1-F4 pick presets and report each change once" =
  let recorded = ref [] in
  let handle = app ~on_preset:(fun preset -> recorded := preset :: !recorded; Ok ()) { width = 120; height = 36 } in
  List.iter [ 1; 2; 2; 3; 4; 5; 1 ] ~f:(fun n -> send handle (key (Function n)));
  ignore (screen handle : string);
  printf "%s\nnow: %s\n" (String.concat ~sep:" " (List.rev_map !recorded ~f:Presets.name)) (status handle);
  [%expect {|
    Decide Configure Demo Monitor
    now: Monitor · amber · focus: Market
    |}]

(* The brief's state-preservation promise: zoom hides other panels but forgets nothing. *)
let%expect_test "zoom round-trips with focus, selection, inspection and preset intact" =
  let backend = History_tests.backend 40 in
  let handle = app ~initial:(Mock_backend.state backend) ~preset:Decide { width = 120; height = 36 } in
  ignore (screen handle : string);
  List.iter [ '3'; 'g' ] ~f:(press handle);
  send handle (key Enter);
  let before = screen handle in
  ensure (contains before "MOCK FROZEN #1") "Setup: nothing inspected";
  press handle 'z';
  let zoomed = screen handle and zoomed_status = status handle in
  ensure (contains zoomed "ZOOM" && contains zoomed "Decisions · MOCK") "Zoom did not show Decisions";
  ensure (not (contains zoomed "MOCK FROZEN #1" || contains zoomed "Rules")) "Zoom still shows other panels";
  press handle 'z';
  let after = screen handle in
  ensure (String.equal before after) "Round trip changed the screen";
  printf "zoom: %s\nrestored: identical screen, %s\n" zoomed_status (status handle);
  [%expect {|
    zoom: Decide · amber · ZOOM · focus: Decisions
    restored: identical screen, Decide · amber · focus: Decisions
    |}]

(* --- Mouse -------------------------------------------------------------------------- *)

let rect_of ~preset size panel =
  List.Assoc.find_exn (body ~preset ~zoom:None ~heatmap:true size) panel ~equal:Keymap.equal_focus

let mouse ?(mods = []) kind ~x ~y = Event.Mouse { kind; position = { Position.x; y }; mods }
(* A body cell sits below the header row. *)
let click handle (r : Ui_types.rect) =
  send handle (mouse Left ~x:(r.col + 3) ~y:(r.row + Layout.header_rows + 2));
  send handle (mouse Release ~x:(r.col + 3) ~y:(r.row + Layout.header_rows + 2))

let%expect_test "a click focuses the panel under the pointer, only when no overlay is open" =
  let size = 120, 36 in
  let handle = app ~preset:Demo { width = 120; height = 36 } in
  List.iter [ Keymap.Rules; Inspector; Latency; Market ] ~f:(fun panel ->
    let r = rect_of ~preset:Demo size panel in
    click handle r;
    ensure (contains (status handle) ("focus: " ^ Keymap.name panel)) ("Click missed " ^ Keymap.name panel));
  send handle (mouse Left ~x:5 ~y:0);
  send handle (mouse Left ~x:5 ~y:35);
  ensure (contains (status handle) "focus: Market") "Header or footer click moved focus";
  press handle '?';
  let r = rect_of ~preset:Demo size Rules in
  click handle r;
  press handle '?';
  ensure (contains (status handle) "focus: Market") "Click leaked through help";
  print_endline "click focuses Rules, Inspector, Latency, Market; header, footer and help ignore it";
  [%expect {| click focuses Rules, Inspector, Latency, Market; header, footer and help ignore it |}]

(* The wheel acts where the pointer is, not where focus is, and never moves focus. *)
let%expect_test "the wheel steps Rules and scrolls Decisions under the pointer" =
  let initial = Shell_tests.state Enabled in
  let first = List.hd_exn initial.rules in
  let second = { first with rule_id = "slot-1"; slot = 1; name = "second_rule" } in
  let initial = { initial with rules = [ first; second ] } in
  let handle = app ~initial ~preset:Decide { width = 120; height = 36 } in
  ignore (screen handle : string);
  press handle '3';
  let rules = rect_of ~preset:Decide (120, 36) Rules in
  let wheel direction (r : Ui_types.rect) =
    send handle (mouse (Scroll direction) ~x:(r.col + 4) ~y:(r.row + Layout.header_rows + 3)) in
  wheel `Down rules;
  ensure (contains (screen handle) "▸ #1 second_rule") "Wheel down did not step Rules";
  wheel `Up rules;
  ensure (contains (screen handle) "▸ #0 buy_below_limit") "Wheel up did not step back";
  ensure (contains (status handle) "focus: Decisions") "Wheel moved focus";
  (* Decisions scrolls through its own scroller, even when it is not focused. *)
  let backend = History_tests.backend 40 in
  let handle = app ~initial:(Mock_backend.state backend) ~preset:Decide { width = 120; height = 36 } in
  ignore (screen handle : string);
  press handle '2';
  let before = screen handle in
  let decisions = rect_of ~preset:Decide (120, 36) Decisions in
  send handle (mouse (Scroll `Up) ~x:(decisions.col + 4) ~y:(decisions.row + Layout.header_rows + 3));
  ensure (not (String.equal before (screen handle))) "Wheel did not scroll Decisions";
  ensure (contains (status handle) "focus: Rules") "Decisions wheel moved focus";
  print_endline "wheel: Rules steps, Decisions scrolls, focus unchanged";
  [%expect {| wheel: Rules steps, Decisions scrolls, focus unchanged |}]

(* --- Themes ------------------------------------------------------------------------- *)

let%expect_test "t cycles amber, Tokyo Night and Mocha, then back" =
  let handle = app { width = 120; height = 36 } in
  List.iter [ "tokyo"; "mocha"; "amber" ] ~f:(fun expected ->
    press handle 't';
    ensure (contains (status handle) expected) ("Expected scheme " ^ expected);
    printf "%s\n" (status handle));
  [%expect {|
    Monitor · tokyo · focus: Market
    Monitor · mocha · focus: Market
    Monitor · amber · focus: Market
    |}]

let rgb_of_flavor flavor colour =
  let { Scheme.Rgb.r; g; b } = Scheme.to_rgb flavor colour in
  r, g, b
let rgb_equal = [%equal: int * int * int]
let themed scheme = Theme.with_scheme (Theme.create Truecolor) scheme

let%expect_test "scheme colours come from the installed colour schemes" =
  let check scheme flavor =
    let theme = themed scheme in
    ensure (rgb_equal (Theme.role_rgb theme Bg) (rgb_of_flavor flavor Scheme.Base)) "Bg is the flavor base";
    ensure (rgb_equal (Theme.role_rgb theme Text) (rgb_of_flavor flavor Scheme.Text)) "Text is the flavor text";
    ensure (rgb_equal (Theme.role_rgb theme Bid) (rgb_of_flavor flavor Scheme.Green)) "Bid is the flavor green" in
  check Tokyo_night Scheme.Tokyo_night_dark.flavor;
  check Catppuccin_mocha Scheme.Catppuccin.Mocha.flavor;
  ensure (rgb_equal (Theme.role_rgb (themed Tickweave_amber) Focus) (0xF5, 0xA6, 0x23)) "Amber palette changed";
  ensure (rgb_equal (Theme.role_rgb (Theme.create Truecolor) Bg) (0x0B, 0x0E, 0x14)) "Default is not amber";
  let distinct = List.map Ui_types.all_of_scheme ~f:(fun scheme -> Theme.role_rgb (themed scheme) Focus)
                 |> List.dedup_and_sort ~compare:[%compare: int * int * int] in
  ensure (List.length distinct = 3) "Schemes share a focus colour";
  ensure (List.length (Theme.attrs (themed Tokyo_night) Alarm) = 3) "Alarm lost its wash and bold";
  let cycle = List.fold Ui_types.all_of_scheme ~init:Ui_types.Tickweave_amber ~f:(fun scheme _ -> Theme.next_scheme scheme) in
  ensure (Ui_types.equal_scheme cycle Tickweave_amber) "Three steps do not return";
  print_endline "Tokyo Night and Mocha RGB match the colour schemes; amber unchanged";
  [%expect {| Tokyo Night and Mocha RGB match the colour schemes; amber unchanged |}]

(* WCAG contrast of every text role against the scheme's own background. *)
let contrast a b =
  let channel c =
    let c = Float.of_int c /. 255. in
    if Float.(c <= 0.03928) then c /. 12.92 else Float.(((c + 0.055) / 1.055) ** 2.4) in
  let luminance (r, g, b) = (0.2126 *. channel r) +. (0.7152 *. channel g) +. (0.0722 *. channel b) in
  let la = luminance a and lb = luminance b in
  (Float.max la lb +. 0.05) /. (Float.min la lb +. 0.05)

let%expect_test "every scheme keeps text roles readable on its background" =
  List.iter Ui_types.all_of_scheme ~f:(fun scheme ->
    let theme = themed scheme in
    let background = Theme.role_rgb theme Bg in
    List.iter Theme.[ Text; Muted; Focus; Bid; Ask; Warn; Info; Alarm ] ~f:(fun role ->
      let ratio = contrast (Theme.role_rgb theme role) background in
      ensure Float.(ratio >= 3.0)
        (sprintf "%s: contrast %.2f" (Sexp.to_string [%sexp (scheme : Ui_types.scheme)]) ratio)));
  print_endline "contrast >= 3 for every text role in every scheme";
  [%expect {| contrast >= 3 for every text role in every scheme |}]

(* --- NO_COLOR ------------------------------------------------------------------------ *)

let%expect_test "NO_COLOR draws no colour in any scheme, and status stays glyph and word" =
  List.iter Ui_types.all_of_scheme ~f:(fun scheme ->
    let theme = Theme.with_scheme (Theme.create No_color) scheme in
    List.iter Theme.[ Bg; Surface; Border; Focus; Text; Muted; Bid; Ask; Warn; Info; Alarm ] ~f:(fun role ->
      ensure (List.is_empty (Theme.attrs theme role)) "NO_COLOR attrs";
      ensure (List.is_empty (Theme.flash_attrs theme role ~intensity:1.)) "NO_COLOR flash");
    ensure (Option.is_none (Theme.rgb_color theme (1, 2, 3))) "NO_COLOR rgb_color");
  let show scenario expected =
    let text = screen (app ~initial:(Shell_tests.state scenario) ~preset:Demo { width = 120; height = 36 }) in
    List.iter expected ~f:(fun word -> ensure (contains text word) (sprintf "missing %S" word));
    printf "%s\n" (String.concat ~sep:"  " expected) in
  show Enabled [ "● ARMED"; "book ✓VALID"; "MOCK"; "focus: Market" ];
  show Connection_lost [ "?UNKNOWN"; "LOST" ];
  show Update_failed [ "✗FAILED" ];
  show Update_pending [ "◐APPLYING" ];
  show Book_invalid [ "✗INVALID" ];
  [%expect {|
    ● ARMED  book ✓VALID  MOCK  focus: Market
    ?UNKNOWN  LOST
    ✗FAILED
    ◐APPLYING
    ✗INVALID
    |}]

(* --- Persistence --------------------------------------------------------------------- *)

let with_directory f =
  let directory = Stdlib.Filename.temp_dir "tickweave-presets" "" in
  Exn.protect ~f:(fun () -> f directory) ~finally:(fun () ->
    ignore (Stdlib.Sys.command (sprintf "rm -rf %s" (Stdlib.Filename.quote directory)) : int))
let getenv_of env name = List.Assoc.find env ~equal:String.equal name

let%expect_test "the last preset round-trips through TICKWEAVE_STATE_DIR and falls back to Monitor" =
  with_directory (fun directory ->
    let getenv = getenv_of [ "TICKWEAVE_STATE_DIR", directory ^ "/nested/state" ] in
    let load () = Presets.name (Presets.load ~getenv ()) in
    printf "missing file: %s\n" (load ());
    List.iter Ui_types.all_of_preset ~f:(fun preset ->
      ensure (Or_error.is_ok (Presets.save ~getenv preset)) "save failed";
      ensure (String.equal (load ()) (Presets.name preset)) "round trip";
      printf "saved %s -> %s\n" (Presets.name preset) (load ()));
    let file = directory ^ "/nested/state/last-preset" in
    Out_channel.write_all file ~data:"not a preset\n";
    printf "garbage: %s\n" (load ());
    Out_channel.write_all file ~data:"";
    printf "empty: %s\n" (load ()));
  [%expect {|
    missing file: Monitor
    saved Monitor -> Monitor
    saved Decide -> Decide
    saved Configure -> Configure
    saved Demo -> Demo
    garbage: Monitor
    empty: Monitor
    |}]

(* A preference that cannot be written must be an error value, never an exception. *)
let%expect_test "unwritable or unresolvable state directories never raise" =
  with_directory (fun directory ->
    let blocker = directory ^ "/file" in
    Out_channel.write_all blocker ~data:"x";
    let blocked = getenv_of [ "TICKWEAVE_STATE_DIR", blocker ^ "/inside" ] in
    ensure (Or_error.is_error (Presets.save ~getenv:blocked Demo)) "Save under a file succeeded";
    ensure (Ui_types.equal_preset (Presets.load ~getenv:blocked ()) Monitor) "Load under a file";
    let nowhere = getenv_of [] in
    ensure (Or_error.is_error (Presets.save ~getenv:nowhere Demo)) "Save with no directory";
    ensure (Ui_types.equal_preset (Presets.load ~getenv:nowhere ()) Monitor) "Load with no directory");
  print_endline "save returns Error, load returns Monitor";
  [%expect {| save returns Error, load returns Monitor |}]

let%expect_test "state directory resolution: override, XDG_STATE_HOME, then HOME" =
  let show env = printf "%s\n" (Option.value (Presets.directory ~getenv:(getenv_of env)) ~default:"none") in
  show [ "TICKWEAVE_STATE_DIR", "/tmp/override"; "XDG_STATE_HOME", "/xdg"; "HOME", "/home/u" ];
  show [ "XDG_STATE_HOME", "/xdg"; "HOME", "/home/u" ];
  show [ "HOME", "/home/u" ];
  show [ "XDG_STATE_HOME", ""; "HOME", "/home/u" ];
  show [];
  [%expect {|
    /tmp/override
    /xdg/tickweave-tui
    /home/u/.local/state/tickweave-tui
    /home/u/.local/state/tickweave-tui
    none
    |}]

(* --- Keys, help and the market toggles -------------------------------------------------- *)

let%expect_test "F1-F4 and the layout keys decode; other function keys are left alone" =
  let describe event = match Keymap.action event with
    | Preset preset -> "preset " ^ Presets.name preset
    | Zoom -> "zoom" | Cycle_theme -> "theme" | Toggle_heatmap -> "heatmap"
    | Toggle_cumulative -> "cumulative" | Toggle_meter -> "meter" | Ignore -> "ignored" | _ -> "other" in
  List.iter [ key (Function 1); key (Function 2); key (Function 3); key (Function 4)
            ; key (Function 5); key (Function 12); key (Function 0)
            ; key (ASCII 'z'); key (ASCII 't'); key (ASCII 'h'); key (ASCII 'd')
            ; key ~mods:[ Ctrl ] (ASCII 'd'); key ~mods:[ Shift ] (Function 1) ]
    ~f:(fun event -> print_endline (describe event));
  [%expect {|
    preset Monitor
    preset Decide
    preset Configure
    preset Demo
    ignored
    meter
    ignored
    zoom
    theme
    heatmap
    cumulative
    ignored
    ignored
    |}]

let%expect_test "help lists every new key and the mouse, and fits the 100x30 minimum" =
  let handle = app { width = 100; height = 30 } in
  press handle '?';
  let help = screen handle in
  List.iter [ "Shift-Tab"; "F1–F4"; "Monitor Decide Configure Demo"; "zoom focused panel"; "heatmap on/off"
            ; "cumulative depth"; "theme amber/Tokyo Night/Mocha"; "click"; "wheel"
            ; "switches to the preset showing it"
            ; "╭ Help · Phase 5 / MOCK"; "╰" ]
    ~f:(fun word -> ensure (contains help word) (sprintf "Help lacks %S" word));
  print_endline "help documents F1-F4, z, h, d, t, mouse and hidden-panel jumps";
  [%expect {| help documents F1-F4, z, h, d, t, mouse and hidden-panel jumps |}]

(* d and h are global toggles in every focus; Ctrl-d pages Decisions, plain d never does. *)
let%expect_test "h hides the heatmap and d flips cumulative depth, held in app state" =
  let handle = app { width = 120; height = 36 } in
  let before = screen handle in
  ensure (contains before "Heatmap ·") "Heatmap not shown";
  press handle 'h';
  ensure (not (contains (screen handle) "Heatmap ·")) "h did not hide the heatmap";
  press handle 'h';
  ensure (contains (screen handle) "Heatmap ·") "h did not restore the heatmap";
  (* Zoomed, only Market is on screen: Tape and Heatmap animate with the clock. *)
  press handle 'z';
  let flat = screen handle in
  press handle 'd';
  ensure (not (String.equal flat (screen handle))) "d did not change the Market panel";
  press handle 'd';
  ensure (String.equal flat (screen handle)) "d did not toggle back";
  print_endline "h toggles Heatmap; d toggles Market depth and back";
  [%expect {| h toggles Heatmap; d toggles Market depth and back |}]

(* --- The real panels, themes through every component, click-to-inspect, save notices ------ *)

(* Catches a placeholder left in any preset at any size, and each real panel's title. *)
let%expect_test "every panel in every preset is the real one, not a placeholder" =
  let seen = ref [] in
  List.iter [ 120, 36; 200, 60 ] ~f:(fun (width, height) ->
    List.iter Ui_types.all_of_preset ~f:(fun preset ->
      let text = screen (app ~preset { width; height }) in
      ensure (not (contains text "pending")) (sprintf "%s %dx%d: placeholder" (Presets.name preset) width height);
      List.iter [ "Heatmap ·"; "Tape ·"; "Metrics ·"; "Latency ·" ] ~f:(fun title ->
        if contains text title && not (List.mem !seen title ~equal:String.equal) then seen := title :: !seen)));
  printf "real panels seen: %s\n" (String.concat ~sep:" " (List.sort !seen ~compare:String.compare));
  [%expect {| real panels seen: Heatmap · Latency · Metrics · Tape · |}]

(* Every amber-palette colour as the ANSI text spells it, with the Alarm wash. *)
let amber_colours =
  "rgb256-42-14-14" :: List.map Theme.[ Bg; Surface; Border; Focus; Text; Muted; Bid; Ask; Warn; Info; Alarm ]
    ~f:(fun role ->
      let r, g, b = Theme.role_rgb (Theme.create Truecolor) role in
      sprintf "rgb256-%d-%d-%d" r g b)
let amber_left text = List.filter amber_colours ~f:(contains text)

let colour_app ?(preset = Ui_types.Demo) () =
  app ~initial:(Mock_backend.state (History_tests.backend 40)) ~theme:(Theme.create Truecolor)
    ~capability:Ansi ~preset { width = 160; height = 45 }

(* Catches a component that captured the starting theme: Decisions, the Configuration
   review modal and its stepper all have to leave amber when [t] is pressed. *)
let%expect_test "t recolors Decisions and the review modal, not just the dashboard" =
  let amber = colour_app () in
  ensure (not (List.is_empty (amber_left (screen amber)))) "Setup: no amber on the dashboard";
  press amber 'c';
  ensure (contains (screen amber) "Configuration review") "Setup: modal did not open";
  ensure (not (List.is_empty (amber_left (screen amber)))) "Setup: no amber in the modal";
  let themed = colour_app () in
  press themed 't';
  let dashboard = screen themed in
  ensure (contains dashboard "Decisions · MOCK") "Decisions missing";
  printf "dashboard keeps amber: %s\n" (String.concat ~sep:" " (amber_left dashboard));
  press themed 'c';
  let modal = screen themed in
  ensure (contains modal "Configuration review") "Modal did not open after t";
  printf "modal keeps amber: %s\n" (String.concat ~sep:" " (amber_left modal));
  [%expect {|
    dashboard keeps amber:
    modal keeps amber:
    |}]

let click_row handle ~(panel : Ui_types.rect) ~row =
  let y = panel.row + Layout.header_rows + 1 + row in
  send handle (mouse Left ~x:(panel.col + 3) ~y);
  send handle (mouse Release ~x:(panel.col + 3) ~y)

(* The decision id printed on a row of the leftmost panel. *)
let id_on_row handle ~(panel : Ui_types.rect) ~row =
  let line = List.nth_exn (String.split_lines (screen handle)) (panel.row + Layout.header_rows + 1 + row + 1) in
  let _, after = String.lsplit2_exn line ~on:'#' in
  String.take_while after ~f:Char.is_digit

let%expect_test "clicking a Decisions row inspects that decision" =
  let handle = app ~initial:(Mock_backend.state (History_tests.backend 40)) ~preset:Decide
      { width = 120; height = 36 } in
  ignore (screen handle : string);
  let panel = rect_of ~preset:Decide (120, 36) Decisions in
  ensure (contains (screen handle) "Select a decision and press Enter to inspect") "Setup: already inspecting";
  List.iter [ 0; 7; 30 ] ~f:(fun row ->
    let id = id_on_row handle ~panel ~row in
    click_row handle ~panel ~row;
    let text = screen handle in
    ensure (contains text ("MOCK FROZEN #" ^ id)) (sprintf "row %d (#%s) not inspected" row id);
    ensure (contains (status handle) "focus: Decisions") "Click did not focus Decisions";
    printf "row %d inspects its own decision\n" row);
  [%expect {|
    row 0 inspects its own decision
    row 7 inspects its own decision
    row 30 inspects its own decision
    |}]

(* The frozen Inspector must not change on a click that hit no row. *)
let%expect_test "a click on the border or below the last row inspects nothing" =
  let handle = app ~initial:(Mock_backend.state (History_tests.backend 3)) ~preset:Decide
      { width = 120; height = 36 } in
  ignore (screen handle : string);
  let panel = rect_of ~preset:Decide (120, 36) Decisions in
  List.iter [ -1; 10; 20 ] ~f:(fun row -> click_row handle ~panel ~row);
  ensure (contains (screen handle) "Select a decision and press Enter to inspect") "Inspected a non-row";
  click_row handle ~panel ~row:1;
  ensure (contains (screen handle) "MOCK FROZEN #2") "A real row was not inspected";
  print_endline "border and empty rows ignored; row 1 inspects #2";
  [%expect {| border and empty rows ignored; row 1 inspects #2 |}]

let%expect_test "a failed preset save shows a short notice, keeps running, and clears on a key" =
  with_directory (fun directory ->
    let blocker = directory ^ "/file" in
    Out_channel.write_all blocker ~data:"x";
    let save getenv preset = Presets.save ~getenv:(getenv_of getenv) preset in
    let broken = app ~on_preset:(save [ "TICKWEAVE_STATE_DIR", blocker ^ "/inside" ]) { width = 120; height = 36 } in
    send broken (key (Function 2));
    let text = screen broken in
    ensure (contains text "preset not saved: Not a directory") "Notice missing";
    ensure (contains text "Decide · amber · focus: Decisions") "Preset did not change anyway";
    ensure (not (contains text "Tab/⇧Tab focus")) "Notice did not replace the hints";
    press broken '2';
    ensure (not (contains (screen broken) "preset not saved")) "Notice survived a key press";
    ensure (contains (screen broken) "focus: Rules") "Console stopped responding";
    let working = app ~on_preset:(save [ "TICKWEAVE_STATE_DIR", directory ^ "/ok" ]) { width = 120; height = 36 } in
    send working (key (Function 2));
    ensure (not (contains (screen working) "preset not saved")) "Notice on a successful save");
  print_endline "notice shown, console kept running, cleared by the next key; none on success";
  [%expect {| notice shown, console kept running, cleared by the next key; none on success |}]

(* --- F12 frame meter, through the live app ------------------------------------------------ *)

let live_app ?(preset = Ui_types.Demo) dimensions =
  let _scheduler = Async.Scheduler.t () in
  Bonsai_term_test.create_handle ~initial_dimensions:dimensions
    (App.live ~initial_preset:preset (module Mock_backend) ~theme:Shell_tests.theme
       ~backend:(Shell_tests.fixture Enabled) ~exit:(fun () -> Effect.Ignore))

(* One 60 Hz frame later. *)
let next_frame handle =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.02);
  Handle.recompute_view_until_stable handle;
  screen handle

let row_of text ~containing =
  fst (List.findi_exn (String.split_lines text) ~f:(fun _ line -> contains line containing))

let%expect_test "F12 toggles the frame meter and it hides neither the header nor the footer" =
  let handle = live_app { width = 120; height = 36 } in
  ensure (not (contains (next_frame handle) "Frame meter")) "Overlay open at start";
  send handle (key (Function 12));
  let open_ = next_frame handle in
  ensure (contains open_ "Frame meter") "F12 did not open the overlay";
  List.iter [ "tickweave ▸ MOCK"; "book ✓VALID"; "trace loss"; "focus: "; "F12" ]
    ~f:(fun field -> ensure (contains open_ field) ("Overlay hid " ^ field));
  let lines = String.split_lines open_ in
  let title = row_of open_ ~containing:"Frame meter" in
  ensure (title >= 2 && title < List.length lines - 3) "Overlay outside the body";
  ensure (contains open_ "frame work: flush+compute+paint") "Overlay lost its definition line";
  send handle (key (Function 12));
  ensure (not (contains (next_frame handle) "Frame meter")) "Second F12 did not close it";
  printf "F12 opens below the header, closes on the second press\n";
  [%expect {| F12 opens below the header, closes on the second press |}]

(* The app hands the driver its view as it is; rationing paints is [Paint_throttle]'s job, between
   the app and the driver, and is tested on its own. A burst must leave the final state. *)
let%expect_test "a burst of keys leaves the final state on screen" =
  let handle = live_app { width = 120; height = 36 } in
  ignore (next_frame handle : string);
  List.iter [ Event.Key.Tab; Tab; Tab ] ~f:(fun k -> send handle (key k));
  ensure (contains (next_frame handle) "focus: Rules") "Burst lost its final state";
  ensure (contains (next_frame handle) "focus: Rules") "State changed without input";
  print_endline "the burst's final state is on screen, and stays";
  [%expect {| the burst's final state is on screen, and stays |}]

let%expect_test "F12 decodes to the meter and is listed in help and the footer" =
  ensure (match Keymap.action (key (Function 12)) with Toggle_meter -> true | _ -> false) "F12 not decoded";
  let handle = app { width = 120; height = 36 } in
  ensure (contains (screen handle) "F12") "Footer lacks F12";
  press handle '?';
  ensure (contains (screen handle) "frame meter") "Help lacks F12";
  print_endline "F12 is decoded, in the footer and in help";
  [%expect {| F12 is decoded, in the footer and in help |}]
