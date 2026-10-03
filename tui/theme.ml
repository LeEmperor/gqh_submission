open! Core
open Bonsai_term

module Scheme = Bonsai_term_color_scheme

type capability = Truecolor | Ansi256 | Ansi16 | No_color [@@deriving equal, sexp]
type role = Bg | Surface | Border | Focus | Text | Muted | Bid | Ask | Warn | Info | Alarm

type t = { capability : capability; dimmed : bool; scheme : Ui_types.scheme } [@@deriving equal]
let create capability = { capability; dimmed = false; scheme = Tickweave_amber }
let dim t = { t with dimmed = true }
let with_scheme t scheme = { t with scheme }
let detect_from ~getenv =
  if Option.is_some (getenv "NO_COLOR") then create No_color
  else if Option.value_map (getenv "COLORTERM") ~default:false
      ~f:(fun value -> String.equal value "truecolor" || String.equal value "24bit")
  then create Truecolor
  else if Option.value_map (getenv "TERM") ~default:false
      ~f:(String.is_substring ~substring:"256color")
  then create Ansi256
  else create Ansi16
let detect () = detect_from ~getenv:Sys.getenv

(* The Tickweave palette. Tokyo Night and Catppuccin Mocha borrow their RGB from the
   installed colour schemes: surfaces and greys from the flavor, one accent for focus. *)
let amber = function
  | Bg -> 0x0B, 0x0E, 0x14 | Surface -> 0x11, 0x15, 0x1C
  | Border -> 0x2A, 0x30, 0x3C | Focus -> 0xF5, 0xA6, 0x23
  | Text -> 0xD6, 0xDA, 0xE1 | Muted -> 0x6B, 0x72, 0x80
  | Bid -> 0x3D, 0xD6, 0x8C | Ask -> 0xFF, 0x6B, 0x6B
  | Warn -> 0xFF, 0xC8, 0x57 | Info -> 0x5A, 0xB0, 0xFF
  | Alarm -> 0xFF, 0x3B, 0x30

let of_flavor (flavor : Scheme.Flavor.t) ~focus ~border ~muted ~warn ~info ~alarm role =
  let { Scheme.Rgb.r; g; b } = Scheme.to_rgb flavor (match role with
    | Bg -> Scheme.Base | Surface -> Scheme.Surface0 | Border -> border | Focus -> focus
    | Text -> Scheme.Text | Muted -> muted | Bid -> Scheme.Green | Ask -> Scheme.Red
    | Warn -> warn | Info -> info | Alarm -> alarm) in
  r, g, b

let tokyo_night =
  of_flavor Scheme.Tokyo_night_dark.flavor ~focus:Scheme.Blue ~border:Scheme.Overlay0
    ~muted:Scheme.Subtext0 ~warn:Scheme.Yellow ~info:Scheme.Sky ~alarm:Scheme.Maroon
let catppuccin_mocha =
  of_flavor Scheme.Catppuccin.Mocha.flavor ~focus:Scheme.Mauve ~border:Scheme.Surface2
    ~muted:Scheme.Overlay1 ~warn:Scheme.Peach ~info:Scheme.Sapphire ~alarm:Scheme.Red

let scheme_rgb (scheme : Ui_types.scheme) role =
  match scheme with
  | Tickweave_amber -> amber role
  | Tokyo_night -> tokyo_night role
  | Catppuccin_mocha -> catppuccin_mocha role

(* The 16-colour fallback is a property of the role, not of the scheme. *)
let ansi16_index = function
  | Bg | Surface -> 0 | Border | Muted -> 8 | Focus -> 3 | Text -> 7 | Bid -> 2 | Ask -> 1
  | Warn -> 11 | Info -> 12 | Alarm -> 9

let scheme_name : Ui_types.scheme -> string = function
  | Tickweave_amber -> "amber" | Tokyo_night -> "tokyo" | Catppuccin_mocha -> "mocha"
let next_scheme scheme =
  let schemes = Ui_types.all_of_scheme in
  let index, _ = List.findi_exn schemes ~f:(fun _ s -> Ui_types.equal_scheme s scheme) in
  List.nth_exn schemes ((index + 1) % List.length schemes)

let effective_role t role =
  if t.dimmed then (match role with Bg | Surface -> role | _ -> Muted) else role
let role_rgb t role = scheme_rgb t.scheme (effective_role t role)

