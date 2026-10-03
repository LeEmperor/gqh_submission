open! Core
open Model_adapter

type filter = All | Match | Admitted | Blocked | Received | Errors [@@deriving equal, sexp]
let filters = [ "all", All; "match", Match; "admitted", Admitted
              ; "blocked", Blocked; "received", Received; "errors", Errors ]
let filter_name filter = fst (List.find_exn filters ~f:(fun (_, f) -> equal_filter f filter))
let parse_filter text = List.Assoc.find filters (String.lowercase (String.strip text)) ~equal:String.equal
let matches filter (decision : decision) = match filter, decision.outcome with
  | All, _ -> true
  | Match, (Admitted_result | Blocked_result _) -> true
  | Admitted, Admitted_result -> true
  | Blocked, Blocked_result _ -> true
  | Received, _ -> Option.is_some decision.receipt_at
  (* An admission rejection is not a software/transport error. Malformed evidence
     is an error; future C0 error events can map to this category at the adapter. *)
  | Errors, _ -> Option.is_none decision.identity.decision_id
                || Option.is_none decision.identity.snapshot_id
                || not decision.inputs.valid
  | _ -> false
let key (decision : decision) = decision.identity.run_id, decision.identity.decision_id
let same_key a b = [%equal: string * int option] (key a) (key b)

type t =
  { live : decision_log; shown : decision_log; selected : decision option
  ; inspected : decision option; paused : bool; follow : bool; unseen : int; paused_arrivals : int
  ; fresh_keys : (string * int option) list; fresh_at : Time_ns.t option
  ; offset : int; filter : filter; filter_open : bool; filter_error : string option; editor : Filter_editor.t }
  [@@deriving equal, sexp]
let empty =
  { live = Decision_buffer.empty; shown = Decision_buffer.empty; selected = None
  ; inspected = None; fresh_keys = []; fresh_at = None; paused = false; follow = true; unseen = 0; paused_arrivals = 0; offset = 0
  ; filter = All; filter_open = false; filter_error = None; editor = Filter_editor.create "all" }
let rows t = Decision_buffer.to_list t.shown |> List.filter ~f:(matches t.filter) |> Array.of_list
(* [now] stamps the arrival that the new rows' highlight fades from. *)
let receive ?(now = Time_ns.epoch) t live =
  (* The records [live] has that [t.live] does not, newest first. The two logs share nearly all
     of their structure, so the difference between them is found without walking the ten
     thousand records: only what a new decision changed. *)
  let fresh_keys = Map.fold_symmetric_diff live.records t.live.records ~data_equal:same_key ~init:[]
      ~f:(fun keys (_, change) ->
        match change with
        | `Left decision | `Unequal (decision, _) -> key decision :: keys
        | `Right _ -> keys) in
  let arrivals = Int.max (List.length fresh_keys) (Int.max 0 (live.next_sequence - t.live.next_sequence)) in
  if t.paused || Option.is_some t.selected || not t.follow
  then { t with live; fresh_keys = []; unseen = t.unseen + arrivals
                   ; paused_arrivals = t.paused_arrivals + (if t.paused then arrivals else 0) }
  else { t with live; shown = live; unseen = 0; fresh_keys
              ; fresh_at = if List.is_empty fresh_keys then t.fresh_at else Some now }
let resume_live t =
  if t.paused then { t with selected = None; follow = true }
  else { t with shown = t.live; selected = None; follow = true; unseen = 0 }
let pause t =
  let t = { t with paused = not t.paused; paused_arrivals = 0; fresh_keys = [] } in
  if not t.paused && t.follow && Option.is_none t.selected then resume_live t else t
let clear_selection t =
  let t = { t with selected = None } in
  if t.follow && not t.paused then resume_live t else t
let set_filter t text = match parse_filter text with
  | None -> { t with filter_error = Some "Choose all / match / admitted / blocked / received / errors" }
  | Some filter -> { t with filter; filter_open = false; filter_error = None; offset = 0 }

type direction = Up | Down | First | Page_up | Page_down [@@deriving equal, sexp]
let navigate t ~height ~offset direction =
  let rows = rows t in
  if Array.is_empty rows then { t with follow = false; offset }
  else (
    let selected_index = Option.bind t.selected ~f:(fun selected ->
      Array.findi rows ~f:(fun _ row -> same_key selected row) |> Option.map ~f:fst) in
    let last_visible = Int.min (Array.length rows - 1) (offset + height - 1) in
    let index = match direction, selected_index with
      | First, _ -> 0
      | Up, Some i -> i - 1 | Down, Some i -> i + 1
      | Page_up, Some i -> i - Int.max 1 (height / 2)
      | Page_down, Some i -> i + Int.max 1 (height / 2)
      | Up, None -> last_visible - 1 | Down, None -> last_visible
      | Page_up, None -> offset
      | Page_down, None -> last_visible in
    let index = Int.clamp_exn index ~min:0 ~max:(Array.length rows - 1) in
    { t with selected = Some rows.(index); follow = false; offset; fresh_keys = [] })
let inspect t = { t with inspected = t.selected }
(* A click on [row] of the window starting at [offset] is Enter-equivalent: it selects the
   row and freezes it in the Inspector. A row outside the log changes nothing. *)
let click t ~offset ~row =
  let rows = rows t in
  if row < 0 || offset + row >= Array.length rows then t
  else inspect { t with selected = Some rows.(offset + row); follow = false; offset; fresh_keys = [] }
let selected_index t = Option.bind t.selected ~f:(fun selected ->
  Array.findi (rows t) ~f:(fun _ row -> same_key selected row) |> Option.map ~f:fst)
