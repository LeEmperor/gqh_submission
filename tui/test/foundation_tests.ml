open! Core
open Bonsai_term
open Tickweave_tui

let ensure condition message = if not condition then failwith message
let focus_equal = Keymap.equal_focus
let cycle ~visible focus direction = Keymap.cycle ~visible focus direction

let%expect_test "cycle wraps within the visible panels in list order" =
  let visible = Keymap.[ Market; Rules; Decisions ] in
  ensure (focus_equal (cycle ~visible Market `Next) Rules) "Market next";
  ensure (focus_equal (cycle ~visible Rules `Next) Decisions) "Rules next";
  ensure (focus_equal (cycle ~visible Decisions `Next) Market) "Next did not wrap";
  ensure (focus_equal (cycle ~visible Decisions `Previous) Rules) "Decisions previous";
  ensure (focus_equal (cycle ~visible Market `Previous) Decisions) "Previous did not wrap";
  ensure (focus_equal (cycle ~visible:[ Inspector ] Inspector `Next) Inspector) "Singleton next";
  ensure (focus_equal (cycle ~visible:[ Inspector ] Inspector `Previous) Inspector) "Singleton previous"

let%expect_test "cycle follows list order, not declaration order" =
  let visible = Keymap.[ Tape; Market; Latency ] in
  ensure (focus_equal (cycle ~visible Tape `Next) Market) "Tape next";
  ensure (focus_equal (cycle ~visible Market `Next) Latency) "Market next";
  ensure (focus_equal (cycle ~visible Latency `Next) Tape) "Latency next"

let%expect_test "cycle from a hidden panel enters at the first or last visible one" =
  let visible = Keymap.[ Rules; Decisions; Inspector ] in
  ensure (focus_equal (cycle ~visible Market `Next) Rules) "Hidden next is first";
  ensure (focus_equal (cycle ~visible Market `Previous) Inspector) "Hidden previous is last"

let%expect_test "cycle with nothing visible keeps the current panel" =
  List.iter [ `Next; `Previous ] ~f:(fun direction ->
    ensure (focus_equal (cycle ~visible:[] Tape direction) Tape) "Empty visible moved focus")

let%expect_test "the original five panels still cycle exactly as before" =
  let original = Keymap.[ Market; Rules; Decisions; Inspector; Configuration ] in
  List.iteri original ~f:(fun i panel ->
    let n = List.length original in
    ensure (focus_equal (Keymap.next panel) (List.nth_exn original ((i + 1) % n))) "next";
    ensure (focus_equal (Keymap.previous panel) (List.nth_exn original ((i + n - 1) % n))) "previous")

let%expect_test "new panels have names and fall back to the original ring" =
  List.iter Keymap.[ Heatmap, "Heatmap"; Tape, "Tape"; Metrics, "Metrics"; Latency, "Latency" ]
    ~f:(fun (panel, expected) ->
      ensure (String.equal (Keymap.name panel) expected) ("name of " ^ expected);
      ensure (focus_equal (Keymap.next panel) Rules) (expected ^ " next");
      ensure (focus_equal (Keymap.previous panel) Market) (expected ^ " previous"));
  ensure ([%equal: Keymap.focus list] Keymap.all_of_focus Ui_types.all_of_panel_id)
    "focus is panel_id"

let rgb_equal = [%equal: int * int * int]
let color_equal = Option.equal Attr.Color.equal

let%expect_test "blend interpolates, rounds and clamps t" =
  let black = 0, 0, 0 and white = 255, 255, 255 in
  ensure (rgb_equal (Theme.blend black white 0.) black) "t=0 is the first colour";
  ensure (rgb_equal (Theme.blend black white 1.) white) "t=1 is the second colour";
  ensure (rgb_equal (Theme.blend black white 0.5) (128, 128, 128)) "midpoint rounds half up";
  ensure (rgb_equal (Theme.blend (10, 20, 30) (30, 20, 10) 0.5) (20, 20, 20)) "per channel";
  ensure (rgb_equal (Theme.blend black white (-3.)) black) "t below 0 clamps";
  ensure (rgb_equal (Theme.blend black white 7.) white) "t above 1 clamps";
  ensure (rgb_equal (Theme.blend white black 0.25) (191, 191, 191)) "descending channels"