let blend (r1, g1, b1) (r2, g2, b2) t =
  let t = Float.clamp_exn t ~min:0. ~max:1. in
  let mix a b = a + Float.iround_nearest_exn (Float.of_int (b - a) *. t) in
  mix r1 r2, mix g1 g2, mix b1 b2

(* xterm 256-colour palette: 16..231 is a 6x6x6 cube over the levels 0, 95, 135, 175,
   215, 255; 232..255 is a grey ramp of 8, 18, ..., 238. *)
let distance (r1, g1, b1) (r2, g2, b2) =
  let square x = x * x in
  square (r1 - r2) + square (g1 - g2) + square (b1 - b2)
let nearest_256 ((r, g, b) as rgb) =
  let cube_level v = if v < 48 then 0 else if v < 115 then 1 else (v - 35) / 40 in
  let cube_value level = if level = 0 then 0 else 55 + (40 * level) in
  let cr, cg, cb = cube_level r, cube_level g, cube_level b in
  let cube = cube_value cr, cube_value cg, cube_value cb in
  let step = Int.clamp_exn (((r + g + b) / 3) - 3) ~min:0 ~max:230 / 10 in
  let grey = 8 + (10 * step) in
  if distance rgb (grey, grey, grey) < distance rgb cube then 232 + step
  else 16 + (36 * cr) + (6 * cg) + cb

(* The 16 default xterm colours, in index order. *)
let ansi16_palette =
  [ 0, 0, 0; 205, 0, 0; 0, 205, 0; 205, 205, 0; 0, 0, 238; 205, 0, 205; 0, 205, 205
  ; 229, 229, 229; 127, 127, 127; 255, 0, 0; 0, 255, 0; 255, 255, 0; 92, 92, 255
  ; 255, 0, 255; 0, 255, 255; 255, 255, 255 ]
let nearest_16 rgb =
  let index, _ =
    List.foldi ansi16_palette ~init:(0, Int.max_value) ~f:(fun index (best, best_distance) entry ->
      let d = distance rgb entry in
      if d < best_distance then index, d else best, best_distance)
  in
  index

let quantize t ((r, g, b) as rgb) =
  match t.capability with
  | Truecolor -> Attr.Color.rgb ~r ~g ~b
  | Ansi256 -> Attr.Color.xterm_256 (nearest_256 rgb)
  | Ansi16 | No_color -> Attr.Color.xterm_256 (nearest_16 rgb)
let rgb_color t rgb =
  match t.capability with
  | No_color -> None
  | Truecolor | Ansi256 | Ansi16 -> Some (quantize t rgb)

let color t role =
  match t.capability with
  | Truecolor | Ansi256 -> quantize t (role_rgb t role)
  | Ansi16 | No_color -> Attr.Color.xterm_256 (ansi16_index (effective_role t role))

(* A dark red wash behind Alarm text. Amber keeps its original constant. *)
let alarm_background t =
  match t.scheme with
  | Tickweave_amber -> 0x2A, 0x0E, 0x0E
  | Tokyo_night | Catppuccin_mocha -> blend (role_rgb t Bg) (role_rgb t Alarm) 0.2

let attrs t role =
  match t.capability with
  | No_color -> []
  | Truecolor | Ansi256 | Ansi16 ->
    let foreground = Attr.fg (color t role) in
    (match role with
     | Alarm when not t.dimmed ->
       let background = match t.capability with
         | Truecolor | Ansi256 -> quantize t (alarm_background t)
         | Ansi16 | No_color -> Attr.Color.xterm_256 0
       in [ foreground; Attr.bg background; Attr.bold ]
     | _ -> [ foreground ])

let backdrop t view =
  match t.capability with
  | No_color -> view
  | Truecolor | Ansi256 | Ansi16 ->
    View.with_colors ~fill_backdrop:true view ~fg:(color t Text) ~bg:(color t Bg)

let flash_attrs t role ~intensity =
  if t.dimmed || Float.(intensity <= 0.) then []
  else match t.capability with
    | No_color -> []
    | Ansi16 -> [ Attr.fg (color t Text); Attr.bg (color t role) ]
    | Ansi256 ->
      [ Attr.bg (quantize t (blend (role_rgb t Bg) (role_rgb t role) intensity)) ]
    | Truecolor ->
      let r, g, b = role_rgb t role in
      let br, bg, bb = role_rgb t Bg in
      let mix base target =
        Float.to_int (Float.of_int base +. (Float.of_int (target - base) *. intensity)) in
      [ Attr.bg (Attr.Color.rgb ~r:(mix br r) ~g:(mix bg g) ~b:(mix bb b)) ]
