open! Core
open Bonsai_term
open Bonsai_test
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let ensure condition message = if not condition then failwith message
let contains text substring = String.is_substring text ~substring
let backend () = Mock_backend.create ~scenario:Update_ok ~seed:42 ~rate_hz:4. |> Or_error.ok_exn
let render view ~width ~height =
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width; height }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  Handle.show_into_string handle
let version_is identity expected = Option.equal Int.equal identity.config_version (Some expected)

let%expect_test "new producer snapshots use the last ACK rather than a proposal identity" =
  let state = Mock_backend.state (backend ()) in
  let original = { state.market with identity =
    { state.market.identity with snapshot_id = Some 91; decision_id = Some 77 } } in
  let proposed = { state.configuration with
    status = Applying "4/6"; identity = { state.configuration.identity with config_version = Some 13 } } in
  let stamped = Config_version.stamp_snapshot ~configuration:proposed original in
  ensure (version_is stamped.identity 12) "Proposed version leaked into snapshot";
  ensure (String.equal stamped.identity.run_id original.identity.run_id) "Run changed";
  ensure (Option.equal Int.equal stamped.identity.snapshot_id (Some 91)) "Snapshot changed";
  ensure (Option.equal Int.equal stamped.identity.decision_id (Some 77)) "Decision changed";
  ensure (equal_snapshot { stamped with identity = original.identity } original) "Snapshot evidence changed";
  let without_ack = Config_version.stamp_snapshot
      ~configuration:{ proposed with last_acknowledged_version = None } original in
  ensure (Option.is_none without_ack.identity.config_version) "Missing ACK fabricated a version";
  let acknowledged = Config_version.stamp_snapshot
      ~configuration:{ proposed with status = Active_acknowledged 13; last_acknowledged_version = Some 13 } original in
  ensure (version_is acknowledged.identity 13) "Observed ACK not used";
  print_endline "Pending proposal v13 stamps v12; missing ACK stays absent; ACK v13 stamps v13";
  print_endline "Run/snapshot/decision IDs and all input evidence preserved";
  [%expect {|
    Pending proposal v13 stamps v12; missing ACK stays absent; ACK v13 stamps v13
    Run/snapshot/decision IDs and all input evidence preserved
    |}]

let candidate_record backend =
  let rec find remaining backend =
    let next = Mock_backend.advance backend in
    match (Mock_backend.state next).latest_decision with
    | Some decision when Option.is_some decision.candidate -> next, decision
    | _ when remaining > 0 -> find (remaining - 1) next
    | _ -> failwith "MOCK did not produce a candidate" in
  find 200 backend

let%expect_test "successful backend apply stamps new decisions and preserves frozen history" =
  let before, frozen = candidate_record (backend ()) in
  ensure (version_is frozen.identity 12) "Initial record is not cfg12";
  let initial = Mock_backend.state before in
  let applying = Mock_backend.handle_command before (Apply_proposal initial.proposal) in
  let rec wait remaining backend observed_steps =
    let state = Mock_backend.state backend in
    match state.configuration.status with
    | Active_acknowledged 13 -> backend, observed_steps
    | Applying step ->
      let header = Status_bar.view ~theme ~state ~clock:"13:37:02.417" ~width:80
        |> render ~width:80 ~height:1 in
      ensure (contains header "cfg ✓ACK v12") "Pending header lost old ACK";
      ensure (contains header step && not (contains header "v13")) "Header is optimistic";
      ensure (version_is state.market.identity 12) "Pre-ACK input used proposed version";
      if remaining = 0 then failwith "Apply did not ACK";
      wait (remaining - 1) (Mock_backend.advance backend) (Set.add observed_steps step)
    | _ -> failwith "Successful apply left pending lifecycle unexpectedly" in
  let acknowledged, observed_steps = wait 30 applying String.Set.empty in
  List.iter [ "1/6"; "2/6"; "3/6"; "4/6"; "5/6"; "6/6" ] ~f:(fun step ->
    ensure (Set.mem observed_steps step) ("Backend step not observed: " ^ step));
  let after, fresh = candidate_record acknowledged in
  let state = Mock_backend.state after in
  ensure (version_is state.market.identity 13 && version_is fresh.identity 13) "Fresh cfg13 identity missing";
  ensure (equal_identity fresh.inputs.identity { fresh.identity with decision_id = None }) "Inputs do not match decision identity";
  let candidate = Option.value_exn fresh.candidate in
  ensure (equal_identity candidate.identity fresh.identity) "Candidate identity differs";
  let records = Decision_buffer.to_list state.decisions in
  let retained = List.find_exn records ~f:(fun decision ->
    Option.equal Int.equal decision.identity.decision_id frozen.identity.decision_id) in
  ensure (equal_decision retained frozen) "Historical record rewritten after ACK";
  ensure (List.exists records ~f:(fun record -> version_is record.identity 13)) "Ledger lacks cfg13";
  ensure (List.exists records ~f:(fun record -> version_is record.identity 12)) "Ledger lost cfg12";
  let inspector record = Inspector.view ~theme ~focus:Keymap.Inspector ~mode:Mock ~decision:(Some record)
      ~width:80 ~height:14 |> render ~width:80 ~height:14 in
  let frozen_screen = inspector frozen and fresh_screen = inspector fresh in
  ensure (contains frozen_screen "cfg v12" && contains frozen_screen "MOCK FROZEN") "Frozen Inspector drifted";
  ensure (not (contains frozen_screen "cfg v13")) "Frozen Inspector uses current configuration";
  ensure (contains fresh_screen "cfg v13" && contains fresh_screen "MOCK FROZEN") "Fresh Inspector cfg13 missing";
  let header = Status_bar.view ~theme ~state ~clock:"13:37:02.417" ~width:80
    |> render ~width:80 ~height:1 in
  ensure (contains header "cfg ✓ACK v13") "Post-ACK header did not advance";
  print_endline "All six backend steps retain header/input cfg12; ACK alone changes header to v13";
  print_endline "New record, input and candidate IDs agree at cfg13; ledger retains both versions";
  print_endline "MOCK frozen Inspector stays cfg12; newly inspected record shows cfg13";
  [%expect {|
    All six backend steps retain header/input cfg12; ACK alone changes header to v13
    New record, input and candidate IDs agree at cfg13; ledger retains both versions
    MOCK frozen Inspector stays cfg12; newly inspected record shows cfg13
    |}]
