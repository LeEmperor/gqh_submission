open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter
module State = Config_review_state
module Textbox = Bonsai_term_textbox

let version = Option.value_map ~default:"—" ~f:(fun v -> "v" ^ Int.to_string v)
let version_text = Option.value_map ~default:"v?" ~f:(fun v -> "v" ^ Int.to_string v)
let text theme role value = View.text ~attrs:(Theme.attrs theme role) value

(* The compact dashboard cell: the active configuration as the backend last reported
   it. Anything the backend has not reported renders as "?". The modal below is the
   only place to change it. *)
let summary_status theme (state : application_state) =
  let last = Config_stepper.last_ack state in
  let status, role = match state.configuration.status with
    | Active_acknowledged version -> sprintf "✓ ACK v%d" version, Theme.Bid
    | Applying _ -> "◐ APPLYING · last ACK " ^ last, Warn
    | Draft -> "○ DRAFT · last ACK " ^ last, Warn
    | Validated -> "○ VALIDATED · last ACK " ^ last, Warn
    | Failed _ -> "✗ FAILED · last ACK " ^ last, Ask
    | Unknown -> "? UNKNOWN · last ACK " ^ last, Alarm in
  let engine, engine_role = match state.engine with
    | Armed -> "● ARMED", Theme.Bid | Disarmed -> "○ DISARMED", Muted
    | Idle -> "○ IDLE", Muted | Engine_unknown -> "? UNKNOWN", Alarm in
  View.hcat [ text theme role status; text theme Muted " · engine "; text theme engine_role engine ]
(* One row per parameter: name, value and unit, then the value placed inside its declared
   range, like [995 ━━━━●──── 1010]. A value outside its range pins to an end with an arrow
   and reads as an error; a parameter the manifest does not declare shows "range ?". When
   the row is too narrow for a bar the range is spelled out instead. *)
let parameter_rows theme (state : application_state) ~width =
  let parameters = state.configuration.parameters in
  if List.is_empty parameters then [ text theme Muted "parameters unknown" ]
  else (
    let widest f = List.fold parameters ~init:0 ~f:(fun w p -> Int.max w (f p)) in
    let name_width = widest (fun (name, _) -> Braille_chart.display_width name)
    and value_width = widest (fun (_, value) -> String.length (Int.to_string value))
    and unit_width = widest (fun (name, _) ->
        Option.value_map (parameter_range state.manifest name) ~default:1
          ~f:(fun (unit, _, _) -> Braille_chart.display_width unit)) in
    List.map parameters ~f:(fun (name, value) ->
      let range = parameter_range state.manifest name in
      let unit = Option.value_map range ~default:"?" ~f:(fun (unit, _, _) -> unit) in
      let head = sprintf "%s %*d %s " (Braille_chart.pad_right name ~width:name_width) value_width value
          (Braille_chart.pad_right unit ~width:unit_width) in
      let fixed_text = Option.value_map range ~default:"range ?"
          ~f:(fun (_, low, high) -> sprintf "range [%d, %d]" low high) in
      match range with
      | Some (_, low, high) ->
        let low_text = Int.to_string low and high_text = Int.to_string high in
        let bar_width =
          width - Braille_chart.display_width head - String.length low_text - String.length high_text - 4 in
        if bar_width < 6 then View.hcat [ text theme Text head; text theme Muted fixed_text ]
        else (
          let track, marker, rest = Sparkline.range_bar ~low ~high ~value ~width:bar_width in
          let in_range = value >= low && value <= high in
          View.hcat
            [ text theme Text head; text theme Muted ("[" ^ low_text ^ " "); text theme Info track
            ; View.text ~attrs:(Theme.attrs theme (if in_range then Focus else Ask) @ [ Attr.bold ]) marker
            ; text theme Muted rest; text theme Muted (" " ^ high_text ^ "]") ])
      | None -> View.hcat [ text theme Text head; text theme Muted fixed_text ]))

