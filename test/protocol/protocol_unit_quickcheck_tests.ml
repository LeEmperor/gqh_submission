open! Core
open! Protocol_testbench

let%test_unit "decoder reset at every partial position and while holding a request" =
  for count = 0 to 8 do
    let cleared, publications, held, accepted, valid_after = Decoder.run_reset count in
    [%test_result: bool] cleared.valid ~expect:false;
    [%test_result: bool] cleared.fault ~expect:false;
    [%test_result: int list] cleared.fields ~expect:[0; 0; 0; 0; 0];
    [%test_result: bool list] publications
      ~expect:[false; false; false; false; false; false; false; true];
    [%test_result: int list] held.fields ~expect:Decoder.fields;
    [%test_result: bool] held.valid ~expect:true;
    [%test_result: bool] accepted ~expect:true;
    [%test_result: bool] valid_after ~expect:false
  done
;;

let%test_unit "fault and acceptance collisions use the pre-edge handshake" =
  List.iter [Decoder.Framing; Decoder.Unexpected_byte] ~f:(fun kind ->
    List.iter [false; true] ~f:(fun ready ->
      let r = Decoder.run_collision kind ready in
      let framing = match kind with Decoder.Framing -> true | Unexpected_byte -> false in
      [%test_result: bool] r.accepted ~expect:(ready && not framing);
      [%test_result: int list] r.before.fields ~expect:Decoder.fields;
      [%test_result: int list] r.after.fields ~expect:Decoder.fields;
      [%test_result: bool] r.after.fault ~expect:true;
      [%test_result: bool] r.after.valid ~expect:false;
      [%test_result: bool] r.locked.fault ~expect:true;
      [%test_result: bool] r.locked.valid ~expect:false;
      [%test_result: bool] r.recovered.fault ~expect:false;
      [%test_result: bool] r.recovered.valid ~expect:true;
      [%test_result: int list] r.recovered.fields ~expect:Decoder.fields))
;;

let%test_unit "framing error takes priority over final-byte publication" =
  let r = Decoder.run_final_error () in
  [%test_result: bool] r.valid ~expect:false;
  [%test_result: bool] r.fault ~expect:true
;;

let check_pair first second stalls drain =
  [%test_result: Sequencer.result]
    (Sequencer.run_pair first second stalls drain)
    ~expect:
      { bytes = Sequencer.bytes first @ Sequencer.bytes second
      ; acceptances = 2; completions = 2 }
;;

let%test_unit "held second response survives send stalls and final drain" =
  List.iter [0; 1; 19] ~f:(fun drain ->
    check_pair Sequencer.first Sequencer.second [0; 1; 2; 0; 7; 1; 0; 13] drain)
;;

let%test_unit "sequencer reset at each sending byte and final drain" =
  for position = 0 to 8 do
    let before, after, idle, accepted, sent, waiting, done_, next =
      Sequencer.run_reset position in
    [%test_result: bool] before.ready ~expect:false;
    [%test_result: bool] before.valid ~expect:false;
    [%test_result: bool] after.done_ ~expect:false;
    [%test_result: bool] after.valid ~expect:false;
    List.iter idle ~f:(fun (o : Sequencer.observation) ->
      [%test_result: bool] o.ready ~expect:true;
      [%test_result: bool] o.valid ~expect:false;
      [%test_result: bool] o.done_ ~expect:false);
    [%test_result: bool] accepted ~expect:true;
    [%test_result: int list] sent ~expect:(Sequencer.bytes Sequencer.second);
    [%test_result: bool] waiting.done_ ~expect:false;
    [%test_result: bool] waiting.valid ~expect:false;
    [%test_result: bool] done_.done_ ~expect:true;
    [%test_result: bool] next.done_ ~expect:false
  done
;;

let%test_unit "generated payloads and backpressure schedules preserve both responses" =
  let open Quickcheck.Generator.Let_syntax in
  let response =
    let%bind index = Int.gen_incl 0 65535 in
    let%bind id1 = Int.gen_incl 0 255 in
    let%bind id2 = Int.gen_incl 0 255 in
    let%bind action1 = Int.gen_incl 0 3 in
    let%map action2 = Int.gen_incl 0 3 in
    [index; id1; action1; id2; action2] in
  let generator =
    let%bind first = response in
    let%bind second = response in
    let%bind stalls = Quickcheck.Generator.list_with_length 8 (Int.gen_incl 0 20) in
    let%map drain = Int.gen_incl 0 30 in
    first, second, stalls, drain in
  Quickcheck.test ~trials:100 ~seed:(`Deterministic "phase-d-held-response")
    ~sexp_of:[%sexp_of: int list * int list * int list * int]
    generator ~f:(fun (first, second, stalls, drain) -> check_pair first second stalls drain)
;;
