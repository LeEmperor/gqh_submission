open! Core
open Bonsai_term

(* The textbox exposes its string only after stabilization. Keep the logical
   input/cursor in the history actor too, so a queued Enter validates all preceding
   edits. Mirror the installed textbox's editing keys; its handler still owns the
   displayed cursor and editing behavior. No global key dispatch occurs here. *)
type t = { text : string; cursor : int } [@@deriving equal, sexp]
let create text = { text; cursor = String.length text }
let apply t event =
  let insert text =
    { text = String.prefix t.text t.cursor ^ text ^ String.drop_prefix t.text t.cursor
    ; cursor = t.cursor + String.length text } in
  match event with
  | Event.Key_press { key = ASCII c; mods = [] } -> insert (Char.to_string c)
  | Key_press { key = Uchar c; mods = [] } -> insert (Uchar.Utf8.to_string c)
  | Key_press { key = ASCII ('u' | 'U'); mods = [ Ctrl ] } ->
    { text = String.drop_prefix t.text t.cursor; cursor = 0 }
  | Key_press { key = Backspace; mods = [] } when t.cursor > 0 ->
    { text = String.prefix t.text (t.cursor - 1) ^ String.drop_prefix t.text t.cursor
    ; cursor = t.cursor - 1 }
  | Key_press { key = Delete; mods = [] } ->
    { t with text = String.prefix t.text t.cursor ^ String.drop_prefix t.text (t.cursor + 1) }
  | Key_press { key = Arrow `Left; mods = [] } -> { t with cursor = Int.max 0 (t.cursor - 1) }
  | Key_press { key = Arrow `Right; mods = [] } -> { t with cursor = Int.min (String.length t.text) (t.cursor + 1) }
  | Key_press { key = Home; mods = [] } -> { t with cursor = 0 }
  | Key_press { key = End; mods = [] } -> { t with cursor = String.length t.text }
  | _ -> t