(* The six apply steps as glyphs, then where the apply is: "apply ✓✓✓◐○○ 4/6 write". *)
let apply_row theme (state : application_state) =
  match state.config_apply with
  | None -> text theme Muted "apply · none in flight"
  | Some progress ->
    let glyph (_, status) = match status with
      | Step_done -> text theme Bid "✓" | Step_active -> text theme Warn "◐"
      | Step_pending -> text theme Muted "○" | Step_failed _ -> text theme Ask "✗"
      | Step_unknown _ -> text theme Alarm "?" in
    let where = match current_step progress with
      | Some step -> sprintf "%d/%d %s" (step_number step) (List.length apply_steps) (step_name step)
      | None -> sprintf "%d/%d acknowledged" (List.count progress.steps ~f:(fun (_, s) -> equal_step_status s Step_done))
                  (List.length apply_steps) in
    View.hcat ([ text theme Muted "apply " ] @ List.map progress.steps ~f:glyph @ [ text theme Text (" " ^ where) ])

(* Whole parts only: a long proposal id drops the deployment class before it clips. *)
let proposal_row theme (state : application_state) ~width =
  let proposal = state.proposal in
  text theme Muted
    (Braille_chart.fit_parts ~width
       [ "proposal " ^ proposal.proposal_id
       ; sprintf "base v%d → v%d" proposal.base_version (proposal.base_version + 1)
       ; deployment_name proposal.deployment_class ])

(* The checks the review modal runs, as one line: ✓ build ✓ base ✓ ranges ✓ engine. Once
   the backend has acknowledged this very proposal its base version is, rightly, stale;
   the line says the proposal was applied instead of flagging a failed check. *)
let preflight_row theme (state : application_state) =
  let applied = Option.bind state.config_apply ~f:(fun progress ->
      if String.equal progress.proposal_id state.proposal.proposal_id then progress.acknowledged_version
      else None) in
  match applied with
  | Some version -> text theme Muted (sprintf "preflight · proposal already applied as ACK v%d" version)
  | None ->
    let validation = validate_proposal ~manifest:state.manifest ~connected_build:state.build_id
        ~active_version:state.configuration.last_acknowledged_version
        ~engine_reachable:(state.connected && not (equal_engine state.engine Engine_unknown)) state.proposal in
    let short = function
      | "build match" -> "build" | "base version match" -> "base" | "every field in range" -> "ranges"
      | "engine reachable" -> "engine" | name -> name in
    View.hcat (text theme Muted "preflight"
               :: List.map validation.checks ~f:(fun check ->
                 text theme (if check.passed then Bid else Ask)
                   (sprintf " %s %s" (if check.passed then "✓" else "✗") (short check.name))))

(* Changed fields only: "Δ maximum_price 1005→1006 · quantity 1→2". *)
let delta_row theme (state : application_state) =
  let changes = List.filter_map state.proposal.changes ~f:(fun (name, proposed) ->
      match List.Assoc.find state.configuration.parameters name ~equal:String.equal with
      | Some active when active = proposed -> None
      | Some active -> Some (sprintf "%s %d→%d" name active proposed)
      | None -> Some (sprintf "%s ?→%d" name proposed)) in
  if List.is_empty changes then text theme Muted "Δ proposal changes nothing"
  else text theme Warn ("Δ " ^ String.concat ~sep:" · " changes)

let manifest_row theme (state : application_state) ~width =
  let rules = state.manifest.compiled_rules in
  text theme Muted
    (Braille_chart.fit_parts ~width
       [ "manifest " ^ state.manifest.build_id; state.manifest.api_schema
       ; sprintf "%d compiled rule%s" (List.length rules) (if List.length rules = 1 then "" else "s")
       ; String.concat ~sep:", " rules ])

