open! Core
open Tickweave_tui
open Model_adapter

let ensure condition message = if not condition then failwith message
let create ?(rate_hz = 4.) name =
  let scenario = Mock_backend.scenario_of_string name |> Or_error.ok_exn in
  Mock_backend.create ~scenario ~seed:42 ~rate_hz |> Or_error.ok_exn
let state = Mock_backend.state
let advance_n backend count =
  List.fold (List.init count ~f:Fn.id) ~init:backend
    ~f:(fun backend _ -> Mock_backend.advance backend)
let apply backend = Mock_backend.handle_command backend (Apply_proposal (state backend).proposal)
let progress backend = Option.value_exn (state backend).config_apply
let status backend step = List.Assoc.find_exn (progress backend).steps step ~equal:equal_apply_step
let acknowledged backend =
  List.filter_map (state backend).config_events ~f:(fun event ->
    match event.payload with Step_acknowledged step -> Some step | _ -> None)
let activation_count backend =
  List.count (state backend).config_events ~f:(fun event ->
    match event.payload with Activation_acknowledged _ -> true | _ -> false)
let ensure_old backend =
  let s = state backend in
  ensure (Option.equal Int.equal s.configuration.last_acknowledged_version (Some 12)) "optimistic version";
  ensure (Option.equal Int.equal s.configuration.identity.config_version (Some 12)) "optimistic identity";
  ensure (List.equal [%equal: string * int] s.configuration.parameters
    [ "maximum_price", 1005; "quantity", 1 ]) "optimistic parameters";
  let rule = List.hd_exn s.rules in
  ensure (Option.equal Int.equal rule.identity.config_version (Some 12)) "optimistic rule identity";
  ensure (List.equal [%equal: string * int * string] rule.parameters
    [ "maximum_price", 1005, "t"; "quantity", 1, "u" ]) "optimistic rule parameters"

(* Catches accepting a command without backend-owned ACK progress, or committing early. *)
let%test_unit "apply commits only after six backend acknowledgments" =
  let initial = create "enabled" in
  let backend = apply initial in
  ensure (equal_step_status (status backend Validate_step) Step_active) "validate not started";
  ensure (List.is_empty (acknowledged backend)) "command fabricated an ACK";
  ensure_old backend;
  let backend = Mock_backend.advance backend in
  ensure (List.is_empty (acknowledged backend)) "ACK happened before half a second";
  let backend = Mock_backend.advance backend in
  ensure (List.equal equal_apply_step (acknowledged backend) [ Validate_step ]) "validate ACK absent";
  ensure (equal_engine (state backend).engine Armed) "disable became optimistic";
  let backend = advance_n backend 2 in
  ensure (equal_engine (state backend).engine Disarmed) "disable ACK did not disarm";
  ensure (not (List.hd_exn (state backend).rules).enabled) "rule remained enabled";
  let backend = advance_n backend 7 in
  ensure_old backend;
  ensure (equal_step_status (status backend Activate_step) Step_active) "activate not waiting";
  let backend = Mock_backend.advance backend in
  let s = state backend in
  ensure (equal_configuration_status s.configuration.status (Active_acknowledged 13)) "final ACK not active";
  ensure (Option.equal Int.equal s.configuration.last_acknowledged_version (Some 13)) "final ACK lost";
  ensure (List.equal [%equal: string * int] s.configuration.parameters
    [ "maximum_price", 1006; "quantity", 2 ]) "proposal values not committed";
  ensure (equal_engine s.engine Armed && (List.hd_exn s.rules).enabled) "previous armed state not restored";
  ensure (List.equal equal_apply_step (acknowledged backend)
    [ Validate_step; Disable_step; Wait_idle_step; Write_step; Verify_readback_step; Activate_step ]) "ACK order";
  ensure (activation_count backend = 1) "activation ACK count";
  ensure (Option.equal Int.equal (progress backend).acknowledged_version (Some 13)) "progress ACK version"

