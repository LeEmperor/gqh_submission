open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let key ?(mods = []) key = Event.Key_press { key; mods }
let contains text fragment = String.is_substring text ~substring:fragment
let fixture () =
  Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4.
  |> Or_error.ok_exn |> Mock_backend.state
let handle ?(dimensions = { Dimensions.width = 100; height = 30 }) initial =
  let commands = ref [] in
  let h = Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
      ~to_view_with_handler:(fun (config, _) ->
        ~view:(Option.value config.Config_review.modal ~default:View.none),
        ~handler:(fun event -> let%map.Effect response = config.handler event in
          Option.iter response.command ~f:(fun command -> commands := command :: !commands)))
      ~handle_incoming:(fun (_, set) state -> set state)
      (fun ~dimensions (local_ graph) ->
        let state, set = Bonsai.state initial graph in
        let width = let%arr dimensions in Int.min 96 (Int.max 4 (dimensions.width - 4)) - 4 in
        let stepper = Config_stepper.component ~theme:(Bonsai.return theme) ~state ~width graph in
        let config = Config_review.component ~theme:(Bonsai.return theme) ~state ~dimensions ~stepper graph in
        let%arr config and set in config, set) in
  h, commands
let screen h = Bonsai_test.Handle.show_into_string h
let result h = ignore (screen h : string); fst (Bonsai_term_test.last_result h)
let send h events = List.iter events ~f:(Bonsai_term_test.send_event h)
let type_text h text = String.iter text ~f:(fun c -> Bonsai_term_test.send_event h (key (ASCII c)))
let confirm h =
  Bonsai_term_test.send_event h (key (ASCII 'A'));
  type_text h "apply";
  Bonsai_term_test.send_event h (key Enter)
let value config name = List.Assoc.find config.Config_review.draft.changes name ~equal:String.equal

let%expect_test "modal diff checklist and backend lifecycle fit minimum dimensions" =
  let h, _ = handle (fixture ()) in
  ignore (screen h : string);
  Bonsai_term_test.send_event h (key (ASCII 'c'));
  let text = screen h in
  List.iter [ "target build m01"; "connected build m01"; "base version v12"; "last ACK active v12"
            ; "CONFIGURATION_ONLY"; "maximum_price"; "1005"; "1006"; "[995, 1010]"
            ; "quantity"; "[1, 5]"; "build match"; "base version match"; "every field in range"
            ; "engine reachable"; "verify readback"; "A Apply" ] ~f:(fun item ->
    if not (contains text item) then failwith ("Missing modal field: " ^ item));
  let view = Option.value_exn (result h).modal in
  printf "all fields visible; size %d×%d; fits 100×30 %b; can apply %b\n"
    (View.width view) (View.height view) (View.width view <= 96 && View.height view <= 28) (result h).can_apply;
  [%expect {| all fields visible; size 96×22; fits 100×30 true; can apply true |}]

let%expect_test "stale build and stale base version cannot emit Apply" =
  let state = fixture () in
  List.iter [ { state with proposal = { state.proposal with target_build = "different" } }
            ; { state with proposal = { state.proposal with base_version = 11 } } ] ~f:(fun state ->
    let h, commands = handle state in
    ignore (screen h : string);
    send h [ key (ASCII 'c'); key (ASCII 'A') ];
    type_text h "apply";
    Bonsai_term_test.send_event h (key Enter);
    let text = screen h in
    printf "stale %b; can apply %b; commands %d\n"
      (contains text "✗ STALE — re-plan required") (result h).can_apply (List.length !commands));
  [%expect {|
    stale true; can apply false; commands 0
    stale true; can apply false; commands 0
  |}]

let%expect_test "queued c Enter q j Tab c question keys belong to the actual textbox" =
  let h, commands = handle (fixture ()) in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key Enter; key (ASCII 'q'); key (ASCII 'j'); key Tab; key (ASCII 'c'); key (ASCII '?') ];
  let text = screen h in
  let config = result h in
  printf "open %b; editing %b; textbox contains queued keys %b; selected stable %b; commands %d; can apply %b\n"
    config.is_open config.is_editing (contains text "1006qjc?")
    (Option.equal String.equal config.selected_parameter (Some "maximum_price")) (List.length !commands) config.can_apply;
  Bonsai_term_test.send_event h (key Escape);
  let config = result h in
  printf "Esc closes %b; resets draft %b; active unchanged %b\n" (not config.is_open)
    (Option.equal Int.equal (value config "maximum_price") (Some 1006))
    (Option.equal Int.equal (List.Assoc.find (fixture ()).configuration.parameters "maximum_price" ~equal:String.equal) (Some 1005));
  [%expect {|
    open true; editing true; textbox contains queued keys true; selected stable true; commands 0; can apply false
    Esc closes true; resets draft true; active unchanged true
  |}]

