open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Tickweave_tui
open Model_adapter

let theme = Theme.create No_color
let key ?(mods = []) key = Event.Key_press { key; mods }
let advance backend count = List.fold (List.init count ~f:Fn.id) ~init:backend
    ~f:(fun backend _ -> Mock_backend.advance backend)
let backend count = Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4.
    |> Or_error.ok_exn |> fun backend -> advance backend count
let log backend = (Mock_backend.state backend).decisions
let handle ?(initial = log (backend 40)) () =
  Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 52; height = 17 }
    ~to_view_with_handler:(fun (history, _) -> ~view:history.History_panel.view, ~handler:(fun event -> let%map.Effect _ = history.handler event in ()))
    ~handle_incoming:(fun (_, set) log -> set log)
    (fun ~dimensions (local_ graph) ->
      let log, set = Bonsai.state initial graph in
      let history = History_panel.component ~theme:(Bonsai.return theme) ~focus:(Bonsai.return Keymap.Decisions)
          ~log ~dimensions graph in
      let%arr history and set in history, set)
let result handle =
  ignore (Bonsai_test.Handle.show_into_string handle : string);
  fst (Bonsai_term_test.last_result handle)
let ids decisions = List.map decisions ~f:History_state.key
let selection model = Option.map model.History_state.selected ~f:History_state.key
let ensure condition message = if not condition then failwith message

let%expect_test "new arrival while scrolled up keeps selection scroll and visible rows" =
  let backend = backend 40 in
  let handle = handle ~initial:(log backend) () in
  ignore (result handle : History_panel.t);
  Bonsai_term_test.send_event handle (key (ASCII 'g'));
  let before = result handle in
  ensure (before.offset = 0 && Option.is_some before.model.selected) "g did not select the top";
  Bonsai_term_test.do_actions handle [ log (advance backend 3) ];
  let after = result handle in
  printf "selection stable %b; scroll stable %b; rows stable %b; new %d\n"
    ([%equal: (string * int option) option] (selection before.model) (selection after.model))
    (before.offset = after.offset) ([%equal: (string * int option) list] (ids before.visible) (ids after.visible))
    after.model.unseen;
  [%expect {| selection stable true; scroll stable true; rows stable true; new 3 |}]

