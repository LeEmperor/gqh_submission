open! Core
open Bonsai_term
open Model_adapter

let move_selection (rules : rule list) ~selected ~direction =
  let ids = List.map rules ~f:(fun rule -> rule.rule_id) in
  let index = Option.bind selected ~f:(fun id -> List.findi ids ~f:(fun _ value -> String.equal id value))
      |> Option.map ~f:fst in
  let index = match direction, index with
    | `First, _ -> 0 | `Last, _ -> List.length ids - 1
    | `Next, Some index -> Int.min (List.length ids - 1) (index + 1)
    | `Previous, Some index -> Int.max 0 (index - 1)
    | (`Next | `Previous), None -> 0 in
  if index < 0 then None else List.nth ids index

(* Wrap between complete fields so resizing cannot turn a clipped integer into
   a different value. A field too wide by itself receives an explicit marker. *)
let field_rows ~width fields =
  let rows, row = List.fold fields ~init:([], "") ~f:(fun (rows, row) field ->
    let field = if Braille_chart.display_width field <= width then field else "VALUE TOO WIDE" in
    let joined = if String.is_empty row then field else row ^ "  " ^ field in
    if Braille_chart.display_width joined <= width then rows, joined
    else row :: rows, field) in
  List.rev (row :: rows)

let unit_symbol = function "ticks" -> "t" | "units" -> "u" | unit -> unit

type upgrade = Funnel | Parameter_table | Meta | Block_note | Recent | Reasons [@@deriving equal]

let percent fraction = sprintf "%3.0f%%" (100. *. fraction)

(* "admitted ▕████░░░░▏ 60%": [filled] cells in [role], the rest as shade. *)
let bar_cells theme ~role ~empty_role ~width ~fraction =
  let { Sparkline.full; partial; empty } = Sparkline.bar ~width ~fraction in
  View.hcat [ View.text ~attrs:(Theme.attrs theme role) (String.concat (List.init full ~f:(fun _ -> "█")) ^ partial)
            ; View.text ~attrs:(Theme.attrs theme empty_role) (String.concat (List.init empty ~f:(fun _ -> "░"))) ]

(* Matched, admitted and blocked as bars against the widest of them, then the admit ratio
   as one bar split between the two outcomes. [None] when the row is too narrow. *)
let funnel ~theme ~inner (rule : rule) =
  let count_width = List.fold [ rule.matched; rule.admitted; rule.blocked ] ~init:0
      ~f:(fun w n -> Int.max w (String.length (Int.to_string n))) in
  let bar_width = inner - 9 - count_width - 1 - 2 - 5 in
  if bar_width < 8 then None
  else (
    let base = Int.max rule.matched (rule.admitted + rule.blocked) in
    let fraction n = if base = 0 then 0. else Float.of_int n /. Float.of_int base in
    let line name n role =
      View.hcat [ View.text ~attrs:(Theme.attrs theme Text) (sprintf "%-9s%*d " name count_width n)
                ; View.text ~attrs:(Theme.attrs theme Muted) "▕"
                ; bar_cells theme ~role ~empty_role:Muted ~width:bar_width ~fraction:(fraction n)
                ; View.text ~attrs:(Theme.attrs theme Muted) "▏"
                ; View.text ~attrs:(Theme.attrs theme Muted) (if base = 0 then "    —" else " " ^ percent (fraction n)) ] in
    let decided = rule.admitted + rule.blocked in
    let ratio =
      View.hcat
        [ View.text ~attrs:(Theme.attrs theme Text) (sprintf "%-*s " (9 + count_width) "admit")
        ; View.text ~attrs:(Theme.attrs theme Muted) "▕"
        ; (if decided = 0
           then View.text ~attrs:(Theme.attrs theme Muted) (String.concat (List.init bar_width ~f:(fun _ -> "·")))
           else bar_cells theme ~role:Bid ~empty_role:Ask ~width:bar_width
               ~fraction:(Float.of_int rule.admitted /. Float.of_int decided))
        ; View.text ~attrs:(Theme.attrs theme Muted) "▏"
        ; View.text ~attrs:(Theme.attrs theme (if decided = 0 then Muted else Bid))
            (if decided = 0 then " none decided"
             else " " ^ percent (Float.of_int rule.admitted /. Float.of_int decided)) ] in
    Some [ line "matched" rule.matched Info; line "admitted" rule.admitted Bid
         ; line "blocked" rule.blocked Ask; ratio ])

