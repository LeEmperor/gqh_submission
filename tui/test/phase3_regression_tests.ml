open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

let backend scenario = Mock_backend.create ~scenario ~seed:42 ~rate_hz:4. |> Or_error.ok_exn

let%expect_test "block fixture rejects the candidate quantity, never liquidity" =
  let state = Mock_backend.advance (backend Blocked) |> Mock_backend.state in
  let reason = (List.hd_exn state.rules).last_block_reason |> Option.value_exn in
  printf "candidate quantity bound: %b\n" (String.is_prefix reason ~prefix:"order qty");
  [%expect {| candidate quantity bound: true |}]

let%expect_test "decisions panel contains an evaluation after an arrival" =
  let initial = Mock_backend.advance (backend Enabled) |> Mock_backend.state in
  let handle = Shell_tests.handle ~initial { width = 120; height = 36 } in
  let text = Bonsai_test.Handle.show_into_string handle in
  printf "decision #1 rendered: %b\n" (String.is_substring text ~substring:"MATCH");
  [%expect {| decision #1 rendered: true |}]
