open! Core
open Bonsai_term
open Model_adapter

type editing = Browse | Parameter of string | Confirmation [@@deriving equal, sexp]
type t =
  { is_open : bool; draft : proposal option; selected_parameter : string option
  ; editing : editing; editor : Filter_editor.t; submitted : string list
  ; failed : string list; reconcile_pending : bool; notice : string option }
  [@@deriving equal, sexp]
type textbox_action = Ignore_textbox | Forward | Set_text of string
let empty =
  { is_open = false; draft = None; selected_parameter = None; editing = Browse
  ; editor = Filter_editor.create ""; submitted = []; failed = []
  ; reconcile_pending = false; notice = None }
let draft t (state : application_state) = Option.value t.draft ~default:state.proposal
let progress_for (state : application_state) (proposal : proposal) =
  Option.filter state.config_apply ~f:(fun p -> String.equal p.proposal_id proposal.proposal_id)
let unknown (state : application_state) =
  equal_engine state.engine Engine_unknown || equal_configuration_status state.configuration.status Unknown
  || Option.value_map state.config_apply ~default:false ~f:(fun p -> p.state_unknown)
let in_flight (state : application_state) =
  (match state.configuration.status with Applying _ -> true | _ -> false)
  || Option.value_map state.config_apply ~default:false ~f:(fun p ->
    Option.is_none p.acknowledged_version && Option.is_none p.failure && not p.state_unknown
    && List.exists p.steps ~f:(fun (_, status) -> match status with
      | Step_pending | Step_active -> true | Step_done | Step_failed _ | Step_unknown _ -> false))
let failed t (state : application_state) (proposal : proposal) =
  List.mem t.failed proposal.proposal_id ~equal:String.equal
  || (match state.config_apply with
      | Some p -> String.equal p.proposal_id proposal.proposal_id
        && (Option.is_some p.failure || List.exists p.steps ~f:(fun (_, status) ->
          match status with Step_failed _ -> true | _ -> false))
      | None -> match state.configuration.status with Failed _ -> true | _ -> false)
let submitted t (proposal : proposal) = List.mem t.submitted proposal.proposal_id ~equal:String.equal
let editable t state (proposal : proposal) =
  not (unknown state || in_flight state || failed t state proposal || submitted t proposal)
let integer text =
  let digits = if String.is_prefix text ~prefix:"-" then String.drop_prefix text 1 else text in
  if String.is_empty digits || not (String.for_all digits ~f:Char.is_digit) then None
  else Option.try_with (fun () -> Int.of_string text)
let invalid_text t = match t.editing with Parameter _ -> Option.is_none (integer t.editor.text) | _ -> false
let validation t (state : application_state) (proposal : proposal) =
  let result = validate_proposal ~manifest:state.manifest ~connected_build:state.build_id
      ~active_version:state.configuration.last_acknowledged_version
      ~engine_reachable:(state.connected && not (equal_engine state.engine Engine_unknown)) proposal in
  if not (invalid_text t) then result else
    { checks = List.map result.checks ~f:(fun check ->
        if String.equal check.name "every field in range" then
          { check with passed = false; detail = "proposed value must be a decimal integer" } else check)
    ; can_apply = false; errors = "proposed value must be a decimal integer" :: result.errors }
let can_apply t state (proposal : proposal) =
  editable t state proposal && (validation t state proposal).can_apply
let sync t (state : application_state) =
  let failed = match state.config_apply with
    | Some p when Option.is_some p.failure || List.exists p.steps ~f:(fun (_, status) ->
        match status with Step_failed _ -> true | _ -> false) ->
      List.dedup_and_sort (p.proposal_id :: t.failed) ~compare:String.compare
    | _ -> t.failed in
  let t = { t with failed; reconcile_pending = t.reconcile_pending && unknown state } in
  if unknown state || not (editable t state (draft t state)) then { t with editing = Browse } else t
let close t =
  { t with is_open = false; draft = None; selected_parameter = None; editing = Browse
         ; editor = Filter_editor.create ""; notice = None }
let open_modal t (state : application_state) =
  { t with is_open = true; draft = Some state.proposal
         ; selected_parameter = Option.map (List.hd state.proposal.changes) ~f:fst
         ; editing = Browse; editor = Filter_editor.create ""; notice = None }