(* How many of the newest decisions the strip and the reason table look at: a bounded
   read of the ring, so a repaint never walks the whole log. *)
let recent_limit = 240

(* This rule's newest outcomes, oldest first. *)
let recent_outcomes (state : application_state) (rule : rule) =
  let newest = Sequence.take (Map.to_sequence ~order:`Decreasing_key state.decisions.records) recent_limit in
  Sequence.filter_map newest ~f:(fun (_, (decision : decision)) ->
    Option.some_if (String.equal decision.rule_id rule.rule_id) decision.outcome)
  |> Sequence.to_list |> List.rev

(* "recent ✓✓✗✓··✓": one glyph per decision, newest at the right edge. *)
let recent_row ~theme ~inner outcomes =
  let width = Int.min recent_limit (inner - 7) in
  let shown = List.drop outcomes (List.length outcomes - width) in
  let glyph = function
    | Admitted_result -> View.text ~attrs:(Theme.attrs theme Bid) "✓"
    | Blocked_result _ -> View.text ~attrs:(Theme.attrs theme Ask) "✗"
    | No_signal_result -> View.text ~attrs:(Theme.attrs theme Muted) "·" in
  View.hcat ([ View.text ~attrs:(Theme.attrs theme Muted) "recent ";
               View.text (String.make (Int.max 0 (width - List.length shown)) ' ') ]
             @ List.map shown ~f:glyph)

(* Blocked reasons among those decisions, most frequent first, at most [rows] of them. *)
let reason_rows ~theme ~inner ~rows outcomes =
  let reasons = List.filter_map outcomes ~f:(function Blocked_result reason -> Some reason | _ -> None) in
  let counts = List.map (List.sort reasons ~compare:String.compare |> List.group ~break:String.( <> ))
      ~f:(fun group -> List.length group, List.hd_exn group)
    |> List.sort ~compare:(fun (a, _) (b, _) -> Int.compare b a) in
  List.take counts rows |> List.map ~f:(fun (count, reason) ->
    let head = sprintf "%4d× " count in
    View.hcat [ View.text ~attrs:(Theme.attrs theme Muted) head
              ; View.text ~attrs:(Theme.attrs theme Ask)
                  (Braille_chart.truncate ~width:(inner - Braille_chart.display_width head) reason) ])

let view ~theme ~focus ~(state : application_state) ~selected ~width ~height =
  let inner = Int.max 0 (width - 4) and rows = Int.max 0 (height - 2) in
  let text role value = View.text ~attrs:(Theme.attrs theme role) value in
  (* Prose is cut to the panel with an ellipsis. Numbers are never cut; see [field_rows]. *)
  let prose role value = text role (Braille_chart.truncate ~width:inner value) in
  let selected_rule = Option.bind selected ~f:(fun id ->
      List.find state.rules ~f:(fun rule -> String.equal rule.rule_id id)) in
  let status_of (rule : rule) =
    if equal_engine state.engine Engine_unknown then "? UNKNOWN", Theme.Alarm
    else if rule.enabled then "● ON", Bid else "○ OFF", Muted in
  let label (rule : rule) ~selected =
    let status, role = status_of rule in
    let cells = Braille_chart.display_width in
    let right = text role status in
    (* A long name gives way to the status, which stays whole at the right edge. *)
    let name = Braille_chart.truncate ~width:(Int.max 1 (inner - cells status - 1))
        (String.concat [ (if selected then "▸" else " "); " #"; Int.to_string rule.slot; " "; rule.name ]) in
    let left = text (if selected then Focus else Text) name in
    (* Another rule shows its outcome counts in the room between name and status. *)
    let middle =
      let decided = rule.admitted + rule.blocked in
      let counts = sprintf "m%d a%d b%d%s" rule.matched rule.admitted rule.blocked
          (if decided = 0 then "" else " " ^ String.strip (percent (Float.of_int rule.admitted /. Float.of_int decided))) in
      if (not selected) && inner - cells name - cells status >= String.length counts + 3
      then Some ("  " ^ counts) else None in
    let used = cells name + cells status + Option.value_map middle ~default:0 ~f:cells in
    View.hcat ([ left ]
               @ Option.value_map middle ~default:[] ~f:(fun counts -> [ text Muted counts ])
               @ [ View.rectangle ~width:(Int.max 1 (inner - used)) ~height:1 (); right ]) in
  let body = match selected_rule with
    | None -> View.vcat
        (prose Muted (if List.is_empty state.rules then "No compiled rules" else "Selected rule unavailable")
         :: List.map state.rules ~f:(fun rule -> label rule ~selected:false))
    | Some rule ->
      let compact_parameters = field_rows ~width:inner (List.map rule.parameters
          ~f:(fun (name, value, unit) -> sprintf "%s %d %s" name value (unit_symbol unit)))
        |> List.map ~f:(text Text) in
      let table_parameters =
        let name_width = List.fold rule.parameters ~init:0 ~f:(fun w (name, _, _) ->
            Int.max w (Braille_chart.display_width name))
        and value_width = List.fold rule.parameters ~init:0 ~f:(fun w (_, value, _) ->
            Int.max w (String.length (Int.to_string value))) in
        List.map rule.parameters ~f:(fun (name, value, unit) ->
          let row = sprintf "%s %*d %s" (Braille_chart.pad_right name ~width:name_width) value_width value
              (unit_symbol unit) in
          (* A row that cannot fit whole is flagged, never clipped into another number. *)
          text Text (if Braille_chart.display_width row <= inner then row else "VALUE TOO WIDE")) in
      let compact_counters = field_rows ~width:inner
          [ sprintf "matched %d" rule.matched; sprintf "admitted %d" rule.admitted
          ; sprintf "blocked %d" rule.blocked ] |> List.map ~f:(text Muted) in
      let funnel = funnel ~theme ~inner rule in
      (* The reason is prose, not a number: too long for the panel it is cut with an ellipsis. *)
      let block_lines = Option.value_map rule.last_block_reason ~default:[] ~f:(fun reason ->
          [ prose Ask ("last block: " ^ reason) ]) in
      let block_note =
        if rule.blocked = 0 then "last block: none (0 blocked)" else "last block: reason not reported" in
      let configuration, config_role = Status_bar.configuration_label state.configuration in
      let others = List.filter state.rules ~f:(fun other -> not (String.equal other.rule_id rule.rule_id)) in
      (* Rows beyond the compact layout go, in order, to the outcome bars, the aligned
         parameter table, the identity line, the last-block placeholder, the recent
         outcome strip and the block-reason table. *)
      let base = 2 + List.length compact_parameters + List.length compact_counters
                 + List.length block_lines + 1 in
      let outcomes = lazy (recent_outcomes state rule) in
      let reasons () = reason_rows ~theme ~inner ~rows:3 (Lazy.force outcomes) in
      let cost = function
        | Funnel -> Option.value_map funnel ~default:Int.max_value
                      ~f:(fun lines -> List.length lines - List.length compact_counters)
        | Parameter_table -> List.length table_parameters - List.length compact_parameters
        | Meta -> 1
        | Block_note -> if List.is_empty block_lines then 1 else Int.max_value
        | Recent -> if List.is_empty (Lazy.force outcomes) then Int.max_value else 1
        | Reasons -> (match reasons () with [] -> Int.max_value | lines -> 1 + List.length lines) in
      let chosen, _ = List.fold [ Funnel; Parameter_table; Meta; Block_note; Recent; Reasons ]
          ~init:([], rows - base) ~f:(fun (chosen, spare) upgrade ->
            if spare > 0 && cost upgrade <= spare then upgrade :: chosen, spare - cost upgrade
            else chosen, spare) in
      let has upgrade = List.mem chosen upgrade ~equal:equal_upgrade in
      let parameters = if has Parameter_table then table_parameters else compact_parameters in
      let counters = match funnel with Some lines when has Funnel -> lines | _ -> compact_counters in
      View.vcat
        ([ label rule ~selected:true; prose Text rule.predicate ]
         @ (if has Meta then
              [ prose Muted (sprintf "%s · config %s" rule.rule_id
                              (Option.value_map rule.identity.config_version ~default:"v?" ~f:(sprintf "v%d"))) ]
            else [])
         @ parameters @ counters
         @ (if has Recent then [ recent_row ~theme ~inner (Lazy.force outcomes) ] else [])
         @ block_lines
         @ (if has Block_note then [ prose Muted block_note ] else [])
         @ (if has Reasons then
              prose Muted (sprintf "blocked by reason · this rule's last %d decisions" (List.length (Lazy.force outcomes)))
              :: reasons ()
            else [])
         @ [ prose config_role (configuration ^ " · " ^ Status_bar.mode_name state.mode) ]
         @ List.map others ~f:(fun other -> label other ~selected:false)) in
  Panel.framed ~theme ~focus ~panel:Rules ~title:"Rules" ~width ~height body