(* What happened, newest first. [#n] is the backend's sequence number: a config event
   carries no wall-clock time, so none is shown. *)
let event_row theme (event : config_event) =
  let step = step_name in
  let glyph, role, description = match event.payload with
    | Step_started s -> "▸", Theme.Warn, step s ^ " started"
    | Step_acknowledged s -> "✓", Bid, step s ^ " acknowledged"
    | Step_rejected (s, reason) -> "✗", Ask, sprintf "%s rejected: %s" (step s) reason
    | Activation_acknowledged v -> "✓", Bid, sprintf "activation ACK v%d" v
    | Communication_lost (s, reason) -> "?", Alarm, sprintf "%s: communication lost, %s" (step s) reason
    | Status_reconciled (version, engine) ->
      "↺", Warn, sprintf "reconciled: last ACK %s, engine %s" (version_text version)
        (match engine with Armed -> "ARMED" | Disarmed -> "DISARMED" | Idle -> "IDLE" | Engine_unknown -> "UNKNOWN") in
  View.hcat [ text theme Muted (sprintf "#%-3d" event.sequence); text theme role (glyph ^ " " ^ description)
            ; text theme Muted (sprintf " · cfg %s" (version_text event.identity.config_version)) ]

let events_rows theme (state : application_state) ~rows =
  let newest_first = List.sort state.config_events ~compare:(fun a b -> Int.compare b.sequence a.sequence) in
  if rows < 2 then []
  else (
    match newest_first with
    | [] -> [ text theme Muted "events · none yet" ]
    | events ->
      text theme Muted "events · newest first · #n is the backend sequence"
      :: List.map (List.take events (rows - 1)) ~f:(event_row theme))

(* Border, status line, one line per parameter, and the hint: the least that is useful. *)
let height (state : application_state) =
  4 + Int.max 1 (List.length state.configuration.parameters)

type block = Apply | Preflight | Proposal | Delta | Manifest [@@deriving equal]

(* Rows beyond [height] are spent in this order: the apply steps, the preflight checks,
   the proposal, what it would change, the manifest, then as many events as fit. The hint
   stays on the last row. *)
let view ~theme ~focus ~(state : application_state) ~width ~height:rect_height =
  let inner = Int.max 0 (width - 4) and rows = Int.max 0 (rect_height - 2) in
  let status = summary_status theme state and hint = text theme Muted "c review / apply" in
  let parameters = parameter_rows theme state ~width:inner in
  let spare = rows - (2 + List.length parameters) in
  let wanted = [ Apply; Preflight; Proposal; Delta; Manifest ] in
  let shown, spare = List.fold wanted ~init:([], spare) ~f:(fun (shown, spare) block ->
      if spare >= 1 then block :: shown, spare - 1 else shown, spare) in
  let has block = List.mem shown block ~equal:equal_block in
  let events = if spare >= 2 then events_rows theme state ~rows:spare else [] in
  let when_ block row = if has block then [ row ] else [] in
  let lines =
    [ status ] @ when_ Apply (apply_row theme state) @ when_ Preflight (preflight_row theme state) @ when_ Proposal (proposal_row theme state ~width:inner)
    @ when_ Delta (delta_row theme state) @ parameters @ when_ Manifest (manifest_row theme state ~width:inner) @ events in
  let body = View.vcat (lines @ [ View.pad ~t:(Int.max 0 (rows - List.length lines - 1)) hint ]) in
  Panel.framed ~theme ~focus ~panel:Configuration
    ~title:("Configuration · " ^ Status_bar.mode_name state.mode) ~width ~height:rect_height body

type response = { command : Model_adapter.command option; is_open : bool }
type t =
  { modal : View.t option; is_open : bool; is_editing : bool
  ; handler : Event.t -> response Effect.t; draft : proposal
  ; selected_parameter : string option; can_apply : bool }
type action = Key of Event.t | Synchronize
let badge theme = function
  | Configuration_only -> text theme Bid "✓ CONFIGURATION_ONLY · declared runtime parameters"
  | Rebuild_required -> text theme Warn "▲ REBUILD_REQUIRED · compiled logic changed; build and re-plan required"
  | Unsupported -> text theme Ask "✗ UNSUPPORTED · proposal cannot be deployed by this engine"
let stale (validation : proposal_validation) =
  List.exists validation.checks ~f:(fun check ->
    (String.equal check.name "build match" || String.equal check.name "base version match") && not check.passed)
let field_text model (name, value) =
  match model.State.editing with
  | Parameter selected when String.equal name selected -> model.editor.text
  | _ -> Int.to_string value
let diff_row ~theme ~state ~model ~name ~proposed =
  let active = List.Assoc.find state.configuration.parameters name ~equal:String.equal in
  let unit, range, valid = match parameter_range state.manifest name with
    | None -> "—", "undeclared", false
    | Some (unit, low, high) ->
      unit, sprintf "[%d, %d]" low high,
      Option.value_map (State.integer proposed) ~default:false ~f:(fun value -> value >= low && value <= high) in
  let selected = Option.value_map model.State.selected_parameter ~default:false ~f:(String.equal name) in
  let changed = not (Option.value_map active ~default:false ~f:(fun value -> String.equal (Int.to_string value) proposed)) in
  let marker = if selected then "▸" else if changed then "Δ" else " " in
  let role = if not valid then Theme.Ask else if changed then Warn else Text in
  let attrs = Theme.attrs theme role @ if selected then [ Attr.bold ] else [] in
  View.text ~attrs (sprintf "%s %-22s │ %8s │ %10s │ %-4s │ %s%s" marker name
    (Option.value_map active ~default:"—" ~f:Int.to_string) proposed unit
    (if valid then "" else "✗ ") range)
let checklist theme validation =
  View.vcat (List.map validation.checks ~f:(fun check ->
    text theme (if check.passed then Bid else Ask)
      (sprintf "%s %-22s  %s" (if check.passed then "✓" else "✗") check.name check.detail)))
let actions ~theme ~state ~model ~proposal ~textbox =
  if State.unknown state then
    text theme Alarm (if model.State.reconcile_pending then "Reconciliation requested — awaiting backend status · Esc close"
      else "r reconcile · Esc close")
  else if State.failed model state proposal then
    text theme Ask "✗ Apply unavailable — failed proposal; fresh re-plan required · Esc close"
  else if State.in_flight state then text theme Warn "Backend apply in flight · Esc close"
  else if Option.is_some (Option.bind (State.progress_for state proposal) ~f:(fun progress -> progress.acknowledged_version)) then
    text theme Bid ("✓ APPLIED — ACK " ^ version state.configuration.last_acknowledged_version ^ " · Esc close")
  else if State.submitted model proposal then text theme Warn "Apply request sent — awaiting backend acknowledgment · Esc close"
  else match model.State.editing with
    | Confirmation -> View.hcat [ text theme Focus "Type apply to confirm: "; textbox.Textbox.view ]
    | Parameter name -> View.hcat [ text theme Focus (name ^ " proposed: "); textbox.view
        ; text theme Muted "  Enter finish · Esc close" ]
    | Browse ->
      text theme (if State.can_apply model state proposal then Focus else Muted)
        (if State.can_apply model state proposal then "j/k select · Enter edit · A Apply · Esc close"
         else "j/k select · Enter edit · Apply unavailable · Esc close")
let render ~theme ~state ~model ~proposal ~textbox ~stepper ~(dimensions : Dimensions.t) =
  let width = Int.min 96 (Int.max 4 (dimensions.width - 4)) in
  let validation = State.validation model state proposal in
  let metadata =
    [ text theme Info (sprintf "target build %-18s │ connected build %s" proposal.target_build state.build_id)
    ; text theme Info (sprintf "base version %-18s │ last ACK active %s" ("v" ^ Int.to_string proposal.base_version)
        (version state.configuration.last_acknowledged_version)) ] in
  let content = if State.unknown state then
      metadata @ [ text theme Alarm ("? STATE UNKNOWN — last ack " ^ version state.configuration.last_acknowledged_version)
                 ; stepper; actions ~theme ~state ~model ~proposal ~textbox ]
    else
      metadata
      @ [ (if stale validation then text theme Ask "✗ STALE — re-plan required" else text theme Muted ("proposal " ^ proposal.proposal_id))
        ; badge theme proposal.deployment_class
        ; text theme Muted "  parameter              │   active │   proposed │ unit │ range"
        ; View.vcat (List.map proposal.changes ~f:(fun (name, value) ->
            diff_row ~theme ~state ~model ~name ~proposed:(field_text model (name, value))))
        ; checklist theme validation; stepper
        ; actions ~theme ~state ~model ~proposal ~textbox
        ; text theme (if Option.is_some model.notice then Ask else Muted)
            (Option.value model.notice ~default:(match model.editing with
              | Confirmation -> "Exact confirmation required · Enter submit · Esc close"
              | _ -> "Backend acknowledgments alone advance lifecycle and active configuration")) ] in
  let body = View.vcat content in
  let height = Int.min (Int.max 2 (dimensions.height - 2)) (View.height body + 2) in
  let body = Panel.fit body ~width:(width - 4) ~height:(height - 2) in
  let box = Bonsai_term_border_box.view ~title:("Configuration review · " ^ Status_bar.mode_name state.mode)
      ~line_type:Round_corners ~title_attrs:(Theme.attrs theme Focus @ [ Attr.bold ])
      ~attrs:(Theme.attrs theme Focus) ~left_padding:1 ~right_padding:1 body in
  Theme.backdrop theme (View.zcat [ box; View.rectangle ~width:(View.width box) ~height:(View.height box) () ])
let component ~(theme : Theme.t Bonsai.t) ~(state : application_state Bonsai.t) ~(dimensions : Dimensions.t Bonsai.t)
    ~(stepper : View.t Bonsai.t) (local_ graph) =
  let model, inject = Bonsai.actor_with_input ~default_model:State.empty
      ~recv:(fun _context input model action ->
        match input with
        | Bonsai.Computation_status.Inactive -> model, (None, State.Ignore_textbox)
        | Active state -> match action with
          | Synchronize -> State.sync model state, (None, Ignore_textbox)
          | Key event -> let model, command, action = State.key model state event in
            model, (Some { command; is_open = model.is_open }, action)) state graph in
  let backend_signature = let%arr state in
    state.build_id, state.connected, state.engine, state.configuration.status,
    state.configuration.last_acknowledged_version, state.proposal.proposal_id, state.config_apply in
  let callback = let%arr inject in fun _ -> let%map.Effect _ = inject Synchronize in () in
  Bonsai.Edge.on_change ~equal:[%equal: string * bool * engine * configuration_status * int option * string * apply_progress option]
    backend_signature ~callback graph;
  let focused = let%arr model in model.is_open && not (State.equal_editing model.editing Browse) in
  let textbox = Textbox.component ~is_focused:focused
      ~text_attrs:(let%arr theme in Theme.attrs theme Text)
      ~cursor_attrs:(let%arr theme in Theme.attrs theme Focus) graph in
  let handler = let%arr inject and textbox in fun event ->
    let open Effect.Let_syntax in
    let%bind response, action = inject (Key event) in
    let%map () = match action with
      | State.Ignore_textbox -> Effect.Ignore | Forward -> textbox.handler event | Set_text text -> textbox.set text in
    Option.value response ~default:{ command = None; is_open = false } in
  let%arr theme and state and dimensions and model and textbox and stepper and handler in
  let proposal = State.draft model state in
  let model = State.sync model state in
  { modal = if model.is_open then Some (render ~theme ~state ~dimensions ~model ~proposal ~textbox ~stepper) else None
  ; is_open = model.is_open; is_editing = not (State.equal_editing model.editing Browse)
  ; handler; draft = proposal; selected_parameter = model.selected_parameter
  ; can_apply = State.can_apply model state proposal }