(* Catches failure fixtures auto-starting or starting with unacknowledged versions. *)
let%test_unit "five lifecycle scenarios start with last ACK twelve and need a command" =
  List.iter [ "update_ok"; "fail_at_idle"; "fail_at_verify"; "lost_at_activate"; "stale_base" ]
    ~f:(fun name ->
      let backend = create name in
      ensure_old backend;
      ensure (Option.is_none (state backend).config_apply) "scenario auto-applied";
      ensure (List.is_empty (state backend).config_events) "scenario fabricated progress";
      let base = if String.equal name "stale_base" then 11 else 12 in
      ensure ((state backend).proposal.base_version = base) "scenario base version";
      let later = advance_n backend 40 in
      ensure_old later;
      ensure (Option.is_none (state later).config_apply && List.is_empty (state later).config_events)
        "scenario auto-applied on a timer")

(* Catches basing timing on market-update count instead of elapsed backend time. *)
let%test_unit "ACK timing follows elapsed time at slow and fast market rates" =
  List.iter [ 2., 1; 4., 2; 60., 30 ] ~f:(fun (rate_hz, updates) ->
    let backend = create ~rate_hz "update_ok" |> apply in
    let before = advance_n backend (updates - 1) in
    ensure (List.is_empty (acknowledged before)) "ACK early at rate";
    let after = Mock_backend.advance before in
    ensure (List.equal equal_apply_step (acknowledged after) [ Validate_step ]) "half-second ACK depends on rate")

(* Catches retries or activation after a known failure. *)
let%test_unit "idle and verify failures stop permanently at last ACK twelve" =
  List.iter [ "fail_at_idle", Wait_idle_step; "fail_at_verify", Verify_readback_step ]
    ~f:(fun (name, step) ->
      let backend = create name |> apply |> fun b -> advance_n b 16 in
      ensure_old backend;
      ensure (equal_engine (state backend).engine Disarmed) "failure did not stay disarmed";
      ensure (not (List.hd_exn (state backend).rules).enabled) "failed rule enabled";
      (match status backend step with Step_failed reason -> ensure (not (String.is_empty reason)) "reason absent"
       | _ -> failwith "step did not fail");
      (match (state backend).configuration.status with Failed _ -> () | _ -> failwith "config not failed");
      ensure (activation_count backend = 0) "failure activated";
      let events = (state backend).config_events in
      let retried = apply backend |> fun b -> advance_n b 24 in
      ensure (List.equal equal_config_event events (state retried).config_events) "failure retried";
      ensure_old retried)

(* Catches trusting UI validation, malformed fields, stale build/base or deployment bypass. *)
let%test_unit "direct backend commands revalidate all declared proposal constraints" =
  let initial = create "update_ok" in
  let p = (state initial).proposal in
  List.iter
    [ { p with base_version = 11 }; { p with target_build = "other" }
    ; { p with changes = [ "quantity", 6 ] }; { p with changes = [ "undeclared", 1 ] }
    ; { p with changes = [ "quantity", 1; "quantity", 2 ] }; { p with changes = [] }
    ; { p with deployment_class = Rebuild_required }; { p with deployment_class = Unsupported } ]
    ~f:(fun proposal ->
      let backend = Mock_backend.handle_command initial (Apply_proposal proposal) in
      ensure_old backend;
      ensure (List.is_empty (acknowledged backend)) "invalid proposal acknowledged";
      ensure (equal_engine (state backend).engine Disarmed) "invalid proposal did not confirm disarmed";
      (match status backend Validate_step with Step_failed _ -> () | _ -> failwith "invalid proposal accepted");
      let later = advance_n backend 20 in
      ensure (activation_count later = 0) "invalid proposal activated";
      ensure_old later);
  let stale = create "stale_base" |> apply in
  (match status stale Validate_step with Step_failed _ -> () | _ -> failwith "stale fixture accepted");
  let unreachable = create "connection_lost" in
  let rejected = apply unreachable in
  ensure (equal_application_state (state unreachable) (state rejected)) "unreachable engine accepted apply"

(* Catches duplicate or replacement commands interrupting an accepted transaction. *)
let%test_unit "inflight and terminal commands cannot replay or replace an apply" =
  let backend = create "update_ok" |> apply |> fun b -> advance_n b 4 in
  let repeated = apply backend in
  ensure (equal_application_state (state backend) (state repeated)) "duplicate command changed progress";
  let altered = { (state backend).proposal with proposal_id = "replacement"; changes = [ "quantity", 3 ] } in
  let replaced = Mock_backend.handle_command backend (Apply_proposal altered) in
  ensure (equal_application_state (state backend) (state replaced)) "inflight replacement accepted";
  let terminal = advance_n backend 20 in
  let replayed = apply terminal |> fun b -> advance_n b 20 in
  ensure (activation_count replayed = 1) "terminal replay activated twice";
  ensure (List.equal equal_config_event (state terminal).config_events (state replayed).config_events) "terminal replay emitted events"

