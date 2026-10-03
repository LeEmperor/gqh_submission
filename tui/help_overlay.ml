open! Core
open Bonsai_term

type line = Heading of string | Entry of string * string | Note of string

(* Two columns of at most 45 cells, so the box fits the 100-column minimum. *)
let left =
  [ Heading "Focus"
  ; Entry ("Tab", "next panel; Shift-Tab previous")
  ; Note "1 Market  2 Rules  3 Decisions"
  ; Note "4 Inspector  5 Configuration"
  ; Note "A key for a panel the preset hides"
  ; Note "switches to the preset showing it."
  ; Heading "Layout"
  ; Entry ("F1–F4", "Monitor Decide Configure Demo")
  ; Entry ("z", "zoom focused panel; z restores")
  ; Entry ("h", "heatmap on/off (Market grows)")
  ; Entry ("d", "cumulative depth (Ctrl-d pages)")
  ; Entry ("t", "theme amber/Tokyo Night/Mocha")
  ; Heading "Mouse"
  ; Entry ("click", "focus the panel under pointer")
  ; Entry ("wheel", "scroll Decisions; step Rules")
  ; Note "Needs a terminal with mouse reporting."
  ; Heading "Shell"
  ; Entry ("F12", "toggle frame meter overlay")
  ; Entry ("?", "toggle help")
  ; Entry ("Esc", "close overlay")
  ; Entry ("q/Ctrl-C", "quit") ]

let right =
  [ Heading "Rules"
  ; Entry ("j/k ↑/↓", "select rule")
  ; Entry ("g/G", "first / last rule")
  ; Heading "Decisions"
  ; Entry ("j/k ↑/↓ · g/G", "select / top / live tail")
  ; Entry ("Ctrl-d / Ctrl-u", "half-page down / up")
  ; Entry ("Enter", "freeze Inspector")
  ; Entry ("/", "filter; Enter apply")
  ; Entry ("Space", "pause / resume")
  ; Entry ("Esc", "deselect; G returns live")
  ; Note "Rows: ✓A admitted ✓R received ✗B blocked"
  ; Heading "Configuration"
  ; Entry ("c", "open review modal")
  ; Entry ("j/k · Enter", "select / edit value")
  ; Entry ("A · apply · Enter", "confirm Apply")
  ; Entry ("r", "reconcile UNKNOWN state")
  ; Note "Market stream continues while help is open."
  ; Note "Trading controls arrive in a later phase." ]

let render_line ~theme ~key_width = function
  | Heading text -> View.text ~attrs:(Theme.attrs theme Focus @ [ Attr.bold ]) text
  | Entry (key, text) ->
    View.hcat [ View.text ~attrs:(Theme.attrs theme Focus) ("  " ^ Braille_chart.pad_right key ~width:key_width)
              ; View.text ~attrs:(Theme.attrs theme Text) text ]
  | Note text -> View.text ~attrs:(Theme.attrs theme Text) ("  " ^ text)

(* Keys line up within a column; the trailing gap separates it from the next. *)
let column ~theme lines =
  let key_width = 1 + List.fold lines ~init:0 ~f:(fun width -> function
    | Entry (key, _) -> Int.max width (Braille_chart.display_width key) | Heading _ | Note _ -> width) in
  View.hcat [ View.vcat (List.map lines ~f:(render_line ~theme ~key_width)); View.text "  " ]

let view ~theme ~dimensions ~quitting =
  let title, body = if quitting then
      "Quit · apply in flight",
      View.vcat (List.map ~f:(View.text ~attrs:(Theme.attrs theme Text))
        [ "An update is pending in the backend."
        ; "Quitting does not cancel the update."
        ; "y / q  confirm quit    Esc  keep monitoring" ])
    else
      "Help · Phase 5 / MOCK",
      View.hcat [ column ~theme left; column ~theme right ]
  in
  let box = Bonsai_term_border_box.view ~title ~line_type:Round_corners
      ~attrs:(Theme.attrs theme Focus) ~left_padding:2 ~right_padding:2 body in
  View.center box ~within:dimensions
