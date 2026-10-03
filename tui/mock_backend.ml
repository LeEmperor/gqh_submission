open! Core
open Async
open Model_adapter

type scenario =
  | Connected_disarmed | Enabled | No_signal | Admitted | Blocked | Received
  | Update_pending | Update_failed | Connection_lost | Book_invalid
  | Update_ok | Fail_at_idle | Fail_at_verify | Lost_at_activate | Stale_base
  [@@deriving equal, sexp]

let scenarios =
  [ "connected_disarmed", Connected_disarmed; "enabled", Enabled
  ; "no_signal", No_signal; "admitted", Admitted; "blocked", Blocked
  ; "received", Received; "update_pending", Update_pending
  ; "update_failed", Update_failed; "connection_lost", Connection_lost
  ; "book_invalid", Book_invalid; "update_ok", Update_ok
  ; "fail_at_idle", Fail_at_idle; "fail_at_verify", Fail_at_verify
  ; "lost_at_activate", Lost_at_activate; "stale_base", Stale_base ]

let scenario_of_string name =
  match List.Assoc.find scenarios name ~equal:String.equal with
  | Some scenario -> Ok scenario
  | None -> Or_error.error_string
      ("Unknown scenario. Choose: " ^ String.concat ~sep:", " (List.map scenarios ~f:fst))

type t =
  { state : application_state; random : Stdlib.Random.State.t; walk : Market_walk.t
  ; force_receipt : bool
  ; apply_outcome : Mock_apply.outcome; applying : Mock_apply.t option
  ; seen_proposals : String.Set.t; polled_at : Time_ns.t option
  ; owed : float  (* the fraction of a step still owed after the last poll *) }

(* MOCK policy only: ten levels, a center of 1003 bid ticks, and a fixed
   declared candidate bounds in Admission.mock_bounds. No hardware limits. Resting sizes
   come from [Market_walk], on a stream of their own. The Phase 1-4 generator drew one
   value per level from [random]; [burn_level_draws] draws as many, so the seeded price
   path, spreads and decisions stay exactly what they were and only the sizes are new. *)
let burn_level_draws random ~bound =
  for _ = 1 to 2 * Market_walk.depth do ignore (Stdlib.Random.State.int random bound : int) done

let draw_spread random =
  match Stdlib.Random.State.int random 8 with 0 | 1 -> 2 | 2 -> 3 | _ -> 1

(* The interactive range. A bench may raise it. *)
let max_rate_hz = 60.

