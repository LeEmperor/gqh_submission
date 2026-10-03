open! Core
open Bonsai_term

let fit view ~width ~height =
  let width = Int.max 0 width and height = Int.max 0 height in
  if View.width view = width && View.height view = height then view else
  view
  |> View.crop ~r:(Int.max 0 (View.width view - width))
       ~b:(Int.max 0 (View.height view - height))
  |> View.pad ~r:(Int.max 0 (width - View.width view))
       ~b:(Int.max 0 (height - View.height view))

(* An unfocused title is plain Text, readable on every scheme; only the rules stay dim. The
   focused panel gets an amber border and title, and the title is also bold and reversed, a
   cue that survives NO_COLOR and 16-colour terminals. A muted panel (no valid data) keeps
   its muted colour but is still reversed when focused, so focus is never colour-only. *)
let title_attrs theme ~focused ~muted =
  let role = if muted then Theme.Muted else if focused then Focus else Text in
  Theme.attrs theme role @ if focused then [ Attr.bold; Attr.invert ] else []

(* The frame is [Bonsai_term_border_box] drawn in fewer text nodes: a one-cell padding is drawn
   with its edge, "│ " and " │", and a border is one run, not a node per character, so a row
   of a panel spends two nodes on its edges, not four. The terminal layer sends a colour
   sequence per node; see [Runs]. Every cell is the one the border box would draw. *)
let frame ?(muted = false) ~theme ~focus ~panel ~title ~width ~height body =
  let focused = Keymap.equal_focus focus panel in
  let role = if muted then Theme.Muted else if focused then Focus else Border in
  let attrs = Theme.attrs theme role in
  let title_attrs = title_attrs theme ~focused ~muted in
  let inner_width = Int.max 0 (width - 4) and inner_height = Int.max 0 (height - 2) in
  let body = fit body ~width:inner_width ~height:inner_height in
  let across = inner_width + 2 in  (* between the corners: the body and a cell of padding each side *)
  let rule count = String.concat (List.init (Int.max 0 count) ~f:(fun _ -> "─")) in
  let text value = View.text ~attrs value in
  let title = View.text ~attrs:title_attrs (" " ^ title ^ " ") in
  let top =
    match Int.sign (across - View.width title) with
    | Neg -> View.hcat [ text "╭"; title ]
    | Zero -> View.hcat [ text "╭"; title; text "╮" ]
    | Pos -> View.hcat [ text "╭"; title; text (rule (across - View.width title) ^ "╮") ] in
  let bottom = text ("╰" ^ rule across ^ "╯") in
  let edge value = View.vcat (List.init inner_height ~f:(fun _ -> text value)) in
  let middle =
    View.hcat [ edge "│ "; View.zcat [ body; View.rectangle ~attrs ~width:inner_width ~height:inner_height () ]
              ; edge " │" ] in
  View.vcat [ top; middle; bottom ] |> fit ~width ~height

let empty ~theme ~focus ~panel ~title ~width ~height =
  frame ~theme ~focus ~panel ~title ~width ~height View.none
