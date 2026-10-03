open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect


let theme = Theme.create No_color
let fixture () = Mock_backend.create ~scenario:Connected_disarmed ~seed:42 ~rate_hz:4.
  |> Or_error.ok_exn |> Mock_backend.state
let ensure condition message = if not condition then failwith message
let contains text substring = String.is_substring text ~substring
let steps_at current status = List.map apply_steps ~f:(fun step ->
  step, if equal_apply_step step current then status
  else if step_number step < step_number current then Step_done else Step_pending)
let progress steps =
  { proposal_id = "mock-proposal-13"; steps; acknowledged_version = None
  ; failure = None; state_unknown = false; reconciliation = Not_requested }
let with_progress progress =
  let state = fixture () in
  { state with engine = Disarmed; config_apply = Some progress
  ; configuration = { state.configuration with status = Applying "4/6" } }
let static_text state =
  let view = Config_stepper.view ~theme ~state ~spinner:(View.text "◐") ~width:80 in
  let handle = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:{ width = 80; height = 10 }
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  Handle.show_into_string handle, view
let component_handle state =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 80; height = 10 }
    ~to_view_with_handler:(fun (view, _) -> ~view, ~handler:(fun _ -> Effect.Ignore))
    ~handle_incoming:(fun (_, inject) next -> inject next)
    (fun ~dimensions:_ (local_ graph) ->
      let state, inject = Bonsai.state state graph in
      let view = Config_stepper.component ~theme:(Bonsai.return theme) ~state ~width:(Bonsai.return 80) graph in
      let%arr view and inject in view, inject)

let%expect_test "six observed rows and pending ACK fit the minimum modal" =
  let state = with_progress (progress (steps_at Write_step Step_active)) in
  let text, view = static_text state in
  ensure (contains text "◐ write · in flight") "Active step missing";
  ensure (contains text "○ ACK v13 · pending") "Pending target missing";
  ensure (not (contains text "✓ ACK") && not (contains text "last ack")) "Pending target shown as acknowledged";
  ensure (View.height view <= 10 && View.width view <= 80) "Stepper exceeds modal";
  Bonsai_term_test.print_view view;
  [%expect {|
    ✓ validate
    ✓ disable
    ✓ wait idle
    ◐ write · in flight
    ○ verify readback
    ○ activate
    ○ ACK v13 · pending
    |}]

let%expect_test "each observed failure names its step and leaves the engine disarmed" =
  List.iter apply_steps ~f:(fun step ->
    let reason = "MOCK rejected " ^ step_name step in
    let progress = { (progress (steps_at step (Step_failed reason))) with
      failure = Some (step, reason) } in
    let state = with_progress progress in
    let state = { state with configuration = { state.configuration with status = Failed reason } } in
    let text, view = static_text state in
    ensure (contains text ("✗ " ^ step_name step ^ " · " ^ reason)) "Failure detail missing";
    ensure (contains text "engine remains DISARMED") "Disarmed outcome missing";
    ensure (not (contains text "◐") && not (contains text "v13")) "Failure looks active";
    ensure (View.height view <= 10) "Failure exceeds modal";
    printf "%s: reason visible; engine remains DISARMED\n" (step_name step));
  [%expect {|
    validate: reason visible; engine remains DISARMED
    disable: reason visible; engine remains DISARMED
    wait idle: reason visible; engine remains DISARMED
    write: reason visible; engine remains DISARMED
    verify readback: reason visible; engine remains DISARMED
    activate: reason visible; engine remains DISARMED
    |}]

let unknown_state () =
  let progress = { (progress (steps_at Activate_step (Step_unknown "MOCK communication lost"))) with
    state_unknown = true } in
  let state = with_progress progress in
  { state with connected = false; engine = Engine_unknown
  ; configuration = { state.configuration with status = Unknown } }

let%expect_test "lost activation is indeterminate and offers only reconcile" =
  let text, view = static_text (unknown_state ()) in
  ensure (contains text "? STATE UNKNOWN — last ack v12") "Unknown summary missing";
  ensure (contains text "? activate · indeterminate") "Activation looks complete";
  ensure (contains text "r reconcile") "Reconcile missing";
  List.iter [ "v13"; "DISARMED"; "disabled"; "◐"; "apply" ] ~f:(fun forbidden ->
    ensure (not (contains text forbidden)) ("Unsafe unknown text: " ^ forbidden));
  Bonsai_term_test.print_view view;
  [%expect {|
    ✓ validate
    ✓ disable
    ✓ wait idle
    ✓ write
    ✓ verify readback
    ? activate · indeterminate: MOCK communication lost
    ? STATE UNKNOWN — last ack v12
    r reconcile
    |}]