let%expect_test "selection survives removal from visible window and backend ring eviction" =
  let backend = backend 40 in
  let handle = handle ~initial:(log backend) () in
  ignore (result handle : History_panel.t);
  Bonsai_term_test.send_event handle (key (ASCII 'g'));
  let before = result handle in
  for _ = 1 to 20 do
    Bonsai_term_test.send_event handle (Event.Mouse { kind = Scroll `Down; position = { x = 4; y = 4 }; mods = [] });
    ignore (result handle : History_panel.t)
  done;
  let outside = result handle in
  let selected = Option.value_exn outside.model.selected in
  ensure (not (List.exists outside.visible ~f:(History_state.same_key selected))) "Selected row is still visible";
  let newest = log (advance backend 10_020) in
  Bonsai_term_test.do_actions handle [ newest ];
  let after = result handle in
  printf "outside window %b; evicted from live ring %b; ID and record preserved %b\n"
    (not (List.exists after.visible ~f:(History_state.same_key selected)))
    (not (List.exists (Decision_buffer.to_list newest) ~f:(History_state.same_key selected)))
    (Option.equal equal_decision before.model.selected after.model.selected);
  [%expect {| outside window true; evicted from live ring true; ID and record preserved true |}]

let%expect_test "paused history freezes while counting every arrival then resumes at tail" =
  let backend = backend 40 in
  let handle = handle ~initial:(log backend) () in
  ignore (result handle : History_panel.t);
  Bonsai_term_test.send_event handle (key (ASCII ' '));
  let before = result handle in
  Bonsai_term_test.do_actions handle [ log (advance backend 5) ];
  let paused = result handle in
  printf "paused %b; rows frozen %b; offset frozen %b; arrivals %d\n"
    paused.model.paused ([%equal: (string * int option) list] (ids before.visible) (ids paused.visible))
    (before.offset = paused.offset) paused.model.unseen;
  Bonsai_term_test.send_event handle (key (ASCII ' '));
  let resumed = result handle in
  printf "resumed %b; tail #%s; arrivals reset %d\n" (not resumed.model.paused)
    (Option.value_exn (List.last_exn resumed.visible).identity.decision_id |> Int.to_string)
    resumed.model.unseen;
  [%expect {|
    paused true; rows frozen true; offset frozen true; arrivals 5
    resumed true; tail #45; arrivals reset 0
  |}]

let%expect_test "less keys and a selected tail do not permit arrivals to move the view" =
  let backend = backend 40 in
  let handle = handle ~initial:(log backend) () in
  ignore (result handle : History_panel.t);
  Bonsai_term_test.send_event handle (key ~mods:[ Ctrl ] (ASCII 'u'));
  let up = result handle in
  Bonsai_term_test.send_event handle (key ~mods:[ Ctrl ] (ASCII 'd'));
  let down = result handle in
  printf "Ctrl-u moves up %b; Ctrl-d moves down %b\n" (up.offset < 26) (down.offset > up.offset);
  Bonsai_term_test.send_event handle (key (ASCII 'G'));
  ignore (result handle : History_panel.t);
  Bonsai_term_test.send_event handle (key (ASCII 'j'));
  let before = result handle in
  Bonsai_term_test.do_actions handle [ log (advance backend 2) ];
  let after = result handle in
  printf "selected tail frozen %b; new %d\n"
    (before.offset = after.offset && Option.equal equal_decision before.model.selected after.model.selected
      && [%equal: (string * int option) list] (ids before.visible) (ids after.visible)) after.model.unseen;
  Bonsai_term_test.send_event handle (key (ASCII 'G'));
  let live = result handle in
  printf "G returns live %b; latest ID %d\n" (live.model.follow && Option.is_none live.model.selected)
    (Option.value_exn (List.last_exn live.visible).identity.decision_id);
  [%expect {|
    Ctrl-u moves up true; Ctrl-d moves down true
    selected tail frozen true; new 2
    G returns live true; latest ID 42
  |}]

let%expect_test "only visible rows are rendered even at full ring capacity" =
  let handle = handle ~initial:(log (backend 10_005)) () in
  let result = result handle in
  printf "ring %d; first %d; visible %d; latest %d\n"
    (Map.length result.model.live.records) result.model.live.first_sequence (List.length result.visible)
    (Option.value_exn (List.last_exn result.visible).identity.decision_id);
  [%expect {| ring 10000; first 5; visible 14; latest 10005 |}]

let%expect_test "all filters preserve decision IDs and distinguish receipt from admission" =
  let log = log (backend 200) in
  let model = History_state.receive History_state.empty log in
  List.iter History_state.filters ~f:(fun (name, filter) ->
    let rows = History_state.rows { model with filter } in
    printf "%s: %d\n" name (Array.length rows));
  [%expect {|
    all: 200
    match: 136
    admitted: 130
    blocked: 6
    received: 83
    errors: 0
  |}]

let%expect_test "filter hiding a selected decision preserves its ID and inspection" =
  let handle = handle () in
  ignore (result handle : History_panel.t);
  List.iter [ key (ASCII 'g'); key (ASCII '/'); key ~mods:[ Ctrl ] (ASCII 'u') ]
    ~f:(Bonsai_term_test.send_event handle);
  String.iter "blocked" ~f:(fun c -> Bonsai_term_test.send_event handle (key (ASCII c)));
  List.iter [ key Enter; key Enter ] ~f:(Bonsai_term_test.send_event handle);
  let result = result handle in
  let selected = Option.value_exn result.model.selected in
  printf "selected #1 %b; filtered out %b; inspection retained %b\n"
    (Option.equal Int.equal selected.identity.decision_id (Some 1))
    (not (List.exists result.visible ~f:(History_state.same_key selected)))
    (Option.equal equal_decision result.model.selected result.model.inspected);
  [%expect {| selected #1 true; filtered out true; inspection retained true |}]

let%expect_test "paused arrival count excludes earlier arrivals while scrolled up" =
  let backend = backend 40 in
  let model = History_state.receive History_state.empty (log backend)
    |> fun t -> History_state.navigate t ~height:14 ~offset:26 First
    |> fun t -> History_state.receive t (log (advance backend 4))
    |> History_state.pause
    |> fun t -> History_state.receive t (log (advance backend 7)) in
  printf "unseen %d; while paused %d\n" model.unseen model.paused_arrivals;
  [%expect {| unseen 7; while paused 3 |}]