(* Catches converting lost activation communication to disarmed or retrying without status read. *)
let%test_unit "lost activation freezes UNKNOWN until explicit reconcile reads backend status" =
  let backend = create "lost_at_activate" |> apply |> fun b -> advance_n b 12 in
  ensure_old backend;
  let s = state backend in
  ensure (equal_configuration_status s.configuration.status Unknown) "lost activation not UNKNOWN";
  ensure (equal_engine s.engine Engine_unknown && not s.connected) "lost engine guessed disabled";
  (match status backend Activate_step with Step_unknown _ -> () | _ -> failwith "activate missing unknown");
  ensure (activation_count backend = 0) "lost ACK fabricated";
  let frozen = advance_n backend 40 in
  ensure (equal_application_state s (state frozen)) "unknown auto-reconciled";
  let invalid = Mock_backend.handle_command frozen (Apply_proposal { s.proposal with proposal_id = "bypass" }) in
  ensure (equal_application_state s (state invalid)) "unknown accepted apply";
  let reading = Mock_backend.handle_command frozen Reconcile in
  ensure (equal_reconciliation_status (progress reading).reconciliation Reconciling) "status read not requested";
  ensure (equal_engine (state reading).engine Engine_unknown) "reconcile guessed disarmed before read";
  ensure (equal_configuration_status (state reading).configuration.status Unknown) "read hid UNKNOWN";
  let early = Mock_backend.advance reading in
  ensure (equal_engine (state early).engine Engine_unknown) "read completed early";
  let reconciled = Mock_backend.handle_command early Reconcile |> Mock_backend.advance in
  ensure_old reconciled;
  ensure (equal_engine (state reconciled).engine Disarmed && (state reconciled).connected) "read status not confirmed";
  (match (state reconciled).configuration.status with Failed _ -> () | _ -> failwith "reconcile did not terminate");
  ensure (List.exists (state reconciled).config_events ~f:(fun event ->
    match event.payload with Status_reconciled (Some 12, Disarmed) -> true | _ -> false)) "read acknowledgment absent";
  let terminal = apply reconciled |> fun b -> advance_n b 20 in
  ensure (activation_count terminal = 0) "reconcile retried activation";
  ensure (List.equal equal_config_event (state reconciled).config_events (state terminal).config_events) "reconcile replayed"

(* Catches stamping only the configuration while decisions continue using stale snapshot identity. *)
let%test_unit "activation stamps future market rule candidate and decision versions without rewriting history" =
  let initial = create "update_ok" |> fun b -> advance_n b 2 in
  let old_decisions = Decision_buffer.to_list (state initial).decisions in
  let applied = apply initial |> fun b -> advance_n b 12 in
  let states = List.folding_map (List.init 40 ~f:Fn.id) ~init:applied ~f:(fun b _ ->
    let b = Mock_backend.advance b in b, state b) in
  List.iter states ~f:(fun s ->
    ensure (Option.equal Int.equal s.market.identity.config_version (Some 13)) "market version stale";
    ensure (Option.equal Int.equal (List.hd_exn s.rules).identity.config_version (Some 13)) "rule version stale";
    Option.iter s.latest_decision ~f:(fun d ->
      ensure (Option.equal Int.equal d.identity.config_version (Some 13)) "decision version stale";
      ensure (Option.equal Int.equal d.inputs.identity.config_version (Some 13)) "input version stale";
      ensure (d.maximum_price_ticks = 1006 && d.quantity_units = 2) "decision values stale";
      Option.iter d.candidate ~f:(fun c -> ensure (equal_identity c.identity d.identity) "candidate identity stale")));
  let decisions = Decision_buffer.to_list (List.last_exn states).decisions in
  List.iter old_decisions ~f:(fun old ->
    ensure (List.exists decisions ~f:(equal_decision old)) "history was rewritten");
  let ids = List.map decisions ~f:(fun d -> Option.value_exn d.identity.decision_id) in
  ensure (List.length ids = List.length (List.dedup_and_sort ids ~compare:Int.compare)) "duplicate decision IDs";
  let events = (List.last_exn states).config_events in
  ensure (List.length events <= 128) "config event buffer unbounded";
  ensure (List.for_all events ~f:(fun event -> equal_mode event.mode Mock)) "event provenance missing";
  ensure (List.for_all (List.zip_exn (List.drop_last_exn events) (List.tl_exn events))
    ~f:(fun (a, b) -> a.sequence < b.sequence)) "event sequences unordered"

