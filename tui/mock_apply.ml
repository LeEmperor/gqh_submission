open! Core
open Model_adapter

(* Backend-owned logical MOCK controller. No register or transport protocol. *)
type outcome = Succeed | Fail_idle | Fail_verify | Lose_activate
type phase = Running of apply_step | Lost | Reading_status | Terminal
type t =
  { proposal : proposal; prior_engine : engine; outcome : outcome
  ; phase : phase; elapsed : float }

let emit (state : application_state) ~proposal_id payload =
  let sequence = Option.value_map (List.last state.config_events) ~default:0
      ~f:(fun event -> event.sequence + 1) in
  let event =
    { identity = state.configuration.identity; mode = Mock; proposal_id; sequence; payload } in
  let config_events = state.config_events @ [ event ] in
  { state with config_events = List.drop config_events (Int.max 0 (List.length config_events - 128)) }

let map_progress (state : application_state) ~f =
  { state with config_apply = Option.map state.config_apply ~f }

let set_step state step status =
  map_progress state ~f:(fun progress ->
    { progress with steps = List.map progress.steps ~f:(fun (current, old) ->
        current, if equal_apply_step current step then status else old) })

let disarm (state : application_state) =
  { state with engine = Disarmed; rules = List.map state.rules ~f:(fun rule -> { rule with enabled = false }) }

let fail state t step reason =
  let state = disarm state |> fun state -> set_step state step (Step_failed reason) in
  let state = map_progress state ~f:(fun progress ->
      { progress with failure = Some (step, reason); state_unknown = false }) in
  let state = { state with configuration = { state.configuration with status = Failed reason } } in
  emit state ~proposal_id:t.proposal.proposal_id (Step_rejected (step, reason)),
  { t with phase = Terminal; elapsed = 0. }

let accepting (state : application_state) =
  state.connected && not (equal_engine state.engine Engine_unknown)
  && (match state.configuration.status, state.config_apply with
      | (Active_acknowledged _ | Draft | Validated), None -> true
      | Active_acknowledged version, Some progress ->
        Option.is_none progress.failure && not progress.state_unknown
        && Option.equal Int.equal progress.acknowledged_version (Some version)
        && Option.equal Int.equal state.configuration.last_acknowledged_version (Some version)
        && List.equal [%equal: apply_step * step_status] progress.steps
            (List.map apply_steps ~f:(fun step -> step, Step_done))
      | Failed _, Some progress -> Option.is_some progress.failure && not progress.state_unknown
      | _ -> false)

let start ~outcome (state : application_state) (proposal : proposal) =
  if not (accepting state) then state, None
  else (
    let t = { proposal; prior_engine = state.engine; outcome; phase = Running Validate_step; elapsed = 0. } in
    let validation = validate_proposal ~manifest:state.manifest ~connected_build:state.build_id
        ~active_version:state.configuration.last_acknowledged_version
        ~engine_reachable:(state.connected && not (equal_engine state.engine Engine_unknown)) proposal in
    let progress =
      { proposal_id = proposal.proposal_id; steps = pending_steps; acknowledged_version = None
      ; failure = None; state_unknown = false; reconciliation = Not_requested } in
    let state = { state with proposal; config_apply = Some progress } in
    let state, t =
      if not validation.can_apply then fail state t Validate_step
          ("MOCK validation rejected: " ^ String.concat ~sep:", " validation.errors)
      else (
        let state = set_step state Validate_step Step_active in
        let state = { state with configuration = { state.configuration with status = Applying (sprintf "%d/6" (step_number Validate_step)) } } in
        emit state ~proposal_id:proposal.proposal_id (Step_started Validate_step), t) in
    state, Some t)

let request_reconcile state t =
  match t.phase with
  | Lost ->
    map_progress state ~f:(fun progress -> { progress with reconciliation = Reconciling }),
    { t with phase = Reading_status; elapsed = 0. }
  | Running _ | Reading_status | Terminal -> state, t