let create_with_max_rate ~max_rate_hz ~scenario ~seed ~rate_hz =
  if not (Float.is_finite rate_hz) || Float.(rate_hz < 0.1 || rate_hz > max_rate_hz)
  then Or_error.error_string (sprintf "--rate must be finite and in [0.1, %g] Hz" max_rate_hz)
  else (
    let identity =
      { run_id = "demo-03"; snapshot_id = Some 0
      ; decision_id = None; config_version = Some 12 }
    in
    let status, engine = match scenario with
      | Connected_disarmed -> Active_acknowledged 12, Disarmed
      | Update_pending -> Applying "write", Disarmed
      | Update_failed -> Failed "MOCK readback mismatch", Disarmed
      | Connection_lost -> Unknown, Engine_unknown
      | Enabled | No_signal | Admitted | Blocked | Received | Book_invalid
      | Update_ok | Fail_at_idle | Fail_at_verify | Lost_at_activate | Stale_base ->
        Active_acknowledged 12, Armed
    in
    let random = Stdlib.Random.State.make [| seed |] in
    let spread = draw_spread random in
    burn_level_draws random ~bound:80;
    let walk = Market_walk.create ~seed ~bid:1003 ~spread in
    let walk, (bids, asks) = Market_walk.advance walk ~dt:(1. /. rate_hz) ~bid:1003 ~spread
        ~previous:([], []) in
    let maximum_price = if equal_scenario scenario No_signal then 990 else 1005 in
    let quantity = if equal_scenario scenario Blocked then 6 else 1 in
    let rule =
      { identity; rule_id = "slot-0"; slot = 0; name = "buy_below_limit"
      ; predicate = "ask_px ≤ maximum_price → BUY qty @ ask_px"
      ; parameters = [ "maximum_price", maximum_price, "t"; "quantity", quantity, "u" ]
      ; enabled = equal_engine engine Armed
      ; matched = 0; admitted = 0; blocked = 0; last_block_reason = None }
    in
    let state =
      { mode = Mock; connected = not (equal_scenario scenario Connection_lost)
      ; build_id = "m01"; run_id = identity.run_id
      ; configuration =
          { identity; status; last_acknowledged_version = Some 12
          ; parameters = [ "maximum_price", maximum_price; "quantity", quantity ] }
      ; engine
      ; market =
          { identity; mode = Mock; instrument = "AAPL"; bids; asks
          ; valid = not (equal_scenario scenario Book_invalid); source = "MOCK seeded mean-reverting walk" }
      ; trace_loss = 0; updates = 0; rate_hz; rules = [ rule ]; latest_decision = None; decisions = Decision_buffer.empty
      ; manifest = mock_manifest identity
      ; proposal = (let proposal = mock_proposal identity in
          if equal_scenario scenario Stale_base then { proposal with base_version = 11 } else proposal)
      ; config_apply = None; config_events = [] }
    in
    let apply_outcome = match scenario with
      | Fail_at_idle -> Mock_apply.Fail_idle | Fail_at_verify -> Mock_apply.Fail_verify
      | Lost_at_activate -> Mock_apply.Lose_activate | _ -> Mock_apply.Succeed in
    Ok { state; random; walk; applying = None; apply_outcome; seen_proposals = String.Set.empty
       ; force_receipt = equal_scenario scenario Received; polled_at = None; owed = 0. })

let create = create_with_max_rate ~max_rate_hz

let state t = t.state

let evaluate (state : application_state) ~market ~force_receipt =
  let rule = List.hd_exn state.rules in
  match List.hd market.asks with
  | Some ask when rule.enabled && equal_engine state.engine Armed && market.valid ->
    let maximum_price_ticks = List.Assoc.find_exn state.configuration.parameters
        "maximum_price" ~equal:String.equal in
    let quantity_units = List.Assoc.find_exn state.configuration.parameters "quantity" ~equal:String.equal in
    let identity = { market.identity with decision_id = market.identity.snapshot_id } in
    let matched = ask.price_ticks <= maximum_price_ticks in
    let candidate = if not matched then None else Some
        { identity; mode = Mock; rule_id = rule.rule_id; side = Buy
        ; price_ticks = ask.price_ticks; quantity_units } in
    let outcome =
      if not matched then No_signal_result
      else Admission.check ~engine:state.engine ~book_valid:market.valid
        ~bounds:Admission.mock_bounds (Option.value_exn candidate) in
    (* Deterministic MOCK clock and receipts. Admission alone never implies receipt. *)
    let sequence = Option.value_exn identity.decision_id in
    let occurred_at = Time_ns.add Time_ns.epoch
        (Time_ns.Span.of_sec (13. *. 3600. +. 37. *. 60. +. Float.of_int sequence /. state.rate_hz)) in
    let receipt_at =
      if equal_decision_outcome outcome Admitted_result && (force_receipt || sequence mod 3 <> 0)
      then Some (Time_ns.add occurred_at (Time_ns.Span.of_sec 0.002)) else None in
    let decision = { identity; mode = Mock; rule_id = rule.rule_id; inputs = market
                   ; maximum_price_ticks; quantity_units; candidate; outcome; occurred_at; receipt_at
                   ; build_id = state.build_id; slot = rule.slot; predicate_result = Some matched
                   ; bounds = Admission.mock_bounds } in
    let rule = match outcome with
      | No_signal_result -> rule
      | Admitted_result -> { rule with matched = rule.matched + 1; admitted = rule.admitted + 1 }
      | Blocked_result reason -> { rule with matched = rule.matched + 1; blocked = rule.blocked + 1
                                            ; last_block_reason = Some reason } in
    [ rule ], Some decision
  | _ -> state.rules, None