(* Catches backend status drifting from the acknowledged numeric lifecycle stage. *)
let%test_unit "backend status exposes the current acknowledged lifecycle position" =
  let _, statuses = List.fold [ "1/6"; "2/6"; "3/6"; "4/6"; "5/6"; "6/6" ]
    ~init:(create "update_ok" |> apply, []) ~f:(fun (backend, statuses) expected ->
      ensure (equal_configuration_status (state backend).configuration.status (Applying expected))
        ("missing numeric apply position " ^ expected);
      advance_n backend 2, expected :: statuses) in
  ensure (List.length statuses = 6) "stages absent"

(* Catches treating a deliberate fresh plan as a retry, or replaying an older failed proposal. *)
let%test_unit "known failure permits only an explicitly fresh proposal ID" =
  let failed = create "fail_at_idle" |> apply |> fun b -> advance_n b 12 in
  let original = (state failed).proposal in
  let fresh = { original with proposal_id = "fresh-plan"; changes = [ "quantity", 3 ] } in
  let restarted = Mock_backend.handle_command failed (Apply_proposal fresh) in
  ensure (String.equal (progress restarted).proposal_id "fresh-plan") "explicit fresh plan blocked";
  ensure (equal_step_status (status restarted Validate_step) Step_active) "fresh plan did not validate";
  ensure_old restarted;
  let failed_again = advance_n restarted 12 in
  let replayed = Mock_backend.handle_command failed_again (Apply_proposal original) in
  ensure (equal_application_state (state failed_again) (state replayed)) "older failed ID replayed";
  let replayed_fresh = Mock_backend.handle_command failed_again (Apply_proposal fresh) in
  ensure (equal_application_state (state failed_again) (state replayed_fresh)) "latest failed ID replayed"

(* Catches silently rejecting an external fresh proposal after a completed ACK. *)
let%test_unit "acknowledged completion accepts a fresh plan and advances the next version" =
  let first = create "update_ok" |> apply |> fun b -> advance_n b 12 in
  let original = (state first).proposal in
  ensure (equal_configuration_status (state first).configuration.status (Active_acknowledged 13))
    "first proposal did not ACK";
  let fresh = { original with proposal_id = "external-plan-14"; base_version = 13
    ; identity = { original.identity with config_version = Some 13 }
    ; changes = [ "maximum_price", 1007; "quantity", 3 ] } in
  let second = Mock_backend.handle_command first (Apply_proposal fresh) in
  ensure (String.equal (progress second).proposal_id "external-plan-14") "fresh completed-state plan blocked";
  ensure (equal_step_status (status second Validate_step) Step_active) "second validation absent";
  ensure (Option.equal Int.equal (state second).configuration.last_acknowledged_version (Some 13))
    "second proposal committed before ACK";
  ensure (List.equal [%equal: string * int] (state second).configuration.parameters
    [ "maximum_price", 1006; "quantity", 2 ]) "second proposal values became optimistic";
  let second = advance_n second 12 in
  let s = state second in
  ensure (equal_configuration_status s.configuration.status (Active_acknowledged 14)) "second ACK did not advance version";
  ensure (Option.equal Int.equal s.configuration.last_acknowledged_version (Some 14)) "second version not acknowledged";
  ensure (List.equal [%equal: string * int] s.configuration.parameters
    [ "maximum_price", 1007; "quantity", 3 ]) "second proposal values absent";
  ensure (equal_engine s.engine Armed && (List.hd_exn s.rules).enabled) "second apply did not restore armed state";
  ensure (Option.equal Int.equal s.market.identity.config_version (Some 14)) "second market version stale";
  ensure (Option.equal Int.equal (List.hd_exn s.rules).identity.config_version (Some 14)) "second rule version stale";
  ensure (activation_count second = 2) "second activation ACK count";
  List.iter [ original; fresh ] ~f:(fun old ->
    let replayed = Mock_backend.handle_command second (Apply_proposal old) in
    ensure (equal_application_state s (state replayed)) "completed proposal ID replayed")
