open! Core
open Bonsai_term

let hint : Keymap.focus -> string = function
  | Market -> "MOCK stream"
  | Heatmap -> "h heatmap · MOCK" | Tape -> "time & sales · MOCK"
  | Metrics -> "rates · MOCK" | Latency -> "synthetic latency · MOCK"
  | Rules -> "j/k ↑/↓ rule  g/G first/last" | Decisions -> "j/k Enter / Space G"
  | Inspector -> "Frozen decision evidence" | Configuration -> "c review configuration"

(* Key hints, richest first. The first set that fits beside the right-hand status wins, so
   a narrow terminal drops hints rather than clipping a word. Hints are [key label] pairs in
   groups; the key is bold Text and the label Muted, so the line reads without colour. *)
type group = Keys of (string * string) list | Note of string

let tiers ~focus =
  let core = Keys [ "Tab/⇧Tab", "focus"; "1–5", "panel" ]
  and layout = Keys [ "F1–F4", "preset"; "z", "zoom" ]
  and meter = Keys [ "F12", "meter" ]
  and extras = Keys [ "t", "theme"; "h/d", "market"; "c", "config" ]
  and tail = Keys [ "?", "help"; "q", "quit" ] in
  [ [ core; layout; meter; extras; tail; Note (hint focus) ]
  ; [ core; layout; meter; extras; tail ]
  ; [ core; layout; meter; tail ]
  ; [ core; layout; tail ]
  ; [ core; tail ] ]

let render ~theme groups =
  let separator = View.text ~attrs:(Theme.attrs theme Border) " │ " in
  let group = function
    | Note text -> View.text ~attrs:(Theme.attrs theme Muted) text
    | Keys pairs ->
      List.map pairs ~f:(fun (key, label) ->
        View.hcat [ View.text ~attrs:(Theme.attrs theme Text @ [ Attr.bold ]) key
                  ; View.text ~attrs:(Theme.attrs theme Muted) (" " ^ label) ])
      |> List.intersperse ~sep:(View.text "  ") |> View.hcat in
  List.map groups ~f:group |> List.intersperse ~sep:separator |> View.hcat

let view ~theme ~focus ~preset ~zoomed ~scheme ~notice ~width =
  let status = String.concat ~sep:" · "
      ([ Presets.name preset; Theme.scheme_name scheme ] @ (if zoomed then [ "ZOOM" ] else [])
       @ [ "focus: " ^ Keymap.name focus ]) in
  let right = View.text ~attrs:(Theme.attrs theme Focus) status in
  let room = width - View.width right - 1 in
  let tiers = tiers ~focus in
  let left = match List.find_map tiers ~f:(fun groups ->
      let view = render ~theme groups in Option.some_if (View.width view <= room) view) with
    | Some view -> view
    | None -> render ~theme (List.last_exn tiers) in
  (* A notice takes the hints' place until the next key; its words carry the meaning. *)
  let left = match notice with
    | Some notice -> View.text ~attrs:(Theme.attrs theme Warn) notice
    | None -> left in
  let space = Int.max 1 (width - View.width left - View.width right) in
  View.hcat [ left; View.text (String.make space ' '); right ] |> Panel.fit ~width ~height:1
