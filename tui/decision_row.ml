open! Core
open Bonsai_term
open Model_adapter

let time time = Time_ns.to_ofday time ~zone:Timezone.utc |> Time_ns.Ofday.to_millisecond_string
let id (decision : decision) = Option.value_map decision.identity.decision_id ~default:"#?"
    ~f:(sprintf "#%d")
let candidate_text (candidate : candidate) =
  sprintf "%s %d @%d" (match candidate.side with Buy -> "BUY" | Sell -> "SELL")
    candidate.quantity_units candidate.price_ticks
let block_summary reason =
  if String.is_prefix reason ~prefix:"order qty" then "qty"
  else if String.is_prefix reason ~prefix:"price" then "price"
  else if String.is_prefix reason ~prefix:"book" then "book"
  else if String.is_prefix reason ~prefix:"engine" then "disarmed" else "error"
(* A new row's highlight fades out over this long. *)
let fresh_fade = Time_ns.Span.of_sec 0.8
let fresh_intensity ~now ~at =
  let age = Time_ns.diff now at in
  if Time_ns.Span.(age < zero || age >= fresh_fade) then 0.
  else Fade.level (1. -. (Time_ns.Span.to_sec age /. Time_ns.Span.to_sec fresh_fade))

(* Row layouts by room. Under [predicate_width] a row is the original id, time, status,
   candidate and badges; from there it gains the rule's comparison, from [config_width] the
   configuration version it ran under, and from [receipt_width] the order-to-receipt delay
   and, for a blocked candidate, the reason in full. Every column comes from the decision
   record, and each has a fixed width so the rows line up whatever they contain. *)
let predicate_width = 65
let config_width = 70
let receipt_width = 82

let pad_to width value = value ^ String.make (Int.max 0 (width - View.width (View.text value))) ' '
let ask_price (decision : decision) = Option.map (List.hd decision.inputs.asks) ~f:(fun l -> l.price_ticks)
(* "ask 1003 ≤ 1005": the best recorded ask against the rule's maximum_price. A no-signal row
   shows why: "ask 1007 > 1005". With no ask in the recorded book there is no comparison. *)
let predicate_text (decision : decision) =
  match ask_price decision with
  | None -> sprintf "ask — vs %d" decision.maximum_price_ticks
  | Some ask ->
    sprintf "ask %d %s %d" ask (if ask <= decision.maximum_price_ticks then "≤" else ">")
      decision.maximum_price_ticks
let config_text (decision : decision) =
  Option.value_map decision.identity.config_version ~default:"v—" ~f:(sprintf "v%d")
let receipt_delay (decision : decision) =
  Option.map decision.receipt_at ~f:(fun at ->
    sprintf "+%.1fms" (Time_ns.diff at decision.occurred_at |> Time_ns.Span.to_ms))

let text ~width (decision : decision) =
  let compact = width < 47 in
  let wide = width >= predicate_width in
  let timestamp = time decision.occurred_at in
  let timestamp = if compact then String.prefix timestamp 8 else timestamp in
  let status, candidate, badges = match decision.outcome with
    | No_signal_result -> "·", "no signal", ""
    | Admitted_result -> "MATCH", Option.value_map decision.candidate ~default:"?"
        ~f:candidate_text,
        ((if compact then "✓A" else "✓ADM")
         ^ if Option.is_some decision.receipt_at then (if compact then " ✓R" else " ✓RCV") else "")
    | Blocked_result reason -> "MATCH", Option.value_map decision.candidate ~default:"?"
        ~f:candidate_text,
        (if compact then "✗B " ^ (if String.is_prefix reason ~prefix:"price" then "px" else block_summary reason)
         else "✗BLK " ^ block_summary reason) in
  let field width value = pad_to width value in
  let base = [ field 5 (id decision); timestamp; field 5 status; field (if wide then 13 else 11) candidate ] in
  let columns =
    if not wide then base @ [ badges ]
    else
      base
      @ [ field 15 (predicate_text decision)
        ; field 10 badges ]
      @ (if width >= config_width then [ field 4 (config_text decision) ] else [])
      @ (if width >= receipt_width then [ field 7 (Option.value (receipt_delay decision) ~default:"") ]
         else []) in
  let result = String.rstrip (String.concat ~sep:" " columns) in
  if View.width (View.text result) > width then sprintf "%s %s VALUE TOO WIDE" (id decision) status
  else (
    (* A blocked candidate's reason follows, whole or not at all: a clipped number would
       read as a different reason. The badge always carries its short form. *)
    match decision.outcome with
    | Blocked_result reason when width >= receipt_width
                              && View.width (View.text result) + 1 + View.width (View.text reason) <= width ->
      result ^ " " ^ reason
    | _ -> result)

(* [fresh] is the highlight's intensity, 1 at a row's arrival, fading to 0. The background
   moves by interpolation, and the row is bold for as long as any of it remains. *)
let view ?(fresh = 0.) ~theme ~width ~selected decision =
  let role = if selected then Theme.Focus else match decision.outcome with
    | No_signal_result -> Muted | Admitted_result -> Bid | Blocked_result _ -> Warn in
  let attrs = Theme.attrs theme role
    @ (if selected then [ Attr.bold; Attr.invert ]
       else if Float.(fresh > 0.) then Attr.bold :: Theme.flash_attrs theme Info ~intensity:(0.18 *. fresh)
       else []) in
  View.text ~attrs (text ~width decision)
