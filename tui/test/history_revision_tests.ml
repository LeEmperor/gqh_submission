open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let ensure = Shell_tests.ensure

let%expect_test "same-sized run replacement refreshes live history" =
  let initial = History_tests.log (History_tests.backend 40) in
  let handle = History_tests.handle ~initial () in
  ignore (History_tests.result handle : History_panel.t);
  let identity (identity : identity) = { identity with run_id = "next-run" } in
  let records = Map.map initial.records ~f:(fun (d : decision) ->
    { d with identity = identity d.identity
           ; inputs = { d.inputs with identity = identity d.inputs.identity }
           ; candidate = Option.map d.candidate ~f:(fun (c : candidate) -> { c with identity = identity c.identity }) }) in
  Bonsai_term_test.do_actions handle [ { initial with records } ];
  let result = History_tests.result handle in
  printf "new run visible %b\n" (List.for_all result.visible ~f:(fun (d : decision) -> String.equal d.identity.run_id "next-run"));
  [%expect {| new run visible true |}]

let%expect_test "receipt evidence updates without a new row refresh live history" =
  let initial = History_tests.log (History_tests.backend 40) in
  let handle = History_tests.handle ~initial () in
  ignore (History_tests.result handle : History_panel.t);
  let sequence, decision = Map.to_alist initial.records |> List.rev
    |> List.find_exn ~f:(fun (_, d) -> equal_decision_outcome d.outcome Admitted_result) in
  let receipt_at = if Option.is_some decision.receipt_at then None else Some decision.occurred_at in
  let decision = { decision with receipt_at } in
  let records = Map.set initial.records ~key:sequence ~data:decision in
  Bonsai_term_test.do_actions handle [ { initial with records } ];
  let result = History_tests.result handle in
  let recorded = Map.find_exn result.model.live.records sequence in
  printf "same-sequence receipt refreshed %b\n" (equal_decision recorded decision);
  [%expect {| same-sequence receipt refreshed true |}]

(* The highlight is a fade against the shared clock, so it is stamped at the arrival and kept:
   it is not cleared by a repaint. Frozen arrivals still only count. *)
let%expect_test "live arrivals are stamped for the fade and frozen arrivals only count" =
  let backend = History_tests.backend 40 in
  let handle = History_tests.handle ~initial:(History_tests.log backend) () in
  Bonsai_test.Handle.recompute_view_until_stable handle;
  Bonsai_term_test.do_actions handle [ History_tests.log (History_tests.advance backend 1) ];
  Bonsai_test.Handle.recompute_view handle;
  let first = fst (Bonsai_term_test.last_result handle) in
  Bonsai_test.Handle.recompute_view handle;
  let second = fst (Bonsai_term_test.last_result handle) in
  printf "arrival frame highlights %d, stamped %b; next frame highlights %d\n"
    (List.length first.model.fresh_keys) (Option.is_some first.model.fresh_at)
    (List.length second.model.fresh_keys);
  Bonsai_term_test.send_event handle (History_tests.key (ASCII 'g'));
  ignore (History_tests.result handle : History_panel.t);
  Bonsai_term_test.do_actions handle [ History_tests.log (History_tests.advance backend 3) ];
  let frozen = History_tests.result handle in
  printf "frozen frame highlights %d; new count %d\n" (List.length frozen.model.fresh_keys) frozen.model.unseen;
  [%expect {|
    arrival frame highlights 1, stamped true; next frame highlights 1
    frozen frame highlights 0; new count 2
  |}]

(* The row's background is interpolated, never switched: each step of the fade is a different
   colour, and a faded row is the row as it would be drawn with no highlight at all. *)
let%expect_test "a new row's highlight fades through intermediate colours to the plain row" =
  let theme = Theme.create Truecolor in
  let decision = List.hd_exn (Decision_buffer.to_list (History_tests.log (History_tests.backend 5))) in
  let render fresh =
    let view = Decision_row.view ~fresh ~theme ~width:60 ~selected:false decision in
    let handle = Bonsai_term_test.create_handle_without_handler ~capability:Ansi
        ~initial_dimensions:{ width = 60; height = 1 }
        (fun ~dimensions:_ (local_ _graph) -> Bonsai.return view) in
    Bonsai_test.Handle.show_into_string handle in
  let steps = List.map [ 1.; 0.75; 0.5; 0.25 ] ~f:render in
  let plain = render 0. in
  ensure (List.for_all steps ~f:(fun step -> not (String.equal step plain))) "A step is not highlighted";
  ensure (List.length (List.dedup_and_sort steps ~compare:String.compare) = List.length steps)
    "Two steps of the fade look the same";
  ensure (String.equal (render (Decision_row.fresh_intensity ~now:(Time_ns.add Time_ns.epoch Decision_row.fresh_fade) ~at:Time_ns.epoch)) plain)
    "A finished fade differs from the plain row";
  print_endline "four distinct fade steps; the finished fade is the plain row";
  [%expect {| four distinct fade steps; the finished fade is the plain row |}]
