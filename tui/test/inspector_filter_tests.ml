open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let key = Shell_tests.key
let contains = Shell_tests.contains
let backend count = History_tests.backend count
let ensure = Shell_tests.ensure
let print_view view =
  let h = Bonsai_term_test.create_handle_without_handler
      ~initial_dimensions:(View.dimensions view)
      (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
  Bonsai_test.Handle.show_into_string h

let%expect_test "filter textbox swallows q j Tab and other global keys even before redraw" =
  let exits = ref 0 in
  let handle = Shell_tests.handle ~initial:(Mock_backend.state (backend 40))
      ~exit:(fun () -> Effect.of_thunk (fun () -> incr exits)) { width = 100; height = 30 } in
  ignore (Shell_tests.screen handle : string);
  List.iter [ key (ASCII '/'); key (ASCII 'q'); key (ASCII 'j'); key Tab; key (ASCII '5'); key (ASCII '?') ]
    ~f:(Bonsai_term_test.send_event handle);
  let text = Shell_tests.screen handle in
  printf "textbox retains q/j %b; no quit %b; focus unchanged %b; no help %b\n"
    (contains text "allqj5?") (!exits = 0) (contains text "focus: Decisions")
    (not (contains text "Help · Phase 3"));
  Bonsai_term_test.send_event handle (key Escape);
  printf "Esc closes %b\n" (not (contains (Shell_tests.screen handle) "Decision filter"));
  [%expect {|
    textbox retains q/j true; no quit true; focus unchanged true; no help true
    Esc closes true
  |}]

let%expect_test "invalid filter keeps focus and valid filter applies on Enter" =
  let handle = Shell_tests.handle ~initial:(Mock_backend.state (backend 40)) { width = 120; height = 36 } in
  ignore (Shell_tests.screen handle : string);
  List.iter [ key (ASCII '/'); key (ASCII 'q'); key Enter ] ~f:(Bonsai_term_test.send_event handle);
  printf "invalid remains open %b\n" (contains (Shell_tests.screen handle) "Choose all / match");
  Bonsai_term_test.send_event handle (key ~mods:[ Ctrl ] (ASCII 'u'));
  String.iter "blocked" ~f:(fun c -> Bonsai_term_test.send_event handle (key (ASCII c)));
  Bonsai_term_test.send_event handle (key Enter);
  let text = Shell_tests.screen handle in
  printf "blocked applied %b; textbox closed %b\n" (contains text "Decisions · MOCK · blocked")
    (not (contains text "Decision filter"));
  [%expect {|
    invalid remains open true
    blocked applied true; textbox closed true
  |}]

let%expect_test "Inspector evidence stays frozen after newer decisions arrive" =
  let backend = backend 40 in
  let handle = History_tests.handle ~initial:(History_tests.log backend) () in
  ignore (History_tests.result handle : History_panel.t);
  List.iter [ key (ASCII 'g'); key Enter ] ~f:(Bonsai_term_test.send_event handle);
  let before = History_tests.result handle in
  let view d = Inspector.view ~theme ~focus:Inspector ~mode:Mock ~decision:d ~width:67 ~height:19 |> print_view in
  let frozen = view before.model.inspected in
  ensure (contains frozen "MOCK FROZEN #1") "Inspector did not capture selection";
  Bonsai_term_test.do_actions handle [ History_tests.log (History_tests.advance backend 10) ];
  let after = History_tests.result handle in
  printf "record frozen %b; rendered Inspector identical %b; contains recorded bid/ask %b\n"
    (Option.equal equal_decision before.model.inspected after.model.inspected)
    (String.equal frozen (view after.model.inspected)) (contains frozen "recorded bid" && contains frozen "ask");
  [%expect {| record frozen true; rendered Inspector identical true; contains recorded bid/ask true |}]

let%expect_test "Inspector labels software reconstruction explicitly and shows declared checks" =
  let decision = (Mock_backend.state (backend 1)).latest_decision |> Option.value_exn in
  let reconstructed = { decision with predicate_result = None } in
  Bonsai_term_test.print_view (Inspector.view ~theme ~focus:Inspector ~mode:Mock ~decision:(Some reconstructed) ~width:67 ~height:15);
  [%expect {|
    ╭ Inspector · MOCK FROZEN ────────────────────────────────────────╮
    │ MOCK FROZEN #1 · 13:37:00.250                                   │
    │ run demo-03 · build m01                                         │
    │ cfg v12 · slot 0 · snapshot #1                                  │
    │ recorded bid 1004 t / 35 u · ask 1005 t / 35 u                  │
    │ ask_px 1005 ≤ maximum_price 1005 = true                         │
    │ (reconstructed) predicate result                                │
    │ candidate BUY 1 @1005                                           │
    │ bounds qty [1, 5] u · price [1001, 1005] t                      │
    │ admission ✓ accepted                                            │
    │ receipt ✓ received 13:37:00.252                                 │
    │                                                                 │
    │                                                                 │
    │                                                                 │
    ╰─────────────────────────────────────────────────────────────────╯
    |}]

let%expect_test "decision rows show correlated status and receipt without implying admission is receipt" =
  let decisions = Decision_buffer.to_list (History_tests.log (backend 200)) in
  let find f = List.find_exn decisions ~f in
  let admitted = find (fun d -> equal_decision_outcome d.outcome Admitted_result && Option.is_none d.receipt_at) in
  let received = find (fun d -> Option.is_some d.receipt_at) in
  let blocked = find (fun d -> match d.outcome with Blocked_result _ -> true | _ -> false) in
  let no_signal = find (fun d -> equal_decision_outcome d.outcome No_signal_result) in
  List.iter [ received; admitted; blocked; no_signal ] ~f:(fun d ->
    print_endline (Decision_row.text ~width:48 d));
  print_endline (Decision_row.text ~width:39 received);
  [%expect {|
    #1    13:37:00.250 MATCH BUY 1 @1005 ✓ADM ✓RCV
    #3    13:37:00.750 MATCH BUY 1 @1003 ✓ADM
    #29   13:37:07.250 MATCH BUY 1 @1000 ✗BLK price
    #4    13:37:01.000 ·     no signal
    #1    13:37:00 MATCH BUY 1 @1005 ✓A ✓R
    |}]

let%expect_test "fixed admission checks reject candidate bounds disarmed and invalid state" =
  let candidate = (Mock_backend.state (backend 1)).latest_decision |> Option.value_exn
    |> fun d -> Option.value_exn d.candidate in
  let check ?(engine = Armed) ?(valid = true) candidate =
    match Admission.check ~engine ~book_valid:valid ~bounds:Admission.mock_bounds candidate with
    | Blocked_result reason -> print_endline reason
    | Admitted_result -> print_endline "admitted"
    | No_signal_result -> failwith "Admission returned no-signal" in
  check candidate;
  check { candidate with quantity_units = 0 };
  check { candidate with quantity_units = 6 };
  check { candidate with price_ticks = 1000 };
  check ~engine:Disarmed candidate;
  check ~valid:false candidate;
  [%expect {|
    admitted
    order qty 0 u outside [1, 5] u
    order qty 6 u outside [1, 5] u
    price 1000 t outside [1001, 1005] t
    engine disarmed / unavailable
    book invalid
  |}]

let%expect_test "Esc followed by Tab restores global focus routing without a redraw" =
  let handle = Shell_tests.handle { width = 100; height = 30 } in
  ignore (Shell_tests.screen handle : string);
  List.iter [ key (ASCII '/'); key Escape; key Tab ] ~f:(Bonsai_term_test.send_event handle);
  (* In Demo, Tab leaves Decisions for the panel below it: Metrics. *)
  printf "filter closed %b; Tab moved to Metrics %b\n"
    (not (contains (Shell_tests.screen handle) "Decision filter"))
    (contains (Shell_tests.screen handle) "focus: Metrics");
  [%expect {| filter closed true; Tab moved to Metrics true |}]

let%expect_test "minimum-size Inspector renders all required frozen fields" =
  let backend = backend 40 in
  (* Decide gives the Inspector two thirds of the right column: room for every field. *)
  let handle = Shell_tests.handle ~initial:(Mock_backend.state backend) ~preset:Decide
      { width = 100; height = 30 } in
  ignore (Shell_tests.screen handle : string);
  List.iter [ key (ASCII '3'); key (ASCII 'g'); key Enter ] ~f:(Bonsai_term_test.send_event handle);
  let before = Shell_tests.screen handle in
  List.iter [ "MOCK FROZEN #1"; "run demo-03"; "build m01"; "cfg v12"; "slot 0"; "snapshot #1"
            ; "recorded bid"; "ask_px 1005 ≤ maximum_price 1005 = true"; "candidate BUY 1 @1005"
            ; "admission ✓ accepted"; "receipt ✓ received 13:37:00.252" ]
    ~f:(fun field -> ensure (contains before field) ("Inspector missing " ^ field));
  Bonsai_term_test.do_actions handle [ Mock_backend.state (History_tests.advance backend 10) ];
  let after = Shell_tests.screen handle in
  printf "all frozen fields visible %b; newer snapshot did not replace Inspector %b\n"
    (not (contains before "VALUE TOO WIDE")) (contains after "snapshot #1" && contains after "MOCK FROZEN #1");
  [%expect {| all frozen fields visible true; newer snapshot did not replace Inspector true |}]
