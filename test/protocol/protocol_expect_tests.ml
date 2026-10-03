open! Core
open! Protocol_testbench

let%expect_test "two accepted responses and exactly two completion events" =
  print_s [%sexp
    (Sequencer.run_pair Sequencer.first Sequencer.second [0; 1; 2; 0; 7; 1; 0; 13] 19
     : Sequencer.result)];
  [%expect {|
    ((bytes (171 205 34 2 17 1 0 0 19 87 17 1 34 0 0 0)) (acceptances 2)
     (completions 2))
    |}]
;;

let%expect_test "request acceptance colliding with faults" =
  List.iter [Decoder.Framing; Decoder.Unexpected_byte] ~f:(fun kind ->
    let r = Decoder.run_collision kind true in
    print_s [%sexp
      (kind : Decoder.collision), (r.accepted : bool),
      (r.before : Decoder.observation), (r.after : Decoder.observation)]);
  [%expect {|
    (Framing false
     ((valid false) (fault false) (fields (43981 34 4660 17 65244)))
     ((valid false) (fault true) (fields (43981 34 4660 17 65244))))
    (Unexpected_byte true
     ((valid true) (fault false) (fields (43981 34 4660 17 65244)))
     ((valid false) (fault true) (fields (43981 34 4660 17 65244))))
    |}]
;;
