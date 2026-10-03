open! Core
open Bonsai_term
open Bonsai_test
open Tickweave_tui
open Model_adapter
module Effect = Bonsai_term.Effect

let commands = ref []
module Backend = struct
  type t = Mock_backend.t
  let state = Mock_backend.state
  let next = Mock_backend.next
  let handle_command backend command =
    commands := command :: !commands;
    Mock_backend.handle_command backend command
end
let contains text part = String.is_substring text ~substring:part
let ensure condition reason = if not condition then failwith reason
let key key = Event.Key_press { key; mods = [] }
(* The live app releases one view per 60 Hz frame, so a frame passes before each read. *)
let screen handle =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.017);
  Handle.show_into_string handle
let send handle keys = List.iter keys ~f:(fun k -> Bonsai_term_test.send_event handle (key k))
let text handle value = String.iter value ~f:(fun c -> send handle [ ASCII c ])
let handle scenario =
  commands := [];
  let _scheduler = Async.Scheduler.t () in
  let exits = ref 0 in
  let backend = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
  let handle = Bonsai_term_test.create_handle ~initial_dimensions:{ width = 120; height = 36 }
      (App.live ~initial_preset:Demo (module Backend) ~theme:(Theme.create No_color) ~backend
         ~exit:(fun () -> Effect.of_thunk (fun () -> incr exits))) in
  ignore (screen handle : string);
  handle, exits
let tick handle =
  Handle.advance_clock_by handle (Time_ns.Span.of_sec 0.25);
  Handle.recompute_view_until_stable handle;
  Async.Scheduler.External.run_cycles_until_determined
    (Async.Scheduler.yield_until_no_jobs_remain ());
  Handle.recompute_view_until_stable handle
let apply handle =
  send handle [ ASCII 'c' ]; ignore (screen handle : string);
  send handle [ ASCII 'A' ]; ignore (screen handle : string);
  text handle "apply"; send handle [ Enter; Enter ]; ignore (screen handle : string)

let%expect_test "app captures queued modal keys and restores focus after cancel" =
  let handle, exits = handle Mock_backend.Connected_disarmed in
  send handle [ ASCII 'c'; Enter; ASCII 'q'; ASCII 'j'; Tab ];
  let view = screen handle in
  ensure (contains view "Configuration review") "Modal did not open";
  ensure (!exits = 0 && List.is_empty !commands) "Editing leaked quit or a command";
  send handle [ Escape; Escape ];
  ensure (contains (screen handle) "focus: Market") "Cancel changed dashboard focus";
  ensure (!exits = 0 && List.is_empty !commands) "Cancel performed an action";
  print_endline "Queued c/Enter/q/j/Tab captured; cancel restores Market; zero commands";
  [%expect {| Queued c/Enter/q/j/Tab captured; cancel restores Market; zero commands |}]

let%expect_test "live apply commits ACK only through backend and freezes old Inspector" =
  let handle, _ = handle Mock_backend.Update_ok in
  tick handle;
  send handle [ ASCII '3'; ASCII 'k'; Enter ];
  ensure (contains (screen handle) "cfg v12") "Old decision missing cfg v12";
  apply handle;
  ensure (List.length !commands = 1) "Duplicate confirmation sent duplicate command";
  let pending = screen handle in
  ensure (contains pending "APPLYING" && contains pending "ACK v12") "Header lost old ACK";
  ensure (contains pending "○ ACK v13" && not (contains pending "✓ ACK v13")) "Optimistic ACK";
  for _ = 1 to 12 do tick handle done;
  ensure (contains (screen handle) "ACK v13") "Backend ACK not displayed";
  send handle [ Escape ];
  ensure (contains (screen handle) "cfg v12") "New configuration mutated frozen evidence";
  tick handle; (* k selects the penultimate row; ensure two post-ACK records exist. *)
  send handle [ ASCII '3'; ASCII 'G'; ASCII 'k'; Enter ];
  ensure (contains (screen handle) "cfg v13") "New decision Inspector missing acknowledged cfg";
  printf "Commands: %d; pending ACK v12; backend ACK v13; old Inspector v12; new Inspector v13\n"
    (List.length !commands);
  [%expect {| Commands: 1; pending ACK v12; backend ACK v13; old Inspector v12; new Inspector v13 |}]