let%expect_test "rgb_color quantises per capability" =
  let check capability rgb expected =
    let got = Theme.rgb_color (Theme.create capability) rgb in
    ensure (color_equal got expected)
      (sprintf "%s %s: got %s" (Sexp.to_string ([%sexp_of: Theme.capability] capability))
         (Sexp.to_string ([%sexp_of: int * int * int] rgb))
         (Sexp.to_string ([%sexp_of: Attr.Color.t option] got)))
  in
  let index i = Some (Attr.Color.xterm_256 i) in
  check Truecolor (0xF5, 0xA6, 0x23) (Some (Attr.Color.rgb ~r:0xF5 ~g:0xA6 ~b:0x23));
  (* 6x6x6 cube: 16 + 36r + 6g + b over levels 0 95 135 175 215 255 *)
  check Ansi256 (255, 0, 0) (index 196);
  check Ansi256 (0, 255, 0) (index 46);
  check Ansi256 (0, 0, 255) (index 21);
  check Ansi256 (0, 0, 0) (index 16);
  check Ansi256 (255, 255, 255) (index 231);
  check Ansi256 (255, 215, 0) (index 220);
  check Ansi256 (0x5F, 0x87, 0xAF) (index 67);
  (* grey ramp 232..255 is 8 + 10i; it wins over the cube for near-greys *)
  check Ansi256 (128, 128, 128) (index 244);
  check Ansi256 (8, 8, 8) (index 232);
  check Ansi256 (238, 238, 238) (index 255);
  (* the 16 standard xterm entries, nearest by squared distance *)
  check Ansi16 (255, 0, 0) (index 9);
  check Ansi16 (0, 255, 0) (index 10);
  check Ansi16 (205, 0, 0) (index 1);
  check Ansi16 (0, 0, 238) (index 4);
  check Ansi16 (0, 0, 0) (index 0);
  check Ansi16 (255, 255, 255) (index 15);
  check Ansi16 (127, 127, 127) (index 8);
  check Ansi16 (0xF5, 0xA6, 0x23) (index 3);
  check No_color (255, 0, 0) None

let%expect_test "detect prefers NO_COLOR, then COLORTERM, then TERM" =
  let detect env =
    (Theme.detect_from ~getenv:(fun name -> List.Assoc.find env ~equal:String.equal name)).capability in
  let check env expected =
    ensure (Theme.equal_capability (detect env) expected)
      (Sexp.to_string ([%sexp_of: (string * string) list] env)) in
  check [] Ansi16;
  check [ "TERM", "xterm-256color" ] Ansi256;
  check [ "TERM", "xterm" ] Ansi16;
  check [ "COLORTERM", "truecolor"; "TERM", "xterm-256color" ] Truecolor;
  check [ "COLORTERM", "24bit" ] Truecolor;
  check [ "COLORTERM", "yes"; "TERM", "screen-256color" ] Ansi256;
  check [ "NO_COLOR", "1"; "COLORTERM", "truecolor"; "TERM", "xterm-256color" ] No_color

let%expect_test "the existing palette is unchanged for Truecolor, Ansi16 and No_color" =
  let truecolor = Theme.create Truecolor and ansi16 = Theme.create Ansi16 in
  ensure (color_equal (Some (Theme.color truecolor Focus)) (Some (Attr.Color.rgb ~r:0xF5 ~g:0xA6 ~b:0x23)))
    "Truecolor Focus";
  ensure (Attr.Color.equal (Theme.color ansi16 Focus) (Attr.Color.xterm_256 3)) "Ansi16 Focus index";
  ensure (Attr.Color.equal (Theme.color ansi16 Bid) (Attr.Color.xterm_256 2)) "Ansi16 Bid index";
  ensure (List.is_empty (Theme.attrs (Theme.create No_color) Alarm)) "No_color has no attrs";
  ensure (rgb_equal (Theme.role_rgb truecolor Focus) (0xF5, 0xA6, 0x23)) "role_rgb Focus";
  ensure (rgb_equal (Theme.role_rgb (Theme.dim truecolor) Focus) (Theme.role_rgb truecolor Muted))
    "dimmed foreground roles read as Muted";
  ensure (rgb_equal (Theme.role_rgb (Theme.dim truecolor) Bg) (Theme.role_rgb truecolor Bg))
    "dimmed Bg is kept"

let%expect_test "Ansi256 colour and attrs go through the cube and grey ramp" =
  let theme = Theme.create Ansi256 in
  ensure (Attr.Color.equal (Theme.color theme Focus) (Attr.Color.xterm_256 214)) "Focus is amber 214";
  ensure (List.length (Theme.attrs theme Alarm) = 3) "Alarm has fg, bg and bold";
  ensure (List.length (Theme.attrs theme Text) = 1) "Text has a foreground only";
  ensure (not (List.is_empty (Theme.flash_attrs theme Bid ~intensity:0.5))) "flash draws a background"