let advance t =
  let t = match t.applying with
    | None -> t
    | Some applying ->
      let state, applying = Mock_apply.advance ~seconds:(1. /. t.state.rate_hz) t.state applying in
      { t with state; applying = Some applying } in
  if not t.state.connected then t
  else (
    let random = Stdlib.Random.State.copy t.random in
    let previous_bid = (List.hd_exn t.state.market.bids).price_ticks in
    (* Reversion plus symmetric seeded noise, rather than unbounded drift. *)
    let bid = previous_bid + ((1003 - previous_bid) / 2) + Stdlib.Random.State.int random 5 - 2 in
    let spread = draw_spread random in
    burn_level_draws random ~bound:79;
    let walk, (bids, asks) = Market_walk.advance t.walk ~dt:(1. /. t.state.rate_hz) ~bid ~spread
        ~previous:(t.state.market.bids, t.state.market.asks) in
    let updates = t.state.updates + 1 in
    let identity = { t.state.market.identity with snapshot_id = Some updates } in
    let market = { t.state.market with identity; bids; asks }
        |> Config_version.stamp_snapshot ~configuration:t.state.configuration in
    let rules, latest_decision = evaluate t.state ~market ~force_receipt:t.force_receipt in
    let decisions = Option.value_map latest_decision ~default:t.state.decisions
        ~f:(Decision_buffer.append t.state.decisions) in
    { t with state = { t.state with market; updates; rules; latest_decision; decisions }; random; walk })

(* The steps owed after [elapsed], on top of [carried] from earlier polls, and what is still
   owed. Dropping the fraction delivered less than the configured rate whenever polls and
   steps did not line up (40 Hz polled every other frame gave 30). Every poll takes at least
   one step, since the app only polls when it expects news, so a poll that arrives early
   overdraws by a fraction (the carry goes negative, to at most one step) that the next polls
   repay. A stall is capped at a second's worth of steps and its debt forgiven. *)
let steps_due ~rate_hz ~elapsed ~carried =
  let owed = carried +. (Time_ns.Span.to_sec elapsed *. rate_hz) in
  let cap = Int.max 1 (Float.to_int rate_hz) in
  let whole = Float.to_int (Float.max 0. owed) in
  if whole > cap then cap, 0.
  else (
    let steps = Int.max 1 whole in
    steps, Float.max (-1.) (owed -. Float.of_int steps))

(* The app polls at most once a frame, and a Bonsai timer cannot fire faster than that.
   Advancing by the steps due since the last poll delivers a stream faster than the
   frame rate as one batch per frame, instead of slowing it to one step per frame. The first
   poll takes one step. *)
let next t =
  let%map.Deferred () = Scheduler.yield () in
  let now = Time_ns.now () in
  let steps, owed = match t.polled_at with
    | None -> 1, 0.
    | Some at -> steps_due ~rate_hz:t.state.rate_hz ~elapsed:(Time_ns.diff now at) ~carried:t.owed in
  let t = Fn.apply_n_times ~n:steps advance t in
  { t with polled_at = Some now; owed }

let handle_command t = function
  | Apply_proposal proposal ->
    if Set.mem t.seen_proposals proposal.proposal_id then t
    else (
      let state, applying = Mock_apply.start ~outcome:t.apply_outcome t.state proposal in
      match applying with
      | None -> t
      | Some applying -> { t with state; applying = Some applying
        ; seen_proposals = Set.add t.seen_proposals proposal.proposal_id })
  | Reconcile ->
    (match t.applying with
     | None -> t
     | Some applying ->
       let state, applying = Mock_apply.request_reconcile t.state applying in
       { t with state; applying = Some applying })