let%expect_test "installed spinner never advances backend steps or ACK" =
  let state = with_progress (progress (steps_at Write_step Step_active)) in
  let handle = component_handle state in
  ignore (Handle.show_into_string handle : string);
  List.iter [ 0.2; 1.; 10. ] ~f:(fun seconds ->
    Handle.advance_clock_by handle (Time_ns.Span.of_sec seconds);
    let text = Handle.show_into_string handle in
    ensure (contains text "write · in flight" && contains text "○ verify readback") "Timer advanced steps";
    ensure (contains text "○ ACK v13 · pending" && not (contains text "✓ ACK")) "Timer advanced ACK");
  let progress = { (Option.value_exn state.config_apply) with
    steps = List.map apply_steps ~f:(fun step -> step, Step_done); acknowledged_version = Some 13 } in
  let acknowledged = { state with config_apply = Some progress
    ; configuration = { state.configuration with status = Active_acknowledged 13
                         ; last_acknowledged_version = Some 13 } } in
  Bonsai_term_test.do_actions handle [ acknowledged ];
  let text = Handle.show_into_string handle in
  ensure (contains text "✓ ACK v13" && not (contains text "in flight")) "Observed ACK not rendered";
  print_endline "Clock changes only spinner; backend ACK alone completes v13";
  [%expect {| Clock changes only spinner; backend ACK alone completes v13 |}]

let%expect_test "reconcile read retains unknown until a backend response" =
  let unknown = unknown_state () in
  let reading = { unknown with config_apply = Option.map unknown.config_apply
      ~f:(fun p -> { p with reconciliation = Reconciling }) } in
  let handle = component_handle reading in
  ignore (Handle.show_into_string handle : string);
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 5.);
  let text = Handle.show_into_string handle in
  ensure (contains text "reading status" && contains text "? STATE UNKNOWN — last ack v12") "Reading hides unknown";
  ensure (not (contains text "v13") && not (contains text "DISARMED")) "Reading assumes outcome";
  let known = { unknown with connected = true; engine = Disarmed
    ; configuration = { unknown.configuration with status = Active_acknowledged 12 }
    ; config_apply = Option.map unknown.config_apply ~f:(fun p ->
        { p with state_unknown = false; steps = pending_steps; acknowledged_version = Some 12
               ; reconciliation = Reconciled "MOCK observed v12" }) } in
  Bonsai_term_test.do_actions handle [ known ];
  let text = Handle.show_into_string handle in
  ensure (contains text "✓ ACK v12" && not (contains text "STATE UNKNOWN")) "Backend reply did not resolve unknown";
  print_endline "Reading spinner keeps unknown; known backend reply resolves it";
  [%expect {| Reading spinner keeps unknown; known backend reply resolves it |}]

let%expect_test "numeric apply headers preserve prior ACK at 100 and 80 columns" =
  List.iter [ 100; 80 ] ~f:(fun width ->
    List.iter apply_steps ~f:(fun step ->
      let state = fixture () in
      let state = { state with engine = Disarmed; configuration =
        { state.configuration with status = Applying (sprintf "%d/6" (step_number step)) } } in
      let label, _ = Status_bar.configuration_label state.configuration in
      let expected = sprintf "cfg ✓ACK v12 ◐ APPLYING %d/6" (step_number step) in
      ensure (String.equal label expected) "Numeric label lost ACK or progress";
      let view = Status_bar.view ~theme ~state ~clock:"13:37:02.417" ~width in
      let handle = Bonsai_term_test.create_handle_without_handler
          ~initial_dimensions:{ width; height = 1 }
          (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
      let text = Handle.show_into_string handle in
      ensure (contains text expected && contains text "DISARMED" && contains text "book ✓VALID") "Safety field dropped";
      ensure (View.height view = 1 && View.width view <= width) "Header wraps";
      ensure (not (contains text "v13")) "Header optimistic"));
  let state = fixture () in
  let legacy = { state.configuration with status = Applying "write" } in
  ensure (String.equal (fst (Status_bar.configuration_label legacy)) "cfg ◐APPLYING(write) last v12") "Legacy label changed";
  print_endline "All six backend progress labels preserve ACK v12 at 100/80; legacy write preserved";
  [%expect {| All six backend progress labels preserve ACK v12 at 100/80; legacy write preserved |}]

let%expect_test "unknown engine or configuration overrides retained failure progress" =
  let p = { (progress (steps_at Write_step (Step_failed "MOCK write rejected"))) with
    failure = Some (Write_step, "MOCK write rejected") } in
  let known = with_progress p in
  List.iter [ { known with engine = Engine_unknown }
            ; { known with configuration = { known.configuration with status = Unknown } } ] ~f:(fun state ->
    let text, _ = static_text state in
    ensure (contains text "? STATE UNKNOWN — last ack v12") "Retained failure hides unknown";
    ensure (not (contains text "engine remains DISARMED")) "Unknown asserts disarmed";
    ensure (not (Config_stepper.needs_spinner state)) "Disconnected failure animates";
    print_endline "Retained failure: UNKNOWN last ack v12; no assertion of DISARMED");
  [%expect {|
    Retained failure: UNKNOWN last ack v12; no assertion of DISARMED
    Retained failure: UNKNOWN last ack v12; no assertion of DISARMED
  |}]