let%expect_test "numeric editing validates out of range and invalid text live" =
  let h, commands = handle (fixture ()) in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key Enter; key ~mods:[ Ctrl ] (ASCII 'u') ];
  type_text h "9999";
  let text = screen h in
  printf "range error visible %b; can apply %b; proposed %d\n"
    (contains text "✗ [995, 1010]") (result h).can_apply (Option.value_exn (value (result h) "maximum_price"));
  Bonsai_term_test.send_event h (key (ASCII 'q'));
  printf "invalid integer live %b; can apply %b\n"
    (contains (screen h) "proposed value must be a decimal integer") (result h).can_apply;
  send h [ key ~mods:[ Ctrl ] (ASCII 'u') ];
  type_text h "1009";
  printf "valid input live %b; proposed %d; no command %b\n" (result h).can_apply
    (Option.value_exn (value (result h) "maximum_price")) (List.is_empty !commands);
  Bonsai_term_test.send_event h (key Escape);
  let config = result h in
  printf "Esc discards valid draft %b; emits nothing %b\n"
    (Option.equal Int.equal (value config "maximum_price") (Some 1006)) (List.is_empty !commands);
  [%expect {|
    range error visible true; can apply false; proposed 9999
    invalid integer live true; can apply false
    valid input live true; proposed 1009; no command true
    Esc discards valid draft true; emits nothing true
  |}]

let%expect_test "exact typed confirmation emits latest draft once even without redraw" =
  let h, commands = handle (fixture ()) in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key Enter; key ~mods:[ Ctrl ] (ASCII 'u') ];
  type_text h "1009";
  send h [ key Enter; key (ASCII 'A'); key (ASCII 'A'); key Enter ];
  printf "A twice cannot confirm %b; remains editing %b\n" (List.is_empty !commands) (result h).is_editing;
  Bonsai_term_test.send_event h (key ~mods:[ Ctrl ] (ASCII 'u'));
  type_text h "apply ";
  Bonsai_term_test.send_event h (key Enter);
  ignore (screen h : string);
  printf "trailing space rejected %b\n" (List.is_empty !commands);
  Bonsai_term_test.send_event h (key Backspace);
  send h [ key Enter; key Enter; key (ASCII 'A') ];
  type_text h "apply";
  Bonsai_term_test.send_event h (key Enter);
  ignore (screen h : string);
  let proposal = match !commands with [ Apply_proposal p ] -> p | _ -> failwith "Expected one Apply_proposal" in
  printf "single atomic Apply %b; latest proposed %d; remains open %b; no optimistic activation %b\n"
    (List.length !commands = 1) (List.Assoc.find_exn proposal.changes "maximum_price" ~equal:String.equal)
    (result h).is_open (contains (screen h) "last ACK active v12");
  [%expect {|
    A twice cannot confirm true; remains editing true
    trailing space rejected true
    single atomic Apply true; latest proposed 1009; remains open true; no optimistic activation true
  |}]

let%expect_test "confirmation rechecks connected build and acknowledged version" =
  let state = fixture () in
  List.iter [ { state with build_id = "new-build" }
            ; { state with configuration = { state.configuration with last_acknowledged_version = Some 13 } } ]
    ~f:(fun changed ->
      let h, commands = handle state in
      ignore (screen h : string);
      send h [ key (ASCII 'c'); key (ASCII 'A') ];
      type_text h "apply";
      Bonsai_term_test.do_actions h [ changed ];
      Bonsai_term_test.send_event h (key Enter);
      printf "stale visible %b; no command %b; can apply %b\n"
        (contains (screen h) "✗ STALE — re-plan required") (List.is_empty !commands) (result h).can_apply);
  [%expect {|
    stale visible true; no command true; can apply false
    stale visible true; no command true; can apply false
  |}]

let%expect_test "deployment class badges explain why no Apply is offered" =
  let state = fixture () in
  List.iter [ Rebuild_required, "compiled logic changed"; Unsupported, "cannot be deployed" ] ~f:(fun (deployment_class, reason) ->
    let h, commands = handle { state with proposal = { state.proposal with deployment_class } } in
    ignore (screen h : string);
    send h [ key (ASCII 'c'); key (ASCII 'A') ];
    let text = screen h in
    printf "%s visible %b; reason visible %b; can apply %b; no confirmation %b; no command %b\n"
      (deployment_name deployment_class) (contains text (deployment_name deployment_class)) (contains text reason)
      (result h).can_apply (not (result h).is_editing) (List.is_empty !commands));
  [%expect {|
    REBUILD_REQUIRED visible true; reason visible true; can apply false; no confirmation true; no command true
    UNSUPPORTED visible true; reason visible true; can apply false; no confirmation true; no command true
  |}]

