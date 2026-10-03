open! Core
open Bonsai_term
open Model_adapter

(* Greedy word wrap into rows of at most [width] cells. A word too wide for a row on its own
   is handed to [too_wide] rather than split. *)
let wrap_words ~width ~too_wide words =
  let rec pack words line lines = match words with
    | [] -> List.rev (if String.is_empty line then lines else line :: lines)
    | word :: rest ->
      let next = if String.is_empty line then word else line ^ " " ^ word in
      if View.width (View.text next) <= width then pack rest next lines
      else if String.is_empty line then pack rest "" (too_wide word :: lines)
      else pack words "" (line :: lines) in
  pack words "" []

(* "· MOCK" is one word, so the mode label is never parted from its dot or cut off the end. *)
let placeholder_words mode =
  String.split "Select a decision and press Enter to inspect" ~on:' ' @ [ "· " ^ Status_bar.mode_name mode ]

let view ~theme ~focus ~mode ~decision ~width ~height =
  let inner_width = Int.max 1 (width - 4) in
  let body, title = match decision with
    | None ->
      (* The empty state wraps onto as many rows as the width needs, since the panel is tall. *)
      let rows = wrap_words ~width:inner_width ~too_wide:(Braille_chart.truncate ~width:inner_width)
          (placeholder_words mode) in
      View.vcat (List.map rows ~f:(View.text ~attrs:(Theme.attrs theme Muted))), "Inspector"
    | Some (d : decision) ->
      let mode = Status_bar.mode_name d.mode in
      let text s = Theme.attrs theme Text, s in
      let recorded side (levels : level list) = match List.hd levels with
        | None -> side ^ " —"
        | Some level -> sprintf "%s %d t / %d u" side level.price_ticks level.quantity_units in
      let number = Option.value_map ~default:"?" ~f:Int.to_string in
      let ask = Option.map (List.hd d.inputs.asks) ~f:(fun l -> l.price_ticks) in
      let result, reconstructed = match d.predicate_result with
        | Some value -> Bool.to_string value, false
        | None -> Option.value_map ask ~default:"unknown"
            ~f:(fun ask -> Bool.to_string (ask <= d.maximum_price_ticks)), true in
      let predicate = sprintf "ask_px %s ≤ maximum_price %d = %s"
          (number ask) d.maximum_price_ticks result in
      let admission = match d.outcome with
        | No_signal_result -> "admission — no candidate"
        | Admitted_result -> "admission ✓ accepted"
        | Blocked_result _ -> "admission ✗ blocked" in
      let reason = match d.outcome with Blocked_result r -> [ text ("reason " ^ r) ] | _ -> [] in
      let fields =
        [ text (sprintf "%s FROZEN %s · %s" mode (Decision_row.id d) (Decision_row.time d.occurred_at))
        ; text (sprintf "run %s · build %s" d.identity.run_id d.build_id)
        ; text (sprintf "cfg v%s · slot %d · snapshot #%s"
            (number d.identity.config_version) d.slot (number d.identity.snapshot_id))
        ; text ("recorded " ^ recorded "bid" d.inputs.bids ^ " · " ^ recorded "ask" d.inputs.asks)
        ; text predicate ]
        @ (if reconstructed then [ (Theme.attrs theme Muted @ [ Attr.italic ], "(reconstructed) predicate result") ] else [])
        @ [ text ("candidate " ^ Option.value_map d.candidate ~default:"—" ~f:Decision_row.candidate_text)
          ; text (sprintf "bounds qty [%d, %d] u · price [%d, %d] t"
              d.bounds.min_qty d.bounds.max_qty d.bounds.min_price_ticks d.bounds.max_price_ticks)
          ; text admission ] @ reason
        @ [ text ("receipt " ^ Option.value_map d.receipt_at ~default:"— not recorded"
                    ~f:(fun time -> "✓ received " ^ Decision_row.time time)) ] in
      (* Keep every numeric value whole. Long fields move to a second row rather
         than silently losing the end of an input or an admission reason. *)
      let wrap (attrs, text) =
        (* Usually all evidence fits one row. For long identities/reasons, wrap
           at word boundaries while retaining the field's evidence styling. *)
        wrap_words ~width:inner_width ~too_wide:(fun _ -> "VALUE TOO WIDE") (String.split text ~on:' ')
        |> List.map ~f:(View.text ~attrs) in
      View.vcat (List.concat_map fields ~f:wrap), "Inspector · " ^ mode ^ " FROZEN"
  in
  Panel.frame ~theme ~focus ~panel:Inspector ~title ~width ~height body
