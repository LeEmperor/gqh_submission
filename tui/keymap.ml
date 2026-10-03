open! Core
open Bonsai_term

type focus = Ui_types.panel_id =
  | Market | Heatmap | Tape | Metrics | Latency
  | Rules | Decisions | Inspector | Configuration
  [@@deriving equal, sexp, enumerate]
let next = function
  | Market | Heatmap | Tape | Metrics | Latency -> Rules
  | Rules -> Decisions | Decisions -> Inspector
  | Inspector -> Configuration | Configuration -> Market
let previous = function
  | Heatmap | Tape | Metrics | Latency -> Market
  | Market -> Configuration | Rules -> Market | Decisions -> Rules
  | Inspector -> Decisions | Configuration -> Inspector
let name = function
  | Market -> "Market" | Heatmap -> "Heatmap" | Tape -> "Tape"
  | Metrics -> "Metrics" | Latency -> "Latency"
  | Rules -> "Rules" | Decisions -> "Decisions"
  | Inspector -> "Inspector" | Configuration -> "Configuration"

(* Step through [visible] in list order, wrapping at either end. A [focus] that is not
   visible enters at the first entry going [`Next] and the last going [`Previous]. *)
let cycle ~visible focus direction =
  match visible, List.findi visible ~f:(fun _ panel -> equal_focus panel focus) with
  | [], _ -> focus
  | _, Some (index, _) ->
    let count = List.length visible in
    let step = match direction with `Next -> 1 | `Previous -> count - 1 in
    List.nth_exn visible ((index + step) % count)
  | first :: _, None ->
    (match direction with `Next -> first | `Previous -> List.last_exn visible)
type action =
  | Next | Previous | Jump of focus | Preset of Ui_types.preset | Zoom | Cycle_theme
  | Toggle_heatmap | Toggle_cumulative | Toggle_meter
  | Help | Close | Quit | Confirm_quit | Move_up | Move_down | First | Last | Ignore

let action = function
  | Event.Key_press { key = Tab; mods = [] } -> Next
  | Key_press { key = Tab; mods = [ Shift ] } -> Previous
  | Key_press { key = Function 12; mods = [] } -> Toggle_meter
  | Key_press { key = Function n; mods = [] } ->
    (* F1..F4 pick a preset in declaration order; other function keys belong to others. *)
    Option.value_map (List.nth Ui_types.all_of_preset (n - 1)) ~default:Ignore
      ~f:(fun preset -> Preset preset)
  | Key_press { key = ASCII 'z'; mods = [] } -> Zoom
  | Key_press { key = ASCII 't'; mods = [] } -> Cycle_theme
  | Key_press { key = ASCII 'h'; mods = [] } -> Toggle_heatmap
  | Key_press { key = ASCII 'd'; mods = [] } -> Toggle_cumulative
  | Key_press { key = ASCII '1'; mods = [] } -> Jump Market
  | Key_press { key = ASCII '2'; mods = [] } -> Jump Rules
  | Key_press { key = ASCII '3'; mods = [] } -> Jump Decisions
  | Key_press { key = ASCII '4'; mods = [] } -> Jump Inspector
  | Key_press { key = ASCII '5'; mods = [] } -> Jump Configuration
  | Key_press { key = (ASCII 'j' | Arrow `Down); mods = [] } -> Move_down
  | Key_press { key = (ASCII 'k' | Arrow `Up); mods = [] } -> Move_up
  | Key_press { key = ASCII 'g'; mods = [] } -> First
  | Key_press { key = ASCII 'G'; mods = [] } -> Last
  | Key_press { key = ASCII '?'; mods = [] } -> Help
  | Key_press { key = Escape; _ } -> Close
  | Key_press { key = ASCII 'q'; mods = [] }
  | Key_press { key = ASCII ('C' | 'c'); mods = [ Ctrl ] } -> Quit
  | Key_press { key = ASCII 'y'; mods = [] } -> Confirm_quit
  | _ -> Ignore
