open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect

let theme = Theme.create No_color
let state scenario =
  Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn |> Mock_backend.state
let contains text substring = String.is_substring text ~substring
let ensure condition message = if not condition then failwith message
let key key = Event.Key_press { key; mods = [] }

let app ?(initial = state Enabled) ?(preset = Ui_types.Demo) dimensions =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
    ~to_view_with_handler:fst
    ~handle_incoming:(fun (_, inject) state -> inject state)
    (fun ~dimensions (local_ graph) ->
      let state, inject = Bonsai.state initial graph in
      let ~view, ~handler = App.component ~initial_preset:preset ~theme ~state ~clock:(Bonsai.return "13:37:02.417")
          ~exit:(fun () -> Effect.Ignore) ~dimensions graph in
      let%arr view and handler and inject in
      ((~view, ~handler), inject))

let text_of view =
  Handle.show_into_string (Bonsai_term_test.create_handle_without_handler
    ~initial_dimensions:{ width = Int.max 1 (View.width view); height = Int.max 1 (View.height view) }
    (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view))
let stepper_text state =
  text_of (Config_stepper.view ~theme ~state ~spinner:(View.text "◐") ~width:80)

(* The stepper's last line: the ACK row, or the unknown banner that replaces it. *)
let ack_row state =
  List.find_exn (String.split_lines (stepper_text state)) ~f:(fun line ->
    contains line "ACK" || contains line "UNKNOWN")
  |> String.substr_replace_all ~pattern:"│" ~with_:"" |> String.strip

let steps_through last = List.map apply_steps ~f:(fun step ->
  step, if step_number step <= step_number last then Step_done else Step_pending)
let progress ?(acknowledged_version = None) steps =
  { proposal_id = "mock-proposal-13"; steps; acknowledged_version
  ; failure = None; state_unknown = false; reconciliation = Not_requested }

(* Catches the stepper reading "✓ ACK v12" before Apply: the active version is
   already in the modal header, and a green tick means the backend acknowledged. *)
let%expect_test "stepper shows the pending target until the backend ACKs it" =
  let idle = state Connected_disarmed in
  let in_flight = { idle with config_apply = Some (progress (steps_through Disable_step))
                  ; configuration = { idle.configuration with status = Applying "4/6" } } in
  let acknowledged = { idle with
    config_apply = Some (progress ~acknowledged_version:(Some 13) (steps_through Activate_step))
  ; configuration = { idle.configuration with status = Active_acknowledged 13
                    ; last_acknowledged_version = Some 13 } } in
  let unknown = { in_flight with connected = false; engine = Engine_unknown
    ; configuration = { idle.configuration with status = Unknown }
    ; config_apply = Some { (progress (steps_through Write_step)) with state_unknown = true } } in
  List.iter [ "before Apply", idle; "in flight", in_flight; "acknowledged", acknowledged
            ; "unknown", unknown ] ~f:(fun (label, state) ->
    printf "%-13s %s\n" label (ack_row state));
  [%expect {|
    before Apply  ○ ACK v13 · pending
    in flight     ○ ACK v13 · pending
    acknowledged  ✓ ACK v13
    unknown       ? STATE UNKNOWN — last ack v12
    |}]

(* Catches the modal showing the active version in two places, or the tick before Apply. *)
let%expect_test "modal header holds the active version and the stepper the target" =
  (* Configure puts the summary above the modal, where it stays visible. *)
  let handle = app ~initial:(state Connected_disarmed) ~preset:Configure { width = 120; height = 36 } in
  Bonsai_term_test.send_event handle (key (ASCII 'c'));
  let screen = Handle.show_into_string handle in
  ensure (contains screen "last ACK active v12") "Header lost the active version";
  ensure (contains screen "○ ACK v13 · pending") "Stepper lost the pending target";
  (* The dashboard summary behind the modal is the one legitimate "✓ ACK v12". *)
  let ticks = List.count (String.split_lines screen) ~f:(fun line -> contains line "✓ ACK v12") in
  ensure (ticks = 1) "Stepper ticks the active version before Apply";
  print_endline "header: active v12; stepper: ○ ACK v13 · pending; only the dashboard says ✓ ACK v12";
  [%expect {| header: active v12; stepper: ○ ACK v13 · pending; only the dashboard says ✓ ACK v12 |}]

let panel_rows screen ~title =
  String.split_lines screen
  |> List.drop_while ~f:(fun line -> not (contains line title))
  |> Fn.flip List.take 10

(* Catches the dashboard Configuration frame staying empty, a line cut off by the
   Inspector's share of the column, and unlabelled mock data. Spare rows may add apply
   progress, preflight and the proposal between the status and the parameters, so the
   four essential lines are checked in order, not at fixed offsets. *)
let%expect_test "dashboard Configuration panel shows every line at both supported sizes" =
  List.iter [ { Dimensions.width = 120; height = 36 }; { width = 100; height = 30 } ]
    ~f:(fun dimensions ->
      let screen = Handle.show_into_string (app dimensions) in
      let rows = List.tl_exn (panel_rows screen ~title:"Configuration · MOCK") in
      let find wanted = List.findi rows ~f:(fun _ row -> contains row wanted)
                        |> Option.value_exn ~message:("Panel row missing: " ^ wanted) in
      let index, status = find "✓ ACK v12 · engine ● ARMED" in
      let price_index, price = find "maximum_price" in
      let quantity_index, quantity = find "quantity" in
      let hint_index, _ = find "c review / apply" in
      ensure (index < price_index && price_index < quantity_index && quantity_index < hint_index)
        "Panel lines out of order";
      ignore (status : string);
      ensure (contains price "1005 t" && contains price "[995 " && contains price " 1010]" && contains price "●")
        "maximum_price lost its value, unit or range bar";
      ensure (contains quantity "1 u" && contains quantity "[1 " && contains quantity " 5]" && contains quantity "●")
        "quantity lost its value, unit or range bar";
      printf "%dx%d: version, ACK, engine, both parameters with range bars, and hint fit\n"
        dimensions.width dimensions.height);
  [%expect {|
    120x36: version, ACK, engine, both parameters with range bars, and hint fit
    100x30: version, ACK, engine, both parameters with range bars, and hint fit
    |}]

(* Catches a blank Inspector before any decision is selected. *)
let%expect_test "Inspector placeholder names the mode" =
  let screen = Handle.show_into_string (app { width = 120; height = 36 }) in
  ensure (contains screen "Select a decision and press Enter to inspect · MOCK") "Placeholder missing";
  print_endline "Inspector placeholder: MOCK";
  [%expect {| Inspector placeholder: MOCK |}]

let summary ?(width = 52) ?height state =
  Config_review.view ~theme ~focus:Market ~state ~width
    ~height:(Option.value height ~default:(Config_review.height state))

(* Catches a summary that invents a value, an ACK or an engine state it was never told. *)
let%expect_test "dashboard Configuration panel renders what is unknown as ?" =
  let enabled = state Enabled in
  let undeclared = { enabled with configuration =
    { enabled.configuration with parameters = [ "slippage", 7 ] } } in
  let silent = { enabled with configuration = { enabled.configuration with parameters = [] } } in
  List.iter [ "connection lost", state Connection_lost; "undeclared parameter", undeclared
            ; "no parameters reported", silent ] ~f:(fun (label, state) ->
    print_endline label;
    Bonsai_term_test.print_view (summary state);
    ensure (not (String.equal label "connection lost") || not (contains (text_of (summary state)) "✓"))
      "Unknown looks acknowledged");
  [%expect {|
    connection lost
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ? UNKNOWN · last ACK v12 · engine ? UNKNOWN      │
    │ maximum_price 1005 t [995 ━━━━━━━━━━●───── 1010] │
    │ quantity         1 u [1 ●──────────────────── 5] │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    undeclared parameter
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    │ slippage 7 ? range ?                             │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    no parameters reported
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    │ parameters unknown                               │
    │ c review / apply                                 │
    ╰──────────────────────────────────────────────────╯
    |}]

(* Catches overflow at small heights, and the status line being the first row lost. *)
let%expect_test "dashboard Configuration panel truncates and never overflows" =
  let enabled = state Enabled in
  ensure (Config_review.height enabled = 6) "Height does not follow the content";
  List.iter [ 0; 1; 2; 3; 4; 5; 6; 9 ] ~f:(fun height ->
    let view = summary ~height enabled in
    ensure (View.height view = height && View.width view = 52) "Panel overflowed its cell";
    printf "height %d fits\n" height);
  Bonsai_term_test.print_view (summary ~height:3 enabled);
  [%expect {|
    height 0 fits
    height 1 fits
    height 2 fits
    height 3 fits
    height 4 fits
    height 5 fits
    height 6 fits
    height 9 fits
    ╭ Configuration · MOCK ────────────────────────────╮
    │ ✓ ACK v12 · engine ● ARMED                       │
    ╰──────────────────────────────────────────────────╯
    |}]

(* Catches a hard-coded MOCK label: the mode must come from the state. *)
let%expect_test "Configuration title and Inspector placeholder follow the mode" =
  List.iter [ Mock; Simulation; Hardware ] ~f:(fun mode ->
    let state = { (state Enabled) with mode } in
    let line_with view part = List.find_exn (String.split_lines (text_of view)) ~f:(fun line -> contains line part) in
    let name = Status_bar.mode_name mode in
    let inspector = Inspector.view ~theme ~focus:Market ~mode ~decision:None ~width:60 ~height:3 in
    ensure (contains (line_with (summary state) "Configuration") ("· " ^ name)) "Title mode wrong";
    let placeholder = line_with inspector "inspect" in
    ensure (contains placeholder ("inspect · " ^ name)) "Placeholder mode wrong";
    printf "%s | %s\n" name (String.strip (String.substr_replace_all placeholder ~pattern:"│" ~with_:"")));
  [%expect {|
    MOCK | Select a decision and press Enter to inspect · MOCK
    SIM | Select a decision and press Enter to inspect · SIM
    HW | Select a decision and press Enter to inspect · HW
    |}]
