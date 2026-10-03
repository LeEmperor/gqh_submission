open! Core
open Bonsai_term

(* A line of text as few text nodes as it can be. The terminal layer sends a full colour
   sequence, some forty bytes in truecolour, for every text node, even one beside another
   with the same attributes, and it resends a whole line when any part of it changes. A row
   built from a node per field is mostly colour sequences, and the screen's busiest rows are
   rewritten a dozen times a second. [view] joins neighbours that are drawn alike, so a caller
   gives a blank (a gap that shows no ink) the attributes of the run beside it. *)
let view segments =
  let runs = List.fold segments ~init:[] ~f:(fun runs (attrs, text) ->
      match runs with
      | (previous, run) :: rest when [%equal: Attr.t list] previous attrs -> (previous, run ^ text) :: rest
      | _ -> (attrs, text) :: runs) in
  View.hcat (List.rev_map runs ~f:(fun (attrs, text) -> View.text ~attrs text))
