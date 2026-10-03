open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

let last_ack (state : application_state) =
  Option.value_map state.configuration.last_acknowledged_version
    ~default:"none" ~f:(sprintf "v%d")

let is_unknown (state : application_state) =
  equal_engine state.engine Engine_unknown
  || equal_configuration_status state.configuration.status Unknown
  || Option.value_map state.config_apply ~default:false ~f:(fun progress -> progress.state_unknown)

let needs_spinner (state : application_state) =
  match state.config_apply with
  | None -> false
  | Some progress ->
    equal_reconciliation_status progress.reconciliation Reconciling
    || (not (is_unknown state) && Option.is_none progress.failure
        && List.exists progress.steps ~f:(fun (_, status) ->
          equal_step_status status Step_active))

let view ~theme ~(state : application_state) ~spinner ~width =
  let text role value = View.text ~attrs:(Theme.attrs theme role) value in
  let row view = Panel.fit view ~width:(Int.max 0 width) ~height:1 in
  let progress = state.config_apply in
  let unknown = is_unknown state in
  (* The active version is already in the modal header. This row tracks the
     version the proposal would create, and only the backend can confirm it. *)
  let pending_ack = text Warn (sprintf "○ ACK v%d · pending" (state.proposal.base_version + 1)) in
  let steps = Option.value_map progress ~default:pending_steps ~f:(fun p -> p.steps) in
  let rows = List.map apply_steps ~f:(fun step ->
    let status = List.Assoc.find steps step ~equal:equal_apply_step
      |> Option.value ~default:Step_pending in
    let icon, detail, role = match status with
      | Step_pending -> text Muted "○", "", Theme.Muted
      | Step_active when not unknown -> spinner, " · in flight", Warn
      | Step_active -> text Alarm "?", " · indeterminate", Alarm
      | Step_done -> text Bid "✓", "", Bid
      | Step_failed reason -> text Ask "✗", " · " ^ reason, Ask
      | Step_unknown reason -> text Alarm "?", " · indeterminate: " ^ reason, Alarm in
    row (View.hcat [ icon; text role (" " ^ step_name step ^ detail) ])) in
  let summary =
    if unknown then
      [ row (text Alarm ("? STATE UNKNOWN — last ack " ^ last_ack state))
      ; row (match progress with
          | Some { reconciliation = Reconciling; _ } ->
            View.hcat [ spinner; text Warn " reading status · r reconcile" ]
          | _ -> text Focus "r reconcile") ]
    else match progress with
      | Some { failure = Some _; _ } -> [ row (text Ask "engine remains DISARMED") ]
      | Some { acknowledged_version = Some version; _ } ->
        [ row (text Bid (sprintf "✓ ACK v%d" version)) ]
      | Some _ -> [ row pending_ack ]
      | None ->
        [ row (match state.configuration.status with
            | Failed reason -> text Ask ("✗ " ^ reason ^ " · engine remains DISARMED")
            | Draft | Validated | Applying _ | Active_acknowledged _ | Unknown -> pending_ack) ] in
  View.vcat (rows @ summary)

let component ~(theme : Theme.t Bonsai.t) ~state ~width (local_ graph) =
  let spinning = let%arr state in needs_spinner state in
  let spinner =
    match%sub spinning with
    | true ->
      Bonsai_term_spinner.component ~kind:Dot
        ~attrs:(let%arr theme in Theme.attrs theme Warn) graph
    | false -> Bonsai.return View.none in
  let%arr theme and state and spinner and width in
  view ~theme ~state ~spinner ~width