let move t proposal direction =
  let names = List.fold proposal.changes ~init:[] ~f:(fun names (name, _) ->
      if List.mem names name ~equal:String.equal then names else names @ [ name ]) in
  let index = Option.bind t.selected_parameter ~f:(fun selected ->
      List.findi names ~f:(fun _ name -> String.equal name selected) |> Option.map ~f:fst)
    |> Option.value ~default:0 in
  let index = match direction with
    | `First -> 0 | `Last -> List.length names - 1
    | `Up -> Int.max 0 (index - 1) | `Down -> Int.min (List.length names - 1) (index + 1) in
  { t with selected_parameter = List.nth names index }
let begin_editor t editing text =
  { t with editing; editor = Filter_editor.create text; notice = None }, Set_text text
let update_parameter t proposal name event =
  let editor = Filter_editor.apply t.editor event in
  let proposal = match integer editor.text with
    | None -> proposal
    | Some value -> { proposal with changes = List.map proposal.changes ~f:(fun (field, old) ->
        field, if String.equal field name then value else old) } in
  { t with editor; draft = Some proposal; notice = None }

(* The entire decision, including live backend validation and submit deduplication,
   happens before the textbox effect yields. No captured rendered model is trusted. *)
let key t state event =
  let t = sync t state in
  let proposal = draft t state in
  let unchanged () = t, None, Ignore_textbox in
  if not t.is_open then (match event with
    | Event.Key_press { key = ASCII 'c'; mods = [] } -> open_modal t state, None, Ignore_textbox
    | _ -> unchanged ())
  else match event with
  | Event.Key_press { key = Escape; _ } -> close t, None, Ignore_textbox
  | _ when unknown state ->
    (match event with
     | Key_press { key = ASCII 'r'; mods = [] } when not t.reconcile_pending
         && not (Option.value_map state.config_apply ~default:false
           ~f:(fun p -> equal_reconciliation_status p.reconciliation Reconciling)) ->
       { t with reconcile_pending = true }, Some Reconcile, Ignore_textbox
     | _ -> unchanged ())
  | _ -> match t.editing with
    | Parameter name ->
      (match event with
       | Key_press { key = Enter; _ } ->
         if invalid_text t then { t with notice = Some "✗ Enter a decimal integer" }, None, Ignore_textbox
         else { t with editing = Browse; notice = None }, None, Ignore_textbox
       | _ -> update_parameter t proposal name event, None, Forward)
    | Confirmation ->
      (match event with
       | Key_press { key = Enter; _ } ->
         if not (String.equal t.editor.text "apply") then
           { t with notice = Some "✗ Confirmation must be exactly apply" }, None, Ignore_textbox
         else if not (can_apply t state proposal) then
           { t with editing = Browse; notice = Some "✗ Live checks changed — re-plan required" }, None, Ignore_textbox
         else
           { t with editing = Browse; submitted = proposal.proposal_id :: t.submitted; notice = None },
           Some (Apply_proposal proposal), Ignore_textbox
       | _ -> { t with editor = Filter_editor.apply t.editor event; notice = None }, None, Forward)
    | Browse ->
      match event with
      | Key_press { key = ASCII 'A'; mods = [] } when can_apply t state proposal ->
        let t, action = begin_editor t Confirmation "" in t, None, action
      | Key_press { key = Enter; mods = [] } when editable t state proposal ->
        (match Option.bind t.selected_parameter ~f:(fun name ->
           List.Assoc.find proposal.changes name ~equal:String.equal |> Option.map ~f:(fun value -> name, value)) with
         | None -> unchanged ()
         | Some (name, value) -> let t, action = begin_editor t (Parameter name) (Int.to_string value) in t, None, action)
      | Key_press { key = (ASCII 'j' | Arrow `Down); mods = [] } -> move t proposal `Down, None, Ignore_textbox
      | Key_press { key = (ASCII 'k' | Arrow `Up); mods = [] } -> move t proposal `Up, None, Ignore_textbox
      | Key_press { key = ASCII 'g'; mods = [] } -> move t proposal `First, None, Ignore_textbox
      | Key_press { key = ASCII 'G'; mods = [] } -> move t proposal `Last, None, Ignore_textbox
      | _ -> unchanged ()