let%expect_test "live lost activation stays unknown until an explicit status read" =
  let handle, _ = handle Mock_backend.Lost_at_activate in
  apply handle;
  for _ = 1 to 12 do tick handle done;
  let unknown = screen handle in
  ensure (contains unknown "STATE UNKNOWN" && contains unknown "last ack v12") "Unknown state not explicit";
  ensure (not (contains unknown "v13") && not (contains unknown "disabled")) "Unknown asserted a final state";
  send handle [ ASCII 'A' ]; text handle "apply"; send handle [ Enter ];
  ignore (screen handle : string);
  ensure (List.length !commands = 1) "Apply allowed during unknown";
  send handle [ ASCII 'r' ]; ignore (screen handle : string);
  ensure (List.length !commands = 2 && equal_command (List.hd_exn !commands) Reconcile) "Status read missing";
  ensure (contains (screen handle) "STATE UNKNOWN") "Reconcile guessed state before reply";
  tick handle; tick handle;
  let reconciled = screen handle in
  ensure (contains reconciled "DISARMED" && not (contains reconciled "v13")) "Status read fabricated activation";
  print_endline "UNKNOWN last ack v12; Apply rejected; Reconcile reads backend; reply confirms DISARMED v12";
  [%expect {| UNKNOWN last ack v12; Apply rejected; Reconcile reads backend; reply confirms DISARMED v12 |}]

let%expect_test "modal remains within both supported terminal sizes" =
  let handle, _ = handle Mock_backend.Connected_disarmed in
  send handle [ ASCII 'c' ];
  List.iter [ 120, 36; 100, 30 ] ~f:(fun (width, height) ->
    Bonsai_term_test.set_dimensions handle { width; height };
    let view = screen handle in
    ensure (Dimensions.equal (Bonsai_term_test.last_dimensions handle) { width; height }) "Modal overflow";
    List.iter [ "Configuration review"; "maximum_price"; "quantity"; "engine reachable"; "CONFIGURATION_ONLY" ]
      ~f:(fun label -> ensure (contains view label) ("Modal clipped " ^ label));
    printf "%dx%d: review table, class and validation visible\n" width height);
  [%expect {|
    120x36: review table, class and validation visible
    100x30: review table, class and validation visible
  |}]

(* Reproduces a poll begun before Apply and delivered after command acceptance. *)
module Delayed_backend = struct
  type t = Mock_backend.t
  let pending = ref None
  let state = Mock_backend.state
  let handle_command = Mock_backend.handle_command
  let next backend =
    let result = Async.Ivar.create () in
    pending := Some (result, backend);
    Async.Ivar.read result
end
let%expect_test "late immutable poll cannot overwrite an accepted Apply command" =
  let _scheduler = Async.Scheduler.t () in
  let backend = Mock_backend.create ~scenario:Mock_backend.Update_ok ~seed:42 ~rate_hz:4. |> Or_error.ok_exn in
  let handle = Bonsai_term_test.create_handle ~initial_dimensions:{ width = 120; height = 36 }
      (App.live ~initial_preset:Demo (module Delayed_backend) ~theme:(Theme.create No_color) ~backend
         ~exit:(fun () -> Effect.Ignore)) in
  ignore (screen handle : string);
  tick handle;
  let pending, before_command = Option.value_exn !(Delayed_backend.pending) in
  apply handle;
  ensure (contains (screen handle) "APPLYING 1/6") "Command not accepted";
  Async.Ivar.fill_exn pending (Mock_backend.advance before_command);
  Async.Scheduler.External.run_cycles_until_determined
    (Async.Scheduler.yield_until_no_jobs_remain ());
  let text = screen handle in
  ensure (contains text "APPLYING 1/6" && contains text "ACK v12") "Old poll rolled back Apply";
  print_endline "Poll started before Apply; late result discarded; accepted lifecycle and ACK v12 retained";
  [%expect {| Poll started before Apply; late result discarded; accepted lifecycle and ACK v12 retained |}]
