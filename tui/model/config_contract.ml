(* PROVISIONAL: replace with tickweave_types when C0 lands.
   Frozen Phase 4 application contract. No transport fields or wire widths. *)
open! Core

type mode = Mock | Simulation | Hardware [@@deriving equal, sexp]
type identity =
  { run_id : string; snapshot_id : int option; decision_id : int option; config_version : int option }
  [@@deriving equal, sexp]
type engine = Armed | Disarmed | Idle | Engine_unknown [@@deriving equal, sexp]
type configuration_status =
  | Draft | Validated | Applying of string | Active_acknowledged of int
  | Failed of string | Unknown
  [@@deriving equal, sexp]
type configuration =
  { identity : identity; status : configuration_status
  ; last_acknowledged_version : int option; parameters : (string * int) list }
  [@@deriving equal, sexp]
type manifest =
  { identity : identity; build_id : string; api_schema : string
  ; compiled_rules : string list; parameter_ranges : (string * string * int * int) list }
  [@@deriving equal, sexp]
type deployment_class = Configuration_only | Rebuild_required | Unsupported [@@deriving equal, sexp]
type proposal =
  { identity : identity; proposal_id : string; target_build : string; base_version : int
  ; changes : (string * int) list; deployment_class : deployment_class
  ; validation_evidence : string list; test_evidence : string list }
  [@@deriving equal, sexp]

type apply_step = Validate_step | Disable_step | Wait_idle_step | Write_step
                | Verify_readback_step | Activate_step [@@deriving equal, sexp]
type step_status = Step_pending | Step_active | Step_done | Step_failed of string
                 | Step_unknown of string [@@deriving equal, sexp]
type reconciliation_status = Not_requested | Reconciling | Reconciled of string
  [@@deriving equal, sexp]
type apply_progress =
  { proposal_id : string; steps : (apply_step * step_status) list
  ; acknowledged_version : int option; failure : (apply_step * string) option
  ; state_unknown : bool; reconciliation : reconciliation_status }
  [@@deriving equal, sexp]
type config_event_payload =
  | Step_started of apply_step | Step_acknowledged of apply_step
  | Step_rejected of apply_step * string | Activation_acknowledged of int
  | Communication_lost of apply_step * string | Status_reconciled of int option * engine
  [@@deriving equal, sexp]
type config_event =
  { identity : identity; mode : mode; proposal_id : string; sequence : int
  ; payload : config_event_payload } [@@deriving equal, sexp]
type command = Apply_proposal of proposal | Reconcile [@@deriving equal, sexp]
type validation_check = { name : string; passed : bool; detail : string } [@@deriving equal, sexp]
type proposal_validation =
  { checks : validation_check list; can_apply : bool; errors : string list } [@@deriving equal, sexp]

let apply_steps = [ Validate_step; Disable_step; Wait_idle_step; Write_step; Verify_readback_step; Activate_step ]
let step_name = function
  | Validate_step -> "validate" | Disable_step -> "disable" | Wait_idle_step -> "wait idle"
  | Write_step -> "write" | Verify_readback_step -> "verify readback" | Activate_step -> "activate"
let step_number step = 1 + (List.findi_exn apply_steps ~f:(fun _ s -> equal_apply_step s step) |> fst)
let pending_steps = List.map apply_steps ~f:(fun step -> step, Step_pending)
let current_step (progress : apply_progress) =
  List.find_map progress.steps ~f:(fun (step, status) -> match status with
    | Step_active | Step_failed _ | Step_unknown _ -> Some step | Step_pending | Step_done -> None)
let deployment_name = function
  | Configuration_only -> "CONFIGURATION_ONLY" | Rebuild_required -> "REBUILD_REQUIRED" | Unsupported -> "UNSUPPORTED"
let parameter_range (manifest : manifest) name =
  List.find_map manifest.parameter_ranges ~f:(fun (field, unit, minimum, maximum) ->
    if String.equal field name then Some (unit, minimum, maximum) else None)
let field_in_range manifest (name, value) =
  Option.value_map (parameter_range manifest name) ~default:false
    ~f:(fun (_, minimum, maximum) -> value >= minimum && value <= maximum)
let validate_proposal ~(manifest : manifest) ~connected_build ~active_version ~engine_reachable (proposal : proposal) =
  let build_match = String.equal proposal.target_build connected_build
                    && String.equal manifest.build_id connected_build in
  let base_match = Option.equal Int.equal active_version (Some proposal.base_version) in
  let unique = List.length proposal.changes = List.length (List.dedup_and_sort
      (List.map proposal.changes ~f:fst) ~compare:String.compare) in
  let in_range = not (List.is_empty proposal.changes) && unique
      && List.for_all proposal.changes ~f:(field_in_range manifest) in
  let checks =
    [ { name = "build match"; passed = build_match; detail = "proposal, manifest and connected build" }
    ; { name = "base version match"; passed = base_match; detail = "last acknowledged active version" }
    ; { name = "every field in range"; passed = in_range; detail = "declared fields, unique names and integer ranges" }
    ; { name = "engine reachable"; passed = engine_reachable; detail = "connected with known engine state" } ] in
  let errors = List.filter_map checks ~f:(fun check -> if check.passed then None else Some check.name)
    @ (if equal_deployment_class proposal.deployment_class Configuration_only then []
       else [ deployment_name proposal.deployment_class ]) in
  { checks; errors; can_apply = List.is_empty errors }

(* Declared deterministic MOCK defaults, not inferred hardware capabilities. *)
let mock_manifest (identity : identity) =
  { identity; build_id = "m01"; api_schema = "MOCK logical C0"
  ; compiled_rules = [ "slot-0/buy_below_limit" ]
  ; parameter_ranges = [ "maximum_price", "t", 995, 1010; "quantity", "u", 1, 5 ] }
let mock_proposal (identity : identity) =
  { identity; proposal_id = "mock-proposal-13"; target_build = "m01"; base_version = 12
  ; changes = [ "maximum_price", 1006; "quantity", 2 ]; deployment_class = Configuration_only
  ; validation_evidence = [ "MOCK declared parameter ranges" ]; test_evidence = [ "MOCK fixture" ] }