let next_step = function
  | Validate_step -> Some Disable_step | Disable_step -> Some Wait_idle_step
  | Wait_idle_step -> Some Write_step | Write_step -> Some Verify_readback_step
  | Verify_readback_step -> Some Activate_step | Activate_step -> None

let commit (state : application_state) t =
  let version = Option.value_exn state.configuration.last_acknowledged_version + 1 in
  let parameters = List.map state.configuration.parameters ~f:(fun (name, active) ->
      name, Option.value (List.Assoc.find t.proposal.changes name ~equal:String.equal) ~default:active) in
  let identity = { state.configuration.identity with config_version = Some version } in
  let engine = if equal_engine t.prior_engine Armed then Armed else Disarmed in
  let rules = List.map state.rules ~f:(fun rule ->
      { rule with identity = { rule.identity with config_version = Some version }
      ; enabled = equal_engine engine Armed
      ; parameters = List.map rule.parameters ~f:(fun (name, active, unit) ->
          name, Option.value (List.Assoc.find parameters name ~equal:String.equal) ~default:active, unit) }) in
  let state =
    { state with engine; rules
    ; configuration = { identity; parameters
      ; status = Active_acknowledged version; last_acknowledged_version = Some version } } in
  let state = map_progress state ~f:(fun progress -> { progress with acknowledged_version = Some version }) in
  emit state ~proposal_id:t.proposal.proposal_id (Activation_acknowledged version),
  { t with phase = Terminal; elapsed = 0. }

let acknowledge state t step =
  match t.outcome, step with
  | Fail_idle, Wait_idle_step -> fail state t step "MOCK idle acknowledgment timeout"
  | Fail_verify, Verify_readback_step -> fail state t step "MOCK readback mismatch"
  | Lose_activate, Activate_step ->
    let reason = "MOCK activation acknowledgment missing" in
    let state = set_step state step (Step_unknown reason) in
    let state = map_progress state ~f:(fun progress -> { progress with state_unknown = true }) in
    let state = { state with connected = false; engine = Engine_unknown
                          ; configuration = { state.configuration with status = Unknown } } in
    emit state ~proposal_id:t.proposal.proposal_id (Communication_lost (step, reason)),
    { t with phase = Lost; elapsed = 0. }
  | _ ->
    let state = set_step state step Step_done in
    let state = emit state ~proposal_id:t.proposal.proposal_id (Step_acknowledged step) in
    let state = if equal_apply_step step Disable_step then disarm state else state in
    match next_step step with
    | None -> commit state t
    | Some next ->
      let state = set_step state next Step_active in
      let state = { state with configuration = { state.configuration with status = Applying (sprintf "%d/6" (step_number next)) } } in
      emit state ~proposal_id:t.proposal.proposal_id (Step_started next),
      { t with phase = Running next }

let reconcile state t =
  let reason = "MOCK status read confirmed last ACK configuration DISARMED; activation not acknowledged" in
  let state = disarm state |> fun state -> set_step state Activate_step (Step_failed reason) in
  let state = { state with connected = true; configuration = { state.configuration with status = Failed reason } } in
  let state = map_progress state ~f:(fun progress ->
      { progress with state_unknown = false; failure = Some (Activate_step, reason)
      ; reconciliation = Reconciled reason }) in
  emit state ~proposal_id:t.proposal.proposal_id
    (Status_reconciled (state.configuration.last_acknowledged_version, Disarmed)),
  { t with phase = Terminal; elapsed = 0. }

let advance ~seconds state t =
  let rec consume state t =
    match t.phase with
    | Terminal | Lost -> state, t
    | Running _ | Reading_status when Float.(t.elapsed < 0.5 -. 1e-9) -> state, t
    | Reading_status -> reconcile state t
    | Running step ->
      let t = { t with elapsed = Float.max 0. (t.elapsed -. 0.5) } in
      let state, t = acknowledge state t step in
      consume state t in
  match t.phase with
  | Terminal | Lost -> state, t
  | Running _ | Reading_status -> consume state { t with elapsed = t.elapsed +. seconds }