let%expect_test "unknown exposes reconcile alone and absorbs apply edit and global keys" =
  let state = fixture () in
  let state = { state with connected = false; engine = Engine_unknown
    ; configuration = { state.configuration with status = Unknown } } in
  let h, commands = handle state in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key Enter; key (ASCII 'A'); key (ASCII 'q'); key Tab; key (ASCII '?') ];
  let text = screen h in
  printf "unknown last ACK %b; reconcile offered %b; no disabled assertion %b; no Apply %b; no editor %b\n"
    (contains text "? STATE UNKNOWN — last ack v12") (contains text "r reconcile")
    (not (contains (String.lowercase text) "disabled")) (not (contains text "Apply")) (not (result h).is_editing);
  send h [ key (ASCII 'r'); key (ASCII 'r') ];
  printf "one Reconcile %b; no parameter change %b\n"
    ([%equal: command list] !commands [ Reconcile ])
    (equal_proposal (result h).draft state.proposal);
  Bonsai_term_test.send_event h (key Escape);
  printf "Esc closes %b\n" (not (result h).is_open);
  [%expect {|
    unknown last ACK true; reconcile offered true; no disabled assertion true; no Apply true; no editor true
    one Reconcile true; no parameter change true
    Esc closes true
  |}]

let%expect_test "stable parameter names navigate and failure blocks retry until re-plan" =
  let state = fixture () in
  let h, _ = handle state in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key (ASCII 'j') ];
  printf "j selects quantity %b; " (Option.equal String.equal (result h).selected_parameter (Some "quantity"));
  send h [ key (ASCII 'g'); key (ASCII 'G'); key (Arrow `Up) ];
  printf "g G up selects maximum_price %b\n"
    (Option.equal String.equal (result h).selected_parameter (Some "maximum_price"));
  let progress =
    { proposal_id = state.proposal.proposal_id
    ; steps = List.map apply_steps ~f:(fun step -> step,
        if equal_apply_step step Write_step then Step_failed "MOCK write rejected" else Step_pending)
    ; acknowledged_version = None; failure = Some (Write_step, "MOCK write rejected")
    ; state_unknown = false; reconciliation = Not_requested } in
  let failed = { state with engine = Disarmed; config_apply = Some progress
    ; configuration = { state.configuration with status = Failed "MOCK write rejected" } } in
  let h, commands = handle failed in
  ignore (screen h : string);
  send h [ key (ASCII 'c'); key Enter ];
  confirm h;
  let text = screen h in
  printf "failure step/reason visible %b; re-plan hint %b; retry blocked %b; edit closed %b\n"
    (contains text "write" && contains text "MOCK write rejected") (contains text "fresh re-plan required")
    (List.is_empty !commands) (not (result h).is_editing);
  Bonsai_term_test.send_event h (key Escape);
  Bonsai_term_test.do_actions h [ { failed with proposal = { state.proposal with proposal_id = "new-plan" } } ];
  Bonsai_term_test.send_event h (key (ASCII 'c'));
  printf "fresh proposal can apply %b\n" (result h).can_apply;
  [%expect {|
    j selects quantity true; g G up selects maximum_price true
    failure step/reason visible true; re-plan hint true; retry blocked true; edit closed true
    fresh proposal can apply true
  |}]

let%expect_test "completed Apply no longer claims it is awaiting acknowledgment" =
  let state = fixture () in
  let h, _ = handle state in
  ignore (screen h : string);
  Bonsai_term_test.send_event h (key (ASCII 'c'));
  confirm h;
  ignore (screen h : string);
  let completed = { state with configuration = { state.configuration with
    status = Active_acknowledged 13; last_acknowledged_version = Some 13 }
    ; config_apply = Some { proposal_id = state.proposal.proposal_id
      ; steps = List.map apply_steps ~f:(fun step -> step, Step_done)
      ; acknowledged_version = Some 13; failure = None; state_unknown = false
      ; reconciliation = Not_requested } } in
  Bonsai_term_test.do_actions h [ completed ];
  let text = screen h in
  if not (contains text "✓ APPLIED — ACK v13") || contains text "awaiting backend acknowledgment"
  then failwith "Completed Apply retained pending action text";
  print_endline "ACK v13 observed: APPLIED; pending submission hint removed";
  [%expect {| ACK v13 observed: APPLIED; pending submission hint removed |}]
